#Requires -Version 7.6

<#
.SYNOPSIS
    Loads the pure planning functions for the SharePoint site publisher:
    decide what to create, update, resolve or remove before anything
    touches SharePoint.

.DESCRIPTION
    The publisher reads the current state of the site (pages, findings list
    items, navigation, asset files), passes it to these functions with the
    freshly built bundle, and gets back a plan. Keeping the decisions out of
    the PnP code means they are unit-tested without a SharePoint connection,
    and -WhatIf can print exactly what a run would do.

    Dot-source this file to define the functions. They live one per file
    under Modules/iSOCBlueprint/Private/SyncPlan:

      Pages/        Get-PageSyncPlan       pages to create, update, skip or
                                           delete
      Findings/     Get-FindingSyncPlan    findings list items to add, update,
                                           reopen, resolve or retire
      Navigation/   Get-NavigationPlan     the top navigation tree
                    Get-NavigationSignature  a string to tell whether the
                                           tree changed
      Assets/       Get-AssetPrunePlan     asset files no longer referenced

.NOTES
    File:         Modules/iSOCBlueprint/Engine/SharePoint/Private/Get-SacSyncPlan.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-08
    Version:      0.2.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file loads functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# The planning functions (the module's own Private/SyncPlan, three folders up
# from here), defined in the caller's scope.
$syncPlanRoot = Join-Path $PSScriptRoot '..' '..' '..' 'Private' 'SyncPlan'
foreach ($syncPlanFile in Get-ChildItem -LiteralPath $syncPlanRoot -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
    . $syncPlanFile.FullName
}
Remove-Variable -Name syncPlanFile, syncPlanRoot -WhatIf:$false
