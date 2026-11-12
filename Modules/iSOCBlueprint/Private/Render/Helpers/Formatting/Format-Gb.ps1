#Requires -Version 7.6

<#
.SYNOPSIS
    Format a number as a GB figure.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Format-Gb.ps1
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

function Format-Gb {
    # Renders any numeric-ish input as a GB value the way the dashboard
    # does: two decimals with thousands separators (56,941.81), `<0.01`
    # for a tiny non-zero value (Format-BlueprintGb). Empty / null inputs
    # return ''; a non-numeric string comes back as given.
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '' }
    return Format-BlueprintGb $Value
}
