#Requires -Version 7.6

<#
.SYNOPSIS
    GetQuery handler for analytics rules.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Get-iSOCAnalyticsRuleKql.ps1
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

function Get-iSOCAnalyticsRuleKql {
    <#
    .SYNOPSIS
        Return the KQL a rule runs.

    .PARAMETER Item
        A repository item from Read-iSOCAnalyticsRuleRepo.

    .OUTPUTS
        [string] The query, or nothing when the file has none.

    .EXAMPLE
        Get-iSOCAnalyticsRuleKql -Item $item
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    $rule = $Item.Data
    if ($rule -is [System.Collections.IDictionary] -and $rule.Contains('query')) { return [string]$rule['query'] }
}
