#Requires -Version 7.6

<#
.SYNOPSIS
    GetQuery handler for hunting queries.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/HuntingQuery/Get-iSOCHuntingQueryKql.ps1
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

function Get-iSOCHuntingQueryKql {
    <#
    .SYNOPSIS
        Return the KQL a hunting query runs.

    .PARAMETER Item
        A repository item from Read-iSOCHuntingQueryRepo.

    .OUTPUTS
        [string] The query, or nothing when the file has none.

    .EXAMPLE
        Get-iSOCHuntingQueryKql -Item $item
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    $hq = $Item.Data
    if ($hq -is [System.Collections.IDictionary] -and $hq.Contains('query')) { return [string]$hq['query'] }
}
