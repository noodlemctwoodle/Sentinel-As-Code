#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for recent hunting activity: the shared helper, rule
    SAC-HNT-01 and the maturity metric bookmarksRecent.

.DESCRIPTION
    A workspace can hold hundreds of bookmarks nobody has touched in a year.
    Get-HuntingActivity counts the hunts and bookmarks created or changed
    within the run's window, unknown when the evidence cannot cover it. Rule
    SAC-HNT-01 fires when hunts or bookmarks exist but none is recent, and
    criterion SAC-HNT-02 is met only by a recent bookmark.

.NOTES
    File:         Tests/iSOCBlueprint/Hunting-Activity.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.1.1
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:engine = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private'
    $script:resourcesDir = Join-Path $script:engine 'Resources'
    $script:fixtureRaw = Join-Path $repoRoot 'Tests/iSOCBlueprint/Fixtures/sample/_raw'
    . (Join-Path $script:engine 'Get-HuntingActivity.ps1')
    . (Join-Path $script:engine 'Get-SentinelGap.ps1')
    . (Join-Path $script:engine 'Get-SentinelMaturity.ps1')

    $script:asOf = [datetime]::new(2026, 10, 15, 12, 0, 0, [System.DateTimeKind]::Utc)
    function New-Bookmark([int]$DaysAgo) {
        $t = $script:asOf.AddDays(-$DaysAgo).ToString('yyyy-MM-ddTHH:mm:ssZ')
        [pscustomobject]@{ name = "bm-$DaysAgo"; properties = [pscustomobject]@{ displayName = "B $DaysAgo"; created = $t; updated = $t } }
    }
    function New-Hunt([Nullable[int]]$DaysAgo) {
        $h = [pscustomobject]@{ name = 'h'; properties = [pscustomobject]@{ displayName = 'H'; status = 'Active' } }
        if ($null -ne $DaysAgo) {
            $t = $script:asOf.AddDays(-$DaysAgo).ToString('yyyy-MM-ddTHH:mm:ssZ')
            $h | Add-Member -NotePropertyName systemData -NotePropertyValue ([pscustomobject]@{ createdAt = $t; lastModifiedAt = $t })
        }
        $h
    }
    $script:table90 = @([pscustomobject]@{ name = 'HuntingBookmark'; properties = [pscustomobject]@{ plan = 'Analytics'; retentionInDays = 90 } })

    # A copy of the fixture's _raw with the hunting files given, for the
    # gap and maturity engines.
    function New-HuntingRaw([hashtable]$Files, [int]$Lookback = 30) {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) "hunting-activity-$(New-Guid)"
        Copy-Item -Path $script:fixtureRaw -Destination $dir -Recurse
        foreach ($n in 'bookmarks.json', 'bookmarks-count.json', 'bookmarks-from-logs.json', 'hunts.json') { Remove-Item (Join-Path $dir $n) -ErrorAction SilentlyContinue }
        foreach ($k in $Files.Keys) { ConvertTo-Json -InputObject $Files[$k] -Depth 10 | Set-Content (Join-Path $dir $k) -Encoding UTF8 }
        $rcPath = Join-Path $dir 'run-context.json'
        $rc = Get-Content $rcPath -Raw | ConvertFrom-Json
        $rc | Add-Member -NotePropertyName LookbackDays -NotePropertyValue $Lookback -Force
        $rc | Add-Member -NotePropertyName StartedAtUtc -NotePropertyValue ($script:asOf.ToString('o')) -Force
        $rc | ConvertTo-Json -Depth 16 | Set-Content $rcPath -Encoding UTF8
        $dir
    }
    function Get-Hnt01([string]$Dir) {
        $out = [System.Collections.Generic.List[object]]::new()
        $findings = (Get-SentinelGap -InputRoot $Dir -ResourcesRoot $script:resourcesDir -RulesPath (Join-Path $script:resourcesDir 'best-practices.json') -GapChecksPath (Join-Path $script:engine 'GapChecks.ps1') -OutcomeCollector $out)
        # Get-SentinelGap returns its list as one object; the pipe unrolls it.
        [pscustomobject]@{ Outcome = ($out | Where-Object Id -eq 'SAC-HNT-01').Outcome; Finding = ($findings | Where-Object Id -eq 'SAC-HNT-01') }
    }
}

