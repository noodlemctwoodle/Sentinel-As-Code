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
    Version:      0.1.1
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
        Name the run's window in a criterion's text: {lookback} as the days
        the KQL captures read, {recent} as the latest days within it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory = $true)] $Window
    )
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $days = { param([int]$n) if ($n -eq 1) { '1 day' } else { "$n days" } }
    return $Text.Replace('{lookback}', (& $days $Window.Days)).Replace('{recent}', (& $days $Window.RecentDays))
}
