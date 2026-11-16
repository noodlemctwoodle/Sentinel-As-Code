#Requires -Version 7.6

<#
.SYNOPSIS
    Price every table with billable data at its plan's rate, projected to 30 days.

.DESCRIPTION
    A step of the cost estimate. Steps run in order and pass their results to
    later ones through the estimate context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Cost/Steps/Get-CostTableRows.ps1
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

function Get-CostTableRows {
    <#
    .SYNOPSIS
        Price every table with billable data at its plan's rate, projected to 30 days.

    .PARAMETER Context
        The estimate context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the estimate context.
    $analyticsUnit = $Context.analyticsUnit
    $auxUnit = $Context.auxUnit
    $basicUnit = $Context.basicUnit
    $benefitOf = $Context.benefitOf
    $lakeUnit = $Context.lakeUnit
    $planByTable = $Context.planByTable
    $tables = $Context.tables
    $toMonth = $Context.toMonth

    # Every table with billable data in the window, at its plan's price per
    # GB, projected to 30 days.
    $rows = foreach ($t in $tables) {
        $name = $t.DataType
        $billable30d = [double]($t.BillableLast30d)
        if ($billable30d -le 0 -or -not $name) { continue }
        $plan = if ($planByTable.ContainsKey($name) -and $planByTable[$name]) { $planByTable[$name] } else { 'Analytics' }
        $unit = switch ($plan) {
            'Basic'     { $basicUnit }
            'Auxiliary' { $auxUnit }
            'DataLake'  { $lakeUnit }
            default     { $analyticsUnit }
        }
        [pscustomobject]@{ Table = $name; Plan = $plan; Gb = $billable30d; Cost = $billable30d * $unit * $toMonth
            Benefit = $(if ($benefitOf.ContainsKey($name)) { $g = $benefitOf[$name]; if ($g.PSObject.Properties.Name -contains 'short' -and $g.short) { [string]$g.short } else { [string]$g.name } } else { '' }) }
    }
    $rows = @($rows)

    # Left for the steps after this one.
    $Context.rows = $rows
}
