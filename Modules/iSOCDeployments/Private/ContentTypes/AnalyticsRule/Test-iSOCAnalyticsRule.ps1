#Requires -Version 7.6

<#
.SYNOPSIS
    Validate handler for analytics rules.

.DESCRIPTION
    The checks Deploy-CustomDetections (Deploy/content/Deploy-CustomContent.ps1)
    makes before it sends a rule, with the same messages.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Test-iSOCAnalyticsRule.ps1
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

function Test-iSOCAnalyticsRule {
    <#
    .SYNOPSIS
        Say why a rule cannot be sent, if it cannot.

    .DESCRIPTION
        A rule needs id, name, kind, severity and query, none of them blank;
        a Scheduled rule also needs queryFrequency, queryPeriod,
        triggerOperator and triggerThreshold. A rule that fails is skipped
        by deploy, as it is today.

    .PARAMETER Item
        A repository item from Read-iSOCAnalyticsRuleRepo.

    .OUTPUTS
        [string] The problem; nothing when the rule can be sent.

    .EXAMPLE
        $issues = @(Test-iSOCAnalyticsRule -Item $item)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    if ($Item.ParseError) { return "YAML does not parse: $($Item.ParseError)" }
    $rule = $Item.Data
    if ($rule -isnot [System.Collections.IDictionary]) { return 'the file does not hold a YAML mapping' }

    $requiredFields = @('id', 'name', 'kind', 'severity', 'query')
    $missingFields = @($requiredFields | Where-Object { -not $rule.Contains($_) -or [string]::IsNullOrWhiteSpace($rule[$_]) })
    if ($missingFields.Count -gt 0) { return "missing required fields: $($missingFields -join ', ')" }

    if ($rule['kind'] -eq 'Scheduled') {
        $scheduledFields = @('queryFrequency', 'queryPeriod', 'triggerOperator', 'triggerThreshold')
        $missingScheduled = @($scheduledFields | Where-Object { -not $rule.Contains($_) })
        if ($missingScheduled.Count -gt 0) { return "Scheduled rule missing required fields: $($missingScheduled -join ', ')" }
    }
}
