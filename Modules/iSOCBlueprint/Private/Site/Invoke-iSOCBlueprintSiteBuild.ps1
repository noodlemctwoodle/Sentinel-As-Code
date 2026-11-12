#Requires -Version 7.6

<#
.SYNOPSIS
    Build the SharePoint site bundle from a Blueprint workspace snapshot.

.DESCRIPTION
    Entry point of the site build. Reads one Blueprint workspace folder (the
    _raw/*.json snapshot and the section model next to it) and writes
    everything the publisher needs into one folder. Each step under Steps/
    builds one part of the model or writes the bundle; they run in order and
    share their figures through a context hashtable.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Invoke-iSOCBlueprintSiteBuild.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>


function Invoke-iSOCBlueprintSiteBuild {
    <#
    .SYNOPSIS
        Build the iSOC Blueprint SharePoint site bundle from a Sentinel
        Blueprint workspace snapshot.

    .DESCRIPTION
        The parameters are those of Engine/SharePoint/Build-SentinelDocsSite.ps1,
        whose help describes the bundle (index.html, model.json, site.json,
        pages, progress records).

    .PARAMETER Source
        The workspace folder that contains _raw/.

    .PARAMETER OutputRoot
        Folder for the bundle. Defaults to <Source>/sharepoint.

    .PARAMETER ProductName
        Product name shown on the site.

    .PARAMETER Title
        Site title. Defaults to "<workspace> - <product>".

    .PARAMETER WorkspaceName
        Workspace name. Defaults to the one in run-context.json.

    .PARAMETER WhatsNewFeedUrl
        Kept for compatibility; the build makes no network call.

    .PARAMETER WhatsNewCount
        Kept for compatibility; the build makes no network call.

    .PARAMETER SkipWhatsNew
        Kept for compatibility; the build makes no network call.

    .PARAMETER MaxTableRows
        Rows a table keeps on a native page; the rest go to a CSV file.

    .PARAMETER HistoryDays
        Days of earlier dashboard copies to keep.

    .PARAMETER EngineRoot
        The Engine folder (Private/Resources and the engine helpers live under it).

    .PARAMETER SiteRoot
        The Engine/SharePoint folder (the dashboard templates live under it).

    .OUTPUTS
        The bundle folder.

    .EXAMPLE
        Invoke-iSOCBlueprintSiteBuild -Source ./SecurityDocs/law-sentinel-prod/2026-11-12 -EngineRoot $engine -SiteRoot $site

        Builds the bundle into ./SecurityDocs/law-sentinel-prod/2026-11-12/sharepoint.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $false)]
        [string]$OutputRoot,

        [Parameter(Mandatory = $false)]
        [string]$ProductName = 'iSOC Blueprint',

        [Parameter(Mandatory = $false)]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [string]$WorkspaceName,

        [Parameter(Mandatory = $false)]
        [string]$WhatsNewFeedUrl = 'https://www.microsoft.com/releasecommunications/api/v2/azure/rss',

        [Parameter(Mandatory = $false)]
        [int]$WhatsNewCount = 8,

        [switch]$SkipWhatsNew,

        [Parameter(Mandatory = $false)]
        [int]$MaxTableRows = 500,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3650)]
        [int]$HistoryDays = 90,

        [Parameter(Mandatory = $true)]
        [string]$EngineRoot,

        [Parameter(Mandatory = $true)]
        [string]$SiteRoot
    )

    $ErrorActionPreference = 'Stop'

    $script:RawRoot = $null

    $context = @{
        Source          = $Source
        OutputRoot      = $OutputRoot
        ProductName     = $ProductName
        Title           = $Title
        WorkspaceName   = $WorkspaceName
        WhatsNewFeedUrl = $WhatsNewFeedUrl
        WhatsNewCount   = $WhatsNewCount
        SkipWhatsNew    = $SkipWhatsNew
        MaxTableRows    = $MaxTableRows
        HistoryDays     = $HistoryDays
        engineRoot      = $EngineRoot
        siteRoot        = $SiteRoot
    }

    $steps = @(
        'Initialize-SiteBuild'
        'Build-SiteWorkspaceModel'
        'Build-SiteFindings'
        'Build-SiteMitre'
        'Build-SiteEstateFlow'
        'Build-SiteEstate'
        'Build-SiteDetection'
        'Build-SiteOperations'
        'Build-SiteAttack'
        'Build-SiteDaily'
        'Build-SiteDataLake'
        'Build-SiteMaturity'
        'Build-SitePages'
        'Build-SiteModel'
        'Write-SiteBundle'
    )
    foreach ($step in $steps) { & $step -Context $context }

    return $context.OutputRoot
}
