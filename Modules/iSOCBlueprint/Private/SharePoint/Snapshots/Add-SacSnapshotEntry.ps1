#Requires -Version 7.6

<#
.SYNOPSIS
    Add a day to the snapshot index.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Snapshots/Add-SacSnapshotEntry.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Add-SacSnapshotEntry {
    <#
    .SYNOPSIS
        Return a new snapshot list with one day's entry added: a second
        publish on the same day replaces that day's entry, and days older
        than -Days before the newest drop out. Pure; the input is not
        changed.

    .PARAMETER Index
        @{ entries = @(...) } as Read-SacSnapshotIndex returns it.

    .PARAMETER Entry
        A hashtable with at least date (yyyy-MM-dd) and file.

    .PARAMETER Days
        How many days to keep, counting back from the newest. Defaults to 90.

    .OUTPUTS
        [hashtable] @{ entries = @(...) newest first; removed = @(file names
        of the days that dropped out) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [hashtable] $Index,
        [Parameter(Mandatory)] [hashtable] $Entry,
        [Parameter()] [ValidateRange(1, 3650)] [int] $Days = 90
    )
    $date = [string]$Entry.date
    $all = @(@(@($Index.entries | Where-Object { $_ -and [string]$_.date -and [string]$_.date -ne $date }) + @($Entry)) |
            Sort-Object @{ Expression = { [string]$_.date }; Descending = $true })
    $newest = [datetime]::ParseExact([string]$all[0].date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $cutoff = $newest.AddDays(1 - $Days).ToString('yyyy-MM-dd')
    $kept = @($all | Where-Object { [string]::CompareOrdinal([string]$_.date, $cutoff) -ge 0 })
    $removed = @($all | Where-Object { [string]::CompareOrdinal([string]$_.date, $cutoff) -lt 0 } | ForEach-Object { [string]$_.file } | Where-Object { $_ })
    return @{ entries = $kept; removed = $removed }
}
