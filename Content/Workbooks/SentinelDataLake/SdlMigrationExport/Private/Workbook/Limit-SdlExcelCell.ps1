#Requires -Version 7.6

<#
.SYNOPSIS
    Truncates strings that are too long for an Excel cell.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Workbook/Limit-SdlExcelCell.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function Limit-SdlExcelCell {
    <#
    .SYNOPSIS
        Truncates strings that are too long for an Excel cell.

    .DESCRIPTION
        Excel stores at most 32,767 characters per cell; longer
        strings (very long rule or function bodies) make the export
        fail or corrupt the sheet. Values longer than the limit are
        cut and marked.

    .PARAMETER Row
        The rows to check; string properties are shortened in place.

    .PARAMETER MaxLength
        The longest string kept whole.

    .OUTPUTS
        The same rows.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([object[]])]
    param (
        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$Row = @(),

        [Parameter()]
        [ValidateRange(1, 32000)]
        [int]$MaxLength = 32000
    )

    foreach ($entry in $Row) {
        foreach ($property in $entry.PSObject.Properties) {
            if ($property.Value -is [string] -and $property.Value.Length -gt $MaxLength) {
                $property.Value = $property.Value.Substring(0, $MaxLength) + ' [truncated for Excel]'
            }
        }
    }
    return $Row
}
