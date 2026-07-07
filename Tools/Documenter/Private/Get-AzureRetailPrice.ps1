#
# Sentinel-As-Code/Tools/Documenter/Private/Get-AzureRetailPrice.ps1
#
# Created by noodlemctwoodle on 06/05/2026.
#

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

.PARAMETER ServiceNames
    Service names to filter on. Defaults to the two Sentinel-relevant services. Override
    if you want to extend the cost calculator (e.g. include 'Storage' for archive).

.OUTPUTS
    [pscustomobject] with FetchedAtUtc, Region, Services, and a Prices array
    holding the union of all returned price rows.

.NOTES
    Endpoint: https://prices.azure.com/api/retail/prices
    Documentation: https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices
#>

function Get-AzureRetailPrice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Region,

        [Parameter(Mandatory = $true)]
        [string]$OutputRoot,

        [Parameter(Mandatory = $false)]
        [string[]]$ServiceNames = @('Microsoft Sentinel', 'Log Analytics')
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -Path $OutputRoot)) {
        New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    }

    $today = (Get-Date).ToString('yyyy-MM-dd')
    $cacheFile = Join-Path $OutputRoot "retail-prices-$Region-$today.json"

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
        # used by the documenter pipeline. Semantically equivalent for
        # the alphanumerics, single quotes, equals, and spaces that
        # appear in the OData $filter string.
        $encoded = [uri]::EscapeDataString($filter)
        $url = "https://prices.azure.com/api/retail/prices?`$filter=$encoded"

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
        Services     = $ServiceNames
        Prices       = $allPrices.ToArray()
    }

    $result | ConvertTo-Json -Depth 10 | Set-Content -Path $cacheFile -Encoding UTF8
    return $result
}
