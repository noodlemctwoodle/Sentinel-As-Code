#Requires -Version 7.6

<#
.SYNOPSIS
    Connect to the site with the token or interactively, and read the web and the last publish state.

.DESCRIPTION
    A step of the SharePoint site publish. Steps run in order and pass their results
    to later ones through the publish context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Publish/Steps/Connect-PublishSite.ps1
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

function Connect-PublishSite {
    <#
    .SYNOPSIS
        Connect to the site with the token or interactively, and read the web and the last publish state.

    .PARAMETER Context
        The publish context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the publish context.
    $AccessToken = $Context.AccessToken
    $ClientId = $Context.ClientId
    $SiteUrl = $Context.SiteUrl
    $Tenant = $Context.Tenant
    $parameterSetName = $Context.parameterSetName

    # ---------------------------------------------------------------------------
    # Connect
    # ---------------------------------------------------------------------------

    if ($parameterSetName -eq 'Token') {
        Connect-PnPOnline -Url $SiteUrl -AccessToken $AccessToken
    } else {
        Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Tenant $Tenant -Interactive
    }
    $script:ConnectedAt = Get-Date
    $webRel = [string](Get-PnPWeb).ServerRelativeUrl
    $state = Read-SacPublishState

    # Left in the publish context for later steps.
    $Context.state = $state
    $Context.webRel = $webRel
}
