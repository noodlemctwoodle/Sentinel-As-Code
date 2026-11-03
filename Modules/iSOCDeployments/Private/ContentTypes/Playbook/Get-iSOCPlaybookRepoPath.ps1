#Requires -Version 7.2

<#
.SYNOPSIS
    GetRepoPath handler for playbooks: the file a Logic App new to the
    repository goes to.

.DESCRIPTION
    Copied from Invoke-PlaybookExport (847ef86:Tools/Export-Playbooks.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookRepoPath.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCPlaybookRepoPath {
    <#
    .SYNOPSIS
        Return Content/Playbooks/<category>/<name>.json for a Logic App.

    .DESCRIPTION
        The category is the trigger's (Get-iSOCPlaybookCategory) and the
        file name the Logic App's name without a leading category prefix
        (Get-iSOCPlaybookFileName).

    .PARAMETER WorkspaceItem
        A Logic App as Read-iSOCPlaybookWorkspace returns it, with its
        definition.

    .OUTPUTS
        [string] The file, relative to the repository.

    .EXAMPLE
        Get-iSOCPlaybookRepoPath -WorkspaceItem $app
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $WorkspaceItem
    )

    $category = Get-iSOCPlaybookCategory -Definition (Get-iSOCPropertyValue -InputObject $WorkspaceItem -Path 'properties.definition')
    $fileName = Get-iSOCPlaybookFileName -LogicAppName ([string](Get-iSOCPropertyValue -InputObject $WorkspaceItem -Path 'name'))
    "Content/Playbooks/$category/$fileName.json"
}
