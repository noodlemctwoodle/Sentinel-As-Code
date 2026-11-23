#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 01-live-snapshot.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/LiveSnapshot/Write-BlueprintLiveSnapshotSection.ps1
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
function Write-BlueprintLiveSnapshotSection {
    <#
    .SYNOPSIS
        Build the figures for and write 01-live-snapshot.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $catalogueStatus = $Context.catalogueStatus
    $connectorCatalogue = $Context.connectorCatalogue
    $connectors = $Context.connectors
    $cost = $Context.cost
    $enabledRules = $Context.enabledRules
    $f = $Context.f
    $gapBySeverity = $Context.gapBySeverity
    $gapFindings = $Context.gapFindings
    $maturityCell = $Context.maturityCell
    $mitreRowsRich = $Context.mitreRowsRich
    $operationalTables = $Context.operationalTables
    $parts = $Context.parts
    $populatedTables = $Context.populatedTables
    $rawRoot = $Context.rawRoot
    $rules = $Context.rules
    $tactics = $Context.tactics
    $top5Findings = $Context.top5Findings
    $workspace = $Context.workspace
    $WorkspaceName = $Context.WorkspaceName
    $workspaceTables = $Context.workspaceTables

    # ---------------------------------------------------------------------------
    # New sections aligned to the formal Sentinel Configuration TOC
    # (TOC numbering shown alongside each MD filename).
    # ---------------------------------------------------------------------------

    # Section 01 — Live snapshot  (TOC 1)
    # Living-documentation framing: this page is regenerated from the live
    # workspace on every CI/CD pipeline trigger and every pull request, so the
    # numbers reflect the workspace at the render timestamp — not a periodic
    # audit deliverable. Title and description avoid "report" / "summary"
    # language to reinforce that this is documentation-as-code, not a
    # point-in-time deck.
    # Synthesised from headline counts + cost + top gap findings + MITRE coverage.
    # $gapBySeverity / $gapByCategory are computed up at the top of the file
    # (around line 285) so 00-overview can also use them. Don't recompute here.

    # Today + days-until calculations drive the deprecation gantt bar widths.
    $today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $clv1Days = Get-BlueprintDaysUntil '2026-09-14'
    $tipDays = Get-BlueprintDaysUntil '2027-06-30'
    $xdrDays = Get-BlueprintDaysUntil '2027-03-31'

    # MITRE coverage rollup. Reuse $mitreRowsRich from section 25 — that view
    # already does the intersect-with-catalogue (rules' tactic shortnames must
    # match a catalogue.sentinelShortName) and categorises each tactic as
    # Covered / Thin / None against the 3-rule threshold. Counting from the
    # same source guarantees the headline and the section-25 matrix agree.
    $tacticsTotal = if ($tactics) { $tactics.Count } else { 14 }
    $tacticsCoveredFull = @($mitreRowsRich | Where-Object { $_.Coverage -eq 'Covered' }).Count
    $tacticsThin = @($mitreRowsRich | Where-Object { $_.Coverage -eq 'Thin' }).Count
    $tacticsNone = @($mitreRowsRich | Where-Object { $_.Coverage -eq 'None' }).Count
    $thinTacticNames = @($mitreRowsRich | Where-Object { $_.Coverage -eq 'Thin' } | Select-Object -ExpandProperty Tactic)
    $noneTacticNames = @($mitreRowsRich | Where-Object { $_.Coverage -eq 'None' } | Select-Object -ExpandProperty Tactic)
    $mitreSuffix = if ($thinTacticNames.Count -gt 0 -or $noneTacticNames.Count -gt 0) {
        $parts = @()
        if ($noneTacticNames.Count -gt 0) { $parts += "uncovered: $($noneTacticNames -join ', ')" }
        if ($thinTacticNames.Count -gt 0) { $parts += "thin: $($thinTacticNames -join ', ')" }
        "  ·  $($parts -join '  ·  ')"
    } else { '' }

    $mmaMachines01 = [long](@(
            Read-BlueprintRawArray 'ama-mma-migration.json' |
                Where-Object { $_ } |
                ForEach-Object { ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $_ 'MMACount' 0) }
            ) |
                Measure-Object -Sum).Sum
    $classicTables01 = @(
        $workspaceTables |
            Where-Object {
                $_ -and [string](Get-BlueprintRawProperty (Get-BlueprintRawProperty (Get-BlueprintRawProperty $_ 'properties') 'schema') 'tableSubType' '') -eq
                'Classic'
            }
    )
    $tiLegacyRows01 = [long](@(
            Read-BlueprintRawArray 'threat-intel-tables.json' |
                Where-Object { $_ -and [string]$_.Table -eq 'ThreatIntelligenceIndicator' } |
                ForEach-Object { ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $_ 'Records30d' 0) }
            ) |
                Measure-Object -Sum).Sum
    $tiLegacyRules01 = @(
        $enabledRules |
            Where-Object { [string](Get-BlueprintRawProperty (Get-BlueprintRawProperty $_ 'properties') 'query' '') -match 'ThreatIntelligenceIndicator(?!s)' }
    ).Count
    $msIncidentRules01 = @(
        $rules |
            Where-Object {
                $_ -and $_.kind -eq 'MicrosoftSecurityIncidentCreation' -and
                (Get-BlueprintRawProperty (Get-BlueprintRawProperty $_ 'properties') 'enabled' $false)
            }
    ).Count
    $ascAlerts01 = [long](@(
            Read-BlueprintRawArray 'analytics-rule-volumes.json' |
                Where-Object { $_ -and [string]$_.ProductName -eq 'Azure Security Center' } |
                ForEach-Object { ConvertTo-BlueprintNumber $_.Alerts }
            ) |
                Measure-Object -Sum).Sum
    $fwLegacy01 = [long](@(
            Read-BlueprintRawArray 'azure-firewall-categories.json' |
                Where-Object { $_ -and [string]$_.Category -like 'AzureFirewall*' } |
                ForEach-Object { ConvertTo-BlueprintNumber $_.LogCount }
            ) |
                Measure-Object -Sum).Sum
    $has01 = { param($f) Test-Path (Join-Path $rawRoot $f) }
    $deprecatedConnectors01 = @($catalogueStatus | Where-Object Deprecated | ForEach-Object { $_.Connector } | Sort-Object -Unique)
    $legacyRows = @(
        Format-BlueprintLegacyRow 'Deprecated data connectors still connected' $deprecatedConnectors01.Count ([bool]$connectorCatalogue -and
            (& $has01 'data-connectors-classic.json')) "$(Format-BlueprintPlural $deprecatedConnectors01.Count 'connector')$(if ($deprecatedConnectors01.Count) { ': ' + ($deprecatedConnectors01 -join '; ') })" '[10-data-connectors.md](10-data-connectors.md)'
        Format-BlueprintLegacyRow 'Legacy Log Analytics agent (MMA / OMS), retired 31 Aug 2024' $mmaMachines01 (& $has01 'ama-mma-migration.json') `
            "$(Format-BlueprintPlural $mmaMachines01 'machine') still heartbeating through it in {lookback}" '[87-azure-monitor-agents.md](87-azure-monitor-agents.md), [SAC-PLT-03]'
        Format-BlueprintLegacyRow 'Classic custom tables (HTTP Data Collector API), retiring 14 Sep 2026' $classicTables01.Count `
        (& $has01 'workspace-tables.json') "$(Format-BlueprintPlural $classicTables01.Count 'table') with tableSubType Classic" '[81-table-plans-retention.md](81-table-plans-retention.md), [SAC-PLT-02]'
        Format-BlueprintLegacyRow 'Retired ThreatIntelligenceIndicator table (ingestion)' $tiLegacyRows01 (& $has01 'threat-intel-tables.json') `
            "$(Format-BlueprintPlural $tiLegacyRows01 'record') in {lookback}" '[27-threat-intelligence.md](27-threat-intelligence.md), [SAC-TI-01]'
        Format-BlueprintLegacyRow 'Retired ThreatIntelligenceIndicator table (rules reading it)' $tiLegacyRules01 (& $has01 'alert-rules.json') `
            "$(Format-BlueprintPlural $tiLegacyRules01 'enabled rule') $(if ($tiLegacyRules01 -eq 1) { 'queries' } else { 'query' }) it" '[20-analytics-rules.md](20-analytics-rules.md), [SAC-TI-02]'
        Format-BlueprintLegacyRow 'Microsoft incident-creation rules (pre-unification)' $msIncidentRules01 (& $has01 'alert-rules.json') `
        (Format-BlueprintPlural $msIncidentRules01 'enabled rule') '[20-analytics-rules.md](20-analytics-rules.md), [SAC-DET-08]'
        Format-BlueprintLegacyRow 'Azure Security Center alert path (replaced by Defender for Cloud)' $ascAlerts01 (& $has01 'analytics-rule-volumes.json') `
            "$(Format-BlueprintPlural $ascAlerts01 'alert') in {lookback}" '[10-data-connectors.md](10-data-connectors.md)'
        Format-BlueprintLegacyRow 'Azure Firewall legacy AzureDiagnostics categories' $fwLegacy01 (& $has01 'azure-firewall-categories.json') `
            "$(Format-BlueprintPlural $fwLegacy01 'row') in {lookback}" '[14-coverage-breakdowns.md](14-coverage-breakdowns.md), [SAC-LOG-06]'
    )

    $execBody = @"
$(Format-Banner -Title 'Live snapshot')

> Living documentation for the Microsoft Sentinel workspace ``$WorkspaceName``. Every page in this set is regenerated from the live workspace on every CI/CD pipeline run and every pull request, so the numbers below describe the workspace as it stands at the timestamp above, not a periodic audit deliverable. If a value looks stale, re-run the pipeline; there is no separate refresh cycle.

## Workspace at a glance

| Indicator | Value |
|---|---:|
| Workspace SKU | $(Format-WorkspaceSku $workspace.properties.sku.name) |
| Default retention | $(Format-BlueprintPlural $workspace.properties.retentionInDays 'day') |
| Daily cap | $(if ($workspace.properties.workspaceCapping.dailyQuotaGb -eq -1) { 'Unlimited' } else { "$(Format-BlueprintGb $workspace.properties.workspaceCapping.dailyQuotaGb) GB" }) |
| Estimated monthly cost | $(if ($cost) { Format-BlueprintMoney $cost.MonthlyTotal $cost.Currency } else { 'n/a' }) |
| Data connectors | $(Format-BlueprintCount $connectors.Count) |
| Analytics rules (enabled / total) | $(Format-BlueprintCount $enabledRules.Count) / $(Format-BlueprintCount $rules.Count) |
| MITRE tactics: Covered / Thin / None | $tacticsCoveredFull / $tacticsThin / $tacticsNone of $tacticsTotal$mitreSuffix |
| Tables receiving data ({lookback-d}) | $(Format-BlueprintCount $populatedTables.Count) populated · $(Format-BlueprintCount $operationalTables.Count) operational · $(Format-BlueprintCount $workspaceTables.Count) catalogue |
| Findings (Critical / Warning / Info) | $($gapBySeverity.Critical) / $($gapBySeverity.Warning) / $($gapBySeverity.Info) |
| Maturity (overall / target) | $maturityCell |
| Legacy features still in use | $(@($legacyRows | Where-Object Status -EQ 'In use').Count) of $(@($legacyRows | Where-Object Status -NE 'Not captured').Count) checked; see [02-deprecated-legacy-features.md](02-deprecated-legacy-features.md) |

The findings by severity and the estate flow, from source families through detection to incidents, are on [00-overview.md](00-overview.md).

## Top recommendations

$(if ($top5Findings.Count -gt 0) { "$(Format-TopFindingsLead $top5Findings.Count $gapFindings.Count) with what was found and how to fix it, $(if ($top5Findings.Count -gt 1) { 'are' } else { 'is' }) on [00-overview.md](00-overview.md); [90-gap-analysis.md](90-gap-analysis.md) lists every one." } else { '_No findings: a clean run._' })

## Where to read more

| Concern | See |
|---|---|
| Retirements and legacy features | [02-deprecated-legacy-features.md](02-deprecated-legacy-features.md) |
| What's new and retiring in Sentinel and Defender | [03-whats-new.md](03-whats-new.md) |
| Connectors and ingestion | [10-data-connectors.md](10-data-connectors.md), [83-data-collection.md](83-data-collection.md) |
| Detection coverage | [20-analytics-rules.md](20-analytics-rules.md), [21-rule-performance.md](21-rule-performance.md), [22-rule-health-quality.md](22-rule-health-quality.md), [25-mitre-coverage.md](25-mitre-coverage.md), [28-detection-opportunities.md](28-detection-opportunities.md) |
| Workspace, tables, retention | [80-workspace.md](80-workspace.md), [81-table-plans-retention.md](81-table-plans-retention.md), [89-retention.md](89-retention.md) |
| Cost | [84-cost-estimate.md](84-cost-estimate.md) |
| Operational health | [11-sentinel-health.md](11-sentinel-health.md), [12-soc-optimization.md](12-soc-optimization.md), [15-incidents.md](15-incidents.md), [16-alerts.md](16-alerts.md) |
| Identity and access | [85-rbac.md](85-rbac.md) |
| Findings vs. best practice | [90-gap-analysis.md](90-gap-analysis.md) |
| Maturity and roadmap | [91-maturity-assessment.md](91-maturity-assessment.md) |
"@
    Write-BlueprintSection '01-live-snapshot.md' $execBody

    # Left in the render context for later sections.
    $Context.classicTables01 = $classicTables01
    $Context.clv1Days = $clv1Days
    $Context.has01 = $has01
    $Context.legacyRows = $legacyRows
    $Context.mmaMachines01 = $mmaMachines01
    $Context.tiLegacyRows01 = $tiLegacyRows01
    $Context.tiLegacyRules01 = $tiLegacyRules01
    $Context.tipDays = $tipDays
    $Context.today = $today
    $Context.xdrDays = $xdrDays
}