Describe 'Get-HuntingActivity' {
    It 'counts the bookmarks the API lists by their created or updated time' {
        $a = Get-HuntingActivity -Bookmarks @((New-Bookmark 5), (New-Bookmark 45), (New-Bookmark 200)) -Hunts @() -WindowDays 30 -AsOf $script:asOf
        $a.Bookmarks | Should -Be 3
        $a.BookmarksRecent | Should -Be 1
        $a.HuntsRecent | Should -Be 0
    }

    It 'leaves the recent count unknown when none is recent and some carry no date' {
        $undated = [pscustomobject]@{ name = 'x'; properties = [pscustomobject]@{ displayName = 'X' } }
        (Get-HuntingActivity -Bookmarks @($undated, (New-Bookmark 200)) -WindowDays 30 -AsOf $script:asOf).BookmarksRecent | Should -BeNullOrEmpty
    }

    It 'reads no change from an empty HuntingBookmark table that keeps the whole window' {
        $a = Get-HuntingActivity -BookmarksCount ([pscustomobject]@{ Count = 350 }) -BookmarksFromLogs @() -WorkspaceTables $script:table90 -WindowDays 90 -AsOf $script:asOf
        $a.Bookmarks | Should -Be 350
        $a.BookmarksRecent | Should -Be 0
    }

    It 'leaves it unknown when the table keeps fewer days than the window, or was not read' {
        (Get-HuntingActivity -BookmarksCount ([pscustomobject]@{ Count = 350 }) -BookmarksFromLogs @() -WorkspaceTables $script:table90 -WindowDays 180 -AsOf $script:asOf).BookmarksRecent | Should -BeNullOrEmpty
        (Get-HuntingActivity -BookmarksCount ([pscustomobject]@{ Count = 350 }) -WorkspaceTables $script:table90 -WindowDays 30 -AsOf $script:asOf).BookmarksRecent | Should -BeNullOrEmpty
    }

    It 'counts the table''s recent rows even when it keeps fewer days than the window' {
        (Get-HuntingActivity -BookmarksCount ([pscustomobject]@{ Count = 350 }) -BookmarksFromLogs @((New-Bookmark 10)) -WorkspaceTables $script:table90 -WindowDays 180 -AsOf $script:asOf).BookmarksRecent | Should -Be 1
    }

    It 'dates hunts by their systemData, and an undated one leaves it unknown' {
        (Get-HuntingActivity -Hunts @((New-Hunt 3), (New-Hunt 300)) -WindowDays 30 -AsOf $script:asOf).HuntsRecent | Should -Be 1
        (Get-HuntingActivity -Hunts @((New-Hunt $null)) -WindowDays 30 -AsOf $script:asOf).HuntsRecent | Should -BeNullOrEmpty
    }
}

