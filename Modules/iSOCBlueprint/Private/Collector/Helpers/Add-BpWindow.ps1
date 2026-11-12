#Requires -Version 7.6

<#
.SYNOPSIS
    Declare the lookback, recent and daily windows ahead of a KQL query.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Helpers/Add-BpWindow.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# One lookback for every query. A query names it as `lookback` (its main
# window) and `recent` (the latest days within it, the shorter of 7 days and
# the lookback); the daily series name `daily` (below). Add-BpWindow declares
# all three ahead of the query text, so no query carries a number of days of
# its own. Two sub-windows stay fixed because they are not lookbacks: a
# table's last 24 hours of ingestion and the one-hour sample the
# duplicate-event check reads.
function Add-BpWindow([string]$Kql) {
    $daily = if ($script:DailyDays -ge 1) { $script:DailyDays } else { [math]::Min(90, $script:LookbackDays) }
    "let lookback = $($script:LookbackDays)d;`nlet recent = $($script:RecentDays)d;`nlet daily = $($daily)d;`n$Kql"
}
