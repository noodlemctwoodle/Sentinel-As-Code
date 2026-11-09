#Requires -Version 7.6

<#
.SYNOPSIS
    Write an ISO 8601 duration in one spelling.

.DESCRIPTION
    Copied from ConvertTo-NormalisedDuration, which Tools/Test-SentinelRuleDrift.ps1
    and Deploy/content/Deploy-SentinelContentHub.ps1 each carry, unchanged in
    behaviour.

.NOTES
    File:         Modules/iSOCDeployments/Private/Drift/ConvertTo-iSOCCanonicalDuration.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCCanonicalDuration {
    <#
    .SYNOPSIS
        Return the spelling XmlConvert writes for a duration.

    .DESCRIPTION
        ISO 8601 has several spellings for one duration (PT24H and P1D), and
        the services return their own rather than the one a file was deployed
        with. Durations are compared in the form XmlConvert writes; a value
        that is not a valid duration comes back trimmed, as written.

    .PARAMETER Value
        The duration.

    .OUTPUTS
        [string] The canonical spelling, the trimmed input, or nothing for an
        empty value.

    .EXAMPLE
        ConvertTo-iSOCCanonicalDuration 'PT24H'

        Returns P1D.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $trimmed = $Value.Trim()
    try {
        [System.Xml.XmlConvert]::ToString([System.Xml.XmlConvert]::ToTimeSpan($trimmed.ToUpperInvariant()))
    }
    catch {
        $trimmed
    }
}
