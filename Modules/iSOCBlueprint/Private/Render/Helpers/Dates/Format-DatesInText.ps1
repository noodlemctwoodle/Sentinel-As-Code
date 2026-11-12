#Requires -Version 7.6

<#
.SYNOPSIS
    Rewrite the ISO dates in a piece of text the way the report writes dates.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Dates/Format-DatesInText.ps1
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

function Format-DatesInText([string]$Text) {
    if (-not $Text) { return $Text }
    $parts = [regex]::Split($Text, '(`[^`]*`)')
    $isoRx = '(?<![\w.:/-])(\d{4})-(\d{2})-(\d{2})(?<time>[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]00:?00)?)?(?![\w:-])'
    $longRx = '\b(\d{1,2}) (January|February|March|April|June|July|August|September|Sept|October|November|December)\b'
    for ($i = 0; $i -lt $parts.Count; $i++) {
        if ($parts[$i].StartsWith('`')) { continue }
        $parts[$i] = [regex]::Replace($parts[$i], $isoRx, {
            param($m)
            $month = [int]$m.Groups[2].Value; $day = [int]$m.Groups[3].Value
            if ($month -lt 1 -or $month -gt 12 -or $day -lt 1 -or $day -gt 31) { return $m.Value }
            if ($m.Groups['time'].Success) { return Format-BlueprintDate $m.Value -Time }
            Format-BlueprintDate $m.Value
        })
        $parts[$i] = [regex]::Replace($parts[$i], $longRx, { param($m) "$($m.Groups[1].Value) $($script:ShortMonth[$m.Groups[2].Value])" })
    }
    return -join $parts
}
