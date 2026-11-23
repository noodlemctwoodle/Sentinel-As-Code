#Requires -Version 7.6

<#
.SYNOPSIS
    Return the days from today until a date.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/LiveSnapshot/Get-BlueprintDaysUntil.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-BlueprintDaysUntil {
    <#
    .SYNOPSIS
        Return the days from today until a date.

    .DESCRIPTION
        The date is read as UTC and the difference from now (UTC) is rounded up to
        whole days, so it is zero or negative once the date has passed.

    .PARAMETER IsoDate
        The date, as text such as 2026-09-14.

    .OUTPUTS
        [int].
    #>
    [CmdletBinding()]
    param([string]$IsoDate)
    $target = [datetime]::Parse($IsoDate, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
    $delta = $target.ToUniversalTime() - (Get-Date).ToUniversalTime()
    [int][math]::Ceiling($delta.TotalDays)
}
