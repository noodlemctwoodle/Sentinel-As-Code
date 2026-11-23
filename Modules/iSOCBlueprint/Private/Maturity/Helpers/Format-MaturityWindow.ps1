#Requires -Version 7.6

<#
.SYNOPSIS
    Name the run's window in a criterion's text.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Maturity/Helpers/Format-MaturityWindow.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Maturity Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-MaturityWindow {
    <#
    .SYNOPSIS
        Name the run's window in a criterion's text.

    .DESCRIPTION
        {lookback} becomes the days the KQL captures read and {recent} the
        latest days within it, each as a count of days, or as 1 day when the
        count is one.

    .PARAMETER Text
        The criterion's text. It is returned as it is when null or empty.

    .PARAMETER Window
        The run's window: Days is the lookback and RecentDays the latest days
        within it.

    .OUTPUTS
        [string] The text with the window named.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory = $true)] $Window
    )
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $days = { param([int]$n) if ($n -eq 1) { '1 day' } else { "$n days" } }
    return $Text.Replace('{lookback}', (& $days $Window.Days)).Replace('{recent}', (& $days $Window.RecentDays))
}
