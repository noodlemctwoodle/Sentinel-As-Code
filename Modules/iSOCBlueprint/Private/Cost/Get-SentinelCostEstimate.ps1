#Requires -Version 7.6

<#
.SYNOPSIS
    Compute an estimated monthly cost for the workspace from the captured Usage and the Retail Prices snapshot.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Cost/Get-SentinelCostEstimate.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, cost estimate
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SentinelCostEstimate {
    <#
    .SYNOPSIS
        Compute an estimated monthly cost for the workspace from the captured Usage over the run's lookback,
        table-plan attribution, and the Azure Retail Prices snapshot.

    .DESCRIPTION
        Pure data-in / data-out so the calculator can be exercised by Pester fixtures with
        no Azure dependency.

        Inputs (all written by Export-iSOCBlueprintInventory):
          - tables-with-data.json    per-table BillableGB / IngestedGB over the lookback (BillableLast30d)
          - workspace-tables.json    per-table plan + retention
          - workspace.json           workspace SKU + commitment level
          - retail-prices.json       Sentinel + Log Analytics retail meters for the region
          - sentinel-data-lake.json  whether the workspace is onboarded to the data lake
          - sentinel-benefit-tables.json  the data grants and the tables each covers

        Output (cost-estimate.json):
          MonthlyTotal                 number, in the API-reported currency
          Currency                     string (e.g. 'GBP')
          CurrencySource               'Region' (from -Currency Auto), 'Parameter', or $null
          Region                       workspace region
          AsOfUtc                      timestamp the prices were fetched
          ByPlan                       hashtable: plan name -> @{ Gb30d; MonthlyCost }
                                       (Gb30d is the GB in the window, MonthlyCost
                                       that projected to 30 days)
          Top10TablesByCost            array of @{ Table; Plan; Gb30d; MonthlyCost; Benefit }
          AllTablesByCost              the same for every table with billable data
          CommitmentTierWhatIf         array of @{ Rung; ProjectedMonthlyCost; DeltaVsCurrent }
          CommitmentTier               the workspace's tier (Level, DailyPrice,
                                       EffectivePerGb, DailyAverageGb, Utilisation),
                                       $null on pay-as-you-go
          BenefitEligible              array of @{ Benefit; Allowance; Tables; Gb30d;
                                       MonthlyCost; Learn }: the data grants that may
                                       cover part of the cost, not deducted
          PricingModel                 'Simplified' or 'Classic': the rate the
                                       estimate priced Analytics data at
          BilledPricingModel           'Simplified' or 'Classic': how the
                                       workspace is billed, from the Microsoft
                                       Sentinel solution's SKU (Unified is
                                       simplified); $null when not captured
          DedicatedClusterCandidate    bool
          Caveats                      array of strings, items NOT priced
          WindowDays                   days of Usage the estimate is projected from
          MethodologyVersion           '2.0.0'

        Methodology notes
        -----------------
        1. Analytics-plan tables are priced at the simplified Microsoft Sentinel
           'Pay-as-you-go Analysis' meter, which covers Sentinel analysis and Log
           Analytics ingestion together. A price list without it (an older
           capture) falls back to the classic pair: Log Analytics ingestion plus
           the Sentinel analysis meter.
        2. A workspace on a commitment tier pays the tier's fixed price a day for
           its GB, and the Analytics GB above it at the tier's effective rate (the
           tier price over its GB), as Microsoft bills it. The cost is shared out
           over the Analytics tables by their GB.
        3. Basic tables use 'Basic Logs Analysis'; data-lake-only tables pay data
           lake ingestion plus data processing; Auxiliary tables pay the same once
           the workspace is onboarded to the data lake, else the Auxiliary meters.
        4. Data grants (Microsoft 365 E5 and Defender for Servers Plan 2) cover
           named tables up to an allowance per licensed user or server that the
           Blueprint cannot read, so they are not deducted; the eligible volume and
           its cost are reported beside the total instead.
        5. The what-if prices every published commitment tier against the window's
           Analytics ingest and reports the cheapest when it beats the current cost.

        Caveats, explicitly NOT priced:
          - Query-time billing for Basic/Auxiliary plans.
          - Search-job and restore-log storage.
          - Retention beyond the free 90 days and data lake storage.
          - Data export egress.
          - Cross-region transfer.
          - Defender XDR-side meters.

    .PARAMETER InputRoot
        The folder holding the captured JSON files (the run's _raw folder).

    .PARAMETER ResourcesRoot
        The folder holding cost-meters.json, commitment-tiers.json and
        sentinel-benefit-tables.json.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputRoot,

        [Parameter(Mandatory = $true)]
        [string]$ResourcesRoot
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $context = @{
        InputRoot     = $InputRoot
        ResourcesRoot = $ResourcesRoot
        result        = $null
        stop          = $false
    }

    $steps = @(
        'Read-CostInput'
        'Initialize-CostResult'
        'Get-CostLookup'
        'Get-CostMeterPrice'
        'Get-CostCommitmentTier'
        'Get-CostPlanRate'
        'Get-CostTableRow'
        'Get-CostCommitment'
        'Get-CostTotal'
        'Get-CostBenefitEligible'
        'Get-CostCommitmentWhatIf'
        'Get-CostEstimateResult'
    )
    foreach ($step in $steps) {
        & $step -Context $context
        if ($context.stop) { break }
    }
    $context.result
}
