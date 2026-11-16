#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 25-mitre-coverage.md (part 2 of 3).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/MitreCoverage/Write-BlueprintMitreCoverageSectionPart2.ps1
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
function Write-BlueprintMitreCoverageSectionPart2 {
    <#
    .SYNOPSIS
        Build the figures for and write 25-mitre-coverage.md (part 2 of 3).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $correlationState = $Context.correlationState
    $enabledRules = $Context.enabledRules
    $msicNote = $Context.msicNote
    $msIncidentRows = $Context.msIncidentRows
    $nrtDisabled = $Context.nrtDisabled
    $nrtEnabled = $Context.nrtEnabled
    $ResourcesRoot = $Context.ResourcesRoot
    $ruleKindsVisualLine = $Context.ruleKindsVisualLine
    $ruleRows = $Context.ruleRows
    $rules = $Context.rules
    $schedDisabled = $Context.schedDisabled
    $schedEnabled = $Context.schedEnabled
    $schedNote = $Context.schedNote

    $rulesBody = @"
$(Format-Banner -Title "Analytics Rules")

## Rule taxonomy

Sentinel's ``alertRules`` API surfaces every kind of detection logic under a single base: the fields every rule carries, then the settings only each kind has, with how many of each this workspace deploys. Worth knowing when later sections refer to "MS Incident Creation rules", because those rules have a completely different shape from Scheduled:

``````mermaid
classDiagram
$ruleKindsVisualLine
    class AlertRule {
        +string id
        +string kind
        +string displayName
        +string severity
        +bool enabled
        +datetime lastModifiedUtc
        +string[] tactics
        +string[] techniques
    }

    class Scheduled {
        +string queryFrequency
        +string queryPeriod
        +int triggerThreshold
        +string query
    }

    class NRT {
        +string query
        +bool eventGrouping
    }

    class Fusion {
        +string alertRuleTemplateName
        +string[] sourceSettings
    }

    class MicrosoftSecurityIncidentCreation {
        +string productFilter
        +string[] severitiesFilter
        +string[] displayNamesFilter
        +string[] displayNamesExcludeFilter
    }

    class ThreatIntelligence {
        +string templateVersion
    }

    AlertRule <|-- Scheduled
    AlertRule <|-- NRT
    AlertRule <|-- Fusion
    AlertRule <|-- MicrosoftSecurityIncidentCreation
    AlertRule <|-- ThreatIntelligence

    note for Scheduled "$schedNote on this workspace"
    note for MicrosoftSecurityIncidentCreation "$msicNote (legacy pre-Defender XDR pattern)"
``````

## Incident correlation engine

$correlationState

[Microsoft Sentinel Fusion technology (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/fusion)
[Microsoft Defender XDR correlation in the unified SecOps portal (Microsoft Learn)](https://learn.microsoft.com/defender-xdr/microsoft-365-defender)

## Per-kind / per-state aggregate

| Total | Enabled | Disabled | Scheduled-Enabled | Scheduled-Disabled | NRT-Enabled | NRT-Disabled |
|---:|---:|---:|---:|---:|---:|---:|
| $(Format-BlueprintCount $rules.Count) | $(Format-BlueprintCount $enabledRules.Count) | $(Format-BlueprintCount ($rules.Count - $enabledRules.Count)) | $(Format-BlueprintCount $schedEnabled) | $(Format-BlueprintCount $schedDisabled) | $(Format-BlueprintCount $nrtEnabled) | $(Format-BlueprintCount $nrtDisabled) |

The Microsoft-managed rules, recent modifications, the Content Hub solution breakdown and the Defender XDR custom detections follow below on this page. Alert volume and incident outcomes per rule are in [21-rule-performance.md](21-rule-performance.md); run failures, complexity, stale rules, template drift and the entity-mapping and incident-creation anti-patterns are in [22-rule-health-quality.md](22-rule-health-quality.md); tables no enabled rule reads, with the templates that would cover them, are in [28-detection-opportunities.md](28-detection-opportunities.md).

## All rules

$(Format-BlueprintTable -Items $ruleRows -Columns 'Kind','Name','Severity','Enabled','Tactics')

## MS Incident Creation rules

These translate first-party security alerts (Defender for Cloud Apps, Defender XDR, etc.) into Sentinel incidents based on per-product filter criteria. They aren't editable as KQL rules; the ``Product`` column is the source product, and ``Includes`` / ``Excludes`` are the alert-name filters.

$(Format-BlueprintTable -Items $msIncidentRows -Columns 'Name','Product','Severities','Includes','Excludes','Enabled')
"@
    # $rulesBody is the first part of 20-analytics-rules.md; the alert-volume,
    # Microsoft-managed, modifications and solution subsections are built after
    # section 15 (they need its effectiveness rows) and the page is written there.

    # ---------------------------------------------------------------------------
    # Section: 25-mitre-coverage
    # ---------------------------------------------------------------------------
    # Catalogue file (resource-bundled) carries:
    #   tactics[]    { id, name, shortname (kebab, STIX), sentinelShortName
    #                  (PascalCase, what Sentinel rules return in tactics[]) }
    #   techniques[] { id, name, tactics (kebab), tacticsSentinel (PascalCase),
    #                  isSubtechnique, parentId, url, platforms, dataSources }
    # The renderer joins each rule's `properties.techniques` against the
    # catalogue so cells show "T1078 — Valid Accounts" rather than a bare ID.
    $mitreFile = Join-Path $ResourcesRoot 'mitre-attack.json'
    $tactics = @()
    $mitreTechniques = @()
    if (Test-Path $mitreFile) {
        $mitreCatalogue = Get-Content $mitreFile -Raw | ConvertFrom-Json
        $tactics = @($mitreCatalogue.tactics)
        $mitreTechniques = @($mitreCatalogue.techniques)
    }

    # Build a technique-id -> name lookup so every render path resolves names
    # consistently. Sub-techniques also get their parent's name prefixed in a
    # separate fullName lookup so a row reading "T1078.004 — Cloud Accounts" can
    # fall back to "Valid Accounts: Cloud Accounts" when richer context helps.
    $techNameById = @{}
    $techFullNameById = @{}
    foreach ($t in $mitreTechniques) {
        if (-not $t.id) { continue }
        $techNameById[$t.id] = $t.name
        if ($t.PSObject.Properties.Name -contains 'parentId' -and $t.parentId) {
            $parent = $techNameById[$t.parentId]
            if ($parent) { $techFullNameById[$t.id] = "${parent}: $($t.name)" }
        }
    }

    $tacticCounts = @{}
    foreach ($t in $tactics) { $tacticCounts[$t.sentinelShortName] = 0 }
    foreach ($r in $enabledRules) {
        # Some rule kinds (e.g. MicrosoftSecurityIncidentCreation) omit the
        # tactics property entirely; @($null) iterates once with $t = $null
        # which would throw on ContainsKey. Filter nulls.
        foreach ($t in @($r.properties.tactics | Where-Object { $_ })) {
            if ($tacticCounts.ContainsKey($t)) { $tacticCounts[$t]++ }
        }
    }

    $mitreRows = foreach ($t in $tactics) {
        $count = $tacticCounts[$t.sentinelShortName]
        [pscustomobject]@{
            ID = $t.id
            Tactic = $t.name
            EnabledRules = $count
            Coverage = if ($count -eq 0) { 'None' } elseif ($count -lt 3) { 'Thin' } else { 'Covered' }
        }
    }

    # Build the hierarchy: tactic -> technique -> sub-technique -> rules, from
    # Get-AttackCoverage (Private/Lookup/Get-AttackCoverage.ps1), which the dashboard's
    # ATT&CK grid reads too, so the two agree. It maps every rule, enabled or
    # not; the tactic and technique tables count enabled rules only, and the
    # rule table at the end lists every rule with its status.
    $attackCoverage = Get-AttackCoverage -Rules @($rules) -Catalogue $(if (Test-Path $mitreFile) { $mitreCatalogue } else { $null })
    $subTotalByParent = $attackCoverage.SubTotals
    $tacticNameByShort = @{}
    foreach ($t in $tactics) { $tacticNameByShort[[string]$t.sentinelShortName] = [string]$t.name }
    $enabledIdx = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($row in $attackCoverage.Rules) { if ($row.Enabled) { [void]$enabledIdx.Add($row.Index) } }
    $mitreHierarchy = @{}
    $anyTechniques = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($tac in $attackCoverage.Cells.Keys) {
        foreach ($tech in $attackCoverage.Cells[$tac].Keys) {
            [void]$anyTechniques.Add($tech)
            $cell = $attackCoverage.Cells[$tac][$tech]
            $on = [System.Collections.Generic.List[int]]::new()
            foreach ($i in $cell.Rules) { if ($enabledIdx.Contains($i)) { $on.Add($i) } }
            if (-not $on.Count) { continue }
            if (-not $mitreHierarchy.ContainsKey($tac)) { $mitreHierarchy[$tac] = @{} }
            $subs = @{}
            foreach ($sub in $cell.Subs.Keys) {
                $subOn = [System.Collections.Generic.List[int]]::new()
                foreach ($i in $cell.Subs[$sub]) { if ($enabledIdx.Contains($i)) { $subOn.Add($i) } }
                if ($subOn.Count) { $subs[$sub] = $subOn }
            }
            $mitreHierarchy[$tac][$tech] = @{ Rules = $on; Subs = $subs }
        }
    }
    $ruleAttackRows = @($attackCoverage.Rules | Sort-Object @{ Expression = { -not $_.Enabled } }, Name | ForEach-Object {
            [pscustomobject]@{
                'Rule'           = $_.Name
                'Status'         = $(if ($_.Enabled) { 'Enabled' } else { 'Disabled' })
                'Tactics'        = $(
                    if ($_.Tactics.Count) {
                        ($_.Tactics |
                            ForEach-Object { if ($tacticNameByShort.ContainsKey($_)) { $tacticNameByShort[$_] } else { Format-TacticName ([string]$_) } }) -join
                            ', '
                    } else { 'None' }
                )
                'Techniques'     = $(if ($_.Techniques.Count) { $_.Techniques -join ', ' } else { 'None' })
                'Sub-techniques' = $(if ($_.SubTechniques.Count) { $_.SubTechniques -join ', ' } else { 'None' })
            }
        })
    $rulesEnabledCount = $enabledIdx.Count
    $rulesWithoutTechnique = @($attackCoverage.Rules | Where-Object { $_.Enabled -and -not $_.Techniques.Count }).Count
    $rulesWithSub = @($attackCoverage.Rules | Where-Object { $_.Enabled -and $_.SubTechniques.Count }).Count
    $enabledTechniques = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($tac in $mitreHierarchy.Keys) { foreach ($tech in $mitreHierarchy[$tac].Keys) { [void]$enabledTechniques.Add($tech) } }
    $disabledOnlyTechniques = @($anyTechniques | Where-Object { -not $enabledTechniques.Contains($_) }).Count

    # Left in the render context for later sections.
    $Context.disabledOnlyTechniques = $disabledOnlyTechniques
    $Context.mitreHierarchy = $mitreHierarchy
    $Context.r = $r
    $Context.row = $row
    $Context.ruleAttackRows = $ruleAttackRows
    $Context.rulesBody = $rulesBody
    $Context.rulesEnabledCount = $rulesEnabledCount
    $Context.rulesWithoutTechnique = $rulesWithoutTechnique
    $Context.rulesWithSub = $rulesWithSub
    $Context.subTotalByParent = $subTotalByParent
    $Context.t = $t
    $Context.tacticCounts = $tacticCounts
    $Context.tactics = $tactics
    $Context.techNameById = $techNameById
}
