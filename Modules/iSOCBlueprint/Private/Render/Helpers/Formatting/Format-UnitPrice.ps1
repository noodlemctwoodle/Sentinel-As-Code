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
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-UnitPrice {
    <#
    .SYNOPSIS
        Format a per-GB unit price.

    .DESCRIPTION
        A unit price (per GB) keeps the fourth decimal that Format-BlueprintMoney
        rounds away below 1,000 (for example 2.2642). Returns an empty string
        when Amount is not a number. Otherwise the currency prefix that
        Format-BlueprintMoney writes, followed by the amount rounded to four
        decimals, written with at least two decimals and thousands separators.

    .PARAMETER Amount
        The price, as a number or numeric text.

    .PARAMETER Currency
        The currency code, passed to Format-BlueprintMoney to get the prefix.

    .OUTPUTS
        [string].
    #>
    [CmdletBinding()]
    param($Amount, [string]$Currency)
    $d = ConvertTo-BlueprintDouble $Amount
    if ($null -eq $d) { return '' }
    $prefix = (Format-BlueprintMoney 0 $Currency) -replace '0\.00$', ''
    return $prefix + [math]::Round($d, 4).ToString('#,0.00##', [System.Globalization.CultureInfo]::InvariantCulture)
}
