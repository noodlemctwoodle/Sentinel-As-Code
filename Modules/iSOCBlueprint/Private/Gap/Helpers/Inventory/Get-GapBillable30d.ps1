#Requires -Version 7.6

<#
.SYNOPSIS
    The billable GB a TablesWithData row carries for the lookback.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Inventory/Get-GapBillable30d.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# ------------------------------------------------------------
# Helper, the billable GB a TablesWithData record carries for the lookback
# (its BillableLast30d). Returns a [double], or 0 when missing.
# ------------------------------------------------------------
function Get-GapBillable30d {
    param([object]$Row)
    $v = Get-PropOrDefault $Row 'BillableLast30d' 0
    if ($null -eq $v) { return 0.0 }
    $d = 0.0
    if ([double]::TryParse([string]$v, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return 0.0
}
