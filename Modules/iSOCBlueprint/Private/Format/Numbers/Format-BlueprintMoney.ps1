#Requires -Version 7.6

<#
.SYNOPSIS
    An amount as the dashboard's fmtMoney writes it: the currency's symbol, whole units from 1,000 and two decimal places below (£137,356, £572.31, -£4.10).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Format/Numbers/Format-BlueprintMoney.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Blueprint text formatting
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-BlueprintMoney {
    <#
    .SYNOPSIS
        An amount as the dashboard's fmtMoney writes it: the currency's
        symbol, whole units from 1,000 and two decimal places below
        (£137,356, £572.31, -£4.10).

    .PARAMETER Amount
        The amount, as a number or numeric string.

    .PARAMETER Currency
        The ISO 4217 code (GBP, USD, EUR). Without one the figure has no
        symbol.

    .OUTPUTS
        [string]; the input as text when it is not a number, '' for $null.
    #>
    [CmdletBinding()]
    param([AllowNull()] $Amount, [AllowNull()] [AllowEmptyString()] [string] $Currency)
    $d = ConvertTo-BlueprintDouble $Amount
    if ($null -eq $d) { return $(if ($null -eq $Amount) { '' } else { [string]$Amount }) }
    $places = if ([math]::Abs($d) -ge 1000) { 0 } else { 2 }
    $figure = Format-BlueprintNumber -Value ([math]::Abs($d)) -Decimals $places
    $code = ([string]$Currency).Trim().ToUpperInvariant()
    $sign = if ($d -lt 0 -and [double]$figure.Replace(',', '') -ne 0) { '-' } else { '' }
    if (-not $code) { return "$sign$figure" }
    if ($script:BlueprintCurrencySymbol.ContainsKey($code)) { return "$sign$($script:BlueprintCurrencySymbol[$code])$figure" }
    "$sign$code $figure"
}
