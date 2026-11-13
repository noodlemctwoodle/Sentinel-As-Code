#Requires -Version 7.6

<#
.SYNOPSIS
    Build the iSOC Blueprint SharePoint site bundle from a Sentinel
    Blueprint workspace snapshot.

.DESCRIPTION
    The build itself is one function per file under
    Modules/iSOCBlueprint/Private/Site (Invoke-iSOCBlueprintSiteBuild and its
    steps); this script loads them and runs it with the same parameters.

    Reads one Blueprint workspace folder (the _raw/*.json snapshot that
    Export-SentinelInventory.ps1 writes and the section model, sections/*.json,
    that Convert-SentinelInventoryToMarkdown.ps1 renders next to it) and
    writes everything Publish-SentinelDocsSite.ps1 needs into one folder.
    No Markdown is read: a run rendered with -OutputFormat Json is enough.
    A snapshot rendered before the section model existed has only the
    NN-name.md files; those are converted on the fly instead.

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
    network, so the bundle can be built from a downloaded pipeline artefact
    and inspected before publishing. What's new in Sentinel and Defender is
    a report page (03-whats-new.md), read by the collector.

    Charts come from the section model as data. The dashboard draws its own,
    and each section page places the chart web part, which draws the chart
    from that data; nothing is pre-rendered.

.PARAMETER Source
    Blueprint workspace folder: the directory that contains _raw/ and
    sections/ (for example SecurityDocs/law-sentinel-prod).

.PARAMETER OutputRoot
    Bundle folder. Defaults to '<Source>/sharepoint'. The pages/ and
    tables/ subfolders are cleared at the start of each build so a removed
    section or table never lingers.

.PARAMETER ProductName
    Product name shown on the dashboard, in page titles and in the site
    descriptor. Defaults to 'iSOC Blueprint'.

.PARAMETER Title
    Dashboard document title. Defaults to '<workspace> - <ProductName>'.

.PARAMETER WorkspaceName
    Override the workspace name. Defaults to the WorkspaceName recorded in
    _raw/run-context.json, else the leaf name of -Source.

.PARAMETER WhatsNewFeedUrl
    No longer used: What's new is a report page the collector reads. Kept
    so existing scripts still run.

.PARAMETER WhatsNewCount
    No longer used; see WhatsNewFeedUrl.

.PARAMETER SkipWhatsNew
    No longer used: the build makes no network call. Kept so existing
    scripts still run.

.PARAMETER MaxTableRows
    Maximum body rows per table on a native page. Defaults to 500, which
    keeps a page within Microsoft's page-weight guidance. A longer table is
    cut with a note linking to the whole table as a CSV file (tables/) and
    to the dashboard, whose copy of the section has every row.

.PARAMETER HistoryDays
    When -Source is a day's folder (yyyy-MM-dd) beside earlier days' folders,
    how many days back, counting this one, the bundle carries for the
    dashboard's date picker. Each earlier day needs its own bundle (its
    sharepoint/index.html). Defaults to 90; 0 carries none.

.OUTPUTS
    [string] The bundle folder path.

.EXAMPLE
    ./Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1 `
        -Source ./SecurityDocs/law-sentinel-prod

    Builds the bundle into ./SecurityDocs/law-sentinel-prod/sharepoint.

.EXAMPLE
    ./Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1 `
        -Source ./artefact/law-sentinel-prod -SkipWhatsNew -WhatIf

    Shows what would be written without writing anything or fetching the
    feed.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-07
    Version:      0.19.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    Credit and thanks: the data behind the dashboard's estate flow,
    maturity and insight panels is based on the Sentinel health-check
    script by thinkndle, kindly given to the Sentinel-As-Code project.
    Thank you, thinkndle, for sharing your work so generously; it shaped
    much of the Blueprint's health, coverage and maturity reporting.
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
    [int]$HistoryDays = 90
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Private/Get-SectionFamily.ps1')
. (Join-Path $PSScriptRoot 'Private/ConvertTo-SharePointPageSegments.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-SacProgress.ps1')
. (Join-Path $PSScriptRoot '../Private/Get-TableFamily.ps1')
. (Join-Path $PSScriptRoot '../Private/Get-AttackCoverage.ps1')
. (Join-Path $PSScriptRoot '../Private/Get-TemplateSolution.ps1')
. (Join-Path $PSScriptRoot '../Private/Get-TableTierProfile.ps1')
. (Join-Path $PSScriptRoot '../Private/Get-FindingMaturityLink.ps1')
# Only for snapshots rendered before the section model: their Markdown is
# converted with the renderer's own converter.
. (Join-Path $PSScriptRoot '../Private/ConvertFrom-BlueprintMermaid.ps1')
. (Join-Path $PSScriptRoot '../Private/ConvertTo-BlueprintSection.ps1')

# The site build and its steps (the module's own Private/Site, two folders up
# from here), defined in this scope.
$siteBuildRoot = Join-Path $PSScriptRoot '..' '..' 'Private' 'Site'
foreach ($siteBuildFile in Get-ChildItem -LiteralPath $siteBuildRoot -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
    . $siteBuildFile.FullName
}
Remove-Variable -Name siteBuildFile, siteBuildRoot -WhatIf:$false

Invoke-iSOCBlueprintSiteBuild @PSBoundParameters -EngineRoot (Join-Path $PSScriptRoot '..') -SiteRoot $PSScriptRoot
