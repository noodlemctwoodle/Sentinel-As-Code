#Requires -Version 7.2

<#
.SYNOPSIS
    New-iSOCBlueprint: produce a Blueprint in any format in one command.

.DESCRIPTION
    Chains the other commands: collect, render, then the Word report and
    the SharePoint site as asked.

.NOTES
    File:         Modules/iSOCBlueprint/Public/New-iSOCBlueprint.ps1
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

function New-iSOCBlueprint {
    <#
    .SYNOPSIS
        Produce a Blueprint of a workspace as JSON, Markdown, a Word report,
        a SharePoint site, or any mix of them, in one command.

    .DESCRIPTION
        Runs the steps the chosen formats need, in order:

          1. Collect the workspace (Export-iSOCBlueprintInventory), unless
             -SkipCollection re-uses an inventory already on disk.
          2. Render it (ConvertTo-iSOCBlueprint): the section model for
             Json and SharePoint, the Markdown report for Markdown and Word.
          3. With -ChartImages, replace the Markdown's Mermaid charts with
             PNG images (ConvertTo-iSOCBlueprintChartImage). The Word report
             carries charts only when this runs.
          4. Word: one .docx beside the workspace folder
             (Export-iSOCBlueprintWord).
          5. SharePoint: the site bundle (New-iSOCBlueprintSite) and, with
             -SiteUrl, the publish (Publish-iSOCBlueprintSite).

        Before anything runs it checks that the machine has what those
        steps need (Test-iSOCBlueprintPrerequisite) and stops with the list
        of what is missing, so a run does not fail half way.

        Output goes to <OutputPath>/<WorkspaceName>/, by default
        ./SecurityDocs/<WorkspaceName>/ under the current directory. The
        folder holds tenant configuration: keep it out of source control
        and share it as you would the workspace itself.

    .PARAMETER WorkspaceName
        Log Analytics workspace name.

    .PARAMETER ResourceGroup
        Resource group that holds the workspace.

    .PARAMETER SubscriptionId
        Subscription that holds the workspace. Defaults to the current Az
        context's subscription.

    .PARAMETER PlaybookResourceGroup
        Resource group that holds the playbooks, when it is not the
        workspace's own.

    .PARAMETER IncludePreview
        Use preview API versions where they add data.

    .PARAMETER TargetMaturityLevel
        Maturity level, 1 to 5, the workspace is aiming for. Defaults to 3.

    .PARAMETER SkipCollection
        Do not collect: render from the inventory already in
        <OutputPath>/<WorkspaceName>/_raw/. Needs no Azure sign-in.

    .PARAMETER Format
        Json, Markdown, Word, SharePoint, or several. Defaults to Markdown
        and Json.

    .PARAMETER OutputPath
        Folder that holds one folder per workspace. Defaults to
        ./SecurityDocs under the current directory.

    .PARAMETER ChartImages
        Replace the Mermaid charts in the Markdown with PNG images (needs
        mmdc). Without it the Word report has no charts; Markdown viewers
        that draw Mermaid, such as GitHub, do not need it.

    .PARAMETER SiteUrl
        Publish the SharePoint format to this site. Without it the site
        bundle is built locally and not published. Needs -AccessToken, or
        -Interactive with -ClientId and -Tenant.

    .PARAMETER AccessToken
        SharePoint access token for -SiteUrl.

    .PARAMETER Interactive
        Sign in to SharePoint interactively for -SiteUrl.

    .PARAMETER ClientId
        Entra app registration for interactive sign-in.

    .PARAMETER Tenant
        Tenant for interactive sign-in, for example contoso.onmicrosoft.com.

    .PARAMETER AppPackagePath
        Path to isoc-blueprint.sppkg, deployed to the site when its version
        differs from the one there.

    .OUTPUTS
        [pscustomobject] WorkspaceName, Path (the workspace folder), Format,
        and what was produced: SectionsPath, MarkdownPath, WordDocument,
        SiteBundle and SiteUrl (each $null when not produced).

    .EXAMPLE
        New-iSOCBlueprint -ResourceGroup rg-sentinel -WorkspaceName law-sentinel-prod -Format Json

        Collects the workspace and writes only the section model.

    .EXAMPLE
        New-iSOCBlueprint -ResourceGroup rg-sentinel -WorkspaceName law-sentinel-prod -Format Word -ChartImages

        Collects, renders, draws the charts and writes
        ./SecurityDocs/law-sentinel-prod.docx.

    .EXAMPLE
        New-iSOCBlueprint -WorkspaceName law-sentinel-prod -SkipCollection -Format SharePoint `
            -SiteUrl https://contoso.sharepoint.com/sites/isoc-prod `
            -Interactive -ClientId '<app-id>' -Tenant contoso.onmicrosoft.com

        Builds the site from an existing inventory and publishes it.

    .EXAMPLE
        New-iSOCBlueprint -ResourceGroup rg-sentinel -WorkspaceName law-sentinel-prod -Format Json, Markdown, Word, SharePoint -ChartImages

        Everything, with the site bundle built locally rather than
        published.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Collect')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $WorkspaceName,

        [Parameter(Mandatory, ParameterSetName = 'Collect')]
        [string] $ResourceGroup,

        [Parameter(ParameterSetName = 'Collect')]
        [string] $SubscriptionId,

        [Parameter(ParameterSetName = 'Collect')]
        [string] $PlaybookResourceGroup,

        [Parameter(ParameterSetName = 'Collect')]
        [switch] $IncludePreview,

        [Parameter(ParameterSetName = 'Collect')]
        [ValidateRange(1, 5)]
        [int] $TargetMaturityLevel = 3,

        [Parameter(Mandatory, ParameterSetName = 'Existing')]
        [switch] $SkipCollection,

        [ValidateSet('Json', 'Markdown', 'Word', 'SharePoint')]
        [string[]] $Format = @('Markdown', 'Json'),

        [string] $OutputPath,

        [switch] $ChartImages,

        [string] $SiteUrl,

        [string] $AccessToken,

        [switch] $Interactive,

        [string] $ClientId,

        [string] $Tenant,

        [string] $AppPackagePath
    )

    $Format = @($Format | Select-Object -Unique)
    $wantMarkdown = ($Format -contains 'Markdown') -or ($Format -contains 'Word')
    $wantJson = ($Format -contains 'Json') -or ($Format -contains 'SharePoint')

    if ($SiteUrl) {
        if ($Format -notcontains 'SharePoint') { throw '-SiteUrl publishes the SharePoint format; add SharePoint to -Format.' }
        if (-not $AccessToken -and -not ($Interactive -and $ClientId -and $Tenant)) {
            throw '-SiteUrl needs -AccessToken, or -Interactive with -ClientId and -Tenant.'
        }
    }
    if ($ChartImages -and -not $wantMarkdown) { throw '-ChartImages draws the Markdown charts; add Markdown or Word to -Format.' }

    $steps = [System.Collections.Generic.List[string]]::new()
    if (-not $SkipCollection) { $steps.Add('Collect') }
    $steps.Add('Render')
    if ($ChartImages) { $steps.Add('ChartImage') }
    if ($Format -contains 'Word') { $steps.Add('Word') }
    if ($Format -contains 'SharePoint') { $steps.Add('Site') }
    if ($SiteUrl) { $steps.Add('Publish') }

    $missing = @(Test-iSOCBlueprintPrerequisite -Step $steps | Where-Object { $_.Required -and -not $_.Found })
    if ($missing.Count -gt 0) {
        $lines = $missing | ForEach-Object { "  - $($_.Name) ($($_.Step -join ', ')): $($_.Detail)" }
        throw "This run needs:`n$($lines -join "`n")"
    }

    $root = Resolve-iSOCBlueprintPath -Path $OutputPath -Default 'SecurityDocs'
    $workspace = Join-Path $root $WorkspaceName
    if (-not $PSCmdlet.ShouldProcess($workspace, "Create a Blueprint ($($Format -join ', '))")) { return }

    if (-not $SkipCollection) {
        $collect = @{ ResourceGroup = $ResourceGroup; WorkspaceName = $WorkspaceName; OutputPath = $root; TargetMaturityLevel = $TargetMaturityLevel }
        Copy-iSOCBlueprintParameter -BoundParameters $PSBoundParameters -Into $collect -Name 'SubscriptionId', 'PlaybookResourceGroup'
        if ($IncludePreview) { $collect.IncludePreview = $true }
        $null = Export-iSOCBlueprintInventory @collect
    }
    elseif (-not (Test-Path -LiteralPath (Join-Path $workspace '_raw') -PathType Container)) {
        throw "-SkipCollection needs an inventory at $(Join-Path $workspace '_raw')."
    }

    $render = @()
    if ($wantMarkdown) { $render += 'Markdown' }
    if ($wantJson) { $render += 'Json' }
    $null = ConvertTo-iSOCBlueprint -WorkspaceName $WorkspaceName -Path $workspace -Format $render

    if ($ChartImages) { $null = ConvertTo-iSOCBlueprintChartImage -Path $root }
    elseif ($Format -contains 'Word') {
        Write-Warning 'The Word report will have no charts: pandoc drops Mermaid charts. Add -ChartImages to draw them as images.'
    }

    $document = $null
    if ($Format -contains 'Word') {
        $document = Export-iSOCBlueprintWord -Path $workspace -OutputPath (Join-Path $root "$WorkspaceName.docx") -Title "$WorkspaceName - iSOC Blueprint"
    }

    $bundle = $null
    $published = $null
    if ($Format -contains 'SharePoint') {
        $bundle = (New-iSOCBlueprintSite -Path $workspace).Path
        if ($SiteUrl) {
            $publish = @{ SiteUrl = $SiteUrl; Path = $bundle }
            if ($AccessToken) { $publish.AccessToken = $AccessToken }
            else {
                $publish.Interactive = $true
                $publish.ClientId = $ClientId
                $publish.Tenant = $Tenant
            }
            if ($AppPackagePath) { $publish.AppPackagePath = $AppPackagePath }
            $published = Publish-iSOCBlueprintSite @publish
        }
    }

    [pscustomobject]@{
        PSTypeName    = 'iSOCBlueprint.Blueprint'
        WorkspaceName = $WorkspaceName
        Path          = $workspace
        Format        = $Format
        SectionsPath  = if ($wantJson) { Join-Path $workspace 'sections' } else { $null }
        MarkdownPath  = if ($wantMarkdown) { $workspace } else { $null }
        WordDocument  = $document
        SiteBundle    = $bundle
        SiteUrl       = $published
    }
}
