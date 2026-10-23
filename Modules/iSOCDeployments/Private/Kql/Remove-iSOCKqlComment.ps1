#Requires -Version 7.2

<#
.SYNOPSIS
    Strip KQL comments before references are read from a query.

.DESCRIPTION
    Copied from Remove-KqlComments in Modules/Sentinel.Common/Sentinel.Common.psm1
    (1.1.1) with the helper names changed and the logic unchanged.
    Tests/iSOCDeployments/Kql.Tests.ps1 holds the two to the same answer
    for every file under Content/.

.NOTES
    File:         Modules/iSOCDeployments/Private/Kql/Remove-iSOCKqlComment.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Remove-iSOCKqlComment {
<#
.SYNOPSIS
    Strip KQL line and block comments from a query string before regex
    extraction so commented-out _GetWatchlist / externaldata calls do
    not produce false positives in the manifest.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Query)

    # Strip /* ... */ block comments first (greedy single-line, lazy
    # multi-line via singleline mode).
    $stripped = [regex]::Replace($Query, '/\*.*?\*/', '', 'Singleline')

    # Strip // line comments to end of line. The negative lookbehind (?<!:)
    # is critical - without it the regex would also match the // in URLs
    # like https://foo.com and chop off the URL host. KQL line comments
    # never legitimately follow a colon (the comment marker has to be
    # whitespace-preceded or at start of line), so excluding ':' is safe.
    $stripped = [regex]::Replace($stripped, '(?<!:)//[^\r\n]*', '')
    return $stripped
}
