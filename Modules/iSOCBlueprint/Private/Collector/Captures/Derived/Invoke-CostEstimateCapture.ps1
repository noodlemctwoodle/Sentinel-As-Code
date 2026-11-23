#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'cost-estimate': writes cost-estimate.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Derived/Invoke-CostEstimateCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-CostEstimateCapture {
    <#
    .SYNOPSIS
        Capture 'cost-estimate': writes cost-estimate.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $rawOut = $Context.rawOut
    $resourcesFolder = $Context.resourcesFolder

    $est = Get-SentinelCostEstimate -InputRoot $rawOut -ResourcesRoot (Join-Path $resourcesFolder 'Data')
    Save-Json -FileName 'cost-estimate.json' -Data $est
}
