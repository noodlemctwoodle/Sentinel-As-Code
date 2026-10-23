#Requires -Version 7.2

<#
.SYNOPSIS
    Initialize-iSOCBlueprintSite: one-time set-up of a Blueprint
    SharePoint site.

.DESCRIPTION
    Runs Engine/SharePoint/Initialize-SentinelDocsSite.ps1.

.NOTES
    File:         Modules/iSOCBlueprint/Public/Initialize-iSOCBlueprintSite.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Permissions:  SharePoint administrator; delegated Sites.FullControl.All on the sign-in app
    Requires:     PowerShell 7.2+

    The set-up script itself requires PowerShell 7.4 and PnP.PowerShell
    3.4.1; see Test-iSOCBlueprintPrerequisite -Step Publish.

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Initialize-iSOCBlueprintSite {
    <#
    .SYNOPSIS
        Create and prepare the SharePoint site a Blueprint publishes to.
        Run once, interactively, by a SharePoint administrator.

    .DESCRIPTION
        Does the part a pipeline should not have the rights to do:

          1. Creates the communication site if it does not exist yet.
          2. Adds a site collection app catalog to it, so the web parts
             are deployed to this site only.
          3. Grants the publisher app registration FullControl on this
             site only (Sites.Selected).
          4. Turns off page comments and turns on the mega menu.
          5. Optionally deploys the web part package now.

        Safe to re-run: each step checks before it changes anything. Site
        membership is the privacy boundary, since the site shows tenant
        configuration, findings and role assignments.

    .PARAMETER SiteUrl
        URL of the site to create or prepare.

    .PARAMETER Title
        Site title when the site is created. Defaults to 'iSOC Blueprint'.

    .PARAMETER Owner
        UPN of the site owner, used when creating the site.

    .PARAMETER PublisherAppId
        Client (application) id of the publisher app registration the
        pipelines use.

    .PARAMETER PublisherAppName
        Display name recorded with the site permission grant.

    .PARAMETER ClientId
        Your Entra app registration for interactive sign-in.

    .PARAMETER Tenant
        Tenant, for example contoso.onmicrosoft.com.

    .PARAMETER TenantAdminUrl
        SharePoint admin centre URL. Defaults to the one derived from
        SiteUrl.

    .PARAMETER AppPackagePath
        Optional path to isoc-blueprint.sppkg to deploy now.

    .OUTPUTS
        None. Progress and the next steps are written to the host.

    .EXAMPLE
        Initialize-iSOCBlueprintSite -SiteUrl https://contoso.sharepoint.com/sites/isoc-prod `
            -Owner secops-lead@contoso.com -PublisherAppId '<publisher-app-id>' `
            -ClientId '<your-app-id>' -Tenant contoso.onmicrosoft.com -WhatIf

        Shows what the set-up would do. Drop -WhatIf to run it.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The engine script makes the ShouldProcess calls; -WhatIf and -Confirm are passed on to it.')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $SiteUrl,

        [string] $Title,

        [Parameter(Mandatory)]
        [string] $Owner,

        [Parameter(Mandatory)]
        [string] $PublisherAppId,

        [string] $PublisherAppName,

        [Parameter(Mandatory)]
        [string] $ClientId,

        [Parameter(Mandatory)]
        [string] $Tenant,

        [string] $TenantAdminUrl,

        [string] $AppPackagePath
    )

    $params = @{
        SiteUrl        = $SiteUrl
        Owner          = $Owner
        PublisherAppId = $PublisherAppId
        ClientId       = $ClientId
        Tenant         = $Tenant
    }
    Copy-iSOCBlueprintParameter -BoundParameters $PSBoundParameters -Into $params -Name 'Title', 'PublisherAppName', 'TenantAdminUrl'
    if ($AppPackagePath) { $params.AppPackagePath = Resolve-iSOCBlueprintPath -Path $AppPackagePath }

    $null = Invoke-iSOCBlueprintEngine -Script 'SharePoint/Initialize-SentinelDocsSite.ps1' -Parameters $params -BoundParameters $PSBoundParameters
}
