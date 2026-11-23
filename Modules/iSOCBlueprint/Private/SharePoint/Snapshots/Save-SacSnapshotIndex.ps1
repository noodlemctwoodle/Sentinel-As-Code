#Requires -Version 7.6

<#
.SYNOPSIS
    Write the snapshot index to the site.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Snapshots/Save-SacSnapshotIndex.ps1
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

function Save-SacSnapshotIndex {
    <#
    .SYNOPSIS
        Write the snapshot list beside the snapshots, where the dashboard
        reads it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [hashtable] $Index)
    $json = @{ entries = @($Index.entries) } | ConvertTo-Json -Depth 6
    $folder = "$script:SacAssetsLibraryUrl/$script:SacSnapshotFolder"
    if ($PSCmdlet.ShouldProcess("$folder/$script:SacSnapshotIndexFile", 'Save snapshot index')) {
        Add-PnPFile -Folder $folder -FileName $script:SacSnapshotIndexFile -Content $json | Out-Null
    }
}
