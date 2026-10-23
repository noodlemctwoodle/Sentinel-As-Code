#Requires -Version 7.2

<#
.SYNOPSIS
    Anonymous client for the Azure Retail Prices API with on-disk caching.

.DESCRIPTION
    Pulls Sentinel and Log Analytics meter prices for the workspace's region. The Retail
    Prices API is anonymous, no auth header needed, so this client uses Invoke-RestMethod
    directly rather than going through Az context.

    Results are cached on disk under the OutputRoot keyed by (region + day) so a same-day
    re-run doesn't refetch. The cost-estimate methodology in 84-cost-estimate.md cites the
    timestamp of the cache file.

    Pagination: the API returns 1000 items per page; follow NextPageLink until exhausted.

.PARAMETER Region
    The Azure ARM region name of the Sentinel workspace (e.g. 'uksouth').

.PARAMETER OutputRoot
    Folder where retail-prices.json should be written. Typically the workspace _raw root.

.PARAMETER CurrencyCode
    The currency to price in, one the Retail Prices API supports. Defaults
    to USD, the API's own default. Resolve-AzureRetailCurrency picks one
    from the region when the run asks for Auto.

.PARAMETER CurrencySource
    Where the currency came from ('Region' or 'Parameter'), recorded with
    the prices so the report can say. Defaults to 'Parameter'.

.PARAMETER ServiceNames
    Service names to filter on. Defaults to the two Sentinel-relevant services:
    'Sentinel' (the simplified analysis, Basic, Auxiliary and data lake meters
    and every commitment tier's daily price) and 'Log Analytics' (the classic
    ingestion meters). The Retail Prices API names the service 'Sentinel';
    'Microsoft Sentinel' matches nothing. Override to extend the cost
    calculator (e.g. include 'Storage' for archive).

.OUTPUTS
    [pscustomobject] with FetchedAtUtc, Region, Currency, CurrencySource,
    Services, and a Prices array holding the union of all returned price
    rows.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/Get-AzureRetailPrice.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-05-06
    Version:      0.3.0
    Last Updated: 2026-10-14
    Requires:     PowerShell 7.2+

    Endpoint:
        https://prices.azure.com/api/retail/prices

.LINK
    https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices
#>

# The currencies the Retail Prices API prices in.
$script:RetailCurrencies = @('USD', 'AUD', 'BRL', 'CAD', 'CHF', 'CNY', 'DKK', 'EUR', 'GBP', 'INR', 'JPY', 'KRW', 'NOK', 'NZD', 'RUB', 'SEK', 'TWD')

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

function Get-AzureRetailPrice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Region,

        [Parameter(Mandatory = $true)]
        [string]$OutputRoot,

        [Parameter(Mandatory = $false)]
        [ValidateScript({ $_ -in $script:RetailCurrencies })]
        [string]$CurrencyCode = 'USD',

        [Parameter(Mandatory = $false)]
        [ValidateSet('Region', 'Parameter')]
        [string]$CurrencySource = 'Parameter',

        [Parameter(Mandatory = $false)]
        [string[]]$ServiceNames = @('Sentinel', 'Log Analytics')
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -Path $OutputRoot)) {
        New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    }

    $today = (Get-Date).ToString('yyyy-MM-dd')
    $cacheFile = Join-Path $OutputRoot "retail-prices-$Region-$CurrencyCode-$today.json"

    if (Test-Path $cacheFile) {
        Write-Verbose "Get-AzureRetailPrice: cache hit $cacheFile"
        return (Get-Content $cacheFile -Raw | ConvertFrom-Json)
    }

    $allPrices = New-Object System.Collections.Generic.List[object]

    foreach ($service in $ServiceNames) {
        # Filter syntax, single-quoted values, AND-joined.
        $filter = "serviceName eq '$service' and armRegionName eq '$Region' and priceType eq 'Consumption'"
        # [uri]::EscapeDataString is built into the BCL, no `Add-Type
        # -AssemblyName System.Web` required, so this works on every
        # PowerShell 7 host including the minimal pwsh container images
        # used by the Blueprint pipeline. Semantically equivalent for
        # the alphanumerics, single quotes, equals, and spaces that
        # appear in the OData $filter string.
        $encoded = [uri]::EscapeDataString($filter)
        $url = "https://prices.azure.com/api/retail/prices?currencyCode='$CurrencyCode'&`$filter=$encoded"

        Write-Verbose "Get-AzureRetailPrice: fetching $service in $Region"
        $page = 0
        while ($url) {
            $page++
            try {
                $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
            } catch {
                # The Retail Prices API is best-effort during the run. If it's unreachable
                # we proceed with whatever we collected and let the cost calculator emit a
                # 'pricing unavailable' caveat, a missing currency line beats a hung run.
                Write-Warning "Retail Prices API failure on page $page for ${service}: $($_.Exception.Message)"
                break
            }

            if ($response.PSObject.Properties.Name -contains 'Items' -and $response.Items) {
                foreach ($item in $response.Items) {
                    $allPrices.Add($item)
                }
            }

            $url = $null
            if ($response.PSObject.Properties.Name -contains 'NextPageLink' -and $response.NextPageLink) {
                $url = $response.NextPageLink
            }
        }
    }

    $result = [pscustomobject]@{
        FetchedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        Region       = $Region
        Currency     = $CurrencyCode
        CurrencySource = $CurrencySource
        Services     = $ServiceNames
        Prices       = $allPrices.ToArray()
    }

    $result | ConvertTo-Json -Depth 10 | Set-Content -Path $cacheFile -Encoding UTF8
    return $result
}
