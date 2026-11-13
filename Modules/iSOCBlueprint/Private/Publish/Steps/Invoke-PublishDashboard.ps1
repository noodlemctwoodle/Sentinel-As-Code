#Requires -Version 7.6

<#
.SYNOPSIS
    Stage 5: publish the dashboard home page.

.DESCRIPTION
    A step of the SharePoint site publish. Steps run in order and pass their results
    to later ones through the publish context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Publish/Steps/Invoke-PublishDashboard.ps1
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

function Invoke-PublishDashboard {
    <#
    .SYNOPSIS
        Stage 5: publish the dashboard home page.

    .PARAMETER Context
        The publish context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the publish context.
    $site = $Context.site
    $TokenLifetimeMinutes = $Context.TokenLifetimeMinutes

    # 5. Dashboard ---------------------------------------------------------------
    Write-PublishStep '5/8 Dashboard home page'
    Assert-TokenFresh 'dashboard'
    Publish-SacDashboardPage -PageName ([string]$site.dashboard.page) -Title ([string]$site.title) `
        -FileRelativeUrl "$script:SacAssetsLibraryUrl/dashboard/$($site.dashboard.file)"
}
