#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'metadata': writes metadata.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Sentinel/Invoke-MetadataCapture.ps1
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

function Invoke-MetadataCapture {
    <#
    .SYNOPSIS
        Capture 'metadata': writes metadata.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $apiVersions = $Context.apiVersions
    $sentinelScope = $Context.sentinelScope

    $meta = Invoke-SentinelRest -Path "$sentinelScope/metadata" -ApiVersion $apiVersions.Sentinel
    Save-Json -FileName 'metadata.json' -Data $meta
}
