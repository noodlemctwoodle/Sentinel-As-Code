#Requires -Version 7.2

<#
.SYNOPSIS
    New-iSOCBlueprintSite: build the SharePoint site bundle from the
    section model.

.DESCRIPTION
    Offline apart from the optional "What's new" feed. Runs
    Engine/SharePoint/Build-SentinelDocsSite.ps1.

.NOTES
    File:         Modules/iSOCBlueprint/Public/New-iSOCBlueprintSite.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function New-iSOCBlueprintSite {
    <#
    .SYNOPSIS
        Build the SharePoint site bundle (dashboard, section pages,
        findings) for one workspace.

    .DESCRIPTION
        Reads the workspace folder (the inventory under _raw/ and the
        section model under sections/) and writes a bundle folder holding
        everything Publish-iSOCBlueprintSite needs: the interactive
        dashboard (index.html) and its model, one page file per section,
        the site descriptor and the findings. Nothing here talks to
        SharePoint or Azure, so the bundle can be built and inspected
        before publishing; open index.html in a browser to preview the
        dashboard. The one network call is the dashboard's "What's new"
        feed, which -SkipWhatsNew leaves out.

        Render with ConvertTo-iSOCBlueprint -Format Json first. A workspace
        rendered before the section model existed (Markdown only) is
        converted on the fly.

    .PARAMETER Path
        The workspace folder holding _raw/ and sections/.

    .PARAMETER OutputPath
        The bundle folder. Defaults to <workspace>/sharepoint. Its pages/
        folder is cleared at the start of each build.

    .PARAMETER ProductName
        Product name on the dashboard and in page titles. Defaults to
        'iSOC Blueprint'.

    .PARAMETER Title
        Dashboard title. Defaults to '<workspace> - <ProductName>'.

    .PARAMETER WorkspaceName
        Workspace name to show. Defaults to the one the inventory recorded,
        else the folder name.

    .PARAMETER WhatsNewFeedUrl
        RSS feed for the dashboard's "What's new" panel. Defaults to
        Microsoft's Azure release-communications feed.

    .PARAMETER WhatsNewCount
        Feed items to keep. Defaults to 8.

    .PARAMETER SkipWhatsNew
        Do not fetch the feed; the panel is left out and the build is fully
        offline.

    .PARAMETER MaxTableRows
        Most rows per table on a SharePoint page. Defaults to 500; longer
        tables point to the dashboard, which has every row.

    .OUTPUTS
        [pscustomobject] WorkspaceName and Path (the bundle folder). Pipe it
        to Publish-iSOCBlueprintSite.

    .EXAMPLE
        New-iSOCBlueprintSite -Path ./SecurityDocs/law-sentinel-prod -SkipWhatsNew

        Builds ./SecurityDocs/law-sentinel-prod/sharepoint offline.

    .EXAMPLE
        ConvertTo-iSOCBlueprint -WorkspaceName law-sentinel-prod -Format Json |
            New-iSOCBlueprintSite |
            Publish-iSOCBlueprintSite -SiteUrl $site -Interactive -ClientId $app -Tenant contoso.onmicrosoft.com

        Renders the section model, builds the bundle and publishes it.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The engine script makes the ShouldProcess calls; -WhatIf and -Confirm are passed on to it.')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Source')]
        [string] $Path,

        [string] $OutputPath,

        [string] $ProductName,

        [string] $Title,

        [string] $WorkspaceName,

        [string] $WhatsNewFeedUrl,

        [int] $WhatsNewCount,

        [switch] $SkipWhatsNew,

        [int] $MaxTableRows
    )

    process {
        $source = Resolve-iSOCBlueprintPath -Path $Path
        $params = @{ Source = $source }
        if ($OutputPath) { $params.OutputRoot = Resolve-iSOCBlueprintPath -Path $OutputPath }
        Copy-iSOCBlueprintParameter -BoundParameters $PSBoundParameters -Into $params -Name 'ProductName', 'Title', 'WorkspaceName', 'WhatsNewFeedUrl', 'WhatsNewCount', 'MaxTableRows'
        if ($SkipWhatsNew) { $params.SkipWhatsNew = $true }

        $result = @(Invoke-iSOCBlueprintEngine -Script 'SharePoint/Build-SentinelDocsSite.ps1' -Parameters $params -BoundParameters $PSBoundParameters)
        $bundle = if ($params.ContainsKey('OutputRoot')) { $params.OutputRoot } else { Join-Path $source 'sharepoint' }
        if ($result.Count -gt 0 -and $result[-1] -is [string]) { $bundle = $result[-1] }

        [pscustomobject]@{
            PSTypeName    = 'iSOCBlueprint.SiteBundle'
            WorkspaceName = if ($WorkspaceName) { $WorkspaceName } else { Split-Path -Leaf $source }
            Path          = $bundle
        }
    }
}
