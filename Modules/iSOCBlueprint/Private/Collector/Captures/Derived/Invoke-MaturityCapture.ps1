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
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

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
    $engineRoot = $Context.engineRoot

    $maturity = Get-SentinelMaturity `
        -InputRoot $rawOut `
        -ResourcesRoot (Join-Path $engineRoot 'Private/Resources') `
        -CriteriaPath (Join-Path $engineRoot 'Private/Resources/maturity-criteria.json') `
        -GapOutcomes $script:GapOutcomes `
        -TargetLevel $TargetMaturityLevel
    Save-Json -FileName 'maturity.json' -Data $maturity
}
