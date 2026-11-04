#Requires -Version 7.2

<#
.SYNOPSIS
    Log the tables to process, and warn of those with no rows.

.DESCRIPTION
    A line per table with its sub type, columns, rows and volume; an empty
    classic table is usually an abandoned forwarder.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Write-iSOCClassicTableInventory.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-iSOCClassicTableInventory {
    <#
    .SYNOPSIS
        Log the tables to process, and warn of those with no rows.

    .DESCRIPTION
        A line per table: name, sub type, columns, rows over 90 days
        (unknown when they could not be counted) and billable GB (n/a when
        the volume could not be read), and the error of a table that could
        not be read. Tables with no rows are named: an empty classic table
        is usually an abandoned forwarder, better deleted than migrated. A
        table whose rows are unknown is not called empty.

    .PARAMETER Inventory
        From Get-iSOCClassicTableInventory.

    .EXAMPLE
        Write-iSOCClassicTableInventory -Inventory $inventory
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Inventory
    )

    Write-iSOCLog ''
    Write-iSOCLog ('{0,-42} {1,-24} {2,6} {3,12} {4,12}' -f 'TABLE', 'SUBTYPE', 'COLS', 'ROWS (90d)', 'GB (Usage)')
    foreach ($row in $Inventory) {
        $rowsText = if ($null -eq $row.RowCount) { 'unknown' } else { '{0:N0}' -f $row.RowCount }
        $gbText = if ($null -eq $row.GB90d) { 'n/a' } else { '{0:N4}' -f $row.GB90d }
        Write-iSOCLog ('{0,-42} {1,-24} {2,6} {3,12} {4,12}' -f $row.Name, $row.SubType, $row.ColumnCount, $rowsText, $gbText)
        if ($row.Error) { Write-iSOCLog "    ! $($row.Error)" -Level Warning }
    }

    $emptyTables = @($Inventory | Where-Object { $_.RowCount -eq 0 -and -not $_.Error })
    if ($emptyTables.Count -gt 0) {
        Write-iSOCLog ''
        Write-iSOCLog "$($emptyTables.Count) table(s) have no rows in the last 90 days: $(($emptyTables.Name) -join ', ')." -Level Warning
        Write-iSOCLog 'An empty classic table is usually an abandoned forwarder. Migrating it carries legacy cruft forward rather than removing it. Consider deleting those tables instead.' -Level Warning
    }
}
