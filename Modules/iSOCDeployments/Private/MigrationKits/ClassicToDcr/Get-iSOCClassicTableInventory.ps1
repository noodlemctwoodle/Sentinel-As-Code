#Requires -Version 7.6

<#
.SYNOPSIS
    Read each table to process: its sub type, plan, columns, rows over 90 days and billable volume.

.DESCRIPTION
    A table that cannot be read is an inventory row with its error, not a
    failure of the run.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCClassicTableInventory.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCClassicTableInventory {
    <#
    .SYNOPSIS
        Read each table to process: its sub type, plan, columns, rows over
        90 days and billable volume.

    .DESCRIPTION
        One row per table, read before anything changes, so the listing and
        the migration see the same picture. The rows are counted
        (Get-iSOCTableRowCount), unknown when they cannot be; the volume is
        the table's entry in -Volume, 0 when it has none, unknown when there
        is no volume at all. A table that cannot be read is a row with
        SubType Unreadable and the first line of the error.

    .PARAMETER Context
        The workspace context.

    .PARAMETER TableName
        The tables.

    .PARAMETER Volume
        Table name to GB, from Get-iSOCTableIngestionVolume; nothing when it
        could not be read.

    .OUTPUTS
        [pscustomobject[]] Name, SubType, Plan, ColumnCount, RowCount,
        GB90d, Columns and Error.

    .EXAMPLE
        Get-iSOCClassicTableInventory -Context $ctx -TableName MyApp_CL -Volume $volume
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $TableName,

        [AllowNull()]
        [hashtable] $Volume
    )

    foreach ($table in $TableName) {
        try {
            $detail = Get-iSOCWorkspaceTableDetail -Context $Context -Table $table
            $gb = if ($null -eq $Volume) { $null }
            elseif ($Volume.ContainsKey($table)) { $Volume[$table] }
            else { 0.0 }
            $rows = Get-iSOCTableRowCount -Context $Context -Table $table

            [pscustomobject]@{
                Name        = $detail.Name
                SubType     = $detail.SubType
                Plan        = $detail.Plan
                ColumnCount = $detail.Columns.Count
                RowCount    = $rows
                GB90d       = $gb
                Columns     = $detail.Columns
                Error       = $null
            }
        } catch {
            [pscustomobject]@{
                Name        = $table
                SubType     = 'Unreadable'
                Plan        = ''
                ColumnCount = 0
                RowCount    = $null
                GB90d       = $null
                Columns     = @()
                Error       = $_.Exception.Message.Split([char]10)[0]
            }
        }
    }
}
