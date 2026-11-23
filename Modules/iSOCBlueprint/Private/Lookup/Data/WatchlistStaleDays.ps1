#Requires -Version 7.6

<#
.SYNOPSIS
    The value WatchlistStaleDays the Get-WatchlistFreshness functions read.

.DESCRIPTION
    One of the helpers beside Get-WatchlistFreshness.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Data/WatchlistStaleDays.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file sets a script-scope value rather than running.
#>

$script:WatchlistStaleDays = 90
