#Requires -Version 7.6

<#
.SYNOPSIS
    Make synthetic records whose fields give a classic table every column suffix.

.DESCRIPTION
    Strings, doubles, booleans and GUIDs, so the Data Collector API makes _s,
    _d, _b and _g columns, and a timestamp that becomes TimeGenerated.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/New-iSOCFixtureRecord.ps1
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

function New-iSOCFixtureRecord {
    <#
    .SYNOPSIS
        Make synthetic records whose fields give a classic table every
        column suffix.

    .DESCRIPTION
        The Data Collector API infers each field's type and suffixes the
        column: a string _s, a double _d, a boolean _b and a GUID-shaped
        string _g. Each record has SourceHost, SourceIp, Severity and
        Message (strings), DurationMs (a double), Success (a boolean),
        EventId (a GUID) and Timestamp, which is sent as the
        time-generated-field and so becomes TimeGenerated. Records count
        back a second at a time from -ReferenceTime.

    .PARAMETER Count
        How many records.

    .PARAMETER ReferenceTime
        The newest record's time, in UTC.

    .PARAMETER SeedGuid
        One GUID for every record's EventId; a new GUID each when omitted.

    .OUTPUTS
        [System.Collections.Generic.List[hashtable]]

    .EXAMPLE
        New-iSOCFixtureRecord -Count 50 -ReferenceTime ([datetime]::UtcNow)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds records in memory; changes nothing.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[hashtable]])]
    param(
        [Parameter(Mandatory)]
        [int] $Count,

        [Parameter(Mandatory)]
        [datetime] $ReferenceTime,

        [string] $SeedGuid
    )

    $hosts = 'web-01', 'web-02', 'db-01', 'app-01'
    $severities = 'Information', 'Warning', 'Error'
    $records = [System.Collections.Generic.List[hashtable]]::new()

    for ($i = 0; $i -lt $Count; $i++) {
        $guid = if ($SeedGuid) { $SeedGuid } else { [guid]::NewGuid().ToString() }
        $records.Add(@{
                Timestamp  = $ReferenceTime.AddSeconds(-1 * $i).ToString('o')
                SourceHost = $hosts[$i % $hosts.Count]
                SourceIp   = "10.0.$($i % 255).$((($i * 7) % 255))"
                Severity   = $severities[$i % $severities.Count]
                Message    = "Synthetic fixture record $i for classic-table migration testing."
                DurationMs = [math]::Round((($i * 13.7) % 900) + 1.5, 2)
                Success    = (($i % 5) -ne 0)
                EventId    = $guid
            })
    }
    , $records
}