Describe 'Rule SAC-HNT-01 judges recent hunting' {
    It 'fires when bookmarks exist but the HuntingBookmark table shows no change in the window' {
        $dir = New-HuntingRaw @{ 'bookmarks-count.json' = @{ Count = 350; Source = 'too large' }; 'bookmarks-from-logs.json' = @(); 'hunts.json' = @() } -Lookback 30
        try {
            $tables = @(Get-Content (Join-Path $dir 'workspace-tables.json') -Raw | ConvertFrom-Json) + $script:table90
            ConvertTo-Json -InputObject $tables -Depth 10 | Set-Content (Join-Path $dir 'workspace-tables.json') -Encoding UTF8
            $r = Get-Hnt01 $dir
            $r.Outcome | Should -Be 'Fired'
            $r.Finding.Evidence | Should -Be '350 bookmarks and 0 hunts exist, but none has been created or changed in the last 30 days, so there is no record of recent proactive hunting in Sentinel.'
        } finally { Remove-Item $dir -Recurse -Force }
    }

    It 'fires when every listed bookmark and hunt is older than the window' {
        $dir = New-HuntingRaw @{ 'bookmarks.json' = @((New-Bookmark 120)); 'hunts.json' = @((New-Hunt 200)) } -Lookback 30
        try { (Get-Hnt01 $dir).Finding.Evidence | Should -Match '^1 bookmark and 1 hunt exist, but none has been created or changed in the last 30 days' }
        finally { Remove-Item $dir -Recurse -Force }
    }

    It 'stays quiet when a bookmark or a hunt is recent' {
        $dir = New-HuntingRaw @{ 'bookmarks.json' = @((New-Bookmark 120)); 'hunts.json' = @((New-Hunt 2)) } -Lookback 30
        try { (Get-Hnt01 $dir).Outcome | Should -Be 'Passed' } finally { Remove-Item $dir -Recurse -Force }
        $dir = New-HuntingRaw @{ 'bookmarks.json' = @((New-Bookmark 4)); 'hunts.json' = @() } -Lookback 30
        try { (Get-Hnt01 $dir).Outcome | Should -Be 'Passed' } finally { Remove-Item $dir -Recurse -Force }
    }

    It 'stays quiet when recency is unknown' {
        $dir = New-HuntingRaw @{ 'bookmarks.json' = @((New-Bookmark 120)); 'hunts.json' = @((New-Hunt $null)) } -Lookback 30
        try { (Get-Hnt01 $dir).Outcome | Should -Be 'Passed' } finally { Remove-Item $dir -Recurse -Force }
    }

    It 'still says none exist when there are no hunts and no bookmarks' {
        $dir = New-HuntingRaw @{ 'bookmarks.json' = @(); 'hunts.json' = @() } -Lookback 30
        try { (Get-Hnt01 $dir).Finding.Evidence | Should -Be 'No hunts and no bookmarks exist in the workspace, so there is no record of proactive hunting in Sentinel.' }
        finally { Remove-Item $dir -Recurse -Force }
    }
}

Describe 'Maturity metric bookmarksRecent' {
    It 'counts the bookmarks created or changed in the window' {
        $dir = New-HuntingRaw @{ 'bookmarks.json' = @((New-Bookmark 5), (New-Bookmark 80)) } -Lookback 30
        try {
            $m = New-MaturityMetrics -InputRoot $dir -ResourcesRoot $script:resourcesDir
            $m.bookmarks | Should -Be 2
            $m.bookmarksRecent | Should -Be 1
        } finally { Remove-Item $dir -Recurse -Force }
    }

    It 'is unknown, not zero, when only the count was captured and the table was not read' {
        $dir = New-HuntingRaw @{ 'bookmarks-count.json' = @{ Count = 350 } } -Lookback 30
        try { (New-MaturityMetrics -InputRoot $dir -ResourcesRoot $script:resourcesDir).bookmarksRecent | Should -BeNullOrEmpty }
        finally { Remove-Item $dir -Recurse -Force }
    }

    It 'decides SAC-HNT-02 and names the window in its evidence' {
        $criteria = Get-Content (Join-Path $script:resourcesDir 'maturity-criteria.json') -Raw | ConvertFrom-Json
        $c = @($criteria.criteria) + @($criteria.areas | ForEach-Object { @($_.criteria) }) | Where-Object { $_ -and $_.id -eq 'SAC-HNT-02' } | Select-Object -First 1
        $c.source.path | Should -Be 'bookmarksRecent'
        $c.evidence.met | Should -Be '{metric} {bookmark|bookmarks} created or changed in {lookback}.'
        $c.evidence.gap | Should -Be 'No bookmark created or changed in {lookback}.'
    }
}
