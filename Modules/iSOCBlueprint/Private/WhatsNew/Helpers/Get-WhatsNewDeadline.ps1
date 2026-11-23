#Requires -Version 7.6

<#
.SYNOPSIS
    The latest date a retirement or call to action names.

.NOTES
    File:         Modules/iSOCBlueprint/Private/WhatsNew/Helpers/Get-WhatsNewDeadline.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, What's new reading
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-WhatsNewDeadline {
    <#
    .SYNOPSIS
        The date a retirement or call to action names, as yyyy-MM-dd, or
        yyyy-MM when it names only a month; the latest when it names more
        than one. $null when it names none.

    .PARAMETER Text
        The text to search for dates written as a month and year, or a month,
        day and year.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Text)
    $months = 'January|February|March|April|May|June|July|August|September|October|November|December'
    $found = foreach ($m in [regex]::Matches($Text, "(?i)\b($months)\s+(?:(\d{1,2})(?:st|nd|rd|th)?,?\s+)?(\d{4})\b")) {
        $mon = [datetime]::ParseExact($m.Groups[1].Value, 'MMMM', [System.Globalization.CultureInfo]::InvariantCulture).Month
        $year = [int]$m.Groups[3].Value
        if ($m.Groups[2].Success) {
            $day = [int]$m.Groups[2].Value
            if ($day -ge 1 -and $day -le [datetime]::DaysInMonth($year, $mon)) {
                [pscustomobject]@{ Sort = (Get-Date -Year $year -Month $mon -Day $day).Date; Text = '{0:D4}-{1:D2}-{2:D2}' -f $year, $mon, $day }
            }
        }
        else { [pscustomobject]@{ Sort = (Get-Date -Year $year -Month $mon -Day 1).Date; Text = '{0:D4}-{1:D2}' -f $year, $mon } }
    }
    if (-not $found) { return $null }
    return (@($found) | Sort-Object Sort | Select-Object -Last 1).Text
}
