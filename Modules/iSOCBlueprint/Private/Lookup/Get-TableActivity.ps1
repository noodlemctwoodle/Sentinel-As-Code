#Requires -Version 7.6

<#
.SYNOPSIS
    Data received per table in the last 7 days, free tables included

.DESCRIPTION
    Split from Get-ConnectorCatalogue.ps1 so each file holds one function.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Get-TableActivity.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-TableActivity {
    <#
    .SYNOPSIS
        Data received per table in the last 7 days, free tables included.

    .DESCRIPTION
        Reads IngestedLast7d (all volume) and falls back to BillableLast7d
        for older captures. tables-with-data.json has one row per table and
        solution, so the rows are summed per table.

    .PARAMETER TablesWithData
        The rows of tables-with-data.json.

    .OUTPUTS
        [hashtable] table name to GB, case-insensitive.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowNull()] [AllowEmptyCollection()] [object[]] $TablesWithData)

    $gb = [System.Collections.Hashtable]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in @($TablesWithData)) {
        if ($null -eq $row -or -not $row.PSObject.Properties['DataType']) { continue }
        $name = [string]$row.DataType
        if (-not $name) { continue }
        $field = if ($row.PSObject.Properties['IngestedLast7d']) {
            'IngestedLast7d'
        } elseif ($row.PSObject.Properties['BillableLast7d']) { 'BillableLast7d' } else { $null }
        $value = 0.0
        if ($field) {
            [void][double]::TryParse([string]$row.$field, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$value)
        }
        $gb[$name] = $(if ($gb.ContainsKey($name)) { $gb[$name] } else { 0.0 }) + $value
    }
    return $gb
}
