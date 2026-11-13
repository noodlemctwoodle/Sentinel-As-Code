#Requires -Version 7.6

<#
.SYNOPSIS
    A table block as CSV text: the header row, then every body row. Lines end in CRLF, as RFC 4180 has it.

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Tables/ConvertTo-SacTableCsv.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, SharePoint page conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function ConvertTo-SacTableCsv {
    <#
    .SYNOPSIS
        A table block as CSV text: the header row, then every body row.
        Lines end in CRLF, as RFC 4180 has it.

    .PARAMETER Table
        A table block from the section model.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] $Table)
    $sb = [System.Text.StringBuilder]::new()
    $columns = @($Table.columns)
    $headers = @($columns | ForEach-Object { Get-SacRunsText -Runs @($_.text) })
    [void]$sb.Append((@($headers | ForEach-Object { ConvertTo-SacCsvField $_ }) -join ',') + "`r`n")
    foreach ($row in @($Table.rows)) {
        $cells = @(@($row) | ForEach-Object { ConvertTo-SacCsvField (Get-SacRunsText -Runs @($_)) })
        [void]$sb.Append(($cells -join ',') + "`r`n")
    }
    return $sb.ToString()
}
