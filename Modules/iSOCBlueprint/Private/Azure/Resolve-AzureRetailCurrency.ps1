#Requires -Version 7.6

<#
.SYNOPSIS
    The currency a workspace in this region is most likely billed in

.DESCRIPTION
    One of the helpers beside Get-AzureRetailPrice.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Azure/Resolve-AzureRetailCurrency.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-05-06
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Resolve-AzureRetailCurrency {
    <#
    .SYNOPSIS
        The currency a workspace in this region is most likely billed in.

    .DESCRIPTION
        A best guess from the region's country for -Currency Auto: billing
        currency follows the billing account's country, not the region, and
        the collector cannot read the billing account. UK regions give GBP,
        the euro-area and other EU regions EUR, Switzerland CHF, Norway NOK,
        Denmark DKK, Canada CAD, Brazil BRL, Australia AUD, New Zealand NZD,
        Japan JPY, Korea KRW, India INR, Taiwan TWD and China CNY; every other
        region, and an unknown one, USD.

    .PARAMETER Region
        The Azure ARM region name (e.g. 'uksouth').

    .OUTPUTS
        [string] A currency code the Retail Prices API supports.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $false)] [AllowEmptyString()] [string]$Region)

    switch -Regex (("$Region").ToLowerInvariant()) {
        '^uk'                                                   { return 'GBP' }
        '^switzerland'                                          { return 'CHF' }
        '^norway'                                               { return 'NOK' }
        '^denmark'                                              { return 'DKK' }
        '^(westeurope|northeurope|france|germany|italy|spain|sweden|poland|austria|belgium|finland|greece)' { return 'EUR' }
        '^canada'                                               { return 'CAD' }
        '^brazil'                                               { return 'BRL' }
        '^australia'                                            { return 'AUD' }
        '^newzealand'                                           { return 'NZD' }
        '^japan'                                                { return 'JPY' }
        '^korea'                                                { return 'KRW' }
        '^(centralindia|southindia|westindia|jioindia)'         { return 'INR' }
        '^taiwan'                                               { return 'TWD' }
        '^china'                                                { return 'CNY' }
        default                                                 { return 'USD' }
    }
}
