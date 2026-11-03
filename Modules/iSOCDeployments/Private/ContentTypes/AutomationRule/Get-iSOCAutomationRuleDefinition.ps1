#Requires -Version 7.2

<#
.SYNOPSIS
    The automation rule content type.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AutomationRule/Get-iSOCAutomationRuleDefinition.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    Docs/Modules/iSOCDeployments/Architecture.md describes every key of a
    content type definition.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCAutomationRuleDefinition {
    <#
    .SYNOPSIS
        Return the automation rule definition.

    .DESCRIPTION
        Automation rules are JSON files anywhere under
        Content/AutomationRules/, one rule per file, named in the workspace
        by their automationRuleId. They deploy after the playbooks they may
        run. One whose dependencies are missing is skipped.

    .OUTPUTS
        [hashtable] The definition.

    .EXAMPLE
        Get-iSOCAutomationRuleDefinition
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Name              = 'AutomationRule'
        DisplayName       = 'Automation rules'
        RepoFolder        = 'Content/AutomationRules'
        Layout            = 'File'
        Format            = 'Json'
        FilePattern       = @('*.json')
        Recurse           = $true
        Endpoint          = 'Arm'
        Scope             = 'Workspace'
        CollectionPath    = '/providers/Microsoft.SecurityInsights/automationRules'
        ApiVersion        = 'SecurityInsights'
        IdentityKey       = 'automationRuleId'
        DeployOrder       = 70
        SettleSeconds     = 0
        MissingDependency = 'Skip'
        Capabilities      = @('Deploy')
        Prerequisites     = @()
        Handlers          = @{
            ReadRepo  = 'Read-iSOCAutomationRuleRepo'
            Validate  = 'Test-iSOCAutomationRule'
            ToRequest = 'ConvertTo-iSOCAutomationRuleRequest'
        }
        Fields            = @(
            @{ Name = 'properties.displayName'; Comparer = 'Exact' }
            @{ Name = 'properties.order'; Comparer = 'Number' }
            @{ Name = 'properties.triggeringLogic'; Comparer = 'Json' }
            @{ Name = 'properties.actions'; Comparer = 'Json' }
        )
    }
}
