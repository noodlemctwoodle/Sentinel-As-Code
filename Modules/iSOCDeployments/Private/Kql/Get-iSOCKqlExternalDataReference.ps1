#Requires -Version 7.2

<#
.SYNOPSIS
    URLs a KQL query reads with externaldata.

.DESCRIPTION
    Copied from Get-KqlExternalDataReferences in Modules/Sentinel.Common/Sentinel.Common.psm1
    (1.1.1) with the helper names changed and the logic unchanged.
    Its answer for every file under Content/ was held to the original's on
    release/26.11.0, until Sentinel.Common was removed;
    Tests/iSOCDeployments/Kql.Tests.ps1 now holds it to the answers the
    original gave.

.NOTES
    File:         Modules/iSOCDeployments/Private/Kql/Get-iSOCKqlExternalDataReference.ps1
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

function Get-iSOCKqlExternalDataReference {
<#
.SYNOPSIS
    Extract every URL referenced by an `externaldata(...)` operator's
    bracket list in the supplied KQL query.

.DESCRIPTION
    The KQL pattern is:
        externaldata(col1: type, col2: type) ["https://..."] with(...)

    The URL list can contain multiple entries; we extract every one.

.OUTPUTS
    String[] of distinct URLs. Returns @() when no references found.
#>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Query)

    if ([string]::IsNullOrWhiteSpace($Query)) { return @() }
    $clean = Remove-iSOCKqlComment -Query $Query

    # Match the whole 'externaldata(...) [ ... ]' block, then pull URL
    # literals from the bracket list. Singleline so the match spans newlines.
    $blockRegex = [regex]::new('externaldata\s*\([^)]+\)\s*\[(?<urls>[^\]]+)\]', 'IgnoreCase, Singleline')
    $urlRegex   = [regex]::new('["''](?<url>https?://[^"'']+)["'']')

    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($block in $blockRegex.Matches($clean)) {
        foreach ($urlMatch in $urlRegex.Matches($block.Groups['urls'].Value)) {
            [void]$found.Add($urlMatch.Groups['url'].Value)
        }
    }
    return @($found | Sort-Object -Unique)
}
