#Requires -Version 7.6

<#
.SYNOPSIS
    Add today's maturity record to a history, replacing the same day.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/State/Add-SacMaturityHistoryEntry.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Add-SacMaturityHistoryEntry {
    <#
    .SYNOPSIS
        Return a new history with one entry appended: the same bundle
        published twice replaces its earlier entry, and the oldest entries
        are dropped past -MaxEntries. Pure; the input is not changed.

    .PARAMETER History
        @{ entries = @(...) } as Read-SacMaturityHistory returns it.

    .PARAMETER Entry
        A hashtable with at least bundleBuiltUtc, publishedUtc and overall.

    .PARAMETER MaxEntries
        How many entries to keep. Defaults to 180 (half a year of daily runs).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [hashtable] $History,
        [Parameter(Mandatory)] [hashtable] $Entry,
        [Parameter()] [ValidateRange(1, 10000)] [int] $MaxEntries = 180
    )
    $key = [string]$Entry.bundleBuiltUtc
    $kept = @($History.entries | Where-Object { $_ -and ([string]$_.bundleBuiltUtc) -ne $key })
    $entries = @($kept) + @($Entry)
    if ($entries.Count -gt $MaxEntries) { $entries = @($entries | Select-Object -Last $MaxEntries) }
    return @{ entries = $entries }
}
