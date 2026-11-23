#Requires -Version 7.6

<#
.SYNOPSIS
    The workbook content type.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Workbook/Get-iSOCWorkbookDefinition.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    Docs/Modules/iSOCDeployments/Architecture.md describes every key of a
    content type definition.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCWorkbookDefinition {
    <#
    .SYNOPSIS
        Return the workbook definition.

    .DESCRIPTION
        Each folder directly under Content/Workbooks/ is one workbook:
        workbook.json holds the gallery template and metadata.json, when
        there is one, the display name, category and workbookId. Workbooks
        are resource group resources, named by their workbookId, or by a
        GUID derived from the workspace and the folder name when metadata
        has none. They deploy after the playbooks. One whose dependencies
        are missing is skipped. Exporting reads the workspace's Sentinel
        workbooks and writes each to its own folder.

    .OUTPUTS
        [hashtable] The definition.

    .EXAMPLE
        Get-iSOCWorkbookDefinition
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Name              = 'Workbook'
        DisplayName       = 'Workbooks'
        RepoFolder        = 'Content/Workbooks'
        Layout            = 'Folder'
        Format            = 'Json'
        FilePattern       = @('workbook.json')
        Recurse           = $false
        Endpoint          = 'Arm'
        Scope             = 'ResourceGroup'
        CollectionPath    = '/providers/Microsoft.Insights/workbooks'
        ApiVersion        = 'Workbooks'
        IdentityKey       = 'workbookId'
        DeployOrder       = 60
        SettleSeconds     = 0
        MissingDependency = 'Skip'
        Capabilities      = @('Deploy', 'Export')
        Prerequisites     = @()
        Handlers          = @{
            ReadRepo      = 'Read-iSOCWorkbookRepo'
            Validate      = 'Test-iSOCWorkbook'
            ToRequest     = 'ConvertTo-iSOCWorkbookRequest'
            ReadWorkspace = 'Read-iSOCWorkbookWorkspace'
            Classify      = 'Get-iSOCWorkbookSource'
            ToRepoFile    = 'ConvertTo-iSOCWorkbookFile'
            GetRepoPath   = 'Get-iSOCWorkbookRepoPath'
        }
        Fields            = @(
            @{ Name = 'properties.displayName'; Comparer = 'Exact' }
            @{ Name = 'properties.category'; Comparer = 'CaseInsensitive' }
            @{ Name = 'properties.serializedData'; Comparer = 'Json' }
        )
    }
}
