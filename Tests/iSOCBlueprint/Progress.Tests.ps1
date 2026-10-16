#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for progress across runs: the record each build writes, the
    history the build and the publisher keep, and the dashboard's Progress
    tab.

.DESCRIPTION
    Each export is a snapshot. The site build writes a progress record for
    its run (the headline numbers and the lists a change is read from) and
    a history of them: from earlier day folders locally, and on the site,
    where the publisher adds each run's record. The dashboard's Progress tab
    compares the run it shows with a baseline from that history.

.NOTES
    File:         Tests/iSOCBlueprint/Progress.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.2.0
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $sp = Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint'
    . (Join-Path $sp 'Private/Get-SacProgress.ps1')
    $script:html = Get-Content (Join-Path $sp 'templates/sharepoint-dashboard.html') -Raw
    $script:publisher = Get-Content (Join-Path $sp 'Publish-SentinelDocsSite.ps1') -Raw
    $script:sacSharePoint = Get-Content (Join-Path $sp 'Private/SacSharePoint.ps1') -Raw

    # A model with just the parts the record reads.
    $script:model = [ordered]@{
        counts        = [ordered]@{ rulesEnabled = 3; rulesTotal = 4; connectors = 5 }
        cost          = [ordered]@{ monthlyTotal = 1234.5; currency = 'GBP' }
        findings      = [ordered]@{ total = 2; bySeverity = [ordered]@{ Critical = 1; Warning = 1 }
            items = @([ordered]@{ id = 'SAC-LOG-03'; severity = 'Warning'; title = 'Daily cap' }, [ordered]@{ id = 'SAC-DET-01'; severity = 'Critical'; title = 'No rules' }) }
        mitre         = @(1, 2, 3)
        mitreCovered  = 2
        estate        = [ordered]@{ totalGb = 100.0; uncoveredGb = 40.0; customDetections = [ordered]@{ captured = $false; enabled = 9 }
            tables = @([ordered]@{ table = 'SigninLogs'; covered = $true }, [ordered]@{ table = 'Syslog'; covered = $false }) }
        maturity      = [ordered]@{ overall = [ordered]@{ score = 2.5; level = 2 }
            areas = @([ordered]@{ id = 'DET'; score = 2.0 })
            criteria = @([ordered]@{ id = 'SAC-DET-01'; name = 'Rules'; status = 'Gap' }, [ordered]@{ id = 'SAC-LOG-01'; name = 'Logs'; status = 'Met' }, [ordered]@{ id = 'SAC-HNT-02'; name = 'Bookmarks'; status = 'Unknown' }) }
        attack        = [ordered]@{
            rules = @([ordered]@{ name = 'Rule A'; enabled = $true }, [ordered]@{ name = 'Rule B'; enabled = $false }, [ordered]@{ name = 'Rule A'; enabled = $true })
            cells = @([ordered]@{ technique = 'T1078'; rules = @(0) }, [ordered]@{ technique = 'T1110'; rules = @(1) }, [ordered]@{ technique = 'T1059'; rules = @(1, 2) }) }
        alertLifecycle = [ordered]@{ openBySeverity = [ordered]@{ High = 2; Medium = 3 }; mttrMinutes = 90.0 }
        usageDaily    = @([ordered]@{ billable = 10.0 }, [ordered]@{ billable = 20.0 })
        window        = [ordered]@{ days = 30 }
    }
    $script:record = New-SacProgressRecord -Model $script:model -Date '2026-10-15' -GeneratedUtc '2026-10-15 09:00 UTC'
    function New-Rec([string]$Date, [int]$Findings = 1) { [ordered]@{ schemaVersion = 1; date = $Date; metrics = [ordered]@{ findings = $Findings } } }
}

