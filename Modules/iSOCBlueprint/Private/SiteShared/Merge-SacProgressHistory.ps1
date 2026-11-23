#Requires -Version 7.6

<#
.SYNOPSIS
    A history with the given records added

.DESCRIPTION
    Split from Get-SacProgress.ps1 so each file holds one function.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SiteShared/Merge-SacProgressHistory.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Merge-SacProgressHistory {
    <#
    .SYNOPSIS
        A history with the given records added: one record a day (a later
        record for the same day replaces the earlier), oldest first, and
        none more than -Days days before the newest (a run exactly -Days
        earlier is kept, so the dashboard's 90-day baseline has one). Pure;
        the inputs are not changed.

    .PARAMETER History
        The history so far, @{ entries = @(...) }, or $null.

    .PARAMETER Records
        Records to add.

    .PARAMETER Days
        How many days back from the newest record to keep, that day
        included. Defaults to 90.

    .OUTPUTS
        [ordered] schemaVersion and entries.
    #>
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [CmdletBinding()]
    param(
        [AllowNull()] $History,
        [AllowNull()] [AllowEmptyCollection()] [object[]] $Records = @(),
        [ValidateRange(1, 3650)] [int] $Days = 90
    )
    $byDate = [ordered]@{}
    $add = {
        param($r)
        if ($null -eq $r) { return }
        $d = [string](Get-SacProgressValue -Object $r -Path 'date')
        if ($d -match '^\d{4}-\d{2}-\d{2}$') { $byDate[$d] = $r }
    }
    foreach ($e in @(Get-SacProgressValue -Object $History -Path 'entries')) { & $add $e }
    foreach ($r in @($Records)) { & $add $r }
    $dates = @($byDate.Keys | Sort-Object)
    if ($dates.Count) {
        $cutoff = [datetime]::ParseExact($dates[-1], 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture).AddDays(-$Days).ToString('yyyy-MM-dd')
        $dates = @($dates | Where-Object { [string]::CompareOrdinal($_, $cutoff) -ge 0 })
    }
    [ordered]@{ schemaVersion = 1; entries = @($dates | ForEach-Object { $byDate[$_] }) }
}
