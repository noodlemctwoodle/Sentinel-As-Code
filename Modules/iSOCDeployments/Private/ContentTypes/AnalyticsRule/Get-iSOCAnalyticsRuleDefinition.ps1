#Requires -Version 7.2

<#
.SYNOPSIS
    The analytics rule content type: where the files live, how they reach
    the workspace and how they are compared.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Get-iSOCAnalyticsRuleDefinition.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    Docs/Modules/iSOCDeployments/Architecture.md describes every key of a
    content type definition.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCAnalyticsRuleDefinition {
    <#
    .SYNOPSIS
        Return the analytics rule definition.

    .DESCRIPTION
        Rules are YAML files anywhere under Content/AnalyticalRules/, one rule
        per file, named in the workspace by their id. They are sent with the
        preview alert rules API, the one that keeps sub-techniques. A rule
        whose dependencies are missing is deployed disabled, as
        Deploy-CustomContent.ps1 does.

        The fields are the ones Tools/Test-SentinelRuleDrift.ps1 compares
        today, by their place in the request body.

    .OUTPUTS
        [hashtable] The definition.

    .EXAMPLE
        Get-iSOCAnalyticsRuleDefinition
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Name              = 'AnalyticsRule'
        DisplayName       = 'Analytics rules'
        RepoFolder        = 'Content/AnalyticalRules'
        Layout            = 'File'
        Format            = 'Yaml'
        FilePattern       = @('*.yaml', '*.yml')
        Recurse           = $true
        Endpoint          = 'Arm'
        Scope             = 'Workspace'
        CollectionPath    = '/providers/Microsoft.SecurityInsights/alertRules'
        ApiVersion        = 'SecurityInsightsPreview'
        IdentityKey       = 'id'
        DeployOrder       = 30
        MissingDependency = 'DeployDisabled'
        Capabilities      = @('Dependencies')
        Prerequisites     = @('powershell-yaml')
        Handlers          = @{
            ReadRepo  = 'Read-iSOCAnalyticsRuleRepo'
            Validate  = 'Test-iSOCAnalyticsRule'
            ToRequest = 'ConvertTo-iSOCAnalyticsRuleRequest'
            GetQuery  = 'Get-iSOCAnalyticsRuleKql'
        }
        Fields            = @(
            @{ Name = 'kind'; Comparer = 'Exact' }
            @{ Name = 'properties.displayName'; Comparer = 'Exact' }
            @{ Name = 'properties.severity'; Comparer = 'CaseInsensitive' }
            @{ Name = 'properties.query'; Comparer = 'Whitespace' }
            @{ Name = 'properties.queryFrequency'; Comparer = 'Duration' }
            @{ Name = 'properties.queryPeriod'; Comparer = 'Duration' }
            @{ Name = 'properties.triggerOperator'; Comparer = 'CaseInsensitive' }
            @{ Name = 'properties.triggerThreshold'; Comparer = 'Number' }
        )
    }
}
