#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'hunts': writes hunts.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Sentinel/Invoke-HuntsCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-HuntsCapture {
    <#
    .SYNOPSIS
        Capture 'hunts': writes hunts.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $apiVersions = $Context.apiVersions
    $sentinelScope = $Context.sentinelScope

    # Hunts exist only on preview api-versions. A tenant or region that does
    # not serve them answers 4xx, which Invoke-SentinelRest throws and
    # Invoke-CaptureAttempt reports, so no file is written and consumers treat hunting
    # activity as unknown rather than as absent.
    $hunts = Invoke-SentinelRest -Path "$sentinelScope/hunts" -ApiVersion $apiVersions.SentinelPreview
    Save-Json -FileName 'hunts.json' -Data $hunts
}
