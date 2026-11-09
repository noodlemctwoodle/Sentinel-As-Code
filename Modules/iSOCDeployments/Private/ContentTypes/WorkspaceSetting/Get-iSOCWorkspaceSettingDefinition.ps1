#Requires -Version 7.6

<#
.SYNOPSIS
    The workspace setting content type.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/WorkspaceSetting/Get-iSOCWorkspaceSettingDefinition.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    Docs/Modules/iSOCDeployments/Architecture.md describes every key of a
    content type definition.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCWorkspaceSettingDefinition {
    <#
    .SYNOPSIS
        Return the workspace setting definition.

    .DESCRIPTION
        Workspace settings are the Microsoft Sentinel settings resources:
        anomalies, EyesOn, Entity Analytics and UEBA. Each is a JSON file
        under Content/WorkspaceSettings/, one setting per file, named by its
        kind, which is also its name in the workspace. They deploy first, so
        UEBA is on before the rules that read its tables, and through a
        Deploy handler of their own, which sends the setting's etag and
        skips one the deployment's identity is not allowed to change.

    .OUTPUTS
        [hashtable] The definition.

    .EXAMPLE
        Get-iSOCWorkspaceSettingDefinition
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Name              = 'WorkspaceSetting'
        DisplayName       = 'Workspace settings'
        RepoFolder        = 'Content/WorkspaceSettings'
        Layout            = 'File'
        Format            = 'Json'
        FilePattern       = @('*.json')
        Recurse           = $true
        Endpoint          = 'Arm'
        Scope             = 'Workspace'
        CollectionPath    = '/providers/Microsoft.SecurityInsights/settings'
        ApiVersion        = 'SecurityInsightsPreview'
        IdentityKey       = 'name'
        DeployOrder       = 5
        SettleSeconds     = 0
        MissingDependency = 'Deploy'
        Capabilities      = @('Deploy')
        Prerequisites     = @()
        Handlers          = @{
            ReadRepo  = 'Read-iSOCWorkspaceSettingRepo'
            Validate  = 'Test-iSOCWorkspaceSetting'
            ToRequest = 'ConvertTo-iSOCWorkspaceSettingRequest'
            Deploy    = 'Invoke-iSOCWorkspaceSettingDeploy'
        }
        Fields            = @(
            @{ Name = 'kind'; Comparer = 'Exact' }
            @{ Name = 'properties.entityProviders'; Comparer = 'Set'; Kind = 'EntityAnalytics' }
            @{ Name = 'properties.dataSources'; Comparer = 'Set'; Kind = 'Ueba' }
        )
    }
}
