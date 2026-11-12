#Requires -Version 7.6

<#
.SYNOPSIS
    Fill the window placeholders in a piece of text.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Window/Resolve-BlueprintWindowText.ps1
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

function Resolve-BlueprintWindowText([string]$Text) {
    if (-not $Text -or $Text.IndexOf('{') -lt 0) { return $Text }
    $w = Get-BlueprintWindow
    $words = { param([int]$n) if ($n -eq 1) { '1 day' } else { "$n days" } }
    return $Text.Replace('{lookback-d}', "$($w.Days)d").Replace('{recent-d}', "$($w.RecentDays)d").Replace('{lookback}', (& $words $w.Days)).Replace('{recent}', (& $words $w.RecentDays))
}
