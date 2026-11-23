#Requires -Version 7.6

<#
.SYNOPSIS
    Strip KQL line and block comments from a query string.

.DESCRIPTION
    Copied unchanged from Modules/Sentinel.Common/Sentinel.Common.psm1, which retired in release
    26.11.0, so this is the Blueprint's own code from then on: fix it here.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Kql/Vendor/Remove-KqlComments.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Remove-KqlComments {
    <#
    .SYNOPSIS
        Strip KQL line and block comments from a query string before regex
        extraction so commented-out _GetWatchlist / externaldata calls do
        not produce false positives in the manifest.

    .PARAMETER Query
        The KQL query text.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Query)

    # Strip /* ... */ block comments first (greedy single-line, lazy
    # multi-line via singleline mode).
    $stripped = [regex]::Replace($Query, '/\*.*?\*/', '', 'Singleline')

    # Strip // line comments to end of line. The negative lookbehind (?<!:)
    # is critical — without it the regex would also match the // in URLs
    # like https://foo.com and chop off the URL host. KQL line comments
    # never legitimately follow a colon (the comment marker has to be
    # whitespace-preceded or at start of line), so excluding ':' is safe.
    $stripped = [regex]::Replace($stripped, '(?<!:)//[^\r\n]*', '')
    return $stripped
}
