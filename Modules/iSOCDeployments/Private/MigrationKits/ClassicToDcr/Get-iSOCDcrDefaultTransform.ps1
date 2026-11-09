#Requires -Version 7.6

<#
.SYNOPSIS
    Build the transform that casts each stream column back to its table column's type.

.DESCRIPTION
    source when every declared column has the table's type, else source |
    extend with a cast for each column that differs.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCDcrDefaultTransform.ps1
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

function Get-iSOCDcrDefaultTransform {
    <#
    .SYNOPSIS
        Build the transform that casts each stream column back to its table
        column's type.

    .DESCRIPTION
        Azure Monitor requires every column a transform outputs to have the
        destination column's type, so a plain source passthrough fails
        (InvalidTransformOutput) wherever the stream declares a column as
        another type: a guid column declared string is the common case. For
        each column the stream declares with a type other than the table's,
        a cast to the table's type is added (toguid, toint, todatetime and
        the rest); a column dropped from the stream needs none, and a type
        with no cast is left to the passthrough with a warning. A table whose
        columns all match gets source.

    .PARAMETER SchemaColumn
        The table's columns, with their Tables API types.

    .PARAMETER StreamColumn
        The columns the stream declares.

    .OUTPUTS
        [string] The transform.

    .EXAMPLE
        Get-iSOCDcrDefaultTransform -SchemaColumn $detail.Columns -StreamColumn $conversion.Columns
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $SchemaColumn,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $StreamColumn
    )

    $castByType = @{
        'string'   = 'tostring'
        'int'      = 'toint'
        'long'     = 'tolong'
        'real'     = 'toreal'
        'boolean'  = 'tobool'
        'datetime' = 'todatetime'
        'guid'     = 'toguid'
        'dynamic'  = 'todynamic'
    }

    $streamTypeByName = @{}
    foreach ($stream in $StreamColumn) {
        if ($stream) { $streamTypeByName[$stream.name] = ([string]$stream.type).ToLowerInvariant() }
    }

    $casts = foreach ($column in $SchemaColumn) {
        if (-not $column) { continue }
        $name = $column.name
        if (-not $streamTypeByName.ContainsKey($name)) { continue }

        $tableType = ([string]$column.type).ToLowerInvariant()
        if ($tableType -eq 'bool') { $tableType = 'boolean' }
        $streamType = $streamTypeByName[$name]

        if ($streamType -ne $tableType) {
            if ($castByType.ContainsKey($tableType)) {
                '{0} = {1}({0})' -f $name, $castByType[$tableType]
            }
            else {
                Write-iSOCLog "Column '$name' has table type '$tableType' with no known cast; leaving it to passthrough." -Level Warning
            }
        }
    }

    $casts = @($casts)
    if ($casts.Count -eq 0) { return 'source' }
    'source | extend ' + ($casts -join ', ')
}
