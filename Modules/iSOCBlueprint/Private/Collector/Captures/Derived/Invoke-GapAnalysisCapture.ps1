#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'gap-analysis': writes gap-analysis.json, gap-checks.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Derived/Invoke-GapAnalysisCapture.ps1
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

function Invoke-GapAnalysisCapture {
    <#
    .SYNOPSIS
        Capture 'gap-analysis': writes gap-analysis.json, gap-checks.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $rawOut = $Context.rawOut
    $engineRoot = $Context.engineRoot

    . (Join-Path $engineRoot 'Private/Get-SentinelGap.ps1')
    $gapOutcomes = [System.Collections.Generic.List[object]]::new()
    $findings = Get-SentinelGap `
        -InputRoot $rawOut `
        -ResourcesRoot (Join-Path $engineRoot 'Private/Resources') `
        -RulesPath (Join-Path $engineRoot 'Private/Resources/best-practices.json') `
        -GapChecksPath (Join-Path $engineRoot 'Private/GapChecks.ps1') `
        -OutcomeCollector $gapOutcomes
    Save-Json -FileName 'gap-analysis.json' -Data $findings
    # One record per rule (Fired / Passed / Errored / Undefined), so a
    # consumer can tell a check that passed from one that never ran.
    $script:GapOutcomes = $gapOutcomes.ToArray()
    Save-Json -FileName 'gap-checks.json' -Data $script:GapOutcomes
}
