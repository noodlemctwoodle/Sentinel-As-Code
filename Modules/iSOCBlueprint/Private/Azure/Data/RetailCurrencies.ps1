#Requires -Version 7.6

<#
.SYNOPSIS
    The currencies the Retail Prices API prices in.

.DESCRIPTION
    One of the helpers beside Get-AzureRetailPrice.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Azure/Data/RetailCurrencies.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-05-06
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file sets a script-scope value rather than running.
#>

# The currencies the Retail Prices API prices in.
$script:RetailCurrencies = @('USD', 'AUD', 'BRL', 'CAD', 'CHF', 'CNY', 'DKK', 'EUR', 'GBP', 'INR', 'JPY', 'KRW', 'NOK', 'NZD', 'RUB', 'SEK', 'TWD')
