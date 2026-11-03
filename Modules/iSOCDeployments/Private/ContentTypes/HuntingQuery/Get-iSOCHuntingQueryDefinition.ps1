#Requires -Version 7.2

<#
.SYNOPSIS
    The hunting query content type: saved searches in the Hunting Queries
    category.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/HuntingQuery/Get-iSOCHuntingQueryDefinition.ps1
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

function Get-iSOCHuntingQueryDefinition {
    <#
    .SYNOPSIS
        Return the hunting query definition.

    .DESCRIPTION
        Hunting queries are YAML files anywhere under Content/HuntingQueries/,
        one query per file, saved as Log Analytics saved searches named by
        their id. A query whose dependencies are missing is skipped, as
        Deploy-CustomContent.ps1 does. The dependency manifest covers them.

    .OUTPUTS
        [hashtable] The definition.

    .EXAMPLE
        Get-iSOCHuntingQueryDefinition
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Name              = 'HuntingQuery'
        DisplayName       = 'Hunting queries'
        RepoFolder        = 'Content/HuntingQueries'
        Layout            = 'File'
        Format            = 'Yaml'
        FilePattern       = @('*.yaml', '*.yml')
        Recurse           = $true
        Endpoint          = 'Arm'
        Scope             = 'Workspace'
        CollectionPath    = '/savedSearches'
        ApiVersion        = 'SavedSearches'
        IdentityKey       = 'id'
        DeployOrder       = 40
        SettleSeconds     = 0
        MissingDependency = 'Skip'
        Capabilities      = @('Deploy', 'Dependencies')
        Prerequisites     = @('powershell-yaml')
        Handlers          = @{
            ReadRepo  = 'Read-iSOCHuntingQueryRepo'
            Validate  = 'Test-iSOCHuntingQuery'
            ToRequest = 'ConvertTo-iSOCHuntingQueryRequest'
            GetQuery  = 'Get-iSOCHuntingQueryKql'
        }
        Fields            = @(
            @{ Name = 'properties.displayName'; Comparer = 'Exact' }
            @{ Name = 'properties.query'; Comparer = 'Whitespace' }
            @{ Name = 'properties.tags'; Comparer = 'Json' }
        )
    }
}
