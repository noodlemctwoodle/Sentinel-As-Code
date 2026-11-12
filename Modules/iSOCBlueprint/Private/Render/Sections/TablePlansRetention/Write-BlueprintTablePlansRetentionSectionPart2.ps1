#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 81-table-plans-retention.md (part 2 of 2).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/TablePlansRetention/Write-BlueprintTablePlansRetentionSectionPart2.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintTablePlansRetentionSectionPart2 {
    <#
    .SYNOPSIS
        Build the figures for and write 81-table-plans-retention.md (part 2 of 2).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $active = $Context.active
    $catalogueOnly = $Context.catalogueOnly
    $catalogueOnlyRows = $Context.catalogueOnlyRows
    $classicBlock = $Context.classicBlock
    $coverageBlock = $Context.coverageBlock
    $gbByPlan = $Context.gbByPlan
    $m = $Context.m
    $n = $Context.n
    $orphans = $Context.orphans
    $planPieAnalytics = $Context.planPieAnalytics
    $planPieAuxiliary = $Context.planPieAuxiliary
    $planPieBasic = $Context.planPieBasic
    $silent = $Context.silent
    $silentDetail = $Context.silentDetail
    $tableRows = $Context.tableRows
    $workspaceTables = $Context.workspaceTables

    $tablePlansBody = @"
$(Format-Banner -Title "Table Plans, Retention and Activity")

## Plan adoption

``````mermaid
pie showData title Operational tables by plan
    "Analytics" : $planPieAnalytics
    "Basic" : $planPieBasic
    "Auxiliary" : $planPieAuxiliary
``````

[SAC-LOG-02] flags high-volume Analytics tables that could move to Basic / Auxiliary for cost savings; this chart shows the current tier distribution at a glance.

The workspace catalogue carries every Microsoft-defined table schema regardless of whether your tenant has onboarded a source for it, typically several hundred. This section focuses on the **operational** subset: tables that have actually received data in the last {lookback} plus all custom (``CustomLog``) tables. The full catalogue counts are at the bottom.

| | |
|---|---:|
| Operational tables shown below | $(Format-BlueprintCount $tableRows.Count) |
| Catalogue-only Microsoft schemas (never ingested, hidden) | $(Format-BlueprintCount $catalogueOnly.Count) |
| Total tables in workspace | $(Format-BlueprintCount $workspaceTables.Count) |

## Summary by plan

$(Format-BlueprintTable -Items $gbByPlan -Columns 'Plan','Tables','Gb90d')

## Operational tables

$(Format-BlueprintTable -Items ($tableRows | Sort-Object -Property Gb90d -Descending) -Columns 'Name','Plan','Interactive','Total','Archive','Type','Gb90d','Last24h','LastIngested')

## Active (received data in last 24h)

Total: **$(Format-BlueprintPlural $active.Count 'table')**.

## Silent (had data in {lookback-d}, nothing in last 24h)

Total: **$(Format-BlueprintPlural $silent.Count 'table')**, likely connector breakage.
$silentDetail

## Orphan custom tables (no data in {lookback-d})

Total: **$(Format-BlueprintCount $orphans.Count)** custom ``_CL`` $(Format-BlueprintPlural $orphans.Count 'table' -NoCount): delete candidates or never-onboarded sources. Microsoft pre-defined tables without data are catalogue entries, not orphans, and are excluded from this list.

## Catalogue-only Microsoft schemas

$(Format-BlueprintCount $catalogueOnly.Count) Microsoft pre-defined table schemas never received data in the last {lookback}. These are part of every workspace's table catalogue and don't represent a deployment problem. ``Connector`` is the data connector that would fill the table, from the connector catalogue (see [10-data-connectors.md](10-data-connectors.md)): the connectors that list it when there are at most three, otherwise how many share it; blank for a table no Content Hub connector writes.

$(Format-BlueprintTable -Items $catalogueOnlyRows -Columns 'Table','Connector')

## Classic custom tables (legacy Data Collector API)

Custom tables created through the HTTP Data Collector API or the Microsoft Monitoring Agent custom-log path (``tableSubType = Classic``) rather than a data collection rule. The Data Collector API retires on 14 Sep 2026; a classic table that still receives data needs a DCR and the Logs Ingestion API before then, and one that rules depend on is a detection outage waiting to happen.

$classicBlock

## Tables by detection coverage

Operational tables with data in the last {lookback}, the number of enabled Sentinel analytics rules that read each one and the number of enabled Defender XDR custom detections that query it (from the Graph detection-rules capture; blank when that capture did not run). A high-volume table with no rules is cost without coverage; [28-detection-opportunities.md](28-detection-opportunities.md) lists the templates that would cover it.

$coverageBlock

Retention per table, with the workspace-level retention checks and what rolls into the lake, is in [89-retention.md](89-retention.md).

[Table plans (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/logs/logs-table-plans) · [Retention & archive](https://learn.microsoft.com/azure/azure-monitor/logs/data-retention-archive) · [Manage table tiers in Sentinel](https://learn.microsoft.com/azure/sentinel/manage-table-tiers-retention)
"@
    Write-BlueprintSection '81-table-plans-retention.md' $tablePlansBody
}
