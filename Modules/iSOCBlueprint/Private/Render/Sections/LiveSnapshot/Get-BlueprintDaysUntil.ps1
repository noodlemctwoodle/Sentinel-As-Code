#Requires -Version 7.6

<#
.SYNOPSIS
    Return the days from today until a date.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/LiveSnapshot/Get-BlueprintDaysUntil.ps1
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

function Get-BlueprintDaysUntil {
    param([string]$IsoDate)
    $target = [datetime]::Parse($IsoDate, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
    $delta = $target.ToUniversalTime() - (Get-Date).ToUniversalTime()
    [int][math]::Ceiling($delta.TotalDays)
}
