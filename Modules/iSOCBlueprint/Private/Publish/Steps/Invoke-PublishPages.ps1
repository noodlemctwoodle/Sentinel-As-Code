#Requires -Version 7.6

<#
.SYNOPSIS
    Stage 4: plan the section pages against the site and create or update them.

.DESCRIPTION
    A step of the SharePoint site publish. Steps run in order and pass their results
    to later ones through the publish context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Publish/Steps/Invoke-PublishPages.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-PublishPages {
    <#
    .SYNOPSIS
        Stage 4: plan the section pages against the site and create or update them.

    .PARAMETER Context
        The publish context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the publish context.
    $AppPackagePath = $Context.AppPackagePath
    $doc = $Context.doc
    $pageDocs = $Context.pageDocs
    $site = $Context.site
    $state = $Context.state
    $webRel = $Context.webRel

    # 4. Pages -------------------------------------------------------------------
    Write-PublishStep '4/8 Section pages'
    $existingPages = Get-SacGeneratedPageNames
    $desired = @($site.sections | ForEach-Object { [pscustomobject]@{ Name = [string]$_.page; Hash = [string]$_.hash } })
    $pagePlan = Get-PageSyncPlan -Desired $desired -ExistingNames $existingPages -PublishedHashes $state.pages
    Write-Host "  Plan: $(($pagePlan | Group-Object Action | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', ')"

    $pageErrors = [System.Collections.Generic.List[string]]::new()
    $publishedHashes = @{}
    # Charts are drawn by the chart web part, which a package deployed a moment
    # ago in step 2 may not have registered yet. A page built without it holds
    # its charts as tables and is left unrecorded, so the next run rebuilds it.
    $needsCharts = @($pagePlan | Where-Object { $_.Action -in 'Create', 'Update' } | ForEach-Object {
            $doc = $pageDocs[$_.Name]; if ($doc) { @($doc.segments | Where-Object type -eq 'chart') }
        }).Count -gt 0
    $chartReady = $false
    if ($needsCharts -and -not $WhatIfPreference) {
        # The component list is read through a page that already exists: the
        # first page this run rebuilds, or the dashboard page.
        $probe = @($pagePlan | Where-Object { $_.Action -in 'Update', 'Skip' } | ForEach-Object { $_.Name })[0]
        if (-not $probe -and (Get-PnPPage -Identity ([string]$site.dashboard.page) -ErrorAction SilentlyContinue)) { $probe = [string]$site.dashboard.page }
        if ($probe) {
            # Wait for it only when step 2 deployed a package this run; otherwise
            # it is either there already or not coming, so look once.
            $chartReady = Wait-SacPageComponent -ComponentId $script:SacChartWebPartComponentId -PageName $probe -WaitSeconds $(
                if ($AppPackagePath) { 300 } else { 0 }
            )
            if (-not $chartReady) {
                $sibling = try { Test-SacPageComponent -ComponentId $script:SacWebPartComponentId -PageName $probe } catch { $false }
                $which = if ($sibling) {
                    'the dashboard web part from the same package is listed, the chart web part is not'
                } else { 'neither web part from the package is listed' }
                Write-Host "  Chart web part not on the site ($which); charts go in as tables and those pages are rebuilt next run." -ForegroundColor Yellow
            }
        }
        else {
            # A first publish: no page exists yet to read the list through, so
            # each new page looks the web part up itself as it is built.
            $chartReady = $true
        }
    }
    foreach ($step in $pagePlan) {
        if ($step.Action -eq 'Delete') { continue }
        $hash = ($desired | Where-Object Name -eq $step.Name | Select-Object -First 1).Hash
        if ($step.Action -eq 'Skip') { $publishedHashes[$step.Name] = $hash; continue }
        Assert-TokenFresh "page $($step.Name)"
        try {
            $native = Publish-SacSectionPage -PageDoc $pageDocs[$step.Name] -Create:($step.Action -eq
                'Create') -WebServerRelativeUrl $webRel -ChartComponentAvailable:$chartReady
            if (-not $WhatIfPreference -and $native) { $publishedHashes[$step.Name] = $hash }
            Write-Host "  $($step.Action): $($step.Name)$(if (-not $native) { ' (charts as tables)' })"
        }
        catch {
            $pageErrors.Add("$($step.Name): $($_.Exception.Message)")
            Write-Host "  FAILED $($step.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Left in the publish context for later steps.
    $Context.pageErrors = $pageErrors
    $Context.pagePlan = $pagePlan
    $Context.publishedHashes = $publishedHashes
}
