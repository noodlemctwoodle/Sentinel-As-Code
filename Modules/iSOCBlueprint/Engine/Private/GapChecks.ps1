#Requires -Version 7.6

<#
.SYNOPSIS
    Loads the gap-analysis check functions, one per row in best-practices.json.

.DESCRIPTION
    Dot-source this file to define every check. The functions themselves live
    one per file under Modules/iSOCBlueprint/Private/Gap:

      Checks/<Area>/Test-*.ps1   one check per rule, grouped by the rule id
                                 prefix (Logging for SAC-LOG-nn, and so on)
      Helpers/                   the finding shape, property reads, the
                                 lookback window and the KQL cell converters
      Data/                      the values the checks share

    Each check takes a single $Inventory parameter, the in-memory object built by
    Get-SentinelGap from the _raw/ JSON files, and returns either:

      $null                   : no gap detected (rule passes)
      [pscustomobject]@{...}  : a finding with Evidence + Detail fields

    Adding a new rule is a two-step process: drop a Test-* file under
    Private/Gap/Checks/<Area>, add a row to best-practices.json that references
    it by name. The engine wires the rest.

.NOTES
    File:           Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1
    Repository:     Sentinel-As-Code
    Author:         noodlemctwoodle
    Website:        https://sentinel.blog
    Created:        2026-05-06
    Version:        0.9.0
    Last Updated:   2026-11-12
    Component:      iSOC Blueprint, Gap Engine
    Requires:       PowerShell 7.6+

    This file loads functions rather than running. Per-parameter detail
    lives on each Test-* function's own help block.

    Credit and thanks: the gap rules ported from the health check's
    checks are based on the Sentinel health-check script by thinkndle,
    kindly given to the Sentinel-As-Code project. Thank you, thinkndle,
    for sharing your work so generously; it shaped much of the
    Blueprint's health, coverage and maturity reporting.
#>

Set-StrictMode -Version Latest

# Counts, GB, money, dates and plurals written as the dashboard writes them.
. (Join-Path $PSScriptRoot 'Format-BlueprintText.ps1')
# The connector catalogue helpers (SAC-PLT-10 reads the catalogue).
. (Join-Path $PSScriptRoot 'Get-ConnectorCatalogue.ps1')
# Watchlist freshness (SAC-DET-15), shared with the watchlists page.
. (Join-Path $PSScriptRoot 'Get-WatchlistFreshness.ps1')
# Recent hunts and bookmarks (SAC-HNT-01), shared with the maturity metrics.
. (Join-Path $PSScriptRoot 'Get-HuntingActivity.ps1')

# The check functions and their helpers (the module's own Private/Gap, two
# folders up from here), defined in the caller's scope.
$gapCheckRoot = Join-Path $PSScriptRoot '..' '..' 'Private' 'Gap'
foreach ($gapCheckFile in Get-ChildItem -LiteralPath $gapCheckRoot -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
    . $gapCheckFile.FullName
}
Remove-Variable -Name gapCheckFile, gapCheckRoot
