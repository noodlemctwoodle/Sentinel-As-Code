#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 89-retention.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Retention/Write-BlueprintRetentionSection.ps1
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
function Write-BlueprintRetentionSection {
    <#
    .SYNOPSIS
        Build the figures for and write 89-retention.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $found = $Context.found
    $m = $Context.m
    $n = $Context.n
    $retentionChartBlock = $Context.retentionChartBlock
    $tableRows = $Context.tableRows
    $workspace = $Context.workspace

    # Section 89: retention. The workspace-level checks and per-table overrides
    # (formerly on section 81) and the retention that rolls into the lake
    # (formerly on section 88), in one place.
    $retentionLakeBlock = if ($retentionChartBlock) { $retentionChartBlock } else {
        @'

## Retention that rolls into the lake

_No table keeps data beyond its analytics retention, so nothing rolls into the lake or into long-term retention._
'@
    }
    $retentionBody = @"
$(Format-Banner -Title 'Data Retention')

How long each table keeps its data and whether the workspace is set up to keep it cheaply. Analytics retention is the period a table stays fully queryable; total retention adds long-term retention beyond it, which bills against the data lake storage meter once the tenant is on the data lake. Table plans are in [81-table-plans-retention.md](81-table-plans-retention.md) and the data lake in [88-sentinel-data-lake.md](88-sentinel-data-lake.md).

## Retention recommendations

The three workspace-level retention checks, each shown whether or not it needs action.

$( $defaultRet = [int](Get-BlueprintRawProperty $workspace.properties 'retentionInDays' 0)
   $cheaperTier = @($tableRows | Where-Object { [string]$_.Plan -in @('Basic', 'Auxiliary', 'DataLake') })
   $overrides = @($tableRows | Where-Object { [string]$_.Interactive -and ([int]$_.Interactive) -ne $defaultRet })
   $retRecs = @(
       [pscustomobject]@{
           Check = 'Default retention covers the free 90 days'
           Status = $(if ($defaultRet -lt 90) { 'Action needed' } else { 'OK' })
           Detail = "Workspace default is $(Format-BlueprintPlural $defaultRet 'day')."
           Recommendation = 'Raise the default to at least 90 days: the first 90 days of retention are included with Microsoft Sentinel ([SAC-LOG-07]).'
       }
       [pscustomobject]@{
           Check = 'Long retention uses a cheaper tier'
           Status = $(if ($defaultRet -gt 90 -and $cheaperTier.Count -eq 0) { 'Action needed' } else { 'OK' })
           Detail = "Default $(Format-BlueprintPlural $defaultRet 'day'); $(Format-BlueprintPlural $cheaperTier.Count 'table') on the Basic, Auxiliary or data lake plan."
           Recommendation = 'Move high-volume tables that few rules read to the data lake tier, which bills well below the Analytics rate and keeps data for up to 12 years.'
       }
       [pscustomobject]@{
           Check = 'Long retention is set per table'
           Status = $(if ($defaultRet -gt 180 -and $overrides.Count -eq 0) { 'Action needed' } else { 'OK' })
           Detail = "Default $(Format-BlueprintPlural $defaultRet 'day'); $(Format-BlueprintPlural $overrides.Count 'table') $(if ($overrides.Count -eq 1) { 'overrides' } else { 'override' }) it."
           Recommendation = 'Keep the default short and extend retention only on the tables that need it, rather than holding every table for the longest period any one of them needs.'
       }
   )
   Format-BlueprintTable -Items $retRecs -Columns 'Check','Status','Detail','Recommendation' )

## Tables with non-default retention

Tables where the Interactive or Total retention setting differs from the workspace default ($(Format-BlueprintPlural $workspace.properties.retentionInDays 'day')) AND that have received billable data in the last {lookback}. A workspace with hundreds of rows here is usually leaking budget on long-retention tables that should be on the cheaper Archive plan.

$( $nonDefaultRows = @($tableRows | Where-Object {
        ($_.Interactive -ne $workspace.properties.retentionInDays -or $_.Total -ne $workspace.properties.retentionInDays) -and ($_.Gb90d -gt 0)
    } | Sort-Object -Property Gb90d -Descending)
   Format-BlueprintTable -Items $nonDefaultRows -Columns 'Name','Plan','Interactive','Total','Archive','Gb90d' )
$retentionLakeBlock

[Data retention (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/logs/data-retention-configure) · [Manage data tiers and retention in Sentinel](https://learn.microsoft.com/azure/sentinel/manage-data-overview)
"@
    Write-BlueprintSection '89-retention.md' $retentionBody
}
