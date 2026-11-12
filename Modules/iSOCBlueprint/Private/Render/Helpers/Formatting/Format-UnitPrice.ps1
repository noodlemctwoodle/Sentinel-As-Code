#Requires -Version 7.6

<#
.SYNOPSIS
    Format a per-GB unit price.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Format-UnitPrice.ps1
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

# A unit price (per GB) keeps the fourth decimal that Format-BlueprintMoney
# rounds away below 1,000: £2.2642.
function Format-UnitPrice($Amount, [string]$Currency) {
    $d = ConvertTo-BlueprintDouble $Amount
    if ($null -eq $d) { return '' }
    $prefix = (Format-BlueprintMoney 0 $Currency) -replace '0\.00$', ''
    return $prefix + [math]::Round($d, 4).ToString('#,0.00##', [System.Globalization.CultureInfo]::InvariantCulture)
}
