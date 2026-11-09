#Requires -Version 7.6

<#
.SYNOPSIS
    Build the result Invoke-iSOCClassicTableMigration returns.

.DESCRIPTION
    An iSOCDeployments.TableMigrationRun: the tables it read, a result per
    table it processed, the counts and the exit code.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/New-iSOCTableMigrationRun.ps1
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

function New-iSOCTableMigrationRun {
    <#
    .SYNOPSIS
        Build the result Invoke-iSOCClassicTableMigration returns.

    .DESCRIPTION
        An iSOCDeployments.TableMigrationRun. Tables is the inventory as
        -ListOnly shows it (without the columns); Results has one entry per
        table processed. ExitCode is 1 when any table failed.

    .PARAMETER Tables
        The inventory, from Get-iSOCClassicTableInventory.

    .PARAMETER Results
        The results, from Invoke-iSOCTableMigrationItem.

    .OUTPUTS
        [pscustomobject] Tables, Results, Migrated, Deployed, Failed and
        ExitCode.

    .EXAMPLE
        New-iSOCTableMigrationRun -Tables $inventory -Results $results
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; changes nothing.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Tables = @(),

        [AllowEmptyCollection()]
        [object[]] $Results = @()
    )

    $failed = @($Results | Where-Object { $_.Error }).Count
    [pscustomobject]@{
        PSTypeName = 'iSOCDeployments.TableMigrationRun'
        Tables     = @($Tables | Select-Object Name, SubType, Plan, ColumnCount, RowCount, GB90d, Error)
        Results    = @($Results)
        Migrated   = @($Results | Where-Object { $_.Migrated }).Count
        Deployed   = @($Results | Where-Object { $_.Deployed }).Count
        Failed     = $failed
        ExitCode   = if ($failed -gt 0) { 1 } else { 0 }
    }
}
