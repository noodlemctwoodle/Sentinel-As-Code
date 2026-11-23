#Requires -Version 7.6

<#
.SYNOPSIS
    Total the cost per table and per plan and rank the tables.

.DESCRIPTION
    A step of the cost estimate. Steps run in order and pass their results to
    later ones through the estimate context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Cost/Steps/Get-CostTotals.ps1
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

function Get-CostTotals {
    <#
    .SYNOPSIS
        Total the cost per table and per plan and rank the tables.

    .PARAMETER Context
        The estimate context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the estimate context.
    $byPlan = $Context.byPlan
    $rows = $Context.rows

    $perTable = @(foreach ($r in $rows) {
            [pscustomobject]@{ Table = $r.Table; Plan = $r.Plan; Gb30d = [math]::Round($r.Gb, 2); MonthlyCost = [math]::Round($r.Cost, 2)
                Benefit = $r.Benefit
            }
            $bucket = if ($byPlan.ContainsKey($r.Plan)) { $r.Plan } else { 'Analytics' }
            $byPlan[$bucket].Gb30d += $r.Gb
            $byPlan[$bucket].MonthlyCost += [math]::Round($r.Cost, 2)
        })

    $monthlyTotal = Get-CostPropertySum $perTable 'MonthlyCost'

    $perTableSorted = @($perTable | Sort-Object -Property MonthlyCost -Descending)
    $top10 = @($perTableSorted | Select-Object -First 10)

    # Left for the steps after this one.
    $Context.perTable = $perTable
    $Context.monthlyTotal = $monthlyTotal
    $Context.perTableSorted = $perTableSorted
    $Context.top10 = $top10
}
