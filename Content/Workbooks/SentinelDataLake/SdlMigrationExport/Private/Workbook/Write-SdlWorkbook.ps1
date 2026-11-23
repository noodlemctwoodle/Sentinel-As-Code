#Requires -Version 7.6

<#
.SYNOPSIS
    Writes the datasets to a multi-sheet Excel workbook.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Workbook/Write-SdlWorkbook.ps1
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

function Write-SdlWorkbook {
    <#
    .SYNOPSIS
        Writes the datasets to a multi-sheet Excel workbook.

    .DESCRIPTION
        One sheet per dataset in the given order. An empty dataset
        gets a one-row placeholder so every sheet exists. Long strings
        are truncated for Excel and columns are sized by
        Resize-SdlColumn. An existing file at the path is replaced.
        Supports -WhatIf.

    .PARAMETER Path
        The .xlsx path.

    .PARAMETER Sheet
        Ordered dictionary of sheet name to rows.

    .OUTPUTS
        None.
    #>
    [CmdletBinding(PositionalBinding = $false, SupportsShouldProcess)]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [System.Collections.Specialized.OrderedDictionary]$Sheet
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'Write the migration workbook')) {
        return
    }
    # .NET path primitives: Split-Path -LiteralPath with -Parent is an invalid
    # parameter-set combination and New-Item has no -LiteralPath.
    $directory = [System.IO.Path]::GetDirectoryName($Path)
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        [void][System.IO.Directory]::CreateDirectory($directory)
    }
    if (Test-Path -LiteralPath $Path) {
        try {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        } catch [System.IO.IOException] {
            throw [System.IO.IOException]::new("Cannot replace '$Path': the file is in use. Close it (for example in Excel) or pass a different -OutputPath, then re-run.", $_.Exception)
        }
    }

    foreach ($name in $Sheet.Keys) {
        $rows = @($Sheet[$name])
        if ($rows.Count -eq 0) {
            $placeholder = [pscustomobject]@{ Note = 'No rows produced for this dataset.' }
            $placeholder | Export-Excel -Path $Path -WorksheetName $name -BoldTopRow -FreezeTopRow
            Write-SdlStatus -Message "$name : 0 rows (placeholder written)"
            continue
        }
        # No -AutoFilter: -TableStyle already adds filter buttons, and a
        # worksheet autofilter over a table range can make Excel report the
        # file as damaged.
        $package = Limit-SdlExcelCell -Row $rows | Export-Excel -Path $Path -WorksheetName $name -BoldTopRow -FreezeTopRow -TableStyle 'Medium2' -PassThru
        Resize-SdlColumn -Worksheet $package.Workbook.Worksheets[$name] -Row $rows
        Close-ExcelPackage -ExcelPackage $package
        Write-SdlStatus -Message "$name : $($rows.Count) rows"
    }
}
