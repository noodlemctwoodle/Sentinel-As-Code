#Requires -Version 7.6

<#
.SYNOPSIS
    Thin SharePoint (PnP.PowerShell) wrappers for the iSOC Blueprint site
    publisher.

.DESCRIPTION
    Dot-source this file to define the SharePoint functions and the names the
    site publisher uses. They live one per file under
    Modules/iSOCBlueprint/Private/SharePoint:

      Site/        the web, its assets library and the findings list
      Apps/        the web part package and the app catalogue
      Files/       uploads to the assets library and the state folder
      State/       the publish state and the maturity and progress histories
      Snapshots/   the per-day dashboard copies and their index
      Pages/       the section pages and the dashboard page
      Findings/    the findings list items and the plan applied to them
      Navigation/  the quick-launch navigation
      Data/        the names, ids and findings columns

    Each function does one SharePoint job (make sure the findings list
    exists, publish one page, rebuild the navigation, ...) and nothing
    else. Decisions about what to do live in Get-SacSyncPlan.ps1. Every
    function that changes the site supports -WhatIf / -Confirm and inherits
    the caller's preference, so Publish-iSOCBlueprintSite -WhatIf reads
    the site but writes nothing.

    The functions assume an open PnP connection (Connect-PnPOnline) and are
    only dot-sourced by the publisher and the bootstrap. Tests dot-source
    the pure helpers here (Resolve-SacSiteUrl, Get-SacAppPackageInfo,
    ConvertTo-SacNavigationTree, Add-SacMaturityHistoryEntry) without PnP
    installed.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/SharePoint/Private/SacSharePoint.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-08
    Version:      0.7.1
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file loads functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# The functions and names (the module's own Private/SharePoint, three folders
# up from here), defined in the caller's scope.
$sacRoot = Join-Path $PSScriptRoot '..' '..' '..' 'Private' 'SharePoint'
foreach ($sacFile in Get-ChildItem -LiteralPath $sacRoot -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
    . $sacFile.FullName
}
Remove-Variable -Name sacFile, sacRoot -WhatIf:$false
