#Requires -Version 7.6

<#
.SYNOPSIS
    Publish an iSOC Blueprint site bundle to its SharePoint Online site.

.DESCRIPTION
    Entry point of the publish. Runs the steps under Steps/ in order: load the
    bundle, connect, then the eight stages (structure and app, assets, pages,
    dashboard, findings, navigation, prune) and the state record. The steps
    share their values through a context hashtable. A run is idempotent, and
    the order means a failure part-way leaves the site consistent.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Publish/Invoke-iSOCBlueprintSitePublish.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.2.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCBlueprintSitePublish {
    <#
    .SYNOPSIS
        Publish an iSOC Blueprint site bundle to its SharePoint Online site.

    .DESCRIPTION
        Takes the bundle New-iSOCBlueprintSite wrote and makes the site match
        it. The whole site content is generated: one page per Blueprint
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
                         page's note links to; when the model carries a
                         maturity assessment, one entry is appended to the
                         score history the dashboard draws as a trend; the
                         run's progress record is added to the progress history
                         the Progress tab compares; and a copy of the dashboard
                         is kept as the day's snapshot
                         (dashboard/history/<date>.html) for its date picker,
                         the last -HistoryDays days
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
        access are created once by Initialize-iSOCBlueprintSite.

        Authentication: pipelines pass -AccessToken, a SharePoint token for an
        app that holds Sites.Selected (FullControl) on this one site, obtained
        through workload identity federation. Locally, use -Interactive with
        your own Entra app registration. An access token cannot be refreshed,
        so the run stops with a clear error if it is still going after
        -TokenLifetimeMinutes.

        Supports -WhatIf, which connects and reads the site, prints the plan,
        and writes nothing. Strict mode is turned off for the call, as the
        script this replaces always ran without it.

    .PARAMETER SiteUrl
        The site collection URL.

    .PARAMETER Bundle
        The bundle folder New-iSOCBlueprintSite wrote (it contains site.json).

    .PARAMETER AccessToken
        An access token for the site (the Token parameter set).

    .PARAMETER Interactive
        Sign in as the user (the Interactive parameter set).

    .PARAMETER ClientId
        The app registration to sign in with (Interactive).

    .PARAMETER Tenant
        The tenant to sign in to (Interactive).

    .PARAMETER AppPackagePath
        The web part package to deploy.

    .PARAMETER TokenLifetimeMinutes
        How long an -AccessToken may be in use before a stage refuses to start
        (Assert-TokenFresh).

    .PARAMETER HistoryDays
        Days of dashboard copies and progress records to keep.

    .OUTPUTS
        [string] The site URL.
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

    Set-StrictMode -Off
    $ErrorActionPreference = 'Stop'

    $script:ConnectedAt = $null
    $script:PublishParameterSet = $PSCmdlet.ParameterSetName
    $script:PublishTokenLifetimeMinutes = $TokenLifetimeMinutes

    $context = @{
        SiteUrl              = $SiteUrl
        Bundle               = $Bundle
        AccessToken          = $AccessToken
        Interactive          = $Interactive
        ClientId             = $ClientId
        Tenant               = $Tenant
        AppPackagePath       = $AppPackagePath
        HistoryDays          = $HistoryDays
        parameterSetName     = $PSCmdlet.ParameterSetName
    }

    $steps = @(
        'Import-PublishBundle'
        'Connect-PublishSite'
        'Invoke-PublishStructure'
        'Invoke-PublishAssets'
        'Invoke-PublishPages'
        'Invoke-PublishDashboard'
        'Invoke-PublishFindings'
        'Invoke-PublishNavigation'
        'Invoke-PublishPrune'
        'Save-PublishRun'
    )
    foreach ($step in $steps) { & $step -Context $context }

    return $SiteUrl
}
