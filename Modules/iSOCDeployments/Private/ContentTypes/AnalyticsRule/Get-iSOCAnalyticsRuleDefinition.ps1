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
    Version:      0.2.0
    Last Updated: 2026-11-03
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

        The fields are the ones Tools/Test-SentinelRuleDrift.ps1 compares,
        by their place in the request body and in its order, with kind
        added; the schedule and trigger are compared for Scheduled rules
        only, as an NRT rule has none. Drift reads the workspace's rules,
        classes each by where its source of truth is (a repository file, a
        Content Hub template, or nothing), and absorbs changes by rewriting
        the file or writing a new one.

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
        SettleSeconds     = 0
        MissingDependency = 'DeployDisabled'
        Capabilities      = @('Deploy', 'Dependencies', 'Compare', 'Sync')
        Prerequisites     = @('powershell-yaml')
        Handlers          = @{
            ReadRepo       = 'Read-iSOCAnalyticsRuleRepo'
            Validate       = 'Test-iSOCAnalyticsRule'
            ToRequest      = 'ConvertTo-iSOCAnalyticsRuleRequest'
            GetQuery       = 'Get-iSOCAnalyticsRuleKql'
            Deploy         = 'Invoke-iSOCAnalyticsRuleDeploy'
            ReadWorkspace  = 'Read-iSOCAnalyticsRuleWorkspace'
            Classify       = 'Get-iSOCAnalyticsRuleSource'
            ToComparable   = 'ConvertTo-iSOCAnalyticsRuleComparable'
            UpdateRepoFile = 'Update-iSOCAnalyticsRuleYaml'
            ToRepoFile     = 'ConvertTo-iSOCAnalyticsRuleYaml'
            GetRepoPath    = 'Get-iSOCAnalyticsRuleRepoPath'
        }
        Fields            = @(
            @{ Name = 'kind'; Comparer = 'Exact' }
            @{ Name = 'properties.query'; Comparer = 'Whitespace' }
            @{ Name = 'properties.queryFrequency'; Comparer = 'Duration'; Kind = 'Scheduled' }
            @{ Name = 'properties.queryPeriod'; Comparer = 'Duration'; Kind = 'Scheduled' }
            @{ Name = 'properties.triggerOperator'; Comparer = 'CaseInsensitive'; Kind = 'Scheduled' }
            @{ Name = 'properties.triggerThreshold'; Comparer = 'Number'; Kind = 'Scheduled' }
            @{ Name = 'properties.severity'; Comparer = 'CaseInsensitive' }
            @{ Name = 'properties.displayName'; Comparer = 'Exact' }
        )
    }
}
