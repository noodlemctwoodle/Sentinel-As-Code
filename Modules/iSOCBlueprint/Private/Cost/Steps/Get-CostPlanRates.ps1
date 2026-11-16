#Requires -Version 7.6

<#
.SYNOPSIS
    Work out the price per GB of each plan from the meter prices.

.DESCRIPTION
    A step of the cost estimate. Steps run in order and pass their results to
    later ones through the estimate context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Cost/Steps/Get-CostPlanRates.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, cost estimate
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-CostPlanRates {
    <#
    .SYNOPSIS
        Work out the price per GB of each plan from the meter prices.

    .PARAMETER Context
        The estimate context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the estimate context.
    $billedModel = $Context.billedModel
    $caveats = $Context.caveats
    $lakeEnrolled = $Context.lakeEnrolled
    $unitPrices = $Context.unitPrices

    # Price per GB by plan. The simplified Sentinel meter, when the price
    # list has it, already includes Log Analytics ingestion.
    $simplified = (Get-CostUnitPrice $unitPrices 'SentinelAnalytics') -gt 0
    $analyticsUnit = if ($simplified) { Get-CostUnitPrice $unitPrices 'SentinelAnalytics' } else { (Get-CostUnitPrice $unitPrices 'AnalyticsLaIngestion') + (Get-CostUnitPrice $unitPrices 'SentinelPremium') }
    if ($billedModel -eq 'Classic' -and $simplified) {
        $caveats += 'The workspace is billed on classic pricing (Microsoft Sentinel analysis and Log Analytics ingestion billed separately), but the price list holds no classic Sentinel meters, so Analytics data is priced at the simplified rate, which can differ from the bill.'
    }
    $basicUnit = if ((Get-CostUnitPrice $unitPrices 'SentinelBasic') -gt 0) { Get-CostUnitPrice $unitPrices 'SentinelBasic' } else { Get-CostUnitPrice $unitPrices 'BasicIngestion' }
    $lakeUnit = (Get-CostUnitPrice $unitPrices 'DataLakeIngestion') + (Get-CostUnitPrice $unitPrices 'DataLakeProcessing')
    $auxUnit = if ($lakeEnrolled -and $lakeUnit -gt 0) { $lakeUnit } else { (Get-CostUnitPrice $unitPrices 'SentinelAuxiliary') + (Get-CostUnitPrice $unitPrices 'AuxiliaryIngestion') }
    # Older property names, kept for any caller reading them.
    $unitPrices.AnalyticsIngestionPerGb = $analyticsUnit
    $unitPrices.BasicIngestionPerGb     = $basicUnit
    $unitPrices.AuxiliaryIngestionPerGb = $auxUnit
    $unitPrices.DataLakeIngestionPerGb  = $lakeUnit

    # Left for the steps after this one.
    $Context.simplified = $simplified
    $Context.analyticsUnit = $analyticsUnit
    $Context.basicUnit = $basicUnit
    $Context.lakeUnit = $lakeUnit
    $Context.auxUnit = $auxUnit
    $Context.caveats = $caveats
}
