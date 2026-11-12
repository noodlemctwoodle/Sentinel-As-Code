#Requires -Version 7.6

<#
.SYNOPSIS
    Convert a date-like value to a UTC datetime, or $null when it is not one.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Dates/ConvertTo-UtcDateTime.ps1
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

function ConvertTo-UtcDateTime {
    # The UTC [datetime] of a date-ish value, or $null when it is not one:
    # the sort key to keep beside Format-DateUtc text, which does not sort
    # as time ("9 Oct" falls after "15 Oct").
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
        return $parsed.ToUniversalTime()
    }
    return $null
}
