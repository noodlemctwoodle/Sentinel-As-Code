#Requires -Version 7.6

<#
.SYNOPSIS
    The classic custom log tables, and every table and column name, from one tables call.

.DESCRIPTION
    The classic tables are the migration candidates. Every table and column
    name feeds the guard that stops a parser alias clashing with a real table
    or column from being followed.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCWorkspaceTableInventory.ps1
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

function Get-iSOCWorkspaceTableInventory {
    <#
    .SYNOPSIS
        The classic custom log tables, and every table and column name, from
        one tables call.

    .DESCRIPTION
        ClassicTables are the tables whose type is CustomLog and sub type
        Classic, except AzureDiagnostics, which can look classic but is
        managed by Microsoft and is never a candidate. AllTableNames is
        every table, built-in ones included, and AllColumnNames every
        column name, sorted and unique: a parser aliased Update or Location
        would otherwise make every query naming the real table or column
        look like it calls that parser.

    .PARAMETER Context
        The workspace context.

    .OUTPUTS
        [pscustomobject] ClassicTables (Name, TableType, TableSubType,
        Plan, RetentionInDays, TotalRetention, ColumnCount, ResourceId),
        AllTableNames and AllColumnNames.

    .EXAMPLE
        $inventory = Get-iSOCWorkspaceTableInventory -Context $ctx
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context
    )

    $tables = @(Invoke-iSOCRestRequest -Method GET -Path "$($Context.WorkspaceResourceId)/tables" -ApiVersion (Get-iSOCApiVersion OperationalInsights))
    $excluded = @('AzureDiagnostics')

    $classic = @($tables | Where-Object {
            (Get-iSOCPropertyValue -InputObject $_ -Path 'properties.schema.tableType') -eq 'CustomLog' -and
            (Get-iSOCPropertyValue -InputObject $_ -Path 'properties.schema.tableSubType') -eq 'Classic' -and
            (Get-iSOCPropertyValue -InputObject $_ -Path 'name') -notin $excluded
        })

    $projected = foreach ($t in $classic) {
        $columns = Get-iSOCPropertyValue -InputObject $t -Path 'properties.schema.columns'
        [pscustomobject]@{
            Name            = Get-iSOCPropertyValue -InputObject $t -Path 'name'
            TableType       = Get-iSOCPropertyValue -InputObject $t -Path 'properties.schema.tableType'
            TableSubType    = Get-iSOCPropertyValue -InputObject $t -Path 'properties.schema.tableSubType'
            Plan            = Get-iSOCPropertyValue -InputObject $t -Path 'properties.plan'
            RetentionInDays = Get-iSOCPropertyValue -InputObject $t -Path 'properties.retentionInDays'
            TotalRetention  = Get-iSOCPropertyValue -InputObject $t -Path 'properties.totalRetentionInDays'
            ColumnCount     = if ($null -eq $columns) { 0 } else { @($columns).Count }
            ResourceId      = Get-iSOCPropertyValue -InputObject $t -Path 'id'
        }
    }

    $columnName = foreach ($t in $tables) {
        $columns = Get-iSOCPropertyValue -InputObject $t -Path 'properties.schema.columns'
        foreach ($c in @($columns)) {
            $name = Get-iSOCPropertyValue -InputObject $c -Path 'name'
            if ($c -and $name) { $name }
        }
    }

    [pscustomobject]@{
        ClassicTables  = @($projected)
        AllTableNames  = @($tables | ForEach-Object { Get-iSOCPropertyValue -InputObject $_ -Path 'name' } | Where-Object { $_ })
        AllColumnNames = @($columnName | Where-Object { $_ } | Sort-Object -Unique)
    }
}
