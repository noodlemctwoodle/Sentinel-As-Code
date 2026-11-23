#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 13-data-source-hygiene.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/DataSourceHygiene/Write-BlueprintDataSourceHygieneSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintDataSourceHygieneSection {
    <#
    .SYNOPSIS
        Build the figures for and write 13-data-source-hygiene.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $m = $Context.m
    $n = $Context.n
    $v = $Context.v

    # Section 13 — Data source hygiene
    $cefDevices = Read-BlueprintRawArray 'cef-devices.json'
    $cefInSyslog = Read-BlueprintRawArray 'cef-in-syslog.json'
    $secEvtDupes = Read-BlueprintRawArray 'security-event-duplicates.json'
    $topEventIds = Read-BlueprintRawArray 'top-event-ids.json'

    $cefDevRows = $cefDevices | ForEach-Object {
        [pscustomobject]@{ DeviceVendor = $_.DeviceVendor; DeviceProduct = $_.DeviceProduct; LogCount = Format-BlueprintCount $_.LogCount }
    }
    $cefSyslogRows = $cefInSyslog | ForEach-Object {
        [pscustomobject]@{
            Computer      = $_.Computer
            ProductVendor = Get-BlueprintRawProperty $_ 'ProductVendor' ''
            LogCount      = Format-BlueprintCount $_.LogCount
        }
    }
    $secEvtDupeRows = $secEvtDupes | ForEach-Object {
        [pscustomobject]@{
            Computer          = $_.Computer
            DuplicateRecords  = Format-BlueprintCount (Get-BlueprintRawProperty $_ 'DuplicateRecords' '')
            Copies            = Format-BlueprintCount $_.LogCount
            DuplicateEventIds = (@($_.DuplicateEventIds) -join ', ')
        }
    }
    $topEventIdRows = $topEventIds | ForEach-Object {
        [pscustomobject]@{
            TableName        = $_.TableName
            EventID          = $_.EventID
            EventDescription = $_.EventDescription
            LogCount         = Format-BlueprintCount (Get-BlueprintRawProperty $_ 'LogCount' '')
            BilledSizeGB     = $_.BilledSizeGB
        }
    }

    # Aggregate CEF logs by DeviceVendor for the headline pie.
    $cefByVendor = @{}
    foreach ($r in $cefDevices) {
        $v = if ($r.DeviceVendor) { [string]$r.DeviceVendor } else { 'Unknown' }
        if (-not $cefByVendor.ContainsKey($v)) { $cefByVendor[$v] = 0 }
        $cefByVendor[$v] += [long]$r.LogCount
    }
    $cefPieRows = Format-PieSlices -Counts $cefByVendor -Limit 6
    $cefChartBlock = if ($cefDevices.Count -gt 0) {
        @"

## CEF vendor mix

``````mermaid
pie showData title CommonSecurityLog by DeviceVendor (last {lookback-d})
$($cefPieRows -join [Environment]::NewLine)
``````

A single vendor dominating means CEF ingestion is mostly that source, likely a candidate for SAC-LOG-15 (`_CL` split) if volume is high.
"@
    } else { '' }

    # Log composition by host: who writes Syslog (by facility) and SecurityEvent.
    $syslogContribRows = @(Read-BlueprintRawArray 'syslog-contributors.json' | Where-Object { $_ } | ForEach-Object {
            [pscustomobject]@{
                Computer = $_.Computer
                Facility = $_.Facility
                LogCount = Format-BlueprintCount $_.LogCount
                SizeMB   = Format-BlueprintNumber $_.SizeMB
            }
        })
    $secEventHostRows = @(Read-BlueprintRawArray 'securityevent-top-hosts.json' | Where-Object { $_ } | ForEach-Object {
            [pscustomobject]@{ Computer = $_.Computer; LogCount = Format-BlueprintCount $_.LogCount; SizeMB = Format-BlueprintNumber $_.SizeMB }
        })
    Write-BlueprintSection '13-data-source-hygiene.md' (@"
$(Format-Banner -Title "Data Source Hygiene")

Operational data-quality findings that drive ingestion-tuning actions: misrouted records, agent dual-collection, and noisy event types. Each table is independent and may show ``_None._`` when the workspace has nothing to report against that check.
$cefChartBlock

## CEF devices (last {lookback-d})

Per-vendor / per-product CEF record counts. A vendor + product combination with very low counts is usually either a misconfigured collector or a forwarder that needs filtering at source.

$(Format-BlueprintTable -Items $cefDevRows -Columns 'DeviceVendor','DeviceProduct','LogCount')

## CEF records misrouted into Syslog (last {lookback-d})

A non-empty table here means a Linux syslog forwarder is shipping CEF-formatted records (a message starting ``CEF:`` or ``0|``) to the wrong workspace table, by forwarder and the vendor and product in the CEF header. Point a CEF data collection rule at the forwarder so the records land parsed in CommonSecurityLog ([SAC-LOG-23]).

$(Format-BlueprintTable -Items $cefSyslogRows -Columns 'Computer','ProductVendor','LogCount')

## SecurityEvent duplicates (last 1h)

Computers reporting duplicate SecurityEvent records within a one-hour window: **Duplicate records** is how many distinct events arrived more than once, **Copies** the total rows those events produced. Almost always an MMA + AMA dual-collection misconfiguration or two DCRs collecting the same events; consolidate the collection path ([SAC-LOG-22]).

$(Format-BlueprintTable -Items $secEvtDupeRows -Columns 'Computer','DuplicateRecords','Copies','DuplicateEventIds')

## Event IDs by billed size (last {lookback-d})

Every Windows event ID in the Event and SecurityEvent tables, largest billed size first, with the record count. Each row is a candidate for filtering at the DCR transform stage.

$(Format-BlueprintTable -Items $topEventIdRows -Columns 'TableName','EventID','EventDescription','LogCount','BilledSizeGB')

## Syslog contributors (last {lookback-d})

Hosts and facilities writing to ``Syslog``, by record count and billed size. One host or facility out of proportion with the rest is the usual sign of a debug level left on or a forwarder relaying a whole network; both are DCR filter candidates.

$(Format-BlueprintTable -Items $syslogContribRows -Columns 'Computer','Facility','LogCount','SizeMB')

## SecurityEvent hosts (last {lookback-d})

Every host writing ``SecurityEvent`` records, most records first. Domain controllers lead on every estate; a member server near the top usually means an audit policy or an event-ID set that is wider than the detections need.

$(Format-BlueprintTable -Items $secEventHostRows -Columns 'Computer','LogCount','SizeMB')

[Filter Windows Security events via DCR (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/connect-windows-security-events)
"@)

    # Left in the render context for later sections.
    $Context.r = $r
}
