#Requires -Version 7.6

<#
.SYNOPSIS
    GetRepoPath handler for workbooks: the folder a workspace workbook new to
    the repository goes to.

.DESCRIPTION
    Copied from the export loop of Tools/Export-SentinelWorkbooks.ps1.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Workbook/Get-iSOCWorkbookRepoPath.ps1
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

function Get-iSOCWorkbookRepoPath {
    <#
    .SYNOPSIS
        Return Content/Workbooks/<folder> for a workspace workbook.

    .DESCRIPTION
        The folder is the display name, its ' - <workspace>' suffix
        removed, made one PascalCase word. A display name with no letters
        or digits has no folder, and throws.

    .PARAMETER WorkspaceItem
        A workbook as Read-iSOCWorkbookWorkspace returns it.

    .PARAMETER Context
        The workspace context.

    .OUTPUTS
        [string] The folder, relative to the repository.

    .EXAMPLE
        Get-iSOCWorkbookRepoPath -WorkspaceItem $workbook -Context $ctx
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $WorkspaceItem,

        [Parameter(Mandatory)]
        [psobject] $Context
    )

    $rawName = [string](Get-iSOCPropertyValue -InputObject $WorkspaceItem -Path 'properties.displayName')
    $folderName = ConvertTo-iSOCWorkbookFolderName -DisplayName (Get-iSOCWorkbookDisplayName -DisplayName $rawName -WorkspaceName $Context.WorkspaceName)
    if (-not $folderName) { throw "The workbook '$rawName' has no letters or digits in its name to make a folder from." }
    "Content/Workbooks/$folderName"
}
