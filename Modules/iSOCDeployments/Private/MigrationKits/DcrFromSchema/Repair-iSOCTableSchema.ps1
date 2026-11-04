#Requires -Version 7.2

<#
.SYNOPSIS
    Make the schema fixes that have one sensible answer.

.DESCRIPTION
    A bad type is left for the schema's author: guessing long or real for a
    count changes what is stored.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Repair-iSOCTableSchema.ps1
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

function Repair-iSOCTableSchema {
    <#
    .SYNOPSIS
        Make the schema fixes that have one sensible answer.

    .DESCRIPTION
        A column whose name Azure will never accept is dropped, and so is
        an exact repeat of an earlier name (names differing by case are two
        columns on Analytics and Basic tables, so both are kept). An invalid
        dataTypeHint is removed and the column kept. A TimeGenerated that
        is not datetime is made datetime, and a missing one is added first.
        Each change is a warning. A bad type is not changed.

    .PARAMETER Column
        The checked columns, from Resolve-iSOCTableSchema.

    .OUTPUTS
        [pscustomobject[]] The columns kept.

    .EXAMPLE
        $columns = @(Repair-iSOCTableSchema -Column $analysis.Columns.ToArray())
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Column
    )

    $kept = [System.Collections.Generic.List[pscustomobject]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    foreach ($entry in $Column) {
        $nameErrors = @($entry.Issues | Where-Object { $_.Severity -eq 'Error' -and $_.Message -notlike 'type *' -and $_.Message -notlike 'dataTypeHint *' })
        if ($nameErrors.Count -gt 0) {
            Write-iSOCLog "Dropping column '$($entry.Name)': $($nameErrors[0].Message)." -Level Warning
            continue
        }

        if (-not $seen.Add($entry.Name)) {
            Write-iSOCLog "Dropping duplicate column '$($entry.Name)'." -Level Warning
            continue
        }

        $hintErrors = @($entry.Issues | Where-Object { $_.Severity -eq 'Error' -and $_.Message -like 'dataTypeHint *' })
        if ($hintErrors.Count -gt 0) {
            Write-iSOCLog "Removing the invalid dataTypeHint '$($entry.DataTypeHint)' from column '$($entry.Name)'. The column is kept." -Level Warning
            $entry.DataTypeHint = ''
        }

        if ($entry.Name -eq 'TimeGenerated' -and $entry.Type -ne 'dateTime') {
            Write-iSOCLog "Correcting TimeGenerated from '$($entry.DeclaredType)' to datetime." -Level Warning
            $entry.Type = 'dateTime'
            $entry.DeclaredType = 'datetime'
        }

        $kept.Add($entry)
    }

    if (-not $seen.Contains('TimeGenerated')) {
        Write-iSOCLog 'Adding the required TimeGenerated column.' -Level Warning
        $kept.Insert(0, (New-iSOCSchemaColumn -Name 'TimeGenerated' -Type 'dateTime'))
    }

    $kept.ToArray()
}
