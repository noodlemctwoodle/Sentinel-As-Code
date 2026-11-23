#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 00-overview.md (part 2 of 2).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Overview/Write-BlueprintOverviewSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintOverviewSection {
    <#
    .SYNOPSIS
        Build the figures for and write 00-overview.md (part 2 of 2).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $autoRules = $Context.autoRules
    $catalogueOnlyCount = $Context.catalogueOnlyCount
    $connectors = $Context.connectors
    $cost = $Context.cost
    $customDetectionRefs = $Context.customDetectionRefs
    $customDetectionsCaptured = $Context.customDetectionsCaptured
    $customDetectionsRaw = $Context.customDetectionsRaw
    $customDetectionTableSet = $Context.customDetectionTableSet
    $dcrs = $Context.dcrs
    $enabledRules = $Context.enabledRules
    $gapFindings = $Context.gapFindings
    $incSummary = $Context.incSummary
    $maturity = $Context.maturity
    $maturityOk = $Context.maturityOk
    $operationalTables = $Context.operationalTables
    $populatedTables = $Context.populatedTables
    $rules = $Context.rules
    $rulesFired = $Context.rulesFired
    $ruleTableRefs = $Context.ruleTableRefs
    $ruleVolumesAll = $Context.ruleVolumesAll
    $tablesWithData = $Context.tablesWithData
    $templateSolutionMap = $Context.templateSolutionMap
    $templateTableRefs = $Context.templateTableRefs
    $top5Findings = $Context.top5Findings
    $topFindingsVisual = $Context.topFindingsVisual
    $usageDaily = $Context.usageDaily
    $watchlists = $Context.watchlists
    $workbooksSaved = $Context.workbooksSaved
    $workspace = $Context.workspace

    $estate = New-BlueprintEstateModel

    $estateBlock = if ($estate.Sources.Count -gt 0 -and $estate.TotalGb -gt 0) {
        @"

## Estate flow

Where the last {lookback} of billable data came from, how much of it an enabled analytics rule reads, and what the detections produced.

$(Format-BlueprintEstateSankey -Estate $estate)

<!-- bp:shown-in-graphic -->

$(Format-BlueprintEstateRingsTable -Estate $estate)

$(Format-BlueprintEstateFamilyTable -Estate $estate)

GB that reaches **Not monitored** is ingested and billed but read by no enabled Sentinel analytics rule; detections that run inside Defender XDR, Entra ID Protection, Defender for Identity or Defender for Cloud do not read workspace tables and are not counted here. [28-detection-opportunities.md](28-detection-opportunities.md) lists those tables with the templates that would cover them.
"@
    } else {
        # No billable ingestion, so no ribbons to draw; first-party alerts and
        # the custom-detection count still belong here when they exist.
        $familyTail = if (@($estate.ProductAlerts).Count -gt 0 -or $estate.CustomDetectionsCaptured) {
            "`n`n" + (Format-BlueprintEstateFamilyTable -Estate $estate)
        } else { '' }
        @"

## Estate flow

_No billable ingestion in the last {lookback}, so there is no flow to draw._$familyTail
"@
    }

    $maturityHeadline = if ($maturityOk -and $null -ne $maturity.overall.score) {
        "**Maturity:** $(Format-BlueprintNumber $maturity.overall.score) / 5 ($($maturity.overall.levelName))  ·  **Target:** $($maturity.targetLevel) ($($maturity.targetLevelName))  ·  **Areas below target:** $(@($maturity.areasBelowTarget).Count) of $(@($maturity.areas).Count)  ·  **Quick wins:** $(@($maturity.quickWins).Count)`n`nScored from the Sentinel workspace only: people and processes were not assessed. Detail in [91-maturity-assessment.md](91-maturity-assessment.md)."
    } elseif ($maturityOk) {
        '_Maturity not assessed: no criterion could be evaluated in this run._ See [91-maturity-assessment.md](91-maturity-assessment.md).'
    } else { '_Maturity assessment not available for this run._' }
    $maturityCell = if ($maturityOk -and $null -ne $maturity.overall.score) {
        "$(Format-BlueprintNumber $maturity.overall.score) / $($maturity.targetLevel) ($($maturity.overall.levelName), target $($maturity.targetLevelName))"
    } else { '_not assessed_' }

    $usageTrendBlock = if ($usageDaily.Count -ge 2) {
        $pts = @($usageDaily | Sort-Object { [datetime]$_.Day })
        # Day labels read "13 Sep", not "09-13".
        $labels = ($pts |
                ForEach-Object { "`"$(([datetime]$_.Day).ToUniversalTime().ToString('d MMM', [System.Globalization.CultureInfo]::InvariantCulture))`"" }) -join
        ', '
        $bill = ($pts | ForEach-Object { [math]::Round((ConvertTo-BlueprintNumber $_.BillableGB), 2) }) -join ', '
        $free = ($pts | ForEach-Object { [math]::Round((ConvertTo-BlueprintNumber $_.FreeGB), 2) }) -join ', '
        $max = 1.0
        foreach ($pt in $pts) { $v = (ConvertTo-BlueprintNumber $pt.BillableGB) + (ConvertTo-BlueprintNumber $pt.FreeGB); if ($v -gt $max) { $max = $v } }
        @"

### Daily ingestion (last {lookback})

``````mermaid
---
config:
  xyChart:
    width: 1400
    height: 420
---
xychart-beta
    title "Daily ingestion, GB (billable and free)"
    x-axis [$labels]
    y-axis "GB" 0 --> $([math]::Ceiling($max * 1.1) + 1)
    line "Billable" [$bill]
    line "Free" [$free]
``````

Billable GB per day, and free GB (the Sentinel benefit and other non-billable data), from ``Usage``. A step up that no connector change explains is the usual first sign of a runaway source.
"@
    } else { '' }

    # Rule ↔ watchlist cross-reference. Scans every rule's KQL query for
    # `_GetWatchlist("alias")` calls (the canonical helper). The output is
    # two hashtables consumed by sections 20 and 50:
    #   $rulesByWatchlistAlias   alias  -> @(rule display names)
    #   $watchlistsByRuleId      ruleId -> @(aliases)
    # Both quote styles and a forgiving whitespace pattern are accepted —
    # matches `_GetWatchlist("X")`, `_GetWatchlist('X')`, and `_GetWatchlist
    # (  "X"  )` with case-insensitive function-name match.
    $rulesByWatchlistAlias = @{}
    $watchlistsByRuleId = @{}
    $rxWatchlistRef = [regex]::new("_GetWatchlist\s*\(\s*['""]([^'""]+)['""]\s*\)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($r in $rules) {
        $q = $r.properties.query
        if (-not $q) { continue }
        $references = $rxWatchlistRef.Matches([string]$q)
        if ($references.Count -eq 0) { continue }
        $ruleName = $r.properties.displayName
        $ruleId = $r.name
        $aliases = New-Object System.Collections.Generic.HashSet[string]
        foreach ($m in $references) { [void]$aliases.Add($m.Groups[1].Value) }
        $watchlistsByRuleId[$ruleId] = @($aliases)
        foreach ($a in $aliases) {
            if (-not $rulesByWatchlistAlias.ContainsKey($a)) { $rulesByWatchlistAlias[$a] = New-Object System.Collections.Generic.List[string] }
            [void]$rulesByWatchlistAlias[$a].Add($ruleName)
        }
    }

    # Severity + category counters hoisted up here (was computed twice further
    # down at the gap-analysis and live-snapshot section blocks). Single
    # computation drives the Mermaid pie/bar charts in 00, 01 and 90.
    $gapBySeverity = @{ Critical = 0; Warning = 0; Info = 0 }
    $gapByCategory = @{}
    foreach ($f in $gapFindings) {
        if ($gapBySeverity.ContainsKey($f.Severity)) { $gapBySeverity[$f.Severity]++ }
        $cat = if ($f.Category) { [string]$f.Category } else { 'Other' }
        if (-not $gapByCategory.ContainsKey($cat)) { $gapByCategory[$cat] = @{ Warning = 0; Info = 0; Critical = 0 } }
        if ($gapByCategory[$cat].ContainsKey($f.Severity)) { $gapByCategory[$cat][$f.Severity]++ }
    }

    $overviewBody = @"
$(Format-Banner -Title 'SIEM Overview')

## Findings at a glance

``````mermaid
pie showData title Open findings by severity
    "Critical" : $($gapBySeverity.Critical)
    "Warning"  : $($gapBySeverity.Warning)
    "Info"     : $($gapBySeverity.Info)
``````

$(Format-BlueprintPlural $gapFindings.Count 'open finding') against the best-practice catalogue. Drill into [90-gap-analysis.md](90-gap-analysis.md) for the per-category breakdown.

## Headline

| | |
|---|---|
| Workspace ID | ``$($workspace.properties.customerId)`` |
| Region | $(Format-WorkspaceRegion $workspace.location -WithCode) |
| SKU | $(Format-WorkspaceSku $workspace.properties.sku.name -WithCode) |
| Default retention | $(Format-BlueprintPlural $workspace.properties.retentionInDays 'day') |
| Daily cap | $(if ($workspace.properties.workspaceCapping.dailyQuotaGb -eq -1) { 'Unlimited' } else { "$(Format-BlueprintGb $workspace.properties.workspaceCapping.dailyQuotaGb) GB" }) |
| Replication | $(if ($workspace.properties.replication.enabled) { 'Enabled' } else { 'Disabled' }) |
| Public network access (ingestion) | ``$($workspace.properties.publicNetworkAccessForIngestion)`` |
| Public network access (query) | ``$($workspace.properties.publicNetworkAccessForQuery)`` |

## Counts

| Artefact | Count |
|---|---:|
| Data connectors | $(Format-BlueprintCount $connectors.Count) |
| Analytics rules | $(Format-BlueprintCount $rules.Count) (enabled: $(Format-BlueprintCount $enabledRules.Count)) |
| Automation rules | $(Format-BlueprintCount $autoRules.Count) |
| Watchlists | $(Format-BlueprintCount $watchlists.Count) |
| Workbooks | $(Format-BlueprintCount $workbooksSaved.Count) |
| Data Collection Rules | $(Format-BlueprintCount $dcrs.Count) |
| Tables operational (populated + custom logs) | $(Format-BlueprintCount $operationalTables.Count) |
| Tables receiving data ({lookback-d}) | $(Format-BlueprintCount $populatedTables.Count) |
| Catalogue-only Microsoft schemas (never ingested) | $(Format-BlueprintCount $catalogueOnlyCount) |
$estateBlock

## Maturity

$maturityHeadline

## Estimated monthly cost

$(if ($cost) {
"**$(Format-BlueprintMoney $cost.MonthlyTotal $cost.Currency)** for the workspace, computed from the last {lookback} of `Usage` against the Azure Retail Prices API on $(Format-BlueprintDate $cost.AsOfUtc -Time). See [84-cost-estimate.md](84-cost-estimate.md) for breakdown and methodology."
} else { '_Cost estimate not available._' })

## Top findings

$(if ($top5Findings.Count -gt 0) { "$(Format-TopFindingsLead $top5Findings.Count $gapFindings.Count) with what was found and how to fix it; [90-gap-analysis.md](90-gap-analysis.md) lists every one.`n`n$topFindingsVisual`n`n<!-- bp:shown-in-graphic -->`n`n" })$(if ($top5Findings.Count -gt 0) {
($top5Findings | ForEach-Object {
    "- **$($_.Severity)** [$($_.Id)] $($_.Title) - $($_.Evidence) [Learn]($($_.Learn))"
}) -join [Environment]::NewLine
} else { '_No findings: a clean run._' })

The deep-dive sections: [data connectors](10-data-connectors.md), [analytics rules](20-analytics-rules.md), [MITRE coverage](25-mitre-coverage.md), [detection opportunities](28-detection-opportunities.md), [workbooks](40-workbooks.md), [workspace](80-workspace.md), [table plans + retention](81-table-plans-retention.md), [data collection](83-data-collection.md), [cost estimate](84-cost-estimate.md), [access control (RBAC)](85-rbac.md), [gap analysis](90-gap-analysis.md), [maturity assessment](91-maturity-assessment.md).
"@

    Write-BlueprintSection '00-overview.md' $overviewBody

    # Left in the render context for later sections.
    $Context.a = $a
    if (Get-Variable -Name 'cat' -Scope 0 -ErrorAction Ignore) { $Context.cat = $cat }
    $Context.f = $f
    $Context.gapByCategory = $gapByCategory
    $Context.gapBySeverity = $gapBySeverity
    $Context.m = $m
    $Context.maturityCell = $maturityCell
    if (Get-Variable -Name 'q' -Scope 0 -ErrorAction Ignore) { $Context.q = $q }
    $Context.r = $r
    if (Get-Variable -Name 'ruleId' -Scope 0 -ErrorAction Ignore) { $Context.ruleId = $ruleId }
    $Context.rulesByWatchlistAlias = $rulesByWatchlistAlias
    $Context.usageTrendBlock = $usageTrendBlock
    if (Get-Variable -Name 'v' -Scope 0 -ErrorAction Ignore) { $Context.v = $v }
}
