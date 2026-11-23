#Requires -Version 7.6

<#
.SYNOPSIS
    The names of the files in an assets library folder.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Files/Get-SacFolderFileNames.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SacFolderFileNames {
    <#
    .SYNOPSIS
        Names of the files in one folder of the assets library, or an empty
        array when the folder does not exist yet.

    .PARAMETER Folder
        The folder to list, relative to the assets library, such as 'diagrams'.

    .OUTPUTS
        [string[]] The file names, as an array even when there is one or none.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [string] $Folder)
    $items = Get-PnPFolderItem -FolderSiteRelativeUrl "$script:SacAssetsLibraryUrl/$Folder" -ItemType File -ErrorAction SilentlyContinue
    return , @($items | ForEach-Object { [string]$_.Name })
}
