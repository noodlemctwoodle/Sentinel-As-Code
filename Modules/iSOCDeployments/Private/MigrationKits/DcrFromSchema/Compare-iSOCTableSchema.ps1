#Requires -Version 7.2

<#
.SYNOPSIS
    Compare the schema's columns with a table that already exists.

.DESCRIPTION
    A new column can be added; an existing column's type cannot change.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Compare-iSOCTableSchema.ps1
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

function Compare-iSOCTableSchema {
    <#
    .SYNOPSIS
        Compare the schema's columns with a table that already exists.

    .DESCRIPTION
        Added: the schema's columns the table does not have. Conflicts: a
        column whose live type differs from the schema's, which Azure
        refuses. OnlyLive: the table's columns the schema leaves out (but
        not the underscore-led system ones), which survive the update.
        Names are matched with case.

    .PARAMETER DesiredColumn
        The schema's accepted columns.

    .PARAMETER ExistingColumn
        The live table's columns.

    .OUTPUTS
        [pscustomobject] Added, Conflicts and OnlyLive.

    .EXAMPLE
        Compare-iSOCTableSchema -DesiredColumn $columns -ExistingColumn $existing.Columns
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $DesiredColumn,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $ExistingColumn
    )

    $existingByName = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($column in $ExistingColumn) {
        if ($column -and $column.PSObject.Properties['name']) {
            $existingByName[[string]$column.name] = $column
        }
    }

    $added = [System.Collections.Generic.List[string]]::new()
    $conflicts = [System.Collections.Generic.List[string]]::new()

    foreach ($column in $DesiredColumn) {
        if (-not $existingByName.ContainsKey($column.Name)) {
            $added.Add($column.Name)
            continue
        }
        $live = $existingByName[$column.Name]
        $liveTypeRaw = if ($live.PSObject.Properties['type']) { [string]$live.type } else { 'string' }
        $liveType = Get-iSOCTableColumnType -DeclaredType $liveTypeRaw
        if ($liveType -and $liveType -ne $column.Type) {
            $conflicts.Add("$($column.Name): live table has '$liveType', the schema says '$($column.Type)'")
        }
    }

    $desiredNames = [System.Collections.Generic.HashSet[string]]::new([string[]] @($DesiredColumn | ForEach-Object { [string]$_.Name }), [StringComparer]::Ordinal)
    $onlyLive = @($existingByName.Keys | Where-Object { -not $desiredNames.Contains($_) -and $_ -notlike '_*' })

    [pscustomobject]@{
        Added     = $added.ToArray()
        Conflicts = $conflicts.ToArray()
        OnlyLive  = @($onlyLive | Sort-Object)
    }
}
