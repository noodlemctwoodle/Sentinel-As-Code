#Requires -Version 7.6

<#
.SYNOPSIS
    Validate handler for hunting queries.

.DESCRIPTION
    The check Deploy-CustomHuntingQueries
    (Deploy/content/Deploy-CustomContent.ps1) makes before it sends a query,
    with the same message.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/HuntingQuery/Test-iSOCHuntingQuery.ps1
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

function Test-iSOCHuntingQuery {
    <#
    .SYNOPSIS
        Say why a hunting query cannot be sent, if it cannot.

    .DESCRIPTION
        A hunting query needs id, name and query, none of them blank. A
        query that fails is skipped by deploy, as it is today.

    .PARAMETER Item
        A repository item from Read-iSOCHuntingQueryRepo.

    .OUTPUTS
        [string] The problem; nothing when the query can be sent.

    .EXAMPLE
        $issues = @(Test-iSOCHuntingQuery -Item $item)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    if ($Item.ParseError) { return "YAML does not parse: $($Item.ParseError)" }
    $hq = $Item.Data
    if ($hq -isnot [System.Collections.IDictionary]) { return 'the file does not hold a YAML mapping' }

    $requiredFields = @('id', 'name', 'query')
    $missingFields = @($requiredFields | Where-Object { -not $hq.Contains($_) -or [string]::IsNullOrWhiteSpace($hq[$_]) })
    if ($missingFields.Count -gt 0) { return "missing required fields: $($missingFields -join ', ')" }
}
