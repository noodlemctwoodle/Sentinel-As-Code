#Requires -Version 7.6

<#
.SYNOPSIS
    Price every published commitment tier against the window's Analytics ingest and report the cheapest when it beats the current cost.

.DESCRIPTION
    A step of the cost estimate. Steps run in order and pass their results to
    later ones through the estimate context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Cost/Steps/Get-CostCommitmentWhatIf.ps1
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

function Get-CostCommitmentWhatIf {
    <#
    .SYNOPSIS
        Price every published commitment tier against the window's Analytics ingest and report the cheapest when it beats the current cost.

    .PARAMETER Context
        The estimate context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the estimate context.
    $byPlan = $Context.byPlan
    $dailyAnalytics = $Context.dailyAnalytics
    $level = $Context.level
    $monthlyTotal = $Context.monthlyTotal
    $perTable = $Context.perTable
    $ResourcesRoot = $Context.ResourcesRoot
    $sku = $Context.sku
    $tierDaily = $Context.tierDaily
    $windowDays = $Context.windowDays

    # Commitment-tier what-if: every published tier priced against the
    # window's Analytics ingest; the cheapest is reported when it beats the
    # current cost by more than 1%. A price list without the tiers (an older
    # capture) keeps the earlier illustrative projection for pay-as-you-go.
    $commitmentWhatIf = @()
    $currentAnalytics = Get-CostPropertySum @($perTable | Where-Object { $_.Plan -notin @('Basic', 'Auxiliary', 'DataLake') }) 'MonthlyCost'
    if ($tierDaily.Count -gt 0 -and $dailyAnalytics -gt 0) {
        $best = $null
        foreach ($r in $tierDaily.Keys) {
            $m = 30.0 * ($tierDaily[$r] + [math]::Max(0.0, $dailyAnalytics - $r) * $tierDaily[$r] / $r)
            if ($null -eq $best -or $m -lt $best.Monthly) { $best = @{ Rung = $r; Monthly = $m } }
        }
        if ($best -and $best.Rung -ne $level -and $best.Monthly -lt $currentAnalytics * 0.99) {
            $projected = [math]::Round($monthlyTotal - $currentAnalytics + $best.Monthly, 2)
            $commitmentWhatIf += [pscustomobject]@{
                Rung                 = $best.Rung
                ProjectedMonthlyCost = $projected
                DeltaVsCurrent       = [math]::Round($projected - $monthlyTotal, 2)
            }
        }
    } elseif ($sku -eq 'PerGB2018') {
        $commitmentTiers = Read-CostJson (Join-Path $ResourcesRoot 'commitment-tiers.json')
        if ($commitmentTiers) {
            $totalGb30d = ($byPlan.Values | Measure-Object -Property Gb30d -Sum).Sum
            $dailyAvg = $totalGb30d / $windowDays
            $smallestRung = ($commitmentTiers.rungsGbPerDay | Measure-Object -Minimum).Minimum
            $qualifying   = @($commitmentTiers.rungsGbPerDay | Where-Object { $dailyAvg -ge $_ })
            $rung = if ($qualifying) {
                ($qualifying | Measure-Object -Maximum).Maximum
            } elseif ($dailyAvg -ge ($smallestRung * 0.8)) {
                $smallestRung
            } else {
                $null
            }
            if ($null -ne $rung) {
                # Illustrative: a ~25% discount at the rung, without published tier prices.
                $projected = [math]::Round(($monthlyTotal * 0.75), 2)
                $commitmentWhatIf += [pscustomobject]@{
                    Rung                 = $rung
                    ProjectedMonthlyCost = $projected
                    DeltaVsCurrent       = [math]::Round($projected - $monthlyTotal, 2)
                }
            }
        }
    }

    # Left for the steps after this one.
    $Context.commitmentWhatIf = $commitmentWhatIf
}
