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
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Resolve-BlueprintWindowText {
    <#
    .SYNOPSIS
        Fill the window placeholders in a piece of text.

    .DESCRIPTION
        {lookback} and {recent} become a number of days in words ("30 days", "1
        day"); {lookback-d} and {recent-d} become the short form ("30d"). Text with
        no placeholder is returned as it is.

    .PARAMETER Text
        The text that may hold placeholders.

    .OUTPUTS
        [string].
    #>
    [CmdletBinding()]
    param([string]$Text)
    if (-not $Text -or $Text.IndexOf('{') -lt 0) { return $Text }
    $w = Get-BlueprintWindow
    $words = { param([int]$n) if ($n -eq 1) { '1 day' } else { "$n days" } }
    return $Text.Replace('{lookback-d}', "$($w.Days)d").Replace('{recent-d}', "$($w.RecentDays)d").Replace('{lookback}', (& $words $w.Days)).Replace('{recent}',
        (& $words $w.RecentDays))
}
