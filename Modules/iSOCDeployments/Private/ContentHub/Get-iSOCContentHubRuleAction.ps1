#Requires -Version 7.6

<#
.SYNOPSIS
    Decide what to do with one Content Hub rule template.

.DESCRIPTION
    Copied from the existing-rule checks in Deploy-AnalyticsRules
    (Deploy/content/Deploy-SentinelContentHub.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubRuleAction.ps1
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

function Get-iSOCContentHubRuleAction {
    <#
    .SYNOPSIS
        Return Create, Update, Unchanged or Protected for a template's rule.

    .DESCRIPTION
        A rule made from the template (matched by alertRuleTemplateName) is
        updated when its solution was installed or updated in this run, when
        -DisableRules is given and the rule is enabled, when the template's
        version is newer than the rule's, or with -ForceContentDeployment;
        otherwise it is unchanged. A rule with the template's display name
        but no link to it was made or changed by hand: it is protected, or
        with protection off updated. A rule about to be updated is
        protected when its query, schedule, trigger or severity differ from
        the template. Anything else is created.

    .PARAMETER Record
        From Read-iSOCContentHubRuleTemplate.

    .PARAMETER RulesByTemplate
        The workspace's rules by alertRuleTemplateName.

    .PARAMETER RulesByName
        The workspace's rules by display name.

    .PARAMETER FromNewSolution
        The template's solution was installed or updated in this run.

    .PARAMETER DisableRules
        Rules are being deployed disabled.

    .PARAMETER ForceContentDeployment
        Redeploy rules that are current.

    .PARAMETER ProtectCustomisedRules
        Leave rules changed in the workspace alone.

    .OUTPUTS
        [hashtable] Action, ExistingRule, Reason and Modifications (the
        fields a protected rule differs in; none for a rule protected by its
        name).

    .EXAMPLE
        $decision = Get-iSOCContentHubRuleAction -Record $record -RulesByTemplate $byTemplate -RulesByName $byName -ProtectCustomisedRules $true
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Record,

        [Parameter(Mandatory)]
        [hashtable] $RulesByTemplate,

        [Parameter(Mandatory)]
        [hashtable] $RulesByName,

        [switch] $FromNewSolution,

        [switch] $DisableRules,

        [switch] $ForceContentDeployment,

        [bool] $ProtectCustomisedRules = $true
    )

    $templateName = $Record.TemplateName
    $displayName = $Record.DisplayName
    $existingRule = $null

    if ($templateName -and $RulesByTemplate.ContainsKey($templateName)) {
        $existingRule = $RulesByTemplate[$templateName]
        $currentVersion = if ($existingRule.properties.PSObject.Properties.Name -contains 'templateVersion') { $existingRule.properties.templateVersion } else { $null }
        $existingEnabled = $true
        if ($existingRule.properties.PSObject.Properties.Name -contains 'enabled') { $existingEnabled = $existingRule.properties.enabled }
        $needsDisable = $DisableRules -and $existingEnabled

        $update = $FromNewSolution -or $needsDisable -or $ForceContentDeployment
        if (-not $update -and $currentVersion -and $Record.TemplateVersion) {
            $update = (Compare-iSOCSemanticVersion -Version1 $Record.TemplateVersion -Version2 $currentVersion) -gt 0
        }
        if (-not $update) {
            return @{ Action = 'Unchanged'; ExistingRule = $existingRule; Reason = 'current'; Modifications = @() }
        }
    }
    elseif ($displayName -and $RulesByName.ContainsKey($displayName)) {
        if ($ProtectCustomisedRules) {
            return @{ Action = 'Protected'; ExistingRule = $RulesByName[$displayName]; Reason = 'a rule of that name is not linked to the template'; Modifications = @() }
        }
        $existingRule = $RulesByName[$displayName]
    }
    else {
        return @{ Action = 'Create'; ExistingRule = $null; Reason = ''; Modifications = @() }
    }

    if ($ProtectCustomisedRules) {
        $customCheck = Test-iSOCContentHubRuleCustomised -ExistingRule $existingRule -TemplateProperties $Record.RuleProperties
        if ($customCheck.IsCustomised) {
            return @{ Action = 'Protected'; ExistingRule = $existingRule; Reason = "modified fields: $($customCheck.Modifications -join ', ')"; Modifications = @($customCheck.Modifications) }
        }
    }
    @{ Action = 'Update'; ExistingRule = $existingRule; Reason = ''; Modifications = @() }
}
