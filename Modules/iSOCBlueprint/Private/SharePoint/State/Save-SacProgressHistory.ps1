#Requires -Version 7.6

<#
.SYNOPSIS
    Write the progress history to the site.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/State/Save-SacProgressHistory.ps1
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

function Save-SacProgressHistory {
    <#
    .SYNOPSIS
        Write the progress history to _state/ (the record) and to dashboard/
        (what the dashboard's Progress tab fetches from beside its page).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] $History)
    $json = $History | ConvertTo-Json -Depth 32 -Compress
    foreach ($folder in '_state', 'dashboard') {
        if ($PSCmdlet.ShouldProcess("$script:SacAssetsLibraryUrl/$folder/$script:SacProgressHistoryFile", 'Save progress history')) {
            Add-PnPFile -Folder "$script:SacAssetsLibraryUrl/$folder" -FileName $script:SacProgressHistoryFile -Content $json | Out-Null
        }
    }
}
