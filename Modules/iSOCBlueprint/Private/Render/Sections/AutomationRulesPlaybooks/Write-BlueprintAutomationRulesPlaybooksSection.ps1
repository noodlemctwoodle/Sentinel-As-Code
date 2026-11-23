#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 60-automation-rules-playbooks.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/AutomationRulesPlaybooks/Write-BlueprintAutomationRulesPlaybooksSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintAutomationRulesPlaybooksSection {
    <#
    .SYNOPSIS
        Build the figures for and write 60-automation-rules-playbooks.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $autoRules = $Context.autoRules
    $connectors = $Context.connectors
    $enabledRules = $Context.enabledRules
    $m = $Context.m
    $n = $Context.n
    $playbookRuns = $Context.playbookRuns
    $rawRoot = $Context.rawRoot
    $title = $Context.title

    $arRows = $autoRules | ForEach-Object {
        [pscustomobject]@{ Name = $_.properties.displayName; Order = $_.properties.order; Enabled = if ($_.properties.triggeringLogic.isEnabled) { 'Yes' } else { 'No' } }
    }
    $playbooks = Read-BlueprintRawArray 'playbooks.json'
    $miAssignments = Read-BlueprintRawArray 'rbac-playbook-mi.json'
    # Note on schema: the Microsoft.Logic/workflows ?api-version=2016-06-01 list
    # response returns PascalCase properties at the top level (Name, State,
    # Version, ProvisioningState, Definition, etc.) — NOT the nested
    # `{ properties: { state, ... } }` shape the docs imply. Defensive lookups
    # below try both paths so the renderer works against the live API response
    # AND against fixtures shaped to the documented schema.
    $pbRows = $playbooks | ForEach-Object {
        $pbName = if ($_.PSObject.Properties.Name -contains 'Name') { $_.Name } else { $_.name }
        $pbState = if ($_.PSObject.Properties.Name -contains 'State') { $_.State }
        elseif ($_.PSObject.Properties.Name -contains 'properties' -and $_.properties) { $_.properties.state }
        else { '' }
        # Closure-scoping note: `Where-Object { $_.Playbook -eq $_.Name }` is
        # ambiguous because $_ inside Where-Object refers to the miAssignment.
        # Capture the outer playbook name first.
        $mi = $miAssignments | Where-Object { $_.Playbook -eq $pbName } | Select-Object -First 1
        $roles = if ($mi -and @($mi.WorkspaceRoles).Count -gt 0) {
            @($mi.WorkspaceRoles) -join ', '
        } elseif ($mi) {
            '_(MI present, no workspace roles)_'
        } else {
            '_(no managed identity)_'
        }
        [pscustomobject]@{
            Name           = $pbName
            State          = $pbState
            WorkspaceRoles = $roles
        }
    }
    $autoCount = $arRows.Count
    $pbCount = $pbRows.Count
    # Run health from playbook-runs.json (7-day window, written by the collector
    # per enabled workflow).
    $pbRunRows = @($playbookRuns | ForEach-Object {
            [pscustomobject]@{
                Playbook       = $_.Playbook
                Runs7d         = [int](ConvertTo-BlueprintNumber $_.Runs7d)
                Failed7d       = [int](ConvertTo-BlueprintNumber $_.Failed7d)
                LastRunStatus  = $_.LastRunStatus
                LastFailureUtc = Format-DateUtc $_.LastFailureUtc
                Note           = if ($_.PSObject.Properties['Note'] -and $_.Note) { [string]$_.Note } else { '' }
            }
        } | Sort-Object -Property Failed7d -Descending)
    $pbUnavailable = @($pbRunRows | Where-Object { $_.LastRunStatus -eq 'Unavailable' }).Count
    $pbRunsTotal = 0; $pbFailedTotal = 0
    foreach ($r in $pbRunRows) { $pbRunsTotal += $r.Runs7d; $pbFailedTotal += $r.Failed7d }
    $pbFailingCount = @($pbRunRows | Where-Object { $_.Failed7d -gt 0 }).Count
    $pbRunsWarning = if ($pbFailingCount -gt 0) {
        "> **$(Format-BlueprintPlural $pbFailingCount 'playbook') had failed runs in the last {lookback}.** A failing playbook is a response step that is quietly not happening; [SAC-AUT-02] carries the detail.`n"
    } else { '' }
    $pbRunsPie = if ($pbRunsTotal -gt 0) {
        @"
``````mermaid
pie showData title Playbook runs by outcome ({lookback-d})
    "Succeeded" : $($pbRunsTotal - $pbFailedTotal)
    "Failed" : $pbFailedTotal
``````
"@
    } else { '' }
    # Automation opportunities: incident titles that are frequent, close fast
    # or close mostly as false positives, with a suggested response per title
    # family. The title-to-action map is ported from the health check
    # contributed by thinkndle.
    $autoPlaybookMap = @(
        @{
            Pattern  = 'brute.?force|password.?spray|failed.?(sign|log).?in'
            Action   = 'Disable the account on threshold, require an MFA reset, notify IAM and tag the incident as identity attack'
            Playbook = 'Disable-AADUser / Confirm-AADRiskyUser'
        }
        @{
            Pattern  = 'impossible travel|atypical travel|anomalous (sign|log).?in'
            Action   = 'Trigger an MFA challenge, revoke sessions, raise the Entra ID Protection risk and notify the manager'
            Playbook = 'Block-AADUser-Sessions'
        }
        @{
            Pattern  = 'phish|suspicious mail|mail.?flow'
            Action   = 'Soft-delete similar messages through Defender for Office 365, block the sender, scan clicked URLs and isolate affected devices'
            Playbook = 'ZAP-Phish-Mail / Defender-Submission'
        }
        @{
            Pattern  = 'malware|ransom|trojan|suspicious process'
            Action   = 'Isolate the device through Defender for Endpoint, run a full scan, block the file hash as a custom indicator and open an IR ticket'
            Playbook = 'Isolate-MDEDevice'
        }
        @{
            Pattern  = 'data exfil|dlp|mass download|unusual upload'
            Action   = 'Suspend the session, block egress at the proxy, restrict sharing and escalate to the DLP team'
            Playbook = 'Block-AADUser + Restrict-Sharing'
        }
        @{
            Pattern  = 'lateral movement|pass.?the.?hash|kerberoast|golden ticket'
            Action   = 'Isolate the source host, reset affected service accounts and review a krbtgt rotation'
            Playbook = 'Isolate-Host + Reset-Account'
        }
        @{
            Pattern  = 'privilege escal|added to (admin|privileged)|role assign'
            Action   = 'Revert the role assignment outside a change window, notify the PIM owner and require a ticket reference'
            Playbook = 'Remove-AADRole'
        }
        @{ Pattern = 'token theft|refresh token|primary refresh'; Action = 'Revoke refresh tokens, force re-authentication with MFA and audit OAuth grants'; Playbook = 'Revoke-AADUserTokens' }
        @{
            Pattern  = 'c2|command.?and.?control|beacon|dns tunneling'
            Action   = 'Isolate the device, sinkhole the domain in DNS and block the indicator at the firewall and proxy'
            Playbook = 'Isolate-MDEDevice + Block-IoC'
        }
        @{ Pattern = 'defender|av disabled|tamper'; Action = 'Isolate the device, re-enable antivirus through Intune and escalate to the endpoint team'; Playbook = 'Isolate-MDEDevice' }
        @{ Pattern = 'guest|external user|b2b'; Action = 'Disable the guest pending review, audit external sharing and notify identity governance'; Playbook = 'Block-AADUser' }
        @{
            Pattern  = 'deprecated|legacy auth|basic auth'
            Action   = 'Block legacy authentication with Conditional Access and notify the owner of the affected app or account'
            Playbook = 'Enforce-CAPolicy'
        }
    )
    $autoOppRows = @(Read-BlueprintRawArray 'incident-title-stats.json' | Where-Object { $_ } | ForEach-Object {
            $title = [string](Get-BlueprintRawProperty $_ 'Title' '')
            $total = ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $_ 'Total' 0); $closed = ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $_ 'Closed' 0)
            $fast = ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $_ 'ClosedWithinHour' 0); $fp = ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $_ 'FP' 0)
            $signal = if ($closed -gt 0 -and $fp / $closed -ge 0.5) { 'Mostly false positive' } elseif ($closed -gt 0 -and $fast / $closed -ge 0.5) { 'Fast-closing' } else { 'Volume' }
            $match = $autoPlaybookMap | Where-Object { $title -match $_.Pattern } | Select-Object -First 1
            [pscustomobject]@{
                Title = $title; Severity = [string](Get-BlueprintRawProperty $_ 'Severity' ''); Total = [int]$total; Closed = [int]$closed
                AvgMinsToClose      = Format-BlueprintNumber (Get-BlueprintRawProperty $_ 'AvgMinsToClose' '')
                ClosedWithinHour    = [int]$fast
                FP                  = [int]$fp
                TP                  = [int](ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $_ 'TP' 0))
                Signal              = $signal
                SuggestedAutomation = if ($match) {
                    $match.Action
                } elseif ($signal -eq 'Mostly false positive') {
                    'Tune the rule or auto-close with a classification and comment through an automation rule'
                } else { 'Automation rule to assign, tag and enrich (TI, watchlists), then close on a verified benign pattern' }
                Playbook            = if ($match) { $match.Playbook } else { 'Generic-Enrich-And-Close' }
            }
        } | Sort-Object -Property @{ Expression = 'Total'; Descending = $true })
    $autoOppCaptured = Test-Path -LiteralPath (Join-Path $rawRoot 'incident-title-stats.json')
    # The alert-to-response chain as data for the SharePoint graphic: the target
    # shape's steps by phase, each marked where a fired finding says this
    # workspace is missing it or has it at risk.
    $chainState = { param([string]$Id, [string]$State) if ($script:FiredFindingIds.ContainsKey($Id)) { [ordered]@{ state = $State; finding = $Id } } else { [ordered]@{ state = ''; finding = '' } } }
    $chainStep = { param([int]$N, [string]$Actor, [string]$Target, [string]$Action, $Flag)
        $s = [ordered]@{ n = $N; actor = $Actor; target = $Target; action = $Action; state = ''; finding = '' }
        if ($Flag) { $s.state = $Flag.state; $s.finding = $Flag.finding }
        $s
    }
    $aut01 = & $chainState 'SAC-AUT-01' 'missing'
    $responseChainVisualLine = Format-VisualLine -Kind 'response-chain' -Data ([ordered]@{ phases = @(
                [ordered]@{ name = 'Ingest'; figure = (Format-BlueprintPlural @($connectors).Count 'data connector'); steps = @(
                        (& $chainStep 1 'Data source' 'DCR / Logs Ingestion' 'Event sent' $null),
                        (& $chainStep 2 'DCR / Logs Ingestion' 'Workspace table' 'Ingested after transform, about 5 minutes' $null))
                }
                [ordered]@{ name = 'Detect'; figure = (Format-BlueprintPlural $enabledRules.Count 'enabled analytics rule'); steps = @(
                        (& $chainStep 3 'Analytics rule' 'Workspace table' 'KQL query on a schedule' $null),
                        (& $chainStep 4 'Analytics rule' 'Incident' 'Incident created' $null))
                }
                [ordered]@{ name = 'Automate'; figure = "$(Format-BlueprintPlural $autoCount 'automation rule'), $(Format-BlueprintPlural $pbCount 'playbook')"; steps = @(
                        (& $chainStep 5 'Incident' 'Automation rule' 'Trigger: incident created' $null),
                        (& $chainStep 6 'Automation rule' 'Incident' 'Assign owner, tag tactic, set Active' $aut01),
                        (& $chainStep 7 'Automation rule' 'Playbook' 'Run playbook' $aut01),
                        (& $chainStep 8 'Playbook' 'Incident' 'Add an enrichment comment' $aut01))
                }
                [ordered]@{ name = 'Notify'; figure = ''; steps = @(
                        (& $chainStep 9 'Playbook' 'Microsoft Teams' 'Post to the SOC channel' (& $chainState 'SAC-AUT-05' 'risk')),
                        (& $chainStep 10 'Microsoft Teams' 'SOC analyst' 'Notification' $null))
                }
                [ordered]@{ name = 'Respond'; figure = ''; steps = @(
                        (& $chainStep 11 'SOC analyst' 'Incident' 'Acknowledge and investigate' (& $chainState 'SAC-INC-05' 'risk')))
                }
            )
        })
    Write-BlueprintSection '60-automation-rules-playbooks.md' (@"
$(Format-Banner -Title "Automation Rules and Playbooks")

**$(Format-BlueprintPlural $autoCount 'automation rule') · $(Format-BlueprintPlural $pbCount 'playbook')** on this workspace.

## Alert-to-response chain: the target shape

The handoff path a response chain enriched by automation follows, from ingestion to the analyst, drawn against this workspace. A step this workspace is missing or has at risk names the finding behind it: steps 6 to 8 need automation rules ([SAC-AUT-01]), step 9 needs the playbook's managed identity role ([SAC-AUT-05]) and step 11 needs analysts to acknowledge incidents ([SAC-INC-05]).

``````mermaid
sequenceDiagram
$responseChainVisualLine
    autonumber
    participant DS as Data source
    participant DCR as DCR / Logs Ingest
    participant Tbl as Workspace table
    participant Rule as Analytics rule
    participant Inc as Incident
    participant Auto as Automation rule
    participant PB as Playbook
    participant Teams as MS Teams
    participant SOC as SOC analyst

    DS->>DCR: Event
    DCR->>Tbl: Ingest (after transform)
    Note over Tbl: ~5 min ingestion latency
    Rule->>Tbl: KQL query on schedule
    Rule-->>Inc: Create incident
    Inc->>Auto: Trigger: incident created
    Auto->>Inc: Assign owner, tag tactic, set Active
    Auto->>PB: Run playbook
    PB->>Inc: Add enrichment comment
    PB->>Teams: Post to SOC channel
    Teams-->>SOC: Notification
    SOC->>Inc: Acknowledge + investigate
``````

## Automation rules

$(Format-BlueprintTable -Items $arRows -Columns 'Name','Order','Enabled')

## Playbooks (Logic Apps)

$(Format-BlueprintTable -Items $pbRows -Columns 'Name','State','WorkspaceRoles')

## Playbook runs (last {lookback-d})

$pbRunsWarning
$pbRunsPie

$(if ($pbUnavailable -gt 0) { "_Run history could not be read for $(Format-BlueprintPlural $pbUnavailable 'playbook') (LastRunStatus 'Unavailable'); their counts are not zero, they are unknown._`n" })
$(Format-BlueprintTable -Items $pbRunRows -Columns 'Playbook','Runs7d','Failed7d','LastRunStatus','LastFailureUtc','Note')

## Automation opportunities (incident titles, last {lookback-d})

Incident titles seen five or more times in {lookback}, with how they close. "Fast-closing" (half or more closed within an hour) and "Mostly false positive" titles are the ones an automation rule or playbook can take off the analysts: enrich, classify and close the benign pattern, or respond automatically where the title maps to a known response. The suggested automation is a starting point per title family, not a prescription.

$(if (-not $autoOppCaptured) { '_Not captured in this run (``incident-title-stats.json`` is absent); re-run the collector to populate it._' } elseif ($autoOppRows.Count -eq 0) { '_No incident title reached five incidents in the last {lookback}._' } else { Format-BlueprintTable -Items $autoOppRows -Columns 'Title','Severity','Total','Closed','AvgMinsToClose','ClosedWithinHour','FP','TP','Signal','SuggestedAutomation','Playbook' })

[Sentinel automation (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/automation/automate-responses-with-playbooks) · [Monitor automation health](https://learn.microsoft.com/azure/sentinel/monitor-automation-health)
"@)

    # Left in the render context for later sections.
    $Context.playbooks = $playbooks
    $Context.r = $r
}
