#Requires -Version 7.6

<#
.SYNOPSIS
    Delete a day's dashboard copy.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Snapshots/Remove-SacSnapshot.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Remove-SacSnapshot {
    <#
    .SYNOPSIS
        Move one day's snapshot that has dropped out of the window to the
        site's recycle bin.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $FileName)
    $url = "$script:SacAssetsLibraryUrl/$script:SacSnapshotFolder/$FileName"
    if ($PSCmdlet.ShouldProcess($url, 'Recycle snapshot')) {
        Remove-PnPFile -SiteRelativeUrl $url -Recycle -Force -ErrorAction SilentlyContinue
    }
}
