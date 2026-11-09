#Requires -Version 7.6

<#
.SYNOPSIS
    Validate handler for automation rules.

.DESCRIPTION
    The check Deploy-CustomAutomationRules
    (Deploy/content/Deploy-CustomContent.ps1) makes before it sends a rule,
    with the same message. A missing field is reported instead of failing
    the rule, where strict mode made the script throw reading it
    (MIGRATION.md edit E9).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AutomationRule/Test-iSOCAutomationRule.ps1
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

function Test-iSOCAutomationRule {
    <#
    .SYNOPSIS
        Say why an automation rule cannot be sent, if it cannot.

    .DESCRIPTION
        A rule needs automationRuleId, displayName, order, triggeringLogic
        and actions. A file that does not parse is reported as such.

    .PARAMETER Item
        A repository item from Read-iSOCAutomationRuleRepo.

    .OUTPUTS
        [string] The problem; nothing when the rule can be sent.

    .EXAMPLE
        $issues = @(Test-iSOCAutomationRule -Item $item)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    if ($Item.ParseError) { return $Item.ParseError }
    $rule = $Item.Data
    $missing = -not (Get-iSOCPropertyValue -InputObject $rule -Path 'automationRuleId') -or
    -not (Get-iSOCPropertyValue -InputObject $rule -Path 'displayName') -or
    $null -eq (Get-iSOCPropertyValue -InputObject $rule -Path 'order') -or
    -not (Get-iSOCPropertyValue -InputObject $rule -Path 'triggeringLogic') -or
    -not (Get-iSOCPropertyValue -InputObject $rule -Path 'actions')
    if ($missing) { return 'missing required fields (automationRuleId, displayName, order, triggeringLogic, actions).' }
}
