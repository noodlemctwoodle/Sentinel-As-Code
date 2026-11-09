#Requires -Version 7.6

<#
.SYNOPSIS
    ToComparable handler for analytics rules: a workspace rule in the
    shape deploy sends.

.DESCRIPTION
    Replaces ConvertTo-NormalisedDeployedRule
    (Tools/Test-SentinelRuleDrift.ps1). The API answers with the same kind
    and properties a PUT takes, so the rule is compared as it comes, field
    by field with the comparers the content type names, instead of being
    normalised into a shape of its own.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCAnalyticsRuleComparable.ps1
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

function ConvertTo-iSOCAnalyticsRuleComparable {
    <#
    .SYNOPSIS
        Return the rule's kind and properties.

    .DESCRIPTION
        A rule with no kind is Scheduled, as the script took it.

    .PARAMETER WorkspaceItem
        A rule as Read-iSOCAnalyticsRuleWorkspace returns it.

    .OUTPUTS
        [hashtable] kind and properties.

    .EXAMPLE
        $actual = ConvertTo-iSOCAnalyticsRuleComparable -WorkspaceItem $rule
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject] $WorkspaceItem
    )

    $kind = Get-iSOCPropertyValue -InputObject $WorkspaceItem -Path 'kind'
    @{
        kind       = if ($kind) { [string]$kind } else { 'Scheduled' }
        properties = Get-iSOCPropertyValue -InputObject $WorkspaceItem -Path 'properties'
    }
}
