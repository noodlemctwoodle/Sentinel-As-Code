#Requires -Version 7.6

<#
.SYNOPSIS
    Assemble the estimate.

.DESCRIPTION
    A step of the cost estimate. Steps run in order and pass their results to
    later ones through the estimate context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Cost/Steps/Get-CostEstimateResult.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, cost estimate
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-CostEstimateResult {
    <#
    .SYNOPSIS
        Assemble the estimate.

    .PARAMETER Context
        The estimate context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the estimate context.
    $asOfUtc = $Context.asOfUtc
    $benefitEligible = $Context.benefitEligible
    $billedModel = $Context.billedModel
    $byPlan = $Context.byPlan
    $caveats = $Context.caveats
    $commitment = $Context.commitment
    $commitmentWhatIf = $Context.commitmentWhatIf
    $currency = $Context.currency
    $currencySource = $Context.currencySource
    $monthlyTotal = $Context.monthlyTotal
    $perTableSorted = $Context.perTableSorted
    $region = $Context.region
    $simplified = $Context.simplified
    $top10 = $Context.top10
    $windowDays = $Context.windowDays

    $totalGb30d = ($byPlan.Values | Measure-Object -Property Gb30d -Sum).Sum
    $clusterCandidate = ($totalGb30d / $windowDays) -gt 500.0

    $Context.result = [pscustomobject]@{
        MonthlyTotal              = [math]::Round($monthlyTotal, 2)
        Currency                  = $currency
        CurrencySource            = $currencySource
        Region                    = $region
        AsOfUtc                   = $asOfUtc
        ByPlan                    = $byPlan
        Top10TablesByCost         = @($top10)
        AllTablesByCost           = @($perTableSorted)
        CommitmentTierWhatIf      = @($commitmentWhatIf)
        CommitmentTier            = $commitment
        BenefitEligible           = @($benefitEligible)
        PricingModel              = $(if ($simplified) { 'Simplified' } else { 'Classic' })
        BilledPricingModel        = $billedModel
        DedicatedClusterCandidate = $clusterCandidate
        Caveats                   = $caveats
        WindowDays                = $windowDays
        MethodologyVersion        = '2.0.0'
    }
}
