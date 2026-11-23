#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 12-soc-optimization.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/SocOptimization/Write-BlueprintSocOptimizationSection.ps1
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
function Write-BlueprintSocOptimizationSection {
    <#
    .SYNOPSIS
        Build the figures for and write 12-soc-optimization.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $m = $Context.m
    $n = $Context.n

    # Section 12 — SOC Optimization Insights (TOC 4.9)
    # Schema note: recommendation objects expose properties.recommendationTypeId
    # (e.g. "Precision_Coverage", "Precision_DataValue"). AffectedItem comes from
    # properties.additionalProperties on a per-kind basis (TableName for DataValue,
    # UseCaseName for Coverage). Split into two sub-tables grouped by kind so the
    # user-action drivers cluster — Coverage rows drive content-hub installs,
    # DataValue rows drive ingestion-tuning.
    $socOpt = Read-BlueprintRawArray 'soc-optimization.json'
    $socCovRows = $socOpt | Where-Object { $_.properties.recommendationTypeId -eq 'Precision_Coverage' } | ForEach-Object { Format-BlueprintSocOptRow $_ 'UseCaseName' }
    $socDvRows = $socOpt | Where-Object { $_.properties.recommendationTypeId -eq 'Precision_DataValue' } | ForEach-Object { Format-BlueprintSocOptRow $_ 'TableName' }
    $socOther = $socOpt | Where-Object { $_.properties.recommendationTypeId -notin @('Precision_Coverage', 'Precision_DataValue') } | ForEach-Object {
        [pscustomobject]@{
            Kind        = $_.properties.recommendationTypeId
            Title       = $_.properties.title
            State       = $_.properties.state
            Description = ($_.properties.description -replace '\s+', ' ')
        }
    }
    # Chart input: bucket recommendations by category for the headline pie.
    $socCategoryCounts = [ordered]@{
        'Coverage'   = $socCovRows.Count
        'Data Value' = $socDvRows.Count
        'Other'      = $socOther.Count
    }
    $socPieRows = $socCategoryCounts.GetEnumerator() | ForEach-Object {
        "    `"$($_.Key)`" : $($_.Value)"
    }
    $socTotal = $socCategoryCounts.Values | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    $socChartBlock = if ($socTotal -gt 0) {
        @"

## Recommendation mix

``````mermaid
pie showData title SOC Optimization recommendations by category
$($socPieRows -join [Environment]::NewLine)
``````

$(Format-BlueprintCount $socTotal) recommendations grouped by what action they drive. Coverage = onboard content; Data Value = tune ingestion; Other = MITRE tagging, UEBA, customers-like-me.
"@
    } else { '' }

    Write-BlueprintSection '12-soc-optimization.md' (@"
$(Format-Banner -Title "SOC Optimization Insights  (TOC 4.9)")

Recommendations from the SOC Optimization service (preview). The endpoint is empty on workspaces where the service has not run, or in regions where it is not yet available. Recommendations are grouped by the kind of action they drive.
$socChartBlock

> Before tuning based on these recommendations, cross-reference [21-rule-performance.md](21-rule-performance.md): the highest-volume rules are usually the right place to start, regardless of which row of this section flagged them.

## Coverage recommendations

Drives Content Hub installs and rule activation. AffectedItem is the use-case name (e.g. ``BEC (Financial Fraud)``).

$(Format-BlueprintTable -Items $socCovRows -Columns 'Title','AffectedItem','State','Description')

## Data Value recommendations

Drives ingestion tuning. AffectedItem is the workspace table name. A high count here is a sign that data is arriving but no detection coverage is matching it.

$(Format-BlueprintTable -Items $socDvRows -Columns 'Title','AffectedItem','State','Description')

## Other recommendations

$(Format-BlueprintTable -Items $socOther -Columns 'Kind','Title','State','Description')

[SOC optimization in Microsoft Sentinel (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/soc-optimization/soc-optimization-access)
"@)
}
