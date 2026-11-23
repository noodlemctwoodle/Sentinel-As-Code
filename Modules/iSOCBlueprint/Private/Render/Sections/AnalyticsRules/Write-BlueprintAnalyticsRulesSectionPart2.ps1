#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 20-analytics-rules.md (part 2 of 2).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/AnalyticsRules/Write-BlueprintAnalyticsRulesSectionPart2.ps1
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
function Write-BlueprintAnalyticsRulesSectionPart2 {
    <#
    .SYNOPSIS
        Build the figures for and write 20-analytics-rules.md (part 2 of 2).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $bySolution = $Context.bySolution
    $counted = $Context.counted
    $customDetectionRefs = $Context.customDetectionRefs
    $customDetectionsCaptured = $Context.customDetectionsCaptured
    $mismatchRows = $Context.mismatchRows
    $modificationsSection = $Context.modificationsSection
    $mouldyRows = $Context.mouldyRows
    $msRulesSection = $Context.msRulesSection
    $props = $Context.props
    $q = $Context.q
    $rawRoot = $Context.rawRoot
    $rules = $Context.rules
    $rulesBody = $Context.rulesBody
    $solCounts = $Context.solCounts
    $solPieRows = $Context.solPieRows

    $solutionSection = @"

## By Content Hub solution

### Top contributing solutions

``````mermaid
pie showData title Analytics rules by Content Hub solution (top 8)
$($solPieRows -join [Environment]::NewLine)
``````

$(Format-BlueprintPlural $solCounts.Count 'distinct solution') contributing $(Format-BlueprintPlural $counted 'rule') in total. A heavy long-tail "(custom or unmapped)" slice usually means repo-deployed content not registered against any Content Hub solution.

Rules grouped by the Content Hub solution that ships them, derived from the metadata link table. '(custom or unmapped)' covers rules that have no metadata association, typically repo-deployed custom rules.

$(Format-BlueprintTable -Items $bySolution -Columns 'Solution','Rule','Enabled','Severity')
"@

    # Stale rules and template drift for section 22, moved from the rule
    # inventory on section 20.
    $staleSection = @"

## Stale rules (enabled, last modified over a year ago)

Rules in this table are still firing but haven't been reviewed in over twelve months. Stale thresholds, deprecated KQL operators, and dropped data sources are all common causes. Each row is a candidate for explicit re-review or retirement.

$(Format-BlueprintTable -Items $mouldyRows -Columns 'Name','Kind','Severity','LastModified')

## Rules behind their latest template version

Rules where the deployed ``templateVersion`` is older than the version available in the Content Hub catalogue. Update via the rule's "Update from template" action in the portal, or re-deploy from the matching repo YAML.

$(Format-BlueprintTable -Items $mismatchRows -Columns 'Name','Kind','CurrentVersion','LatestVersion')
"@

    # Rule complexity: a heuristic over each Scheduled or NRT rule's query, so
    # the longest, most joined queries (the ones that time out or quietly
    # return nothing after a schema change) are easy to find. Idea from the
    # health check contributed by thinkndle; the scoring here is this project's.
    $complexityRows = @($(foreach ($r in $rules) {
                if (-not $r -or $r.kind -notin @('Scheduled', 'NRT')) { continue }
                $props = Get-BlueprintRawProperty $r 'properties'
                $q = [string](Get-BlueprintRawProperty $props 'query' '')
                if ([string]::IsNullOrWhiteSpace($q)) { continue }
                $lets = ([regex]::Matches($q, '(?im)^\s*let\s')).Count
                $joins = ([regex]::Matches($q, '(?i)\bjoin\b')).Count
                $unions = ([regex]::Matches($q, '(?i)\bunion\b')).Count
                $ents = @(Get-BlueprintRawProperty $props 'entityMappings' @()).Count
                $ti = [bool]($q -match '(?i)ThreatIntel')
                $incOn = [bool](Get-BlueprintRawProperty (Get-BlueprintRawProperty $props 'incidentConfiguration') 'createIncident' $true)
                $score = [math]::Min(10, [math]::Round($q.Length / 400.0) + $lets + 2 * $joins + $unions + $(
                        if ($ti) { 1 } else { 0 }
                    ) + $(if ($ents -eq 0) { 1 } else { 0 }))
                [pscustomobject]@{
                    Rule       = [string](Get-BlueprintRawProperty $props 'displayName' $r.name)
                    Kind       = $r.kind
                    Complexity = [int]$score
                    Chars      = $q.Length
                    Lets       = $lets
                    Joins      = $joins
                    Unions     = $unions
                    Entities   = $ents
                    TI         = if ($ti) { 'Yes' } else { '' }
                    Incident   = if ($incOn) { 'Yes' } else { 'No' }
                }
            }) | Sort-Object -Property @{ Expression = 'Complexity'; Descending = $true }, @{ Expression = 'Chars'; Descending = $true })
    $complexitySection = @"

## Rule complexity

A heuristic per Scheduled or NRT rule with a query: one point per 400 characters, one per ``let``, two per ``join``, one per ``union``, one when the query reads a threat-intelligence table and one when the rule maps no entities, capped at 10. A score of 8 or more marks a query to run by hand against its lookback before trusting it; it is the first place to look when a rule times out or starts returning nothing after a schema change.

$(Format-BlueprintTable -Items $complexityRows -Columns 'Rule','Kind','Complexity','Chars','Lets','Joins','Unions','Entities','TI','Incident')
"@

    # Rule run failures from SentinelHealth (rule-health.json). Absent file:
    # the collector did not run this capture; empty file: no failures.
    $ruleHealthCaptured = Test-Path -LiteralPath (Join-Path $rawRoot 'rule-health.json')
    $ruleHealthRows = @(Read-BlueprintRawArray 'rule-health.json' | Where-Object { $_ } | ForEach-Object {
            [pscustomobject]@{
                Rule                 = $_.RuleName
                Status               = $_.Status
                Failures             = $_.Failures
                'Last failure (UTC)' = Format-DateUtc (Get-BlueprintRawProperty $_ 'LastFailure')
                Reason               = [string](Get-BlueprintRawProperty $_ 'Reason' '')
            }
        } | Sort-Object { ConvertTo-BlueprintNumber $_.Failures } -Descending | ForEach-Object { $_.Failures = Format-BlueprintCount $_.Failures; $_ })
    $ruleHealthSection = @"

## Rule run failures (last {lookback-d})

Analytics rules whose scheduled runs failed, from ``SentinelHealth``, with the failure count, the last failure and the reason Sentinel recorded. A failing rule is a detection that stopped without an alert; the usual causes are a query past the timeout, a table or column that no longer exists, or a KQL function the rule depends on that was removed. [SAC-DET-14] fires while any rule is failing.

$(if (-not $ruleHealthCaptured) { '_Not captured in this run (``rule-health.json`` is absent); re-run the collector to populate it._' } elseif ($ruleHealthRows.Count -eq 0) { '_No analytics rule run failed in the last {lookback}._' } else { Format-BlueprintTable -Items $ruleHealthRows -Columns 'Rule','Status','Failures','Last failure (UTC)','Reason' })
"@

    # Defender XDR custom detections from the Graph capture: the other detection
    # logic that reads this data, listed with the tables each one queries.
    $customDetectionRows = @($customDetectionRefs | Where-Object { $_ } | ForEach-Object {
            [pscustomobject]@{
                Name         = [string](Get-BlueprintRawProperty $_ 'RuleName' '')
                Enabled      = $(if ((Get-BlueprintRawProperty $_ 'Enabled' $false) -eq $true) { 'Yes' } else { 'No' })
                Severity     = [string](Get-BlueprintRawProperty $_ 'Severity' '')
                Period       = [string](Get-BlueprintRawProperty $_ 'Period' '')
                Tables       = (@(Get-BlueprintRawProperty $_ 'Tables' @()) -join ', ')
                LastModified = Format-DateUtc (Get-BlueprintRawProperty $_ 'LastModified')
            }
        } | Sort-Object -Property @{ Expression = { $_.Enabled -eq 'No' } }, Name)
    $customDetectionSection = @"

## Defender XDR custom detections

Custom detection rules defined in the Defender portal (Microsoft Graph ``security/rules/detectionRules``). They run inside Defender XDR over the same advanced-hunting data the workspace receives, so they count as detection coverage on the tables they query, on this page, on the table-coverage view and in the estate flow. Period ``0`` is near-real-time.

$(if (-not $customDetectionsCaptured) { '_Not captured in this run: the Graph call was not made or was refused. The identity needs the ``CustomDetection.Read.All`` application permission (delegated access through Azure PowerShell does not carry it); until then coverage counts Sentinel rules only._' } elseif ($customDetectionRows.Count -eq 0) { '_No custom detection rules are defined in Defender XDR for this tenant._' } else { Format-BlueprintTable -Items $customDetectionRows -Columns 'Name','Enabled','Severity','Period','Tables','LastModified' })
"@

    # One page for the rule estate: the core view built in the section-20 block
    # above, then the alert-volume, Microsoft-managed, modifications and
    # solution subsections (formerly 21 to 24).
    $analyticsLinks = @'

[Built-in detections (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/detect-threats-built-in) · [Detect threats from template](https://learn.microsoft.com/azure/sentinel/detect-threats-from-template) · [Alert and incident tuning](https://learn.microsoft.com/azure/sentinel/false-positives)
'@
    # Each part begins with a newline and ends without one; joining with a
    # newline keeps a blank line between a table and the next heading.
    Write-BlueprintSection '20-analytics-rules.md' (@(
            $rulesBody.TrimEnd(), $msRulesSection, $modificationsSection, $solutionSection, $customDetectionSection, $analyticsLinks
        ) -join [Environment]::NewLine)

    # Left in the render context for later sections.
    $Context.analyticsLinks = $analyticsLinks
    $Context.complexitySection = $complexitySection
    if (Get-Variable -Name 'props' -Scope 0 -ErrorAction Ignore) { $Context.props = $props }
    if (Get-Variable -Name 'q' -Scope 0 -ErrorAction Ignore) { $Context.q = $q }
    $Context.r = $r
    $Context.ruleHealthSection = $ruleHealthSection
    $Context.staleSection = $staleSection
}
