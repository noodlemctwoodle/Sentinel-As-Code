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
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Get-GapBillable30d {
    <#
    .SYNOPSIS
        The billable GB a TablesWithData row carries for the lookback.

    .DESCRIPTION
        Reads the row's BillableLast30d, which is the historical name of the
        lookback figure. Text is parsed with the invariant culture, and a
        missing, null or non-numeric value gives 0.0.

    .PARAMETER Row
        A TablesWithData record.

    .OUTPUTS
        [double]
    #>
    [CmdletBinding()]
    param([object]$Row)
    $v = Get-PropOrDefault $Row 'BillableLast30d' 0
    if ($null -eq $v) { return 0.0 }
    $d = 0.0
    if ([double]::TryParse([string]$v, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return 0.0
}
