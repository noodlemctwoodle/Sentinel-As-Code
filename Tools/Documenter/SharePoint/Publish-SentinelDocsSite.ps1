#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'PnP.PowerShell'; ModuleVersion = '3.4.1' }

<#
.SYNOPSIS
    Publish an iSOC Blueprint site bundle to its SharePoint Online site.

.DESCRIPTION
    Takes the bundle Build-SentinelDocsSite.ps1 wrote and makes the site
    match it. The whole site content is generated: one page per Documenter
    section, the top navigation, the findings list and the dashboard home
    page. A run is idempotent, and steps run in this order so a failure
    part-way leaves the site consistent:

      1. Structure   the 'Documenter Assets' library and the 'Sentinel
                     Findings' list (with its columns) exist
      2. App         the dashboard web part's .sppkg is deployed to the
                     site collection app catalog, only when its version
                     differs from what is deployed (-AppPackagePath)
      3. Assets      dashboard HTML, its model and the diagrams uploaded;
                     when the model carries a maturity assessment, one
                     entry is appended to the score history the dashboard
                     draws as a trend
      4. Pages       section pages created or rebuilt, skipping any whose
                     content hash matches the last publish; per-page
                     failures are collected rather than stopping the run
      5. Dashboard   the home page hosts the dashboard web part, pointed at
                     the uploaded HTML on every run
      6. Findings    list items added, updated, reopened, resolved or
                     retired (findings that stop firing keep their history)
      7. Navigation  the top navigation rebuilt from the pages that exist,
                     only when it differs from the plan
      8. Prune       pages and diagrams the bundle no longer has are sent
                     to the recycle bin, only when every page published

    The site itself, its site collection app catalog and this identity's
    access are created once by Initialize-SentinelDocsSite.ps1.

    Authentication: pipelines pass -AccessToken, a SharePoint token for an
    app that holds Sites.Selected (FullControl) on this one site, obtained
    through workload identity federation. Locally, use -Interactive with
    your own Entra app registration. An access token cannot be refreshed,
    so the run stops with a clear error if it is still going after
    -TokenLifetimeMinutes.

    -WhatIf connects and reads the site, prints the plan, and writes
    nothing.

.PARAMETER SiteUrl
    Absolute URL of the site, for example
    https://contoso.sharepoint.com/sites/isoc-law-sentinel-prod.

.PARAMETER Bundle
    The bundle folder Build-SentinelDocsSite.ps1 wrote (it contains
    site.json).

.PARAMETER AccessToken
    SharePoint access token (audience https://<tenant>.sharepoint.com).
    Used by the pipelines.

.PARAMETER Interactive
    Sign in interactively instead. Requires -ClientId and -Tenant.

.PARAMETER ClientId
    Entra app registration used for interactive sign-in.

.PARAMETER Tenant
    Tenant for interactive sign-in, for example contoso.onmicrosoft.com.

.PARAMETER AppPackagePath
    Path to sentinel-navigator.sppkg. When given, the package is deployed
    to the site collection app catalog if its version differs from the one
    already there. When omitted, the deployed package is used as-is.

.PARAMETER TokenLifetimeMinutes
    How long an -AccessToken is trusted for before the run stops. Defaults
    to 50 (tokens last about 60 to 90 minutes).

.OUTPUTS
    [string] The site URL.

.EXAMPLE
    ./Tools/Documenter/SharePoint/Publish-SentinelDocsSite.ps1 `
        -SiteUrl 'https://contoso.sharepoint.com/sites/isoc-law-sentinel-prod' `
        -Bundle ./SecurityDocs/law-sentinel-prod/sharepoint `
        -Interactive -ClientId '<app-id>' -Tenant 'contoso.onmicrosoft.com' -WhatIf

    Signs in as you, reads the site and prints what a publish would change.

.EXAMPLE
    ./Tools/Documenter/SharePoint/Publish-SentinelDocsSite.ps1 `
        -SiteUrl $env:SHAREPOINT_SITE_URL -Bundle $bundle `
        -AccessToken $token -AppPackagePath ./sentinel-navigator.sppkg

    What the pipelines run.

.NOTES
    File:         Tools/Documenter/SharePoint/Publish-SentinelDocsSite.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-07
    Version:      0.3.0
    Last Updated: 2026-10-09
    Permissions:  Sites.Selected (SharePoint, application) with FullControl on the target site
    Requires:     PowerShell 7.4+, PnP.PowerShell 3.4.1
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Token')]
param(
    [Parameter(Mandatory = $true)]
    [string]$SiteUrl,

    [Parameter(Mandatory = $true)]
    [string]$Bundle,

    [Parameter(Mandatory = $true, ParameterSetName = 'Token')]
    [string]$AccessToken,

    [Parameter(Mandatory = $true, ParameterSetName = 'Interactive')]
    [switch]$Interactive,

    [Parameter(Mandatory = $true, ParameterSetName = 'Interactive')]
    [string]$ClientId,

    [Parameter(Mandatory = $true, ParameterSetName = 'Interactive')]
    [string]$Tenant,

    [Parameter(Mandatory = $false)]
    [string]$AppPackagePath,

    [Parameter(Mandatory = $false)]
    [int]$TokenLifetimeMinutes = 50
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Private/Get-SectionFamily.ps1')
. (Join-Path $PSScriptRoot 'Private/Get-SacSyncPlan.ps1')
. (Join-Path $PSScriptRoot 'Private/SacSharePoint.ps1')

function Write-Step {
    param([Parameter(Mandatory)] [string] $Message)
    Write-Host "`n$Message" -ForegroundColor Cyan
}

