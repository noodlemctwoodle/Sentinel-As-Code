#Requires -Version 7.6

<#
.SYNOPSIS
    Return the lookback window the collector captured over.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Window/Get-BlueprintWindow.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

# The window the collector's KQL captures read (run-context.json): every
# capture's lookback, and the recent window (the shorter of 7 days and the
# lookback) its latest-days figures cover. A snapshot collected before the
# setting existed read 30 days and 7. Pages name the window through tokens,
# {lookback}, {lookback-d}, {recent} and {recent-d}, which Write-Section
# fills, so a label, a heading or a chart title follows whatever the run
# read. The "30d", "90d" and "7d" property names in the captures are their
# historical names for the lookback and recent figures.
function Get-BlueprintWindow {
    if ($script:BpWindow) { return $script:BpWindow }
    $rc = Read-BlueprintRaw 'run-context.json'
    $days = 30
    if ($rc -and $rc.PSObject.Properties['LookbackDays'] -and [int]$rc.LookbackDays -ge 1) { $days = [int]$rc.LookbackDays }
    $recent = [math]::Min(7, $days)
    if ($rc -and $rc.PSObject.Properties['RecentDays'] -and [int]$rc.RecentDays -ge 1) { $recent = [int]$rc.RecentDays }
    $script:BpWindow = [pscustomobject]@{ Days = $days; RecentDays = $recent }
    return $script:BpWindow
}
