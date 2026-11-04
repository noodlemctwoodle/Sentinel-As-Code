#Requires -Version 7.2

<#
.SYNOPSIS
    Make one synthetic record that matches a stream's columns.

.DESCRIPTION
    Every declared column gets a value of its type; strings carry the run
    marker, so the run's rows can be found.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/New-iSOCStreamRecord.ps1
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

function New-iSOCStreamRecord {
    <#
    .SYNOPSIS
        Make one synthetic record that matches a stream's columns.

    .DESCRIPTION
        Each declared column gets a value of its type: datetime the
        reference time, int and long the index, real a number from it,
        boolean whether it is even, dynamic an object with the index and the
        run marker, and anything else a string carrying the run marker, so
        the run's rows can be found. TimeGenerated is always set.

    .PARAMETER StreamColumn
        The stream's columns.

    .PARAMETER Index
        The record's number in the run.

    .PARAMETER RunId
        The run marker.

    .PARAMETER ReferenceTime
        The time stamped on the record.

    .OUTPUTS
        [hashtable]

    .EXAMPLE
        New-iSOCStreamRecord -StreamColumn $columns -Index 0 -RunId $runId -ReferenceTime ([datetime]::UtcNow)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a record in memory; changes nothing.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [object[]] $StreamColumn,

        [Parameter(Mandatory)]
        [int] $Index,

        [Parameter(Mandatory)]
        [string] $RunId,

        [Parameter(Mandatory)]
        [datetime] $ReferenceTime
    )

    $record = @{}
    foreach ($column in $StreamColumn) {
        $name = $column.name
        $type = ([string]$column.type).ToLowerInvariant()
        $record[$name] = switch ($type) {
            'datetime' { $ReferenceTime.ToString('o') }
            'int' { $Index }
            'long' { [long]$Index }
            'real' { [math]::Round(($Index * 1.5) + 0.5, 2) }
            'boolean' { (($Index % 2) -eq 0) }
            'dynamic' { @{ index = $Index; runId = $RunId } }
            default { "dcr-test $RunId #$Index" }
        }
    }
    if (-not $record.ContainsKey('TimeGenerated')) { $record['TimeGenerated'] = $ReferenceTime.ToString('o') }
    $record
}
