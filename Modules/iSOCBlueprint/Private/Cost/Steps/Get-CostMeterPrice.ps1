#Requires -Version 7.6

<#
.SYNOPSIS
    Read the unit price of each meter category from the price list, by the meter names in cost-meters.json.

.DESCRIPTION
    A step of the cost estimate. Steps run in order and pass their results to
    later ones through the estimate context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Cost/Steps/Get-CostMeterPrice.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, cost estimate
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-CostMeterPrice {
    <#
    .SYNOPSIS
        Read the unit price of each meter category from the price list, by the meter names in cost-meters.json.

    .PARAMETER Context
        The estimate context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the estimate context.
    $caveats = $Context.caveats
    $pricesBlob = $Context.pricesBlob
    $ResourcesRoot = $Context.ResourcesRoot

    # Pricing table lookup driven by Resources/Data/cost-meters.json. Each
    # category in that file declares either:
    #   - meterNames, exact-match meter strings (case-sensitive), OR
    #   - meterContains, list of substrings that must ALL be present in
    #                     the meter name (used for the Data Lake meter
    #                     whose exact wording has varied).
    # Microsoft renames Retail Prices meters periodically; supporting the
    # Blueprint on a new tenant should be a JSON edit, not a code change.
    #
    # When the API returns more than one row for the same meter (a
    # 0-priced commitment-tier 'included' row plus a non-zero PAYG row),
    # we take the MAX unit price across rows, that yields the PAYG rate,
    # which is the right baseline for an uncommitted workspace. The
    # CommitmentTierWhatIf surface below projects savings from this
    # baseline.
    $metersCatalog = Read-CostJson (Join-Path $ResourcesRoot 'cost-meters.json')
    if (-not $metersCatalog) {
        throw "cost-meters.json missing or unreadable under $ResourcesRoot"
    }

    $unitPrices = @{}
    foreach ($cat in $metersCatalog.categories) { $unitPrices[$cat.id] = 0.0 }
    $skipMeters = @{}
    if ($metersCatalog.skipMeters) { foreach ($s in $metersCatalog.skipMeters) { $skipMeters[$s] = $true } }

    $currency = 'unknown'
    $asOfUtc = $null
    $region = $null
    # Where the currency came from: the region (-Currency Auto) or the run's
    # setting; an older price list does not say.
    $currencySource = $null

    if ($pricesBlob) {
        $region = $pricesBlob.Region
        $asOfUtc = $pricesBlob.FetchedAtUtc
        if ($pricesBlob.PSObject.Properties.Name -contains 'CurrencySource') { $currencySource = [string]$pricesBlob.CurrencySource }
        foreach ($p in @($pricesBlob.Prices)) {
            $meter = ($p.meterName) -as [string]
            $price = ($p.unitPrice) -as [double]
            $cc = ($p.currencyCode) -as [string]
            if ($cc) { $currency = $cc }
            if (-not $meter -or $skipMeters.ContainsKey($meter)) { continue }

            foreach ($cat in $metersCatalog.categories) {
                $hit = $false
                if ($cat.PSObject.Properties.Name -contains 'meterNames' -and $cat.meterNames) {
                    if ($cat.meterNames -contains $meter) { $hit = $true }
                }
                if (-not $hit -and $cat.PSObject.Properties.Name -contains 'meterContains' -and $cat.meterContains) {
                    $allMatch = $true
                    foreach ($needle in $cat.meterContains) {
                        if ($meter -notlike "*$needle*") { $allMatch = $false; break }
                    }
                    if ($allMatch) { $hit = $true }
                }
                if ($hit -and $price -gt $unitPrices[$cat.id]) {
                    $unitPrices[$cat.id] = $price
                }
            }
        }
    } else {
        $caveats += 'Retail Prices snapshot unavailable, monthly cost is reported as zero.'
    }

    # Left for the steps after this one.
    $Context.unitPrices = $unitPrices
    $Context.currency = $currency
    $Context.asOfUtc = $asOfUtc
    $Context.region = $region
    $Context.currencySource = $currencySource
    $Context.caveats = $caveats
}
