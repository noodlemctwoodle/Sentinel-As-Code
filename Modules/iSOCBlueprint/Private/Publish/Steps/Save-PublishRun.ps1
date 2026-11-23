#Requires -Version 7.6

<#
.SYNOPSIS
    Record the publish state, and fail the run when any page failed.

.DESCRIPTION
    A step of the SharePoint site publish. Steps run in order and pass their results
    to later ones through the publish context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Publish/Steps/Save-PublishRun.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Save-PublishRun {
    <#
    .SYNOPSIS
        Record the publish state, and fail the run when any page failed.

    .PARAMETER Context
        The publish context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the publish context.
    $appVersion = $Context.appVersion
    $navPlan = $Context.navPlan
    $pageErrors = $Context.pageErrors
    $publishedHashes = $Context.publishedHashes
    $site = $Context.site
    $SiteUrl = $Context.SiteUrl

    # State ------------------------------------------------------------------------
    if (-not $WhatIfPreference) {
        $newState = @{
            pages          = $publishedHashes
            navSignature   = $navPlan.Signature
            appVersion     = $appVersion
            publishedUtc   = (Get-Date).ToUniversalTime().ToString('o')
            bundleBuiltUtc = [string]$site.builtUtc
        }
        Save-SacPublishState -State $newState
    }

    if ($pageErrors.Count -gt 0) {
        throw "Published with $($pageErrors.Count) page failure(s):`n  " + ($pageErrors -join "`n  ")
    }

    Write-Host "`nPublished: $SiteUrl" -ForegroundColor Green

}
