#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'maturity': writes maturity.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Derived/Invoke-MaturityCapture.ps1
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

function Invoke-MaturityCapture {
    <#
    .SYNOPSIS
        Capture 'maturity': writes maturity.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $rawOut = $Context.rawOut
    $TargetMaturityLevel = $Context.TargetMaturityLevel
    $resourcesFolder = $Context.resourcesFolder

    $maturity = Get-SentinelMaturity `
        -InputRoot $rawOut `
        -ResourcesRoot (Join-Path $resourcesFolder 'Data') `
        -CriteriaPath (Join-Path $resourcesFolder 'Data/maturity-criteria.json') `
        -GapOutcomes $script:GapOutcomes `
        -TargetLevel $TargetMaturityLevel
    Save-Json -FileName 'maturity.json' -Data $maturity
}
