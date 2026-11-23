#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertTo-BpTable

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Parsing/ConvertTo-BpTable.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Section model conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-BpTable {
    param([object] $Table)
    $rows = @($Table)
    $header = $rows | Where-Object { $_.IsHeader } | Select-Object -First 1
    $defs = @($Table.ColumnDefinitions)
    $columns = @()
    if ($header) {
        $i = 0
        $columns = foreach ($cell in $header) {
            $align = if ($i -lt $defs.Count -and $null -ne $defs[$i].Alignment) { ([string]$defs[$i].Alignment).ToLowerInvariant() } else { $null }
            $i++
            [ordered]@{ text = @(ConvertTo-BpCellRuns -Cell $cell); align = $align }
        }
    }
    # Lists, not pipeline output: a one-row table or a one-cell row would
    # otherwise unroll into the wrong shape.
    $body = [System.Collections.Generic.List[object]]::new()
    # @(): a single TableRow left bare would be enumerated as its cells.
    foreach ($row in @($rows | Where-Object { -not $_.IsHeader })) {
        $cells = [System.Collections.Generic.List[object]]::new()
        foreach ($cell in $row) { $cells.Add(@(ConvertTo-BpCellRuns -Cell $cell)) }
        $body.Add($cells.ToArray())
    }
    return [ordered]@{ type = 'table'; columns = @($columns); rows = $body.ToArray() }
}
