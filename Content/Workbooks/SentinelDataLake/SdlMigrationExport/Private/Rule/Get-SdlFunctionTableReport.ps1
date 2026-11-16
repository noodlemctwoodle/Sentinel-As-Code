#Requires -Version 7.2

<#
.SYNOPSIS
    Lists the tables each workspace function reaches.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Rule/Get-SdlFunctionTableReport.ps1
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

function Get-SdlFunctionTableReport {
    <#
    .SYNOPSIS
        Lists the tables each workspace function reaches.

    .DESCRIPTION
        One row per function that reaches at least one table,
        including tables reached through nested functions.

    .PARAMETER FunctionReach
        The hashtable from Get-SdlFunctionReach.

    .OUTPUTS
        [pscustomobject] FunctionAlias, DisplayName, TablesReferenced
        and TableCount.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [hashtable]$FunctionReach
    )

    foreach ($alias in @($FunctionReach.Keys | Sort-Object)) {
        $info = $FunctionReach[$alias]
        if ($info.Tables.Count -eq 0) {
            continue
        }
        [pscustomobject]@{
            FunctionAlias    = $alias
            DisplayName      = $info.Function.DisplayName
            TablesReferenced = (@($info.Tables | Sort-Object) -join '; ')
            TableCount       = $info.Tables.Count
        }
    }
}
