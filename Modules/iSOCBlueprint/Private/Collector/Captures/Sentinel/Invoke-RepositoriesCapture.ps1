#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'repositories': writes repositories.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Sentinel/Invoke-RepositoriesCapture.ps1
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

function Invoke-RepositoriesCapture {
    <#
    .SYNOPSIS
        Capture 'repositories': writes repositories.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $apiVersions = $Context.apiVersions
    $sentinelScope = $Context.sentinelScope

    # sourceControls is published on a different api-version cadence than the
    # rest of Sentinel. The Sentinel GA pin '2024-09-01' returns
    # UnsupportedApiVersion against ARM. Try the GA Sentinel pin first, then
    # known-good fallbacks for sourceControls specifically. Treat all 4xx as
    # 'feature not present' rather than a failure.
    $repos = $null
    foreach ($v in @($apiVersions.Sentinel, '2023-11-01', '2023-06-01-preview', '2022-12-01-preview')) {
        try {
            $repos = Invoke-SentinelRest -Path "$sentinelScope/sourceControls" -ApiVersion $v
            break
        } catch {
            $repos = $null
        }
    }
    Save-Json -FileName 'repositories.json' -Data $repos
}
