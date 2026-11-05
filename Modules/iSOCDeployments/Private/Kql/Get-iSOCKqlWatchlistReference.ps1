#Requires -Version 7.2

<#
.SYNOPSIS
    Watchlist aliases a KQL query reads.

.DESCRIPTION
    Copied from Get-KqlWatchlistReferences in Modules/Sentinel.Common/Sentinel.Common.psm1
    (1.1.1) with the helper names changed and the logic unchanged.
    Its answer for every file under Content/ was held to the original's on
    release/26.11.0, until Sentinel.Common was removed;
    Tests/iSOCDeployments/Kql.Tests.ps1 now holds it to the answers the
    original gave.

.NOTES
    File:         Modules/iSOCDeployments/Private/Kql/Get-iSOCKqlWatchlistReference.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.1
    Last Updated: 2026-11-05
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCKqlWatchlistReference {
<#
.SYNOPSIS
    Extract every watchlist alias referenced via _GetWatchlist('alias')
    or _GetWatchlist("alias") in the supplied KQL query.

.OUTPUTS
    String[] of distinct alias names. Returns @() when no references found.
#>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Query)

    if ([string]::IsNullOrWhiteSpace($Query)) { return @() }
    $clean = Remove-iSOCKqlComment -Query $Query

    # `$matches` is a PowerShell automatic variable populated by the
    # -match operator; assigning to it would shadow that. Use a
    # local-scoped name instead (PSAvoidAssignmentToAutomaticVariable).
    $matchResults = [regex]::Matches($clean, "_GetWatchlist\s*\(\s*['""]([^'""]+)['""]\s*\)")
    return @($matchResults | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}
