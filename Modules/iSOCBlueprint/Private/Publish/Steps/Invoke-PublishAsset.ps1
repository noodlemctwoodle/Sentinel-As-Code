#Requires -Version 7.6

<#
.SYNOPSIS
    Stage 3: upload the dashboard, diagrams and table CSVs, and keep the maturity, progress and snapshot histories.

.DESCRIPTION
    A step of the SharePoint site publish. Steps run in order and pass their results
    to later ones through the publish context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Publish/Steps/Invoke-PublishAsset.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-PublishAsset {
    <#
    .SYNOPSIS
        Stage 3: upload the dashboard, diagrams and table CSVs, and keep the maturity, progress and snapshot histories.

    .PARAMETER Context
        The publish context: the values earlier steps produced and this one adds to.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Reports each asset upload and history step to the operator at the console as the publish runs.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the publish context.
    $Bundle = $Context.Bundle
    $HistoryDays = $Context.HistoryDays
    $site = $Context.site
    $siteTables = $Context.siteTables

    # 3. Assets ------------------------------------------------------------------
    Write-PublishStep '3/8 Dashboard, diagrams and tables'
    Assert-TokenFresh 'assets'
    Send-SacFile -Path (Join-Path $Bundle 'index.html') -Folder 'dashboard'
    Send-SacFile -Path (Join-Path $Bundle 'model.json') -Folder 'dashboard'
    $existingDiagrams = Get-SacFolderFileName -Folder 'diagrams'
    $uploaded = 0
    foreach ($file in @($site.diagrams)) {
        if (-not $file -or $existingDiagrams -contains $file) { continue }   # names are content hashes
        Send-SacFile -Path (Join-Path (Join-Path $Bundle 'diagrams') $file) -Folder 'diagrams'
        $uploaded++
    }
    Write-Host "  Diagrams uploaded: $uploaded (already present: $(@($site.diagrams).Count - $uploaded))"

    # Each table cut on its page, whole, as CSV: uploaded every run, since the
    # data behind it changes with every collection.
    foreach ($file in $siteTables) {
        $csvPath = Join-Path (Join-Path $Bundle 'tables') $file
        if (-not (Test-Path -LiteralPath $csvPath -PathType Leaf)) { throw "site.json lists tables/$file but the bundle does not have it. Rebuild the bundle." }
        Send-SacFile -Path $csvPath -Folder 'tables'
    }
    Write-Host "  Table CSVs $(if ($WhatIfPreference) { 'to upload' } else { 'uploaded' }): $($siteTables.Count)"

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
    } else {
        Write-Host '  Maturity history: no assessment in this bundle, nothing appended.'
    }

    # Progress history: each run's record (the headline numbers and the lists
    # the Progress tab compares), one a day. The bundle carries this run's record
    # and any earlier days' from local day folders; the site keeps the rest, so a
    # pipeline run, which starts with no earlier folders, still adds to it.
    $progressRecords = @()
    $bundleProgressHistory = Join-Path $Bundle 'progress-history.json'
    $bundleProgress = Join-Path $Bundle 'progress.json'
    if (Test-Path -LiteralPath $bundleProgressHistory -PathType Leaf) {
        $progressRecords = @((Get-Content -LiteralPath $bundleProgressHistory -Raw | ConvertFrom-Json -Depth 32).entries)
    } elseif (Test-Path -LiteralPath $bundleProgress -PathType Leaf) {
        $progressRecords = @(Get-Content -LiteralPath $bundleProgress -Raw | ConvertFrom-Json -Depth 32)
    }
    if ($progressRecords.Count) {
        $progress = Merge-SacProgressHistory -History (Read-SacProgressHistory) -Records $progressRecords -Days $(
            if ($HistoryDays -gt 0) { $HistoryDays } else { 90 }
        )
        Save-SacProgressHistory -History $progress
        Write-Host "  Progress history: $(if ($WhatIfPreference) { 'would keep' } else { 'kept' }) $(@($progress.entries).Count) run(s)"
    } else {
        Write-Host '  Progress history: no progress record in this bundle (built before progress tracking), nothing added.'
    }

    # Dashboard snapshots: the day's dashboard kept beside the live one, listed
    # in history/index.json for the dashboard's date picker. The day is the
    # inventory's, so a re-publish of the same run replaces that day's copy.
    if ($HistoryDays -gt 0) {
        $generated = [string]$site.generatedUtc
        $snapDate = if ($generated -match '^\d{4}-\d{2}-\d{2}') { $Matches[0] } else { (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd') }
        $snapFile = "$snapDate.html"
        $findingItems = @(
            if ($model.PSObject.Properties['findings'] -and $model.findings -and $model.findings.PSObject.Properties['items']) { @($model.findings.items) }
        )
        $snapEntry = @{
            date      = $snapDate
            file      = $snapFile
            generated = $generated
            findings  = $findingItems.Count
            critical  = @($findingItems | Where-Object { $_ -and [string]$_.severity -eq 'Critical' }).Count
            score     = $(
                if ($model.PSObject.Properties['maturity'] -and $model.maturity -and $model.maturity.PSObject.Properties['overall']) {
                    $model.maturity.overall.score
                } else { $null }
            )
        }
        # Days the bundle carries (a local run written to day folders) that the
        # site does not have yet go up first, so a first publish brings the
        # history with it.
        $siteIndex = Read-SacSnapshotIndex
        $onSite = @($siteIndex.entries | ForEach-Object { [string]$_.date })
        $cutoff = [datetime]::ParseExact($snapDate, 'yyyy-MM-dd',
            [System.Globalization.CultureInfo]::InvariantCulture).AddDays(1 - $HistoryDays).ToString('yyyy-MM-dd')
        $bundleIndexPath = Join-Path $Bundle 'history/index.json'
        $carried = @(
            if (Test-Path -LiteralPath $bundleIndexPath) { @((Get-Content -LiteralPath $bundleIndexPath -Raw | ConvertFrom-Json -AsHashtable).entries) }
        )
        $seeded = 0
        foreach ($e in $carried) {
            $d = [string]$e.date
            if (-not $d -or $d -eq $snapDate -or $onSite -contains $d -or [string]::CompareOrdinal($d, $cutoff) -lt 0) { continue }
            $file = Join-Path $Bundle "history/$([string]$e.file)"
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
            Send-SacSnapshot -Path $file -FileName ([string]$e.file)
            $siteIndex = @{ entries = (Add-SacSnapshotEntry -Index $siteIndex -Entry $e -Days $HistoryDays).entries }
            $seeded++
        }
        Send-SacSnapshot -Path (Join-Path $Bundle 'index.html') -FileName $snapFile
        $snapshots = Add-SacSnapshotEntry -Index $siteIndex -Entry $snapEntry -Days $HistoryDays
        foreach ($old in @($snapshots.removed)) { Remove-SacSnapshot -FileName $old }
        if ($seeded) { Write-Host "  Snapshots: $seeded earlier day(s) from the bundle $(if ($WhatIfPreference) { 'would be' } else { 'were' }) added" }
        Save-SacSnapshotIndex -Index $snapshots
        Write-Host "  Snapshots: $(if ($WhatIfPreference) { 'would keep' } else { 'kept' }) $snapFile; $(@($snapshots.entries).Count) day(s) in the last $HistoryDays, $(@($snapshots.removed).Count) dropped"
    } else {
        Write-Host '  Snapshots: off (-HistoryDays 0).'
    }
}
