#Requires -Version 7.2

<#
.SYNOPSIS
    The playbook content type.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookDefinition.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    Docs/Modules/iSOCDeployments/Architecture.md describes every key of a
    content type definition.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCPlaybookDefinition {
    <#
    .SYNOPSIS
        Return the playbook definition.

    .DESCRIPTION
        Playbooks are ARM templates anywhere under Content/Playbooks/, one
        Logic App per file, grouped in folders by trigger. They deploy to the
        playbook resource group as resource group deployments through
        Az.Resources, not as REST requests, so the type has its own Deploy
        handler, and its own Order handler: the templates in Module folders
        go first, in the order their workflow references need. A Logic App
        is named by its template's PlaybookName parameter. One whose
        dependencies are missing is skipped. Exporting reads the Logic Apps
        in the playbook resource group and writes each as a parameterised
        template.

    .OUTPUTS
        [hashtable] The definition.

    .EXAMPLE
        Get-iSOCPlaybookDefinition
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Name              = 'Playbook'
        DisplayName       = 'Playbooks'
        RepoFolder        = 'Content/Playbooks'
        Layout            = 'File'
        Format            = 'Json'
        FilePattern       = @('*.json')
        Recurse           = $true
        Endpoint          = 'Arm'
        Scope             = 'PlaybookResourceGroup'
        CollectionPath    = '/providers/Microsoft.Logic/workflows'
        ApiVersion        = 'LogicApps'
        IdentityKey       = 'parameters.PlaybookName.defaultValue'
        DeployOrder       = 50
        SettleSeconds     = 0
        MissingDependency = 'Skip'
        Capabilities      = @('Deploy', 'Export')
        Prerequisites     = @('Az.Resources')
        Handlers          = @{
            ReadRepo      = 'Read-iSOCPlaybookRepo'
            Validate      = 'Test-iSOCPlaybook'
            ToRequest     = 'ConvertTo-iSOCPlaybookRequest'
            Deploy        = 'Invoke-iSOCPlaybookDeploy'
            Order         = 'Get-iSOCPlaybookOrder'
            ReadWorkspace = 'Read-iSOCPlaybookWorkspace'
            Classify      = 'Get-iSOCPlaybookSource'
            ToRepoFile    = 'ConvertTo-iSOCPlaybookFile'
            GetRepoPath   = 'Get-iSOCPlaybookRepoPath'
        }
        Fields            = @(
            @{ Name = 'properties.state'; Comparer = 'CaseInsensitive' }
            @{ Name = 'properties.definition'; Comparer = 'Json' }
            @{ Name = 'properties.parameters'; Comparer = 'Json' }
        )
    }
}
