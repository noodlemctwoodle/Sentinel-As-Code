#Requires -Version 7.6

<#
.SYNOPSIS
    The lookback and recent window the KQL captures read, with their defaults.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Window/Get-GapWindow.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# ------------------------------------------------------------
# The window the KQL captures read
# ------------------------------------------------------------
# Every capture reads the run's lookback (run-context.json, carried on the
# inventory as Window.Days), and the latest days within it the recent
# window (Window.RecentDays). A run collected before the setting existed
# read 30 days and 7. A finding names the window it judged; a threshold set
# per 30 days compares a 30-day-equivalent rate, so it holds whatever the
# lookback. The "30d", "90d" and "7d" property names in tables-with-data
# and the other captures are their historical names for the lookback and
# recent figures.
function Get-GapWindow {
    param($Inventory)
    $w = if ($null -ne $Inventory) { Get-PropOrDefault $Inventory 'Window' $null } else { $null }
    $days = if ($w) { [int](Get-PropOrDefault $w 'Days' 30) } else { 30 }
    if ($days -lt 1) { $days = 30 }
    $recent = if ($w) { [int](Get-PropOrDefault $w 'RecentDays' ([math]::Min(7, $days))) } else { [math]::Min(7, $days) }
    [pscustomobject]@{ Days = $days; RecentDays = $recent }
}
