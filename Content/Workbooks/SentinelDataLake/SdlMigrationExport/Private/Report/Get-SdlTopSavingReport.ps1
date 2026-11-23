#Requires -Version 7.6

<#
.SYNOPSIS
    Lists the ten tables with the largest monthly saving.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Report/Get-SdlTopSavingReport.ps1
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

function Get-SdlTopSavingReport {
    <#
    .SYNOPSIS
        Lists the ten tables with the largest monthly saving.

    .DESCRIPTION
        Read off the Migration Report: only rows with status Eligible
        (a positive saving), ranked by saving.

    .PARAMETER Currency
        The currency code used in the saving column name.

    .PARAMETER MigrationReport
        Rows from Get-SdlMigrationReport.

    .OUTPUTS
        [pscustomobject] Table, GBPerMonth and the saving column.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Z]{3}$')]
        [string]$Currency,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$MigrationReport = @()
    )

    $savingColumn = "MonthlySaving_$Currency"
    $eligible = $MigrationReport | Where-Object -FilterScript { $_.Status -eq 'Eligible' }
    $top = $eligible | Sort-Object -Property { [double]$_.$savingColumn } -Descending | Select-Object -First 10
    foreach ($row in $top) {
        [pscustomobject]@{
            Table         = $row.Table
            GBPerMonth    = $row.GBPerMonth
            $savingColumn = $row.$savingColumn
        }
    }
}
