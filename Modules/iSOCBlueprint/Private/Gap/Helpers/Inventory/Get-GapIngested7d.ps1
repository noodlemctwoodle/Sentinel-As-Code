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
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Get-GapIngested7d {
    <#
    .SYNOPSIS
        GB ingested in the recent window for a TablesWithData row, billable or not.

    .DESCRIPTION
        Reads the row's IngestedLast7d, the historical name of the recent
        window figure. IngestedLast7d was added to tables-with-data in the
        same change as these rules, so a row without it falls back to its
        BillableLast7d.

    .PARAMETER Row
        A TablesWithData record.

    .OUTPUTS
        [double]
    #>
    [CmdletBinding()]
    param([object]$Row)
    if ($null -ne $Row -and $Row.PSObject.Properties.Name -contains 'IngestedLast7d') {
        return ConvertTo-GapDouble (Get-PropOrDefault $Row 'IngestedLast7d' 0)
    }
    return ConvertTo-GapDouble (Get-PropOrDefault $Row 'BillableLast7d' 0)
}
