#Requires -Version 7.6

<#
.SYNOPSIS
    Read each commitment tier's fixed price a day from the price list.

.DESCRIPTION
    A step of the cost estimate. Steps run in order and pass their results to
    later ones through the estimate context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Cost/Steps/Get-CostCommitmentTiers.ps1
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

function Get-CostCommitmentTiers {
    <#
    .SYNOPSIS
        Read each commitment tier's fixed price a day from the price list.

    .PARAMETER Context
        The estimate context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the estimate context.
    $pricesBlob = $Context.pricesBlob

    # Commitment tiers: each tier's fixed price a day, by its GB a day.
    $tierDaily = @{}
    if ($pricesBlob) {
        foreach ($p in @($pricesBlob.Prices)) {
            $meter = ($p.meterName) -as [string]
            $price = ($p.unitPrice) -as [double]
            if ($meter -match '^(\d+) GB Commitment Tier Capacity Reservation$' -and $price -gt 0) {
                $gb = [int]$Matches[1]
                if (-not $tierDaily.ContainsKey($gb) -or $price -gt $tierDaily[$gb]) { $tierDaily[$gb] = $price }
            }
        }
    }

    # Left for the steps after this one.
    $Context.tierDaily = $tierDaily
}