Describe 'A run''s progress record' {
    It 'carries the headline numbers' {
        $m = $script:record.metrics
        $m.maturityScore | Should -Be 2.5
        $m.findings | Should -Be 2
        $m.findingsCritical | Should -Be 1
        $m.rulesEnabled | Should -Be 3
        $m.tacticsCovered | Should -Be 2
        $m.tacticsTotal | Should -Be 3
        $m.monthlyCost | Should -Be 1234.5
        $m.openIncidents | Should -Be 5
        $m.dailyGb | Should -Be 15
        $m.uncoveredTables | Should -Be 1
        $script:record.currency | Should -Be 'GBP'
        $script:record.areas['DET'] | Should -Be 2.0
    }

    It 'leaves out what was not captured rather than reporting zero' {
        $script:record.metrics.customDetections | Should -BeNullOrEmpty
    }

    It 'counts a technique only when an enabled rule covers it, the first rule included' {
        @($script:record.sets.techniques) | Should -Be @('T1059', 'T1078')
        $script:record.metrics.techniquesCovered | Should -Be 2
    }

    It 'lists the enabled rules by name, once each, and the tables no detection reads' {
        @($script:record.sets.rules) | Should -Be @('Rule A')
        @($script:record.sets.tables) | Should -Be @('SigninLogs', 'Syslog')
        @($script:record.sets.uncovered) | Should -Be @('Syslog')
    }

    It 'codes each criterion Met, Gap or Unknown, with its name' {
        $c = @($script:record.sets.criteria)
        ($c | Where-Object id -eq 'SAC-DET-01').status | Should -Be 'G'
        ($c | Where-Object id -eq 'SAC-LOG-01').status | Should -Be 'M'
        ($c | Where-Object id -eq 'SAC-HNT-02').status | Should -Be 'U'
        ($c | Where-Object id -eq 'SAC-LOG-01').name | Should -Be 'Logs'
        $script:record.metrics.criteriaMet | Should -Be 1
    }

    It 'lists the findings with their severity and title' {
        $f = @($script:record.sets.findings)
        $f.Count | Should -Be 2
        ($f | Where-Object id -eq 'SAC-DET-01').severity | Should -Be 'Critical'
    }
}

Describe 'The progress history' {
    It 'keeps one record a day, the later replacing the earlier, oldest first' {
        $h = Merge-SacProgressHistory -History @{ entries = @((New-Rec '2026-10-14' 5), (New-Rec '2026-10-13' 7)) } -Records @((New-Rec '2026-10-14' 4), (New-Rec '2026-10-15' 3))
        @($h.entries | ForEach-Object date) | Should -Be @('2026-10-13', '2026-10-14', '2026-10-15')
        ($h.entries | Where-Object date -eq '2026-10-14').metrics.findings | Should -Be 4
    }

    It 'drops records older than the days kept before the newest' {
        $h = Merge-SacProgressHistory -History $null -Records @((New-Rec '2026-07-01'), (New-Rec '2026-09-20'), (New-Rec '2026-10-15')) -Days 30
        @($h.entries | ForEach-Object date) | Should -Be @('2026-09-20', '2026-10-15')
    }

    It 'keeps a run exactly the days kept before the newest, so the 90-day baseline has one' {
        $h = Merge-SacProgressHistory -History $null -Records @((New-Rec '2026-07-16'), (New-Rec '2026-07-17'), (New-Rec '2026-10-15')) -Days 90
        @($h.entries | ForEach-Object date) | Should -Be @('2026-07-17', '2026-10-15')
    }

    It 'reads a history saved as JSON, as the publisher does' {
        $json = Merge-SacProgressHistory -History $null -Records @((New-Rec '2026-10-14')) | ConvertTo-Json -Depth 8
        $h = Merge-SacProgressHistory -History ($json | ConvertFrom-Json) -Records @((New-Rec '2026-10-15'))
        @($h.entries).Count | Should -Be 2
    }
}

