#Requires -Version 7.2

<#
.SYNOPSIS
    Whether a table is provably the dependency fixture's.

.DESCRIPTION
    Its name is in the fixture set, it is a CustomLog, it has the marker
    column, and it is not AzureDiagnostics.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Test-iSOCFixtureOwnedTable.ps1
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

function Test-iSOCFixtureOwnedTable {
    <#
    .SYNOPSIS
        Whether a table is provably the dependency fixture's.

    .DESCRIPTION
        Every one of: the name is in the fixture's closed set (not a prefix
        match), the table is a CustomLog, it has the SacFixtureMarker_s
        column only the fixture's records make, and it is not
        AzureDiagnostics. A table with the right name but no marker column
        belongs to someone else.

    .PARAMETER Table
        The table.

    .PARAMETER ExpectedTableName
        The fixture's table names.

    .OUTPUTS
        [bool]

    .EXAMPLE
        Test-iSOCFixtureOwnedTable -Table $table -ExpectedTableName $names
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [object] $Table,

        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]] $ExpectedTableName
    )

    if ($null -eq $Table) { return $false }
    $name = [string](Get-iSOCPropertyValue -InputObject $Table -Path 'name')
    if ([string]::IsNullOrWhiteSpace($name)) { return $false }
    if ($name -in @('AzureDiagnostics')) { return $false }

    $matched = $false
    foreach ($expected in @($ExpectedTableName)) {
        if ([string]::Equals($name, $expected, [System.StringComparison]::OrdinalIgnoreCase)) { $matched = $true; break }
    }
    if (-not $matched) { return $false }
    if ([string](Get-iSOCPropertyValue -InputObject $Table -Path 'properties.schema.tableType') -ne 'CustomLog') { return $false }

    $markerColumn = (Get-iSOCDependencyFixtureSetting).MarkerColumnName
    $columns = Get-iSOCPropertyValue -InputObject $Table -Path 'properties.schema.columns'
    foreach ($column in @($columns)) {
        if ($null -eq $column) { continue }
        $colName = $column.PSObject.Properties['name']
        if ($colName -and [string]::Equals([string]$colName.Value, $markerColumn, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    $false
}
