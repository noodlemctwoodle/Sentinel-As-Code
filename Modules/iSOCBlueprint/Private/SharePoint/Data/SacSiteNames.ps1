#Requires -Version 7.6

<#
.SYNOPSIS
    Names and ids the site publisher owns on the SharePoint site.

.DESCRIPTION
    Defines the $script:Sac* names (library, list, state files, snapshot folder and web part component ids).

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Data/SacSiteNames.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines values rather than running.
#>

$script:SacAssetsLibraryTitle = 'Blueprint Assets'
$script:SacAssetsLibraryUrl = 'BlueprintAssets'
# The assets library's name before the Documenter was renamed Blueprint. The
# state readers fall back to it, and a clean publish recycles it.
$script:SacLegacyAssetsLibraryUrl = 'DocumenterAssets'
$script:SacFindingsListTitle = 'Sentinel Findings'
$script:SacFindingsListUrl = 'Lists/SentinelFindings'
$script:SacStateFile = 'publish-state.json'
$script:SacMaturityHistoryFile = 'maturity-history.json'
$script:SacProgressHistoryFile = 'progress-history.json'
# A copy of the dashboard per day, beside the live one, for its date picker.
$script:SacSnapshotFolder = 'dashboard/history'
$script:SacSnapshotIndexFile = 'index.json'
$script:SacWebPartComponentId = 'a2fd5aa3-01c5-431e-8c98-66f76c89803a'
# The isoc-blueprint chart web part: draws one chart from the section model's
# chart data, on the section pages.
$script:SacChartWebPartComponentId = '4ae8707c-ca6f-40cb-a974-c94d023de6e5'
$script:SacLinklessHeaderUrl = 'http://linkless.header/'
