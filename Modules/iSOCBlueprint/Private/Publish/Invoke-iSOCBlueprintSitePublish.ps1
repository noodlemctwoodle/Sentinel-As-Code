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
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>


function Invoke-iSOCBlueprintSitePublish {
    <#
    .SYNOPSIS
        Publish an iSOC Blueprint site bundle to its SharePoint Online site.

    .DESCRIPTION
        The parameters are those of Engine/SharePoint/Publish-SentinelDocsSite.ps1,
        whose help describes the stages. Supports -WhatIf, which reads the site
        and prints the plan without writing.

    .PARAMETER SiteUrl
        The site collection URL.

    .PARAMETER Bundle
        The bundle folder Build-SentinelDocsSite.ps1 wrote.

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
    [int]$HistoryDays = 90)

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
