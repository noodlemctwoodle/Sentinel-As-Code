#Requires -Version 7.2

<#
.SYNOPSIS
    The summary rule content type.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/SummaryRule/Get-iSOCSummaryRuleDefinition.ps1
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

function Get-iSOCSummaryRuleDefinition {
    <#
    .SYNOPSIS
        Return the summary rule definition.

    .DESCRIPTION
        Summary rules are JSON files anywhere under Content/SummaryRules/,
        one rule per file, named in the workspace by their name. They are a
        Log Analytics resource (summarylogs), not a Sentinel one, and deploy
        last. One whose dependencies are missing is skipped.

    .OUTPUTS
        [hashtable] The definition.

    .EXAMPLE
        Get-iSOCSummaryRuleDefinition
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Name              = 'SummaryRule'
        DisplayName       = 'Summary rules'
        RepoFolder        = 'Content/SummaryRules'
        Layout            = 'File'
        Format            = 'Json'
        FilePattern       = @('*.json')
        Recurse           = $true
        Endpoint          = 'Arm'
        Scope             = 'Workspace'
        CollectionPath    = '/summarylogs'
        ApiVersion        = 'SummaryRules'
        IdentityKey       = 'name'
        DeployOrder       = 80
        SettleSeconds     = 0
        MissingDependency = 'Skip'
        Capabilities      = @('Deploy')
        Prerequisites     = @()
        Handlers          = @{
            ReadRepo  = 'Read-iSOCSummaryRuleRepo'
            Validate  = 'Test-iSOCSummaryRule'
            ToRequest = 'ConvertTo-iSOCSummaryRuleRequest'
        }
        Fields            = @(
            @{ Name = 'properties.displayName'; Comparer = 'Exact' }
            @{ Name = 'properties.description'; Comparer = 'Whitespace' }
            @{ Name = 'properties.ruleDefinition.query'; Comparer = 'Whitespace' }
            @{ Name = 'properties.ruleDefinition.binSize'; Comparer = 'Number' }
            @{ Name = 'properties.ruleDefinition.binDelay'; Comparer = 'Number' }
            @{ Name = 'properties.ruleDefinition.binStartTime'; Comparer = 'Exact' }
            @{ Name = 'properties.ruleDefinition.destinationTable'; Comparer = 'Exact' }
        )
    }
}
