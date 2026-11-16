#Requires -Version 7.6

<#
.SYNOPSIS
    Write the bundle: pages, tables, dashboard HTML, model and site descriptors.

.DESCRIPTION
    A step of the SharePoint site build. Steps run in order and pass their results
    to later ones through the build context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Steps/Write-SiteBundle.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-SiteBundle {
    <#
    .SYNOPSIS
        Write the bundle: pages, tables, dashboard HTML, model and site descriptors.

    .PARAMETER Context
        The build context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the build context.
    $buildWarnings = $Context.buildWarnings
    $chartCount = $Context.chartCount
    $findingList = $Context.findingList
    $generatedBuildUtc = $Context.generatedBuildUtc
    $generatedUtc = $Context.generatedUtc
    $HistoryDays = $Context.HistoryDays
    $maturityModel = $Context.maturityModel
    $MaxTableRows = $Context.MaxTableRows
    $model = $Context.model
    $OutputRoot = $Context.OutputRoot
    $p = $Context.p
    $pageDocs = $Context.pageDocs
    $ProductName = $Context.ProductName
    $progressRecord = $Context.progressRecord
    $runDay = $Context.runDay
    $siteSections = $Context.siteSections
    $Source = $Context.Source
    $tableFiles = $Context.tableFiles
    $Title = $Context.Title
    $workspace = $Context.workspace
    $WorkspaceName = $Context.WorkspaceName
    $siteRoot = $Context.siteRoot

    # ---------------------------------------------------------------------------
    # Findings for the SharePoint list
    # ---------------------------------------------------------------------------

    $gapChecksPath = Join-Path $script:RawRoot 'gap-checks.json'
    $checks = $null
    if (Test-Path -LiteralPath $gapChecksPath) {
        $checkRows = Read-SiteRawArray 'gap-checks.json'
        $checks = @($checkRows | Where-Object { $_ } | ForEach-Object { [ordered]@{ id = $_.Id; outcome = $_.Outcome } })
    }
    $findingsDoc = [ordered]@{
        generatedUtc      = $generatedUtc
        analysisAvailable = (Test-Path -LiteralPath (Join-Path $script:RawRoot 'gap-analysis.json'))
        items             = $findingList
        checks            = $checks
    }
    if ($null -eq $checks) {
        $buildWarnings.Add('No _raw/gap-checks.json in this snapshot (collected before per-check outcomes were recorded). Findings that stop firing will be resolved on absence.')
    }

    # ---------------------------------------------------------------------------
    # Write the bundle
    # ---------------------------------------------------------------------------

    $pagesDir = Join-Path $OutputRoot 'pages'
    $tablesDir = Join-Path $OutputRoot 'tables'

    if ($PSCmdlet.ShouldProcess($OutputRoot, 'Prepare bundle folder')) {
        New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
        # diagrams/ is what a bundle built before charts became data carried.
        foreach ($d in $pagesDir, $tablesDir, (Join-Path $OutputRoot 'diagrams')) {
            if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
        }
        New-Item -ItemType Directory -Path $pagesDir -Force | Out-Null
        if ($tableFiles.Count) { New-Item -ItemType Directory -Path $tablesDir -Force | Out-Null }
    }

    # Cut tables, whole. UTF-8 with a byte order mark, so Excel reads names
    # with accents and symbols as they are.
    $csvEncoding = [System.Text.UTF8Encoding]::new($true)
    foreach ($t in $tableFiles) {
        $csvPath = Join-Path $tablesDir ([string]$t.file)
        if ($PSCmdlet.ShouldProcess($csvPath, 'Write table CSV')) {
            [System.IO.File]::WriteAllText($csvPath, [string]$t.csv, $csvEncoding)
        }
    }

    # Dashboard. EscapeHtml encodes <, >, & and quotes as \uXXXX so no value in
    # the data (a rule name, finding evidence, a feed title) can close the
    # <script type="application/json"> block it is embedded in.
    $modelJson = $model | ConvertTo-Json -Depth 24 -Compress -EscapeHandling EscapeHtml
    $template = Get-SiteDashboardTemplate -Root (Join-Path $siteRoot 'templates/dashboard')
    # The chart web part's renderers, bundled by WebParts/Build-DashboardCharts.ps1,
    # draw the diagrams the dashboard does not draw itself.
    $chartBundlePath = Join-Path $siteRoot 'templates/dashboard-charts.js'
    $chartBundle = if (Test-Path -LiteralPath $chartBundlePath) { Get-Content -LiteralPath $chartBundlePath -Raw -Encoding utf8 } else { $buildWarnings.Add('templates/dashboard-charts.js is missing: the dashboard draws only pie and xy charts.'); '' }
    $html = $template.Replace('__TITLE__', (ConvertTo-HtmlText $Title)).Replace('/*__MODEL__*/null', $modelJson).Replace('/*__SAC_CHARTS__*/', $chartBundle)
    $indexPath = Join-Path $OutputRoot 'index.html'
    if ($PSCmdlet.ShouldProcess($indexPath, 'Write dashboard HTML')) {
        Set-Content -LiteralPath $indexPath -Value $html -Encoding utf8 -NoNewline
    }
    Write-SiteBundleJson -Path (Join-Path $OutputRoot 'model.json') -Data $model -What 'Write dashboard model'

    # Progress: this run's record, and the history the Progress tab reads beside
    # the dashboard. A run in a day's folder takes the records earlier days'
    # builds left in their bundles; the publisher keeps the history on the site,
    # so a pipeline run, which has no earlier folders, still adds to it.
    Write-SiteBundleJson -Path (Join-Path $OutputRoot 'progress.json') -Data $progressRecord -What 'Write progress record'
    $earlierProgress = @()
    if ($runDay -eq (Split-Path -Leaf $Source)) {
        foreach ($day in @(Get-ChildItem -LiteralPath (Split-Path -Parent $Source) -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and [string]::CompareOrdinal($_.Name, $runDay) -lt 0 })) {
            $p = Join-Path $day.FullName 'sharepoint/progress.json'
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
            try { $earlierProgress += , (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json -Depth 32) } catch { $buildWarnings.Add("Unreadable progress record in $($day.Name): $($_.Exception.Message)") }
        }
    }
    $progressHistory = Merge-SacProgressHistory -History $null -Records (@($earlierProgress) + , $progressRecord) -Days $(if ($HistoryDays -gt 0) { $HistoryDays } else { 90 })
    Write-SiteBundleJson -Path (Join-Path $OutputRoot 'progress-history.json') -Data $progressHistory -What 'Write progress history'

    foreach ($p in $pageDocs) {
        Write-SiteBundleJson -Path (Join-Path $pagesDir "$($p.name).json") -Data $p -What 'Write page'
    }

    Write-SiteBundleJson -Path (Join-Path $OutputRoot 'findings.json') -Data $findingsDoc -What 'Write findings'

    $site = [ordered]@{
        schemaVersion = 1
        product       = $ProductName
        title         = "$ProductName - $WorkspaceName"
        workspace     = [ordered]@{
            name           = $WorkspaceName
            id             = $workspace.id
            region         = $workspace.region
            subscriptionId = $workspace.subscriptionId
            resourceGroup  = $workspace.resourceGroup
        }
        generatedUtc  = $generatedUtc
        builtUtc      = $generatedBuildUtc
        blueprintVersion = $workspace.blueprintVer
        dashboard     = [ordered]@{ page = $script:DashboardPage; file = 'index.html' }
        findingsList  = [ordered]@{ title = $script:FindingsTitle; url = $script:FindingsListUrl }
        familyOrder   = @(Get-SectionFamilyOrder)
        # The run at a glance, for a snapshot list without reading the model.
        summary       = [ordered]@{
            findings = @($findingList).Count
            critical = @($findingList | Where-Object { $_.severity -eq 'Critical' }).Count
            score    = $(if ($maturityModel -and $maturityModel.overall) { $maturityModel.overall.score } else { $null })
        }
        sections      = $siteSections
        # The cut tables' CSV files under tables/, for the publisher to upload
        # (and to prune the ones a later bundle no longer has).
        tables        = @($tableFiles | ForEach-Object { [string]$_.file })
        # Always empty now that charts are data: the publisher recycles the
        # diagram images an earlier bundle uploaded.
        diagrams      = @()
        warnings      = $buildWarnings.ToArray()
    }
    Write-SiteBundleJson -Path (Join-Path $OutputRoot 'site.json') -Data $site -What 'Write site descriptor'

    # History: a run written to a day's folder (yyyy-MM-dd) beside earlier days
    # carries their dashboards, so the date picker works on this bundle and the
    # publisher can take those days to the site. Each earlier day's own bundle
    # is copied as it was built, so it runs that day's dashboard code. The list
    # keeps this day and up to -HistoryDays - 1 days before it.
    $sourceDay = Split-Path -Leaf $Source
    if ($HistoryDays -gt 0 -and $sourceDay -match '^\d{4}-\d{2}-\d{2}$') {
        $historyDir = Join-Path $OutputRoot 'history'
        $cutoff = [datetime]::ParseExact($sourceDay, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture).AddDays(1 - $HistoryDays).ToString('yyyy-MM-dd')
        $dayFolders = @(Get-ChildItem -LiteralPath (Split-Path -Parent $Source) -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and [string]::CompareOrdinal($_.Name, $cutoff) -ge 0 -and [string]::CompareOrdinal($_.Name, $sourceDay) -le 0 } |
            Sort-Object Name -Descending)
        $historyEntries = [System.Collections.Generic.List[object]]::new()
        if ($PSCmdlet.ShouldProcess($historyDir, 'Write dashboard history')) {
            if (Test-Path -LiteralPath $historyDir) { Remove-Item -LiteralPath $historyDir -Recurse -Force }
            New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
            foreach ($day in $dayFolders) {
                $isThis = $day.Name -eq $sourceDay
                $dayBundle = if ($isThis) { $OutputRoot } else { Join-Path $day.FullName 'sharepoint' }
                $dayHtml = Join-Path $dayBundle 'index.html'
                if (-not (Test-Path -LiteralPath $dayHtml -PathType Leaf)) { continue }
                Copy-Item -LiteralPath $dayHtml -Destination (Join-Path $historyDir "$($day.Name).html") -Force
                $daySite = if ($isThis) { $site } else {
                    $p = Join-Path $dayBundle 'site.json'
                    if (Test-Path -LiteralPath $p) { try { Get-Content -LiteralPath $p -Raw | ConvertFrom-Json } catch { $null } } else { $null }
                }
                $daySummary = if ($daySite -and $daySite.summary) { $daySite.summary } else { $null }
                $historyEntries.Add([ordered]@{
                    date      = $day.Name
                    file      = "$($day.Name).html"
                    generated = $(if ($daySite) { [string]$daySite.generatedUtc } else { '' })
                    findings  = $(if ($daySummary) { $daySummary.findings } else { $null })
                    critical  = $(if ($daySummary) { $daySummary.critical } else { $null })
                    score     = $(if ($daySummary) { $daySummary.score } else { $null })
                })
            }
            ([ordered]@{ entries = $historyEntries.ToArray() } | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $historyDir 'index.json') -Encoding utf8
        }
        Write-SiteLog "  History: $($historyEntries.Count) day(s) of dashboard copies kept (last $HistoryDays)" Info
    }

    # A table cut on a native page is a display limit, not missing data: the
    # dashboard's Sections tab carries every row. One note names the pages
    # rather than a warning a table.
    $cappedPattern = '^(?<page>\S+) : a table was capped at \d+ rows \((?<rows>\d+) not shown\)(; every row is in tables/\S+)?\.$'
    $cappedTables = @($buildWarnings | Where-Object { $_ -match $cappedPattern })
    foreach ($w in @($buildWarnings | Where-Object { $_ -notmatch $cappedPattern })) { Write-SiteLog "  ! $w" Warning }
    if ($cappedTables.Count) {
        $cappedPages = @($cappedTables | ForEach-Object { if ($_ -match $cappedPattern) { $Matches['page'] } } | Select-Object -Unique)
        Write-SiteLog "  Long tables: $($cappedTables.Count) table(s) longer than $MaxTableRows rows show their first $MaxTableRows on the native pages ($($cappedPages -join ', ')). Every row is in a CSV file under tables/ ($($tableFiles.Count)), linked from each page once published, and on the dashboard's Sections tab." Info
    }
    Write-SiteLog "  Progress: $(@($progressHistory.entries).Count) run(s) for the Progress tab ($(@($earlierProgress).Count) earlier, from this workspace's day folders)" Info
    Write-SiteLog "Bundle -> $OutputRoot ($($pageDocs.Count) pages, $chartCount charts, $($findingList.Count) findings)" Success

}