$script:ConnectedAt = $null
function Assert-TokenFresh {
    param([Parameter(Mandatory)] [string] $Step)
    if ($PSCmdlet.ParameterSetName -ne 'Token' -or -not $script:ConnectedAt) { return }
    $age = (Get-Date) - $script:ConnectedAt
    if ($age.TotalMinutes -gt $TokenLifetimeMinutes) {
        throw "Stopping before '$Step': the access token has been in use for $([int]$age.TotalMinutes) minutes (limit $TokenLifetimeMinutes). Re-run the publish to continue with a fresh token."
    }
}

# ---------------------------------------------------------------------------
# Load the bundle
# ---------------------------------------------------------------------------

$Bundle = (Resolve-Path -LiteralPath $Bundle).Path
$sitePath = Join-Path $Bundle 'site.json'
if (-not (Test-Path -LiteralPath $sitePath)) { throw "No site.json in '$Bundle'. Run Build-SentinelDocsSite.ps1 first." }
$site = Get-Content -LiteralPath $sitePath -Raw | ConvertFrom-Json -Depth 32
$findingsDoc = Get-Content -LiteralPath (Join-Path $Bundle 'findings.json') -Raw | ConvertFrom-Json -Depth 32
$pageDocs = @{}
foreach ($f in Get-ChildItem -LiteralPath (Join-Path $Bundle 'pages') -Filter '*.json' -ErrorAction SilentlyContinue) {
    $doc = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json -Depth 32
    $pageDocs[[string]$doc.name] = $doc
}
if ($AppPackagePath -and -not (Test-Path -LiteralPath $AppPackagePath)) { throw "App package not found: $AppPackagePath" }

