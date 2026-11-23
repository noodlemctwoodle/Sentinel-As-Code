#Requires -Version 7.6

<#
.SYNOPSIS
    Read the workspace's SKU and, on a commitment tier, share its cost out over the Analytics tables.

.DESCRIPTION
    A step of the cost estimate. Steps run in order and pass their results to
    later ones through the estimate context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Cost/Steps/Get-CostCommitment.ps1
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

function Get-CostCommitment {
    <#
    .SYNOPSIS
        Read the workspace's SKU and, on a commitment tier, share its cost out over the Analytics tables.

    .PARAMETER Context
        The estimate context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the estimate context.
    $caveats = $Context.caveats
    $rows = $Context.rows
    $tierDaily = $Context.tierDaily
    $windowDays = $Context.windowDays
    $workspace = $Context.workspace

    $sku = $null
    $level = 0
    # Guard against a missing or corrupt workspace.json. Under StrictMode,
    # navigating $workspace.properties.sku.name on a null would throw and abort
    # the whole estimate, so treat an unreadable SKU as unknown.
    if ($workspace -and
        ($workspace.PSObject.Properties.Name -contains 'properties') -and $workspace.properties -and
        ($workspace.properties.PSObject.Properties.Name -contains 'sku') -and $workspace.properties.sku) {
        $sku = ($workspace.properties.sku.name) -as [string]
        if ($workspace.properties.sku.PSObject.Properties.Name -contains 'capacityReservationLevel') { $level = [int]($workspace.properties.sku.capacityReservationLevel -as [int]) }
    }

    # On a commitment tier, the Analytics data costs the tier's price a day
    # for its GB and the effective rate for the GB above it; that is shared
    # out over the Analytics tables by their GB.
    $analyticsRows = @($rows | Where-Object { $_.Plan -notin @('Basic', 'Auxiliary', 'DataLake') })
    $analyticsGb = Get-CostPropertySum $analyticsRows 'Gb'
    $dailyAnalytics = $analyticsGb / $windowDays
    $commitment = $null
    if ($sku -eq 'CapacityReservation' -and $level -gt 0) {
        if ($tierDaily.ContainsKey($level)) {
            $price = $tierDaily[$level]
            $effective = $price / $level
            $tierMonthly = 30.0 * ($price + [math]::Max(0.0, $dailyAnalytics - $level) * $effective)
            foreach ($r in $analyticsRows) { $r.Cost = $(if ($analyticsGb -gt 0) { $tierMonthly * $r.Gb / $analyticsGb } else { 0.0 }) }
            $commitment = [pscustomobject]@{
                Level          = $level
                DailyPrice     = [math]::Round($price, 2)
                EffectivePerGb = [math]::Round($effective, 4)
                DailyAverageGb = [math]::Round($dailyAnalytics, 1)
                Utilisation    = [math]::Round(100.0 * $dailyAnalytics / $level, 1)
            }
        } else {
            $caveats += "The workspace is on the $level GB a day commitment tier, but the price list has no price for it, so its Analytics data is priced at pay-as-you-go."
        }
    }

    # Left for the steps after this one.
    $Context.sku = $sku
    $Context.level = $level
    $Context.dailyAnalytics = $dailyAnalytics
    $Context.commitment = $commitment
    $Context.caveats = $caveats
}
