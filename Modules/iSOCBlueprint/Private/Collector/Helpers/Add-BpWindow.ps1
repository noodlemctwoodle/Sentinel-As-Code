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
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Add-BpWindow {
    <#
    .SYNOPSIS
        Declare the lookback, recent and daily windows ahead of a KQL query.

    .DESCRIPTION
        One lookback for every query. A query names it as `lookback` (its main
        window) and `recent` (the latest days within it, the shorter of 7 days
        and the lookback); the daily series name `daily`. The three are
        declared as let statements from the script-scope LookbackDays,
        RecentDays and DailyDays, so no query carries a number of days of its
        own. daily is DailyDays when that is 1 or more, else the smaller of 90
        and LookbackDays. Two sub-windows stay fixed because they are not
        lookbacks: a table's last 24 hours of ingestion and the one-hour sample
        the duplicate-event check reads.

    .PARAMETER Kql
        The query text the declarations are placed before.

    .OUTPUTS
        [string] The three let statements followed by the query.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param([string]$Kql)
    $daily = if ($script:DailyDays -ge 1) { $script:DailyDays } else { [math]::Min(90, $script:LookbackDays) }
    "let lookback = $($script:LookbackDays)d;`nlet recent = $($script:RecentDays)d;`nlet daily = $($daily)d;`n$Kql"
}