Write-Host "iSOC Blueprint publish" -ForegroundColor Cyan
Write-Host "  Site      : $SiteUrl"
Write-Host "  Bundle    : $Bundle ($($pageDocs.Count) pages, $(@($site.diagrams).Count) diagrams, $(@($findingsDoc.items).Count) findings)"
Write-Host "  Workspace : $($site.workspace.name)"
if ($WhatIfPreference) { Write-Host '  Mode      : WhatIf (read and plan only)' -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# Connect
# ---------------------------------------------------------------------------

if ($PSCmdlet.ParameterSetName -eq 'Token') {
    Connect-PnPOnline -Url $SiteUrl -AccessToken $AccessToken
}
else {
    Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Tenant $Tenant -Interactive
}
$script:ConnectedAt = Get-Date
$webRel = [string](Get-PnPWeb).ServerRelativeUrl
$state = Read-SacPublishState

# 1. Structure ---------------------------------------------------------------
Write-Step '1/8 Site structure'
Initialize-SacSiteStructure

# 2. App ---------------------------------------------------------------------
$appVersion = $state.appVersion
if ($AppPackagePath) {
    Write-Step '2/8 Dashboard web part package'
    Assert-TokenFresh 'app package'
    $appVersion = Publish-SacAppPackage -Path $AppPackagePath
}
else {
    Write-Step '2/8 Dashboard web part package (skipped: no -AppPackagePath)'
}

# 3. Assets ------------------------------------------------------------------
Write-Step '3/8 Dashboard and diagrams'
Assert-TokenFresh 'assets'
Send-SacFile -Path (Join-Path $Bundle 'index.html') -Folder 'dashboard'
Send-SacFile -Path (Join-Path $Bundle 'model.json') -Folder 'dashboard'
$existingDiagrams = Get-SacFolderFileNames -Folder 'diagrams'
$uploaded = 0
foreach ($file in @($site.diagrams)) {
    if (-not $file -or $existingDiagrams -contains $file) { continue }   # names are content hashes
    Send-SacFile -Path (Join-Path (Join-Path $Bundle 'diagrams') $file) -Folder 'diagrams'
    $uploaded++
}
Write-Host "  Diagrams uploaded: $uploaded (already present: $(@($site.diagrams).Count - $uploaded))"

# Maturity history: one entry per published bundle, keyed on the bundle's
# build time so a re-publish of the same bundle does not add a point.
$model = Get-Content -LiteralPath (Join-Path $Bundle 'model.json') -Raw | ConvertFrom-Json -Depth 32
if ($model.PSObject.Properties['maturity'] -and $model.maturity -and $model.maturity.PSObject.Properties['overall']) {
    $entry = @{
        publishedUtc   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        bundleBuiltUtc = [string]$site.builtUtc
        targetLevel    = [int]$model.maturity.targetLevel
        overall        = @{ score = $model.maturity.overall.score; level = $model.maturity.overall.level }
        areas          = @(@($model.maturity.areas) | ForEach-Object { @{ id = [string]$_.id; score = $_.score } })
    }
    $history = Add-SacMaturityHistoryEntry -History (Read-SacMaturityHistory) -Entry $entry
    Save-SacMaturityHistory -History $history
    Write-Host "  Maturity history: $(if ($WhatIfPreference) { 'would append' } else { 'appended' }) score $($entry.overall.score) for bundle $($entry.bundleBuiltUtc) ($(@($history.entries).Count) entries)"
}
else {
    Write-Host '  Maturity history: no assessment in this bundle, nothing appended.'
}

# 4. Pages -------------------------------------------------------------------
Write-Step '4/8 Section pages'
$existingPages = Get-SacGeneratedPageNames
$desired = @($site.sections | ForEach-Object { [pscustomobject]@{ Name = [string]$_.page; Hash = [string]$_.hash } })
$pagePlan = Get-PageSyncPlan -Desired $desired -ExistingNames $existingPages -PublishedHashes $state.pages
Write-Host "  Plan: $(($pagePlan | Group-Object Action | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', ')"

$pageErrors = [System.Collections.Generic.List[string]]::new()
$publishedHashes = @{}
foreach ($step in $pagePlan) {
    if ($step.Action -eq 'Delete') { continue }
    $hash = ($desired | Where-Object Name -eq $step.Name | Select-Object -First 1).Hash
    if ($step.Action -eq 'Skip') { $publishedHashes[$step.Name] = $hash; continue }
    Assert-TokenFresh "page $($step.Name)"
    try {
        Publish-SacSectionPage -PageDoc $pageDocs[$step.Name] -Create:($step.Action -eq 'Create') -WebServerRelativeUrl $webRel
        if (-not $WhatIfPreference) { $publishedHashes[$step.Name] = $hash }
        Write-Host "  $($step.Action): $($step.Name)"
    }
    catch {
        $pageErrors.Add("$($step.Name): $($_.Exception.Message)")
        Write-Host "  FAILED $($step.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 5. Dashboard ---------------------------------------------------------------
Write-Step '5/8 Dashboard home page'
Assert-TokenFresh 'dashboard'
Publish-SacDashboardPage -PageName ([string]$site.dashboard.page) -Title ([string]$site.title) `
    -FileRelativeUrl "$script:SacAssetsLibraryUrl/dashboard/$($site.dashboard.file)"

# 6. Findings ----------------------------------------------------------------
Write-Step '6/8 Findings list'
Assert-TokenFresh 'findings'
$checks = if ($null -ne $findingsDoc.checks) { @($findingsDoc.checks | ForEach-Object { [pscustomobject]@{ Id = $_.id; Outcome = $_.outcome } }) } else { $null }
$findingPlan = Get-FindingSyncPlan -Current @($findingsDoc.items) -Existing (Get-SacFindingItems) `
    -Checks $checks -AnalysisAvailable ([bool]$findingsDoc.analysisAvailable) -NowUtc (Get-Date).ToUniversalTime()
Write-Host "  Plan: $(if ($findingPlan.Count) { ($findingPlan | Group-Object Action | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', ' } else { 'no changes' })"
Invoke-SacFindingPlan -Plan $findingPlan

# 7. Navigation --------------------------------------------------------------
Write-Step '7/8 Navigation'
Assert-TokenFresh 'navigation'
# Get-SacGeneratedPageNames returns its array as one object; assign it
# directly rather than wrapping it in @(), which would nest it.
$pagesNow = Get-SacGeneratedPageNames
if ($WhatIfPreference) { $pagesNow = @($pagesNow) + @($pagePlan | Where-Object Action -eq 'Create' | ForEach-Object Name) }
$navPlan = Get-NavigationPlan -Sections @($site.sections) -ExistingPages $pagesNow -FamilyOrder @($site.familyOrder) `
    -DashboardPage ([string]$site.dashboard.page) -FindingsListUrl ([string]$site.findingsList.url)
$currentSignature = Get-NavigationSignature -Nodes (Get-SacNavigation -WebServerRelativeUrl $webRel)
if ($currentSignature -eq $navPlan.Signature) {
    Write-Host '  Navigation unchanged.'
}
else {
    Set-SacNavigation -Nodes $navPlan.Nodes -WebServerRelativeUrl $webRel
    Write-Host "  Navigation rebuilt: $($navPlan.Nodes.Count) top-level nodes."
}

# 8. Prune -------------------------------------------------------------------
Write-Step '8/8 Prune'
if ($pageErrors.Count -gt 0) {
    Write-Host '  Skipped: some pages failed, so nothing is removed this run.' -ForegroundColor Yellow
}
else {
    foreach ($step in ($pagePlan | Where-Object Action -eq 'Delete')) {
        Assert-TokenFresh "remove page $($step.Name)"
        if ($PSCmdlet.ShouldProcess("SitePages/$($step.Name).aspx", 'Send page to recycle bin')) {
            Remove-PnPPage -Identity $step.Name -Force -Recycle
            Write-Host "  Removed page: $($step.Name)"
        }
    }
    $stale = Get-AssetPrunePlan -DesiredFiles @($site.diagrams) -ExistingFiles (Get-SacFolderFileNames -Folder 'diagrams')
    foreach ($file in $stale) {
        if ($PSCmdlet.ShouldProcess("$script:SacAssetsLibraryUrl/diagrams/$file", 'Send diagram to recycle bin')) {
            Remove-PnPFile -SiteRelativeUrl "$script:SacAssetsLibraryUrl/diagrams/$file" -Force -Recycle
        }
    }
    Write-Host "  Pages removed: $(@($pagePlan | Where-Object Action -eq 'Delete').Count)   Diagrams removed: $($stale.Count)"
}

# State ------------------------------------------------------------------------
if (-not $WhatIfPreference) {
    $newState = @{
        pages        = $publishedHashes
        navSignature = $navPlan.Signature
        appVersion   = $appVersion
        publishedUtc = (Get-Date).ToUniversalTime().ToString('o')
        bundleBuiltUtc = [string]$site.builtUtc
    }
    Save-SacPublishState -State $newState
}

if ($pageErrors.Count -gt 0) {
    throw "Published with $($pageErrors.Count) page failure(s):`n  " + ($pageErrors -join "`n  ")
}

Write-Host "`nPublished: $SiteUrl" -ForegroundColor Green
return $SiteUrl
