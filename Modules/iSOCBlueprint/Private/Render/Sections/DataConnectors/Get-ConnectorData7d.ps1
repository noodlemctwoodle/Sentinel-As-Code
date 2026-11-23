#Requires -Version 7.6

<#
.SYNOPSIS
    Return what a connector wrote over the last 7 days.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/DataConnectors/Get-ConnectorData7d.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-ConnectorData7d {
    <#
    .SYNOPSIS
        Return what a connector wrote over the last 7 days.

    .DESCRIPTION
        Looks up the connector's target tables in $tablesByNameForConnectors (set by
        the calling section) and reads BillableLast7d. RestApiPoller and Push
        connectors write to the one table named in properties.dataType; other kinds
        map each data type to a table through Get-ConnectorTargetTable. The result
        is 'Yes' when any table has billable data, 'No' when none does, and an empty
        string when the connector names no table or data types.

    .PARAMETER Connector
        The data connector resource.

    .OUTPUTS
        [string]: 'Yes', 'No' or an empty string.
    #>
    [CmdletBinding()]
    param([psobject]$Connector)
    # RestApiPoller / Push connectors write to a single table at
    # properties.dataType. The table name itself is the join key — no
    # data-type-to-table mapping is needed.
    if ($Connector.kind -in @('RestApiPoller','Push')) {
        $tbl = $Connector.properties.dataType
        if (-not $tbl) { return '' }
        if ($tablesByNameForConnectors.ContainsKey($tbl)) {
            $row = $tablesByNameForConnectors[$tbl]
            $bill7d = if ($null -ne $row.BillableLast7d) { [double]$row.BillableLast7d } else { 0 }
            if ($bill7d -gt 0) { return 'Yes' }
        }
        return 'No'
    }
    $dataTypes = $Connector.properties.dataTypes
    if ($null -eq $dataTypes) { return '' }
    $anyData = $false
    foreach ($dtName in @($dataTypes.PSObject.Properties.Name)) {
        $table = Get-ConnectorTargetTable -Kind $Connector.kind -DataType $dtName
        if (-not $table) { continue }
        if ($tablesByNameForConnectors.ContainsKey($table)) {
            $row = $tablesByNameForConnectors[$table]
            $bill7d = if ($null -ne $row.BillableLast7d) { [double]$row.BillableLast7d } else { 0 }
            if ($bill7d -gt 0) { $anyData = $true; break }
        }
    }
    if ($anyData) { 'Yes' } else { 'No' }
}
