#Requires -Version 7.6

<#
.SYNOPSIS
    Turn a rule frequency, or a retired period, into the canonical ISO
    8601 duration.

.DESCRIPTION
    Copied from ConvertTo-DetectionFrequency
    (Deploy/content/Deploy-DefenderDetections.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/ConvertTo-iSOCDefenderDetectionFrequency.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCDefenderDetectionFrequency {
    <#
    .SYNOPSIS
        Return the frequency as XmlConvert writes it, or nothing when the
        service does not run it.

    .DESCRIPTION
        PT24H and P1D both become P1D, and a retired period such as 3H
        becomes PT3H. The service runs rules every 1, 3, 12 or 24 hours;
        anything else returns nothing.

    .PARAMETER Value
        The frequency or period as the file writes it.

    .OUTPUTS
        [string] The canonical duration; nothing when it is not one the
        service runs.

    .EXAMPLE
        ConvertTo-iSOCDefenderDetectionFrequency -Value 'PT24H'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $text = $Value.Trim().ToUpperInvariant()
    if ($text -match '^(\d+)H$') { $text = "PT$($Matches[1])H" }

    try { $span = [System.Xml.XmlConvert]::ToTimeSpan($text) }
    catch { return $null }

    if ($span.TotalHours -notin (Get-iSOCDefenderDetectionContract).ValidDetectionFrequencyHours) { return $null }
    [System.Xml.XmlConvert]::ToString($span)
}
