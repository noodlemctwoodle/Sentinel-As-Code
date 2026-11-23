#Requires -Version 7.6

<#
.SYNOPSIS
    Upload one file to the assets library.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Files/Send-SacFile.ps1
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

function Send-SacFile {
    <#
    .SYNOPSIS
        Upload one local file into a folder of the assets library.

    .PARAMETER Path
        The local file to upload.

    .PARAMETER Folder
        The folder of the assets library to upload it into.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Folder
    )
    $target = "$script:SacAssetsLibraryUrl/$Folder"
    if ($PSCmdlet.ShouldProcess("$target/$(Split-Path $Path -Leaf)", 'Upload')) {
        Add-PnPFile -Path $Path -Folder $target | Out-Null
    }
}