Describe 'The site build''s progress files' {
    BeforeAll {
        $fixtureRaw = Join-Path $script:repoRoot 'Tests/iSOCBlueprint/Fixtures/sample/_raw'
        $script:pgRoot = Join-Path ([System.IO.Path]::GetTempPath()) "progress-test-$(New-Guid)"
        $day = Join-Path $script:pgRoot 'law-sentinel-test/2026-10-15'
        $earlier = Join-Path $script:pgRoot 'law-sentinel-test/2026-10-08/sharepoint'
        New-Item -ItemType Directory -Path (Join-Path $day '_raw'), $earlier -Force | Out-Null
        Copy-Item -Path (Join-Path $fixtureRaw '*.json') -Destination (Join-Path $day '_raw')
        # An earlier day's build left its record in its bundle.
        New-Rec '2026-10-08' 9 | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $earlier 'progress.json')
        & (Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Convert-SentinelInventoryToMarkdown.ps1') -WorkspaceName 'law-sentinel-test' -InputRoot $day -OutputRoot $day -OutputFormat Json `
            -ResourcesRoot (Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Private/Resources') -InformationAction SilentlyContinue *> $null
        & (Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1') -Source $day -HistoryDays 30 6> $null | Out-Null
        $script:bundle = Join-Path $day 'sharepoint'
    }

    AfterAll {
        if ($script:pgRoot -and (Test-Path $script:pgRoot)) { Remove-Item $script:pgRoot -Recurse -Force }
    }

    It 'writes this run''s record, dated by its day folder' {
        $r = Get-Content (Join-Path $script:bundle 'progress.json') -Raw | ConvertFrom-Json
        $r.date | Should -Be '2026-10-15'
        $r.metrics.PSObject.Properties.Name | Should -Contain 'rulesEnabled'
    }

    It 'gathers the earlier days'' records into the history' {
        $h = Get-Content (Join-Path $script:bundle 'progress-history.json') -Raw | ConvertFrom-Json
        @($h.entries | ForEach-Object date) | Should -Be @('2026-10-08', '2026-10-15')
    }

    It 'carries this run''s record in the dashboard model' {
        $model = Get-Content (Join-Path $script:bundle 'model.json') -Raw | ConvertFrom-Json
        $model.progress.date | Should -Be '2026-10-15'
    }
}

Describe 'The publisher keeps the history on the site' {
    It 'merges the bundle''s records with the site''s and saves them beside the dashboard' {
        $script:publisher | Should -Match '\. \(Join-Path \$PSScriptRoot ''Private/Get-SacProgress\.ps1''\)'
        $script:publisher | Should -Match 'Merge-SacProgressHistory -History \(Read-SacProgressHistory\) -Records \$progressRecords'
        $script:publisher | Should -Match 'Save-SacProgressHistory -History \$progress'
        $script:sacSharePoint | Should -Match '\$script:SacProgressHistoryFile = ''progress-history\.json'''
        $script:sacSharePoint | Should -Match "foreach \(\`$folder in '_state', 'dashboard'\) \{\s*if \(\`$PSCmdlet\.ShouldProcess\(""\`$script:SacAssetsLibraryUrl/\`$folder/\`$script:SacProgressHistoryFile"""
    }
}

Describe 'The dashboard''s Progress tab' {
    It 'has its tab and its board, and names what it compares in the header' {
        $script:html | Should -Match '<div class="tab" data-tab="progress" role="tab">'
        # No bar of its own: the header's context line carries the sentence.
        $script:html | Should -Not -Match 'data-views="progress"|id="progressNote"'
        $script:html | Should -Match '<p class="hero-ctx" id="heroCtx" aria-live="polite" hidden></p>'
        $script:html.Contains('HERO_CTX.progress=()=>ctxHtml;') | Should -BeTrue
        $script:html.Contains("const setCtx=h=>{ ctxHtml=h; if(curView==='progress') paintHeroCtx(); };") | Should -BeTrue
        $script:html | Should -Match '<section data-view="progress" class="hidden">\s*<div id="progressBoard"></div>'
        # No picker of its own: the top bar's dates choose the runs.
        $script:html | Should -Not -Match 'id="progressPick"|id="progressRun"|id="progressAny"|id="progressDates"'
    }

    It 'compares the runs kept at the start and the end of the chosen dates' {
        $script:html.Contains("SNAP.read('progress-history.json')") | Should -BeTrue
        $script:html.Contains('const end=runs.filter(r=>dayT(r.date)<=WIN.endT).pop()||null;') | Should -BeTrue
        $script:html.Contains('return {end, base:before.filter(r=>dayT(r.date)<=WIN.startT).pop() || before.find(r=>dayT(r.date)>=WIN.startT) || null};') | Should -BeTrue
        # Without daily series, the snapshot's run against the previous one.
        $script:html.Contains('if(WIN.endT==null){ const i=runs.indexOf(latest); return {end:latest, base:i>0? runs[i-1] : null}; }') | Should -BeTrue
        # The trends cover the runs between the two; the kept days go to the calendar.
        $script:html.Contains("viewRuns=entries.filter(e=>(!base || e.date>=base.date) && e.date<=cur.date)") | Should -BeTrue
        $script:html.Contains("'Change from the run of <b>'+esc(long(base.date))+'</b> to the run of <b>'+esc(long(cur.date))+'</b>, '") | Should -BeTrue
    }

    It 'draws in the dashboard''s own parts: tiles, area bars, trend cards' {
        $script:html.Contains('<div class="tiles pgtiles">') | Should -BeTrue
        $script:html.Contains("<div class=""insights pgcards"">") | Should -BeTrue
        # Balanced rows, as the other boards (eight tiles are 4 + 4, not 7 + 1).
        $script:html.Contains("['.pgtiles',150],['.pgcards',380]") | Should -BeTrue
        $script:html.Contains("requestAnimationFrame(()=>{ if(typeof balanceGrids==='function') balanceGrids(); });") | Should -BeTrue
        # Each trend scaled to its own range, so a small move shows.
        $script:html.Contains("{theme:theme,unit:m[3]==='gb'?' GB':'',fit:true}") | Should -BeTrue
    }

    It 'marks the target level on the area bars, as the maturity view does, and the change as a segment' {
        $script:html.Contains("(target!=null? '<div class=""am"" style=""--t:'+(target/5*100)+'%""></div>' : '')") | Should -BeTrue
        $script:html.Contains("'<div class=""pgd '+(d>0?'up':'down')+'""") | Should -BeTrue
        $script:html.Contains('.abar .pgd.up{background:var(--green);') | Should -BeTrue
    }

    It 'colours a change by which way is better' {
        $script:html.Contains("const cls=!better? 'pg-same' : (d>0)===(better==='up')? 'pg-good' : 'pg-bad';") | Should -BeTrue
    }

    It 'lists every change by subject, the first entries then Show all' {
        $script:html.Contains("changeCard('Findings',[{label:'Resolved',tone:'good'") | Should -BeTrue
        $script:html.Contains("changeCard('Maturity criteria',[{label:'Now met',tone:'good'") | Should -BeTrue
        $script:html.Contains("changeCard('Analytics rules',[{label:'Enabled',tone:'good'") | Should -BeTrue
        $script:html.Contains("changeCard('ATT&CK coverage',[{label:'Now covered',tone:'good'") | Should -BeTrue
        $script:html.Contains("changeCard('Detection coverage of tables',[{label:'Now read by a detection',tone:'good'") | Should -BeTrue
        $script:html.Contains("changeCard('Ingestion',[{label:'Started ingesting',tone:''") | Should -BeTrue
        $script:html.Contains("(i>=SHOW?' data-mr hidden':'')") | Should -BeTrue
        $script:html.Contains("sbtn(all,'data-more data-all=""'+all+'"" data-less=""Show fewer""',{cls:'morebtn'})") | Should -BeTrue
        # A subject with no change has no card; one line names them.
        $script:html.Contains("'<p class=""note pgquiet"">No change in '+esc(andList(quiet))+'.</p>'") | Should -BeTrue
    }

    It 'opens a finding, criterion or rule from its change' {
        $script:html.Contains("if(l.classList.contains('pgfind') && typeof window.showFinding==='function') window.showFinding(l.dataset.id);") | Should -BeTrue
        $script:html.Contains("window.showCriterion(l.dataset.id)") | Should -BeTrue
        $script:html.Contains("window.openRuleReport(l.dataset.name)") | Should -BeTrue
    }

    It 'closes a fitted trend''s area at the foot of its scale' {
        $script:html.Contains("+','+y(lo).toFixed(1)+' L'+x(0).toFixed(1)+','+y(lo).toFixed(1)+' Z'") | Should -BeTrue
    }

    It 'keeps a tile''s value in line when its label wraps, and dates its window' {
        $script:html.Contains('.pgtiles .pill .k{line-height:1.35;min-height:2.7em}') | Should -BeTrue
        $script:html.Contains("' Activity and cost are each run\'s own collected window ('+WIN.words(+cur.windowDays||WIN.collected)+' here), whatever dates are chosen at the top.'") | Should -BeTrue
        $script:html.Contains('const short=d=>fmtDate(d,{year:false});') | Should -BeTrue
    }

    It 'says so when a snapshot predates progress tracking' {
        $script:html | Should -Match 'This snapshot was built before progress tracking'
    }
}
