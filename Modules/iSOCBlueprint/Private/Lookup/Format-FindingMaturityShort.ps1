#Requires -Version 7.6

<#
.SYNOPSIS
    A short label for a finding's effect on the maturity score

.DESCRIPTION
    One of the helpers beside Get-FindingMaturityLink.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Format-FindingMaturityShort.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-FindingMaturityShort {
    <#
    .SYNOPSIS
        A short label for a finding's effect on the maturity score: the
        lift and area when closing it lifts the score, the area alone when
        the criterion carries no lift, 'Not scored' when no criterion reads
        the finding.

    .PARAMETER Links
        The finding's entry from Get-FindingMaturityLink, or $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [object[]] $Links)

    if (-not $Links -or @($Links).Count -eq 0) { return 'Not scored' }
    $parts = @($Links | ForEach-Object {
            # The lift to two places, as the roadmap, the finding cards and
            # every score on the pages write it.
            if ($null -ne $_.Lift -and $_.Lift -gt 0) { '+{0} to {1}' -f ([double]$_.Lift).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture), $_.Area }
            else { $_.Area }
        } | Sort-Object -Unique)
    return ($parts -join '; ')
}
