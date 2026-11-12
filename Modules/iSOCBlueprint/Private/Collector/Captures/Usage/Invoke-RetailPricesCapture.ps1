#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'retail-prices': writes retail-prices.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Usage/Invoke-RetailPricesCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Invoke-RetailPricesCapture {
    <#
    .SYNOPSIS
        Capture 'retail-prices': writes retail-prices.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $Currency = $Context.Currency
    $rawOut = $Context.rawOut

    $region = $script:WorkspaceObject.location
    # Auto prices in the currency the region suggests; the report says so.
    $currencyCode = if ($Currency -eq 'Auto') { Resolve-AzureRetailCurrency -Region $region } else { $Currency }
    $prices = Get-AzureRetailPrice -Region $region -OutputRoot $rawOut -CurrencyCode $currencyCode -CurrencySource $(if ($Currency -eq 'Auto') { 'Region' } else { 'Parameter' })
    Save-Json -FileName 'retail-prices.json' -Data $prices
}
