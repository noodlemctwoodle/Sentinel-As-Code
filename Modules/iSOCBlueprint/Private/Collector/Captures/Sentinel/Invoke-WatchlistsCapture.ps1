#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'watchlists': writes watchlists.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Sentinel/Invoke-WatchlistsCapture.ps1
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

function Invoke-WatchlistsCapture {
    <#
    .SYNOPSIS
        Capture 'watchlists': writes watchlists.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $apiVersions = $Context.apiVersions
    $sentinelScope = $Context.sentinelScope

    # Enumerate watchlist definitions only. Item contents are intentionally not
    # captured, on workspaces with large lookup lists (GeoIP ranges, asset
    # inventories) the per-watchlist /watchlistItems pagination dominates the
    # collector runtime, and the rendered report never embeds item bodies.
    # Watchlist contents in a customer environment are expected to be sourced
    # from the IaC repository (Watchlists/*.csv), not from the live API.
    $wls = Invoke-SentinelRest -Path "$sentinelScope/watchlists" -ApiVersion $apiVersions.Sentinel
    Save-Json -FileName 'watchlists.json' -Data $wls
}
