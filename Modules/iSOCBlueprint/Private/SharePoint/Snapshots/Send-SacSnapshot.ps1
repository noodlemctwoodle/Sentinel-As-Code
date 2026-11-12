#Requires -Version 7.6

<#
.SYNOPSIS
    Upload one day's dashboard copy.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Snapshots/Send-SacSnapshot.ps1
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

function Send-SacSnapshot {
    <#
    .SYNOPSIS
        Upload the dashboard as one day's snapshot, history/<date>.html.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $FileName
    )
    $target = "$script:SacAssetsLibraryUrl/$script:SacSnapshotFolder"
    if ($PSCmdlet.ShouldProcess("$target/$FileName", 'Upload snapshot')) {
        Add-PnPFile -Path $Path -Folder $target -NewFileName $FileName | Out-Null
    }
}
