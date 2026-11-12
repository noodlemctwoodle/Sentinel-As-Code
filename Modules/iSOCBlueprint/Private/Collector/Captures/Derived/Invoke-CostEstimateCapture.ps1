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
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

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
    $engineRoot = $Context.engineRoot

    . (Join-Path $engineRoot 'Private/Get-SentinelCostEstimate.ps1')
    $est = Get-SentinelCostEstimate -InputRoot $rawOut -ResourcesRoot (Join-Path $engineRoot 'Private/Resources')
    Save-Json -FileName 'cost-estimate.json' -Data $est
}
