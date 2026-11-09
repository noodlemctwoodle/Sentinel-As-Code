#Requires -Version 7.6

<#
.SYNOPSIS
    The name deploy gives a workbook whose metadata sets no workbookId.

.DESCRIPTION
    Moved out of ConvertTo-iSOCWorkbookRequest so export can recognise a
    workbook the repository deploys under that name.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Workbook/Get-iSOCWorkbookResourceName.ps1
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

function Get-iSOCWorkbookResourceName {
    <#
    .SYNOPSIS
        Return the GUID made from the workspace and a workbook's folder
        name.

    .DESCRIPTION
        The first 16 bytes of the SHA-256 of
        '<workspace resource id>-<folder name>', as a GUID, so a workbook
        keeps its name across runs (Deploy-CustomWorkbooks in
        Deploy/content/Deploy-CustomContent.ps1).

    .PARAMETER Context
        The workspace context.

    .PARAMETER FolderName
        The workbook's folder under Content/Workbooks/.

    .OUTPUTS
        [string] The GUID, in lower case.

    .EXAMPLE
        Get-iSOCWorkbookResourceName -Context $context -FolderName 'MicrosoftSentinelCostGbp'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $FolderName
    )

    $hashBytes = [System.Text.Encoding]::UTF8.GetBytes("$($Context.WorkspaceResourceId)-$FolderName")
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try { $hashResult = $sha256.ComputeHash($hashBytes) }
    finally { $sha256.Dispose() }
    [byte[]] $guidBytes = $hashResult[0..15]
    ([guid]::new($guidBytes)).ToString()
}
