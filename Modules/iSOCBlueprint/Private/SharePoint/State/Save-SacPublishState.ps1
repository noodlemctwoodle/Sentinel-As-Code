#Requires -Version 7.6

<#
.SYNOPSIS
    Write the publish state to the site.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/State/Save-SacPublishState.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Save-SacPublishState {
    <#
    .SYNOPSIS
        Write the publish state file into the assets library.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [hashtable] $State)
    $json = $State | ConvertTo-Json -Depth 8
    if ($PSCmdlet.ShouldProcess("$script:SacAssetsLibraryUrl/_state/$script:SacStateFile", 'Save publish state')) {
        Add-PnPFile -Folder "$script:SacAssetsLibraryUrl/_state" -FileName $script:SacStateFile -Content $json | Out-Null
    }
}
