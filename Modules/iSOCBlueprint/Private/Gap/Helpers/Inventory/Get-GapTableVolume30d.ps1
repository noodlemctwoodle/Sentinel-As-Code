#Requires -Version 7.6

<#
.SYNOPSIS
    Billable GB over the lookback per table, summed across the per-solution rows.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Inventory/Get-GapTableVolume30d.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Get-GapTableVolume30d {
    <#
    .SYNOPSIS
        Billable GB over the lookback per table, summed across the per-solution rows.

    .DESCRIPTION
        Each TablesWithData row adds its Get-GapBillable30d figure to the entry
        for its DataType. Null rows and rows without a DataType are skipped.

    .PARAMETER Inventory
        The gap inventory; its TablesWithData rows are read.

    .OUTPUTS
        [hashtable] DataType to billable GB.
    #>
    [CmdletBinding()]
    param([object]$Inventory)
    $gb = @{}
    foreach ($row in @($Inventory.TablesWithData)) {
        if ($null -eq $row) { continue }
        $t = [string](Get-PropOrDefault $row 'DataType' '')
        if (-not $t) { continue }
        $gb[$t] = ($(if ($gb.ContainsKey($t)) { $gb[$t] } else { 0.0 })) + (Get-GapBillable30d $row)
    }
    return $gb
}
