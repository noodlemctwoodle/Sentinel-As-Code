#Requires -Version 7.6

<#
.SYNOPSIS
    Make the few records that bring one dependency fixture table into being.

.DESCRIPTION
    Every record carries the ownership marker, which becomes the
    SacFixtureMarker_s column.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/New-iSOCDependencyFixtureRecord.ps1
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

function New-iSOCDependencyFixtureRecord {
    <#
    .SYNOPSIS
        Make the few records that bring one dependency fixture table into
        being.

    .DESCRIPTION
        The Data Collector API makes the table from the first post, each
        string field a _s column. Every record carries the marker field,
        which becomes the SacFixtureMarker_s column: the only ownership
        evidence a table can hold, and readable from the Tables API without
        a query. The batch is small on purpose: ingestion is billable and
        cannot be recalled.

    .PARAMETER Count
        How many records.

    .PARAMETER ReferenceTime
        The newest record's time, in UTC; records count back a second at a
        time.

    .PARAMETER Marker
        The ownership marker written into every record.

    .PARAMETER ScenarioName
        The scenario the table belongs to.

    .OUTPUTS
        [System.Collections.Generic.List[hashtable]]

    .EXAMPLE
        New-iSOCDependencyFixtureRecord -Count 5 -ReferenceTime ([datetime]::UtcNow) -Marker $marker -ScenarioName OneHop
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds records in memory; changes nothing.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[hashtable]])]
    param(
        [Parameter(Mandatory)]
        [int] $Count,

        [Parameter(Mandatory)]
        [datetime] $ReferenceTime,

        [Parameter(Mandatory)]
        [string] $Marker,

        [Parameter(Mandatory)]
        [string] $ScenarioName
    )

    $markerField = (Get-iSOCDependencyFixtureSetting).MarkerFieldName
    $sourceHost = 'fixture-01', 'fixture-02', 'fixture-03'
    $severity = 'Information', 'Warning'
    $records = [System.Collections.Generic.List[hashtable]]::new()
    for ($i = 0; $i -lt $Count; $i++) {
        $records.Add(@{
                Timestamp    = $ReferenceTime.AddSeconds(-1 * $i).ToString('o')
                SourceHost   = $sourceHost[$i % $sourceHost.Count]
                Severity     = $severity[$i % $severity.Count]
                Scenario     = $ScenarioName
                Message      = "Dependency fixture record $i for scenario $ScenarioName."
                $markerField = $Marker
            })
    }
    , $records
}
