#Requires -Version 7.6

<#
.SYNOPSIS
    Write the maturity history to the site.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/State/Save-SacMaturityHistory.ps1
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

function Save-SacMaturityHistory {
    <#
    .SYNOPSIS
        Write the maturity history to _state/ (the record) and to dashboard/
        (what the dashboard fetches from beside its own page).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [hashtable] $History)
    $json = $History | ConvertTo-Json -Depth 8
    foreach ($folder in '_state', 'dashboard') {
        if ($PSCmdlet.ShouldProcess("$script:SacAssetsLibraryUrl/$folder/$script:SacMaturityHistoryFile", 'Save maturity history')) {
            Add-PnPFile -Folder "$script:SacAssetsLibraryUrl/$folder" -FileName $script:SacMaturityHistoryFile -Content $json | Out-Null
        }
    }
}
