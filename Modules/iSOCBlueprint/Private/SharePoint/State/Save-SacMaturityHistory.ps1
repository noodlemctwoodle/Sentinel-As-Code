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
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Save-SacMaturityHistory {
    <#
    .SYNOPSIS
        Write the maturity history to _state/ (the record) and to dashboard/
        (what the dashboard fetches from beside its own page).

    .PARAMETER History
        The maturity history, written as JSON to the maturity history file in
        both folders.
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
