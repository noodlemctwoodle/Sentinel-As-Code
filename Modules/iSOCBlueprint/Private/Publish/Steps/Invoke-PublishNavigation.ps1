#Requires -Version 7.6

<#
.SYNOPSIS
    Stage 7: rebuild the navigation when it differs from the plan.

.DESCRIPTION
    A step of the SharePoint site publish. Steps run in order and pass their results
    to later ones through the publish context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Publish/Steps/Invoke-PublishNavigation.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-PublishNavigation {
    <#
    .SYNOPSIS
        Stage 7: rebuild the navigation when it differs from the plan.

    .PARAMETER Context
        The publish context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the publish context.
    $pagePlan = $Context.pagePlan
    $site = $Context.site
    $webRel = $Context.webRel

    # 7. Navigation --------------------------------------------------------------
    Write-PublishStep '7/8 Navigation'
    Assert-TokenFresh 'navigation'
    # Get-SacGeneratedPageName returns its array as one object; assign it
    # directly rather than wrapping it in @(), which would nest it.
    $pagesNow = Get-SacGeneratedPageName
    if ($WhatIfPreference) { $pagesNow = @($pagesNow) + @($pagePlan | Where-Object Action -EQ 'Create' | ForEach-Object { $_.Name }) }
    $navPlan = Get-NavigationPlan -Sections @($site.sections) -ExistingPages $pagesNow -FamilyOrder @($site.familyOrder) `
        -DashboardPage ([string]$site.dashboard.page) -FindingsListUrl ([string]$site.findingsList.url)
    $currentSignature = Get-NavigationSignature -Nodes (Get-SacNavigation -WebServerRelativeUrl $webRel)
    if ($currentSignature -eq $navPlan.Signature) {
        Write-Host '  Navigation unchanged.'
    } else {
        Set-SacNavigation -Nodes $navPlan.Nodes -WebServerRelativeUrl $webRel
        Write-Host "  Navigation rebuilt: $($navPlan.Nodes.Count) top-level nodes."
    }

    # Left in the publish context for later steps.
    $Context.navPlan = $navPlan
}
