#Requires -Version 7.6

<#
.SYNOPSIS
    Compare two dotted version strings.

.DESCRIPTION
    Copied from Compare-SemanticVersion
    (Deploy/content/Deploy-SentinelContentHub.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Compare-iSOCSemanticVersion.ps1
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

function Compare-iSOCSemanticVersion {
    <#
    .SYNOPSIS
        Return 1 when the first version is newer, -1 when older, 0 when the
        same.

    .DESCRIPTION
        Each dotted part is compared as a whole number, a missing part
        counting as 0 (1.2 equals 1.2.0). A version with a part that is not
        a number is compared as text, ordinally.

    .PARAMETER Version1
        The first version.

    .PARAMETER Version2
        The second version.

    .OUTPUTS
        [int] 1, -1 or 0; any sign for the text comparison.

    .EXAMPLE
        Compare-iSOCSemanticVersion -Version1 '3.0.10' -Version2 '3.0.9'
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string] $Version1,

        [Parameter(Mandatory)]
        [string] $Version2
    )

    try {
        $v1Parts = $Version1.Split('.') | ForEach-Object { [int]$_ }
        $v2Parts = $Version2.Split('.') | ForEach-Object { [int]$_ }

        $maxLength = [Math]::Max(@($v1Parts).Count, @($v2Parts).Count)

        for ($i = 0; $i -lt $maxLength; $i++) {
            $p1 = if ($i -lt @($v1Parts).Count) { @($v1Parts)[$i] } else { 0 }
            $p2 = if ($i -lt @($v2Parts).Count) { @($v2Parts)[$i] } else { 0 }

            if ($p1 -gt $p2) { return 1 }
            if ($p1 -lt $p2) { return -1 }
        }

        return 0
    }
    catch {
        return [string]::Compare($Version1, $Version2, [StringComparison]::Ordinal)
    }
}
