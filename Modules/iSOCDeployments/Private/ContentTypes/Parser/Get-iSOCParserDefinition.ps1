#Requires -Version 7.2

<#
.SYNOPSIS
    The parser content type: KQL functions saved in the workspace.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Parser/Get-iSOCParserDefinition.ps1
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

function Get-iSOCParserDefinition {
    <#
    .SYNOPSIS
        Return the parser definition.

    .DESCRIPTION
        Parsers are YAML files anywhere under Content/Parsers/, one function
        per file, saved as Log Analytics saved searches named by their id.
        They deploy first, since rules and hunting queries call them by
        their functionAlias, and the deployer does not check their own
        dependencies.

    .OUTPUTS
        [hashtable] The definition.

    .EXAMPLE
        Get-iSOCParserDefinition
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Name              = 'Parser'
        DisplayName       = 'Parsers'
        RepoFolder        = 'Content/Parsers'
        Layout            = 'File'
        Format            = 'Yaml'
        FilePattern       = @('*.yaml', '*.yml')
        Recurse           = $true
        Endpoint          = 'Arm'
        Scope             = 'Workspace'
        CollectionPath    = '/savedSearches'
        ApiVersion        = 'SavedSearches'
        IdentityKey       = 'id'
        DeployOrder       = 10
        MissingDependency = 'Deploy'
        Capabilities      = @()
        Prerequisites     = @('powershell-yaml')
        Handlers          = @{
            ReadRepo  = 'Read-iSOCParserRepo'
            Validate  = 'Test-iSOCParser'
            ToRequest = 'ConvertTo-iSOCParserRequest'
        }
        Fields            = @(
            @{ Name = 'properties.displayName'; Comparer = 'Exact' }
            @{ Name = 'properties.functionAlias'; Comparer = 'Exact' }
            @{ Name = 'properties.query'; Comparer = 'Whitespace' }
            @{ Name = 'properties.functionParameters'; Comparer = 'Whitespace' }
            @{ Name = 'properties.category'; Comparer = 'Exact' }
        )
    }
}
