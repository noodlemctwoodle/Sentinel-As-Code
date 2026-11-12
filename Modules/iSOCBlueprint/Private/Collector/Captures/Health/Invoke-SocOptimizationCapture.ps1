#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'soc-optimization': writes soc-optimization.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Health/Invoke-SocOptimizationCapture.ps1
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

function Invoke-SocOptimizationCapture {
    <#
    .SYNOPSIS
        Capture 'soc-optimization': writes soc-optimization.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $apiVersions = $Context.apiVersions
    $sentinelScope = $Context.sentinelScope

    # Sentinel SOC Optimization recommendations (preview surface). The endpoint
    # only exists when the workspace is onboarded and the recommendations
    # service has run at least once. 4xx is treated as 'no recommendations'.
    try {
        $opt = Invoke-SentinelRest -Path "$sentinelScope/recommendations" -ApiVersion $apiVersions.SentinelPreview
        Save-Json -FileName 'soc-optimization.json' -Data $opt
    } catch {
        Skip-Capture -FileName 'soc-optimization.json' -ErrorRecord $_
    }
}
