#Requires -Version 7.2

<#
.SYNOPSIS
    Publish-iSOCBlueprintSite: make a SharePoint site match a site bundle.

.DESCRIPTION
    Runs Engine/SharePoint/Publish-SentinelDocsSite.ps1.

.NOTES
    File:         Modules/iSOCBlueprint/Public/Publish-iSOCBlueprintSite.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+

    The publisher itself requires PowerShell 7.4 and PnP.PowerShell 3.4.1;
    see Test-iSOCBlueprintPrerequisite -Step Publish.

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Publish-iSOCBlueprintSite {
    <#
    .SYNOPSIS
        Publish a site bundle to its SharePoint Online site.

    .DESCRIPTION
        Makes the site match the bundle New-iSOCBlueprintSite wrote: the
        asset library and the findings list, the web part package when
        -AppPackagePath is given and its version differs, the dashboard,
        one page per section (pages whose content has not changed since the
        last publish are skipped), the findings (added, updated, reopened,
        resolved or retired, keeping their history), the navigation, and
        finally the pages and images the bundle no longer has. A run is
        idempotent, and the steps run in that order so a failure part way
        leaves the site consistent.

        Set the site up once with Initialize-iSOCBlueprintSite.

        Pipelines pass -AccessToken, a SharePoint token for an app that
        holds Sites.Selected (FullControl) on this one site. Locally, use
        -Interactive with your own Entra app registration. -WhatIf connects,
        reads the site, prints the plan and writes nothing.

    .PARAMETER SiteUrl
        Absolute URL of the site, for example
        https://contoso.sharepoint.com/sites/isoc-law-sentinel-prod.

    .PARAMETER Path
        The bundle folder (it contains site.json).

    .PARAMETER AccessToken
        SharePoint access token (audience https://<tenant>.sharepoint.com).

    .PARAMETER Interactive
        Sign in interactively instead. Needs -ClientId and -Tenant.

    .PARAMETER ClientId
        Entra app registration used for interactive sign-in.

    .PARAMETER Tenant
        Tenant for interactive sign-in, for example contoso.onmicrosoft.com.

    .PARAMETER AppPackagePath
        Path to isoc-blueprint.sppkg (the dashboard and chart web parts).
        Deployed to the site collection app catalog when its version
        differs from the one there. When omitted, the deployed package is
        used as it is.

    .PARAMETER TokenLifetimeMinutes
        How long an -AccessToken is trusted before the run stops with a
        clear error, since it cannot be refreshed. Defaults to 50.

    .OUTPUTS
        [string] The site URL.

    .EXAMPLE
        Publish-iSOCBlueprintSite -SiteUrl https://contoso.sharepoint.com/sites/isoc-prod `
            -Path ./SecurityDocs/law-sentinel-prod/sharepoint `
            -Interactive -ClientId '<app-id>' -Tenant contoso.onmicrosoft.com -WhatIf

        Signs in as you, reads the site and prints what a publish would
        change.

    .EXAMPLE
        Publish-iSOCBlueprintSite -SiteUrl $env:SHAREPOINT_SITE_URL -Path $bundle -AccessToken $token

        What a pipeline runs.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The engine script makes the ShouldProcess calls; -WhatIf and -Confirm are passed on to it.')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Token')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $SiteUrl,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Bundle')]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'Token')]
        [string] $AccessToken,

        [Parameter(Mandatory, ParameterSetName = 'Interactive')]
        [switch] $Interactive,

        [Parameter(Mandatory, ParameterSetName = 'Interactive')]
        [string] $ClientId,

        [Parameter(Mandatory, ParameterSetName = 'Interactive')]
        [string] $Tenant,

        [string] $AppPackagePath,

        [int] $TokenLifetimeMinutes
    )

    process {
        $params = @{ SiteUrl = $SiteUrl; Bundle = (Resolve-iSOCBlueprintPath -Path $Path) }
        if ($PSCmdlet.ParameterSetName -eq 'Token') { $params.AccessToken = $AccessToken }
        else {
            $params.Interactive = $true
            $params.ClientId = $ClientId
            $params.Tenant = $Tenant
        }
        if ($AppPackagePath) { $params.AppPackagePath = Resolve-iSOCBlueprintPath -Path $AppPackagePath }
        Copy-iSOCBlueprintParameter -BoundParameters $PSBoundParameters -Into $params -Name 'TokenLifetimeMinutes'

        $result = @(Invoke-iSOCBlueprintEngine -Script 'SharePoint/Publish-SentinelDocsSite.ps1' -Parameters $params -BoundParameters $PSBoundParameters)
        if ($result.Count -gt 0) { [string]$result[-1] }
    }
}
