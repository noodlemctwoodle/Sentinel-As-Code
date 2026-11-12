#Requires -Version 7.6

<#
.SYNOPSIS
    Return the UTC yyyy-MM-dd of a date-like value.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Dates/Get-IsoDay.ps1
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

function Get-IsoDay {
    # yyyy-MM-dd (UTC) of a date-ish value: the form a sort or a
    # machine-readable field wants, never page text. Unparseable inputs
    # come back as given.
    param($Value)
    if ($null -eq $Value) { return '' }
    $utc = ConvertTo-UtcDateTime $Value
    if ($null -eq $utc) { return [string]$Value }
    return $utc.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
}
