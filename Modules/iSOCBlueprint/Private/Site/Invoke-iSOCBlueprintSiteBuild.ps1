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
    Version:      0.3.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.

    Credit and thanks: the data behind the dashboard's estate flow,
    maturity and insight panels is based on the Sentinel health-check
    script by thinkndle, kindly given to the Sentinel-As-Code project.
    Thank you, thinkndle, for sharing your work so generously; it shaped
    much of the Blueprint's health, coverage and maturity reporting.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCBlueprintSiteBuild {
    <#
    .SYNOPSIS
        Build the iSOC Blueprint SharePoint site bundle from a Sentinel
        Blueprint workspace snapshot.

    .DESCRIPTION
        Reads one Blueprint workspace folder (the _raw/*.json snapshot that
        Export-iSOCBlueprintInventory writes and the section model,
        sections/*.json, that ConvertTo-iSOCBlueprint renders next to it) and
        writes everything the publisher needs into one folder. No Markdown is
        read: a run rendered with -Format Json is enough. A snapshot rendered
        before the section model existed has only the NN-name.md files; those
        are converted on the fly instead.

          index.html          the interactive dashboard: a single self-contained
                              HTML file (inline CSS and JS, data embedded as
                              JSON) that the site's home page hosts
          model.json          the dashboard's data model
          site.json           site descriptor: product name, workspace, the
                              section list with page names, families and hashes
          pages/<page>.json   one file per section: title and the ordered
                              segments (HTML for Text web parts, chart data for
                              the isoc-blueprint chart web part)
          progress.json       this run's progress record: the headline numbers
                              and the lists the dashboard's Progress tab compares
          progress-history.json  every kept day's record, oldest first, from the
                              earlier day folders' bundles (the publisher keeps
                              the site's own)
          tables/<name>.csv   each table cut at -MaxTableRows on its page, whole,
                              as CSV (UTF-8); the page's note links to it and
                              the publisher puts it in the assets library
          findings.json       gap-analysis findings plus per-check outcomes,
                              for the findings list
          history/            when the source is a day's folder (yyyy-MM-dd)
                              beside earlier days: each kept day's dashboard as
                              <date>.html and index.json listing them, for the
                              dashboard's date picker

        Nothing here talks to SharePoint, Azure or anything else on the
        network, so the bundle can be built from a downloaded pipeline
        artefact and inspected before publishing. What's new in Sentinel and
        Defender is a report page (03-whats-new.md), read by the collector.
        Charts come from the section model as data; nothing is pre-rendered.

        Strict mode is turned off for the call, as the script this replaces
        always ran without it. Supports -WhatIf, which shows what would be
        written without writing anything.

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

    .PARAMETER ResourcesFolder
        The module's Resources folder (its Data folder holds the catalogues the
        build reads). Defaults to the module's own.

    .PARAMETER SiteRoot
        The Resources/SharePoint folder (the dashboard templates live under it).
        Defaults to the module's own.

    .OUTPUTS
        The bundle folder.

    .EXAMPLE
        Invoke-iSOCBlueprintSiteBuild -Source ./SecurityDocs/law-sentinel-prod/2026-11-12

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

        [Parameter(Mandatory = $false)]
        [string]$ResourcesFolder = $script:iSOCBlueprintResourcesRoot,

        [Parameter(Mandatory = $false)]
        [string]$SiteRoot = (Join-Path $script:iSOCBlueprintResourcesRoot 'SharePoint')
    )

    Set-StrictMode -Off
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
        resourcesFolder = $ResourcesFolder
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
