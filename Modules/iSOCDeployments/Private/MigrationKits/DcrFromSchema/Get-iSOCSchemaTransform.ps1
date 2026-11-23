#Requires -Version 7.6

<#
.SYNOPSIS
    Build the ingestion-time transform that casts each stream column back to its table column's type.

.DESCRIPTION
    Azure checks that every column the transform outputs has the table's type,
    so a plain passthrough of a guid column fails.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Get-iSOCSchemaTransform.ps1
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

function Get-iSOCSchemaTransform {
    <#
    .SYNOPSIS
        Build the ingestion-time transform that casts each stream column
        back to its table column's type.

    .DESCRIPTION
        For each column whose stream type differs from its table type, an
        extend with the cast to the table type (EventId = toguid(EventId));
        'source' when none differ. A table type with no known cast is a
        warning and left to the passthrough. Columns are matched by name
        with case, as the schema may hold names that differ only by case,
        which Get-iSOCDcrDefaultTransform (for classic tables) does not.

    .PARAMETER Column
        The accepted table columns.

    .PARAMETER StreamColumn
        The stream columns.

    .OUTPUTS
        [string] The transform.

    .EXAMPLE
        Get-iSOCSchemaTransform -Column $columns -StreamColumn $streamColumns
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Column,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $StreamColumn
    )

    $castByType = (Get-iSOCTableSchemaSetting).CastByType
    $streamTypeByName = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    foreach ($stream in $StreamColumn) {
        if ($stream) { $streamTypeByName[[string]$stream.name] = ([string]$stream.type).ToLowerInvariant() }
    }

    $casts = foreach ($entry in $Column) {
        if (-not $entry) { continue }
        $name = $entry.Name
        if (-not $streamTypeByName.ContainsKey($name)) { continue }

        $tableType = ([string]$entry.Type).ToLowerInvariant()
        $streamType = $streamTypeByName[$name]
        if ($streamType -ne $tableType) {
            if ($castByType.ContainsKey($tableType)) {
                '{0} = {1}({0})' -f $name, $castByType[$tableType]
            } else {
                Write-iSOCLog "Column '$name' has table type '$tableType' with no known cast; leaving it to passthrough." -Level Warning
            }
        }
    }

    $casts = @($casts)
    if ($casts.Count -eq 0) { return 'source' }
    'source | extend ' + ($casts -join ', ')
}
