#Requires -Version 7.6

<#
.SYNOPSIS
    New-iSOCBlueprint: produce a Blueprint in any format in one command.

.DESCRIPTION
    Chains the other commands: collect, render, then the Word report and
    the SharePoint site as asked. The steps live one per file under
    Modules/iSOCBlueprint/Private/Run and share a run context; this file
    holds the command's parameters and help and calls them in order.

.NOTES
    File:         Modules/iSOCBlueprint/Public/New-iSOCBlueprint.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.4.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

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
          4. Word: one .docx in the run's folder
             (Export-iSOCBlueprintWord).
          5. SharePoint: the site bundle (New-iSOCBlueprintSite) and, with
             -SiteUrl, the publish (Publish-iSOCBlueprintSite).

        Before anything runs it checks that the machine has what those
        steps need (Test-iSOCBlueprintPrerequisite) and stops with the list
        of what is missing, so a run does not fail half way.

        Output goes to a folder for the day, <OutputPath>/<WorkspaceName>/
        <yyyy-MM-dd>/ (UTC), by default under ./SecurityDocs in the current
        directory, so a run does not overwrite the last; a second run on
        the same day replaces that day. The SharePoint bundle of a day
        carries the earlier days' dashboards for its date picker.
        -NoDateFolder writes to <OutputPath>/<WorkspaceName>/ instead. The
        folders hold tenant configuration: keep them out of source control
        and share them as you would the workspace itself.

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

    .PARAMETER LookbackDays
        Days of activity every KQL capture reads, 1 to 730. Defaults to 30.
        Incidents, alerts, usage and cost, health, agents and table activity
        all cover this window, and the figures for the latest days within it
        the shorter of 7 days and this. The pages, the dashboard's cards and
        the findings name the window; the cost estimate projects a month
        from it.

    .PARAMETER Currency
        The currency the cost estimate prices in. Auto (the default) takes
        it from the workspace's region (UK regions GBP, EU regions EUR, and
        so on); or one of USD, AUD, BRL, CAD, CHF, CNY, DKK, EUR, GBP, INR,
        JPY, KRW, NOK, NZD, RUB, SEK or TWD. Billing currency follows the
        billing account, not the region, so set it when the guess is wrong.

    .PARAMETER SkipCollection
        Do not collect: render from the newest day's inventory under
        <OutputPath>/<WorkspaceName>/ (or <OutputPath>/<WorkspaceName>/_raw/
        with -NoDateFolder). Needs no Azure sign-in.

    .PARAMETER Format
        Json, Markdown, Word, SharePoint, or several. Defaults to Markdown
        and Json.

    .PARAMETER OutputPath
        Folder that holds one folder per workspace. Defaults to
        ./SecurityDocs under the current directory.

    .PARAMETER NoDateFolder
        Write to the workspace's folder itself rather than a folder for the
        day, so each run replaces the last. The pipelines use it.

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

    .PARAMETER HistoryDays
        Days of dashboard snapshots the site keeps for its date picker, and
        of earlier day folders the bundle carries in history/. Defaults to
        90; 0 keeps none.

    .OUTPUTS
        [pscustomobject] WorkspaceName, Path (the run's day folder, or the
        workspace folder with -NoDateFolder), Format,
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

        [Parameter(ParameterSetName = 'Collect')]
        [ValidateRange(1, 730)]
        [int] $LookbackDays = 30,

        [Parameter(ParameterSetName = 'Collect')]
        [ValidateSet('Auto', 'USD', 'AUD', 'BRL', 'CAD', 'CHF', 'CNY', 'DKK', 'EUR', 'GBP', 'INR', 'JPY', 'KRW', 'NOK', 'NZD', 'RUB', 'SEK', 'TWD')]
        [string] $Currency = 'Auto',

        [Parameter(Mandatory, ParameterSetName = 'Existing')]
        [switch] $SkipCollection,

        [ValidateSet('Json', 'Markdown', 'Word', 'SharePoint')]
        [string[]] $Format = @('Markdown', 'Json'),

        [string] $OutputPath,

        [switch] $NoDateFolder,

        [switch] $ChartImages,

        [string] $SiteUrl,

        [string] $AccessToken,

        [switch] $Interactive,

        [string] $ClientId,

        [string] $Tenant,

        [string] $AppPackagePath,

        [ValidateRange(0, 3650)]
        [int] $HistoryDays = 90
    )

    $run = @{
        BoundParameters = $PSBoundParameters; WorkspaceName = $WorkspaceName; ResourceGroup = $ResourceGroup
        TargetMaturityLevel = $TargetMaturityLevel; LookbackDays = $LookbackDays; Currency = $Currency
        IncludePreview = [bool]$IncludePreview; SkipCollection = [bool]$SkipCollection; Format = $Format
        OutputPath = $OutputPath; NoDateFolder = [bool]$NoDateFolder; ChartImages = [bool]$ChartImages
        SiteUrl = $SiteUrl; AccessToken = $AccessToken; Interactive = [bool]$Interactive; ClientId = $ClientId
        Tenant = $Tenant; AppPackagePath = $AppPackagePath; HistoryDays = $HistoryDays
    }

    Test-iSOCBlueprintRunRequest -Run $run
    Resolve-iSOCBlueprintRunFolder -Run $run
    if (-not $PSCmdlet.ShouldProcess($run.Workspace, "Create a Blueprint ($($run.Format -join ', '))")) { return }
    $run.Timer = [System.Diagnostics.Stopwatch]::StartNew()

    Invoke-iSOCBlueprintRunCollect -Run $run
    Invoke-iSOCBlueprintRunRender -Run $run
    Invoke-iSOCBlueprintRunWord -Run $run
    Invoke-iSOCBlueprintRunSite -Run $run
    Complete-iSOCBlueprintRun -Run $run
}
