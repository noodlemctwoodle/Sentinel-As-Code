#Requires -Version 7.2

<#
.SYNOPSIS
    Sets each column's width from its header and its longest early value.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Workbook/Resize-SdlColumn.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.2+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function Resize-SdlColumn {
    <#
    .SYNOPSIS
        Sets each column's width from its header and its longest early
        value.

    .DESCRIPTION
        Replaces Export-Excel -AutoSize, which needs libgdiplus and
        only warns on macOS and Linux. Widths come from the header and
        the first rows, capped so long text does not make a column
        unreadably wide.

    .PARAMETER Worksheet
        The EPPlus worksheet to size.

    .PARAMETER Row
        The rows written to the sheet.

    .PARAMETER MaxWidth
        The widest a column may be.

    .PARAMETER SampleSize
        How many rows to measure.

    .OUTPUTS
        None.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [object]$Worksheet,

        [Parameter(Mandatory)]
        [object[]]$Row,

        [Parameter()]
        [ValidateRange(10, 255)]
        [int]$MaxWidth = 60,

        [Parameter()]
        [ValidateRange(1, 100000)]
        [int]$SampleSize = 200
    )

    $names = @($Row[0].PSObject.Properties.Name)
    $sampleRow = @($Row | Select-Object -First $SampleSize)
    for ($index = 0; $index -lt $names.Count; $index++) {
        $width = $names[$index].Length
        foreach ($entry in $sampleRow) {
            $value = $entry.($names[$index])
            if ($null -ne $value) {
                $width = [Math]::Max($width, ([string]$value).Length)
            }
        }
        $Worksheet.Column($index + 1).Width = [Math]::Min($MaxWidth, $width + 2)
    }
}
