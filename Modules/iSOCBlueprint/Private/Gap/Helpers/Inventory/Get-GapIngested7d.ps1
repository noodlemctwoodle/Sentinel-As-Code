#Requires -Version 7.6

<#
.SYNOPSIS
    GB ingested in the recent window for a TablesWithData row, billable or not.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Inventory/Get-GapIngested7d.ps1
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

# GB ingested in the recent window, billable or not. IngestedLast7d was added
# to tables-with-data in the same change as these rules; older captures
# fall back to the billable figure.
function Get-GapIngested7d {
    param([object]$Row)
    if ($null -ne $Row -and $Row.PSObject.Properties.Name -contains 'IngestedLast7d') {
        return ConvertTo-GapDouble (Get-PropOrDefault $Row 'IngestedLast7d' 0)
    }
    return ConvertTo-GapDouble (Get-PropOrDefault $Row 'BillableLast7d' 0)
}
