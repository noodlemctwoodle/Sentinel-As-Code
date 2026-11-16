#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'PnP.PowerShell'; ModuleVersion = '3.4.1' }

<#
.SYNOPSIS
    Publish an iSOC Blueprint site bundle to its SharePoint Online site.

.DESCRIPTION
    The publish itself is one function per file under
    Modules/iSOCBlueprint/Private/Publish (Invoke-iSOCBlueprintSitePublish and
    its steps); this script loads them and runs it with the same parameters.

    Takes the bundle Build-SentinelDocsSite.ps1 wrote and makes the site
    match it. The whole site content is generated: one page per Blueprint
    section, the top navigation, the findings list and the dashboard home
    page. A run is idempotent, and steps run in this order so a failure
    part-way leaves the site consistent:

      1. Structure   the 'Blueprint Assets' library and the 'Sentinel
                     Findings' list (with its columns) exist
      2. App         the isoc-blueprint .sppkg (the dashboard and chart
                     web parts) is deployed to the site collection app
                     catalog, only when its version differs from what is
                     deployed (-AppPackagePath)
      3. Assets      dashboard HTML and its model uploaded (and diagrams,
                     from a bundle built before charts became data); the
                     CSV of each table cut on its page (tables/), which the
                     page's note links to;
                     when the model carries a maturity assessment, one
                     entry is appended to the score history the dashboard
                     draws as a trend; the run's progress record is added
                     to the progress history the Progress tab compares;
                     and a copy of the dashboard is kept as the day's
                     snapshot (dashboard/history/<date>.html)
                     for its date picker, the last -HistoryDays days
      4. Pages       section pages created or rebuilt, skipping any whose
                     content hash matches the last publish; each chart is
                     placed as the chart web part, or as a table while the
                     web part is not on the site (that page is rebuilt on
                     the next run); per-page failures are collected rather
                     than stopping the run
      5. Dashboard   the home page hosts the dashboard web part, pointed at
                     the uploaded HTML on every run
      6. Findings    list items added, updated, reopened, resolved or
                     retired (findings that stop firing keep their history)
      7. Navigation  the top navigation rebuilt from the pages that exist,
                     only when it differs from the plan
      8. Prune       pages, diagrams and table CSVs the bundle no longer
                     has are sent to the recycle bin, only when every page
                     published

    The site itself, its site collection app catalog and this identity's
    access are created once by Initialize-SentinelDocsSite.ps1.

    Authentication: pipelines pass -AccessToken, a SharePoint token for an
    app that holds Sites.Selected (FullControl) on this one site, obtained
    through workload identity federation. Locally, use -Interactive with
    your own Entra app registration. An access token cannot be refreshed,
    so the run stops with a clear error if it is still going after
    -TokenLifetimeMinutes.

    -WhatIf connects and reads the site, prints the plan, and writes
    nothing.

.PARAMETER SiteUrl
    Absolute URL of the site, for example
    https://contoso.sharepoint.com/sites/isoc-law-sentinel-prod.

.PARAMETER Bundle
    The bundle folder Build-SentinelDocsSite.ps1 wrote (it contains
    site.json).

.PARAMETER AccessToken
    SharePoint access token (audience https://<tenant>.sharepoint.com).
    Used by the pipelines.

.PARAMETER Interactive
    Sign in interactively instead. Requires -ClientId and -Tenant.

.PARAMETER ClientId
    Entra app registration used for interactive sign-in.

.PARAMETER Tenant
    Tenant for interactive sign-in, for example contoso.onmicrosoft.com.

.PARAMETER AppPackagePath
    Path to isoc-blueprint.sppkg. When given, the package is deployed
    to the site collection app catalog if its version differs from the one
    already there. When omitted, the deployed package is used as-is.

.PARAMETER TokenLifetimeMinutes
    How long an -AccessToken is trusted for before the run stops. Defaults
    to 50 (tokens last about 60 to 90 minutes).

.PARAMETER HistoryDays
    How many days of dashboard snapshots to keep for the dashboard's date
    picker, counting back from the newest. Each publish keeps one per day
    (a second publish that day replaces it), so the history grows with the
    pipeline's daily runs up to this many days; older days go to the
    recycle bin. Defaults to 90; 0 keeps none.

.OUTPUTS
    [string] The site URL.

.EXAMPLE
    ./Modules/iSOCBlueprint/Engine/SharePoint/Publish-SentinelDocsSite.ps1 `
        -SiteUrl 'https://contoso.sharepoint.com/sites/isoc-law-sentinel-prod' `
        -Bundle ./SecurityDocs/law-sentinel-prod/sharepoint `
        -Interactive -ClientId '<app-id>' -Tenant 'contoso.onmicrosoft.com' -WhatIf

    Signs in as you, reads the site and prints what a publish would change.

.EXAMPLE
    ./Modules/iSOCBlueprint/Engine/SharePoint/Publish-SentinelDocsSite.ps1 `
        -SiteUrl $env:SHAREPOINT_SITE_URL -Bundle $bundle `
        -AccessToken $token -AppPackagePath ./isoc-blueprint.sppkg

    What the pipelines run.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/SharePoint/Publish-SentinelDocsSite.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-07
    Version:      0.8.0
    Last Updated: 2026-11-13
    Permissions:  Sites.Selected (SharePoint, application) with FullControl on the target site
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Token')]
param(
    [Parameter(Mandatory = $true)]
    [string]$SiteUrl,

    [Parameter(Mandatory = $true)]
    [string]$Bundle,

    [Parameter(Mandatory = $true, ParameterSetName = 'Token')]
    [string]$AccessToken,

    [Parameter(Mandatory = $true, ParameterSetName = 'Interactive')]
    [switch]$Interactive,

    [Parameter(Mandatory = $true, ParameterSetName = 'Interactive')]
    [string]$ClientId,

    [Parameter(Mandatory = $true, ParameterSetName = 'Interactive')]
    [string]$Tenant,

    [Parameter(Mandatory = $false)]
    [string]$AppPackagePath,

    [Parameter(Mandatory = $false)]
    [int]$TokenLifetimeMinutes = 50,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 3650)]
    [int]$HistoryDays = 90
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' '..' 'Private' 'SiteShared' 'Get-SectionFamily.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-SacSyncPlan.ps1')
. (Join-Path $PSScriptRoot 'Private/SacSharePoint.ps1')
. (Join-Path $PSScriptRoot '..' '..' 'Private' 'SiteShared' 'Get-SacProgress.ps1')
# Publish-SacSectionPage writes a chart as a table, through
# ConvertTo-SacChartFallbackHtml, when the chart web part is missing.
. (Join-Path $PSScriptRoot 'Private/ConvertTo-SharePointPageSegments.ps1')

# The publish and its steps (the module's own Private/Publish, two folders up
# from here), defined in this scope.
$publishRoot = Join-Path $PSScriptRoot '..' '..' 'Private' 'Publish'
foreach ($publishFile in Get-ChildItem -LiteralPath $publishRoot -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
    . $publishFile.FullName
}
Remove-Variable -Name publishFile, publishRoot -WhatIf:$false

Invoke-iSOCBlueprintSitePublish @PSBoundParameters
