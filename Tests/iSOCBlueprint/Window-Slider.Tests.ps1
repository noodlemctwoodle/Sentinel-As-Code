#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the dashboard's window slider and the daily series
    behind it.

.DESCRIPTION
    The collector counts five series per day ago over the daily span (the
    lookback, at most 90), and playbook runs per day. The site build carries
    them in the dashboard model as model.daily, and the dashboard sums the
    last N days of them to rebuild every card that counts activity for the
    window the slider picks. These tests hold the captures to the daily
    window, the model to the shape the dashboard reads (and to the collected
    figures over the whole span), and the dashboard to its slider.

.NOTES
    File:         Tests/iSOCBlueprint/Window-Slider.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-14
    Version:      0.1.0
    Last Updated: 2026-10-14
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:engine = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine'
    $script:fixtureRaw = Join-Path $repoRoot 'Tests/iSOCBlueprint/Fixtures/sample/_raw'
    $script:collector = Get-Content (Join-Path $script:engine 'Export-SentinelInventory.ps1') -Raw
    $script:html = Get-Content (Join-Path $script:engine 'SharePoint/templates/sharepoint-dashboard.html') -Raw
    $script:buildScript = Join-Path $script:engine 'SharePoint/Build-SentinelDocsSite.ps1'
    $script:outDir = Join-Path ([System.IO.Path]::GetTempPath()) ("bp-slider-" + [guid]::NewGuid())

    # The fixture's _raw in a workspace folder, changed by $Edit, built.
    function Build-Fixture([string]$Name, [scriptblock]$Edit) {
        $ws = Join-Path $script:outDir $Name
        New-Item -ItemType Directory -Path (Join-Path $ws '_raw') -Force | Out-Null
        Copy-Item -Path (Join-Path $script:fixtureRaw '*.json') -Destination (Join-Path $ws '_raw')
        if ($Edit) { & $Edit (Join-Path $ws '_raw') }
        $bundle = & $script:buildScript -Source $ws -SkipWhatsNew 6> $null 3> $null
        return Get-Content (Join-Path $bundle 'model.json') -Raw | ConvertFrom-Json
    }
    # A day entry's value at index $I, summed over the whole series.
    function Get-SeriesSum($Series, [int]$I) {
        $s = 0.0
        foreach ($x in @($Series)) { foreach ($e in @($x.d)) { $s += [double]$e[$I] } }
        return $s
    }
    # A function from a script, by name, for a test to call.
    function Get-ScriptFunction([string]$Path, [string]$Name) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        return $ast.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $Name }, $true).Extent.Text
    }

    $script:model = Build-Fixture 'law-slider' $null
}

AfterAll {
    if ($script:outDir -and (Test-Path $script:outDir)) { Remove-Item $script:outDir -Recurse -Force }
}

Describe 'The collector counts the daily series' {
    It 'covers the lookback, at most 90 days, and records it in run-context.json' {
        $script:collector | Should -Match '\$script:DailyDays\s+= \[math\]::Min\(90, \$LookbackDays\)'
        $script:collector | Should -Match 'DailyDays\s+= \$script:DailyDays'
    }

    It 'declares daily with lookback and recent, falling back to the lookback capped at 90' {
        . ([scriptblock]::Create((Get-ScriptFunction (Join-Path $script:engine 'Export-SentinelInventory.ps1') 'Add-BpWindow')))
        $script:LookbackDays = 120; $script:RecentDays = 7; $script:DailyDays = 0
        Add-BpWindow 'Usage | take 1' | Should -Be "let lookback = 120d;`nlet recent = 7d;`nlet daily = 90d;`nUsage | take 1"
        $script:DailyDays = 14
        Add-BpWindow 'Usage | take 1' | Should -Be "let lookback = 120d;`nlet recent = 7d;`nlet daily = 14d;`nUsage | take 1"
    }

    It 'reads each of the five series over the daily window, per day ago' {
        foreach ($name in 'daily-table-usage', 'daily-alerts', 'daily-incidents', 'daily-rule-incidents', 'daily-health') {
            $m = [regex]::Match($script:collector, "Try-Capture '$name' \{(.*?)\n\}\n", 'Singleline')
            $m.Success | Should -BeTrue -Because $name
            $m.Groups[1].Value | Should -Match 'ago\(daily\)' -Because $name
            $m.Groups[1].Value | Should -Match 'DaysAgo = toint\(\(now\(\) - TimeGenerated\) / 1d\)' -Because $name
            $m.Groups[1].Value | Should -Not -Match 'ago\(lookback\)|ago\(\d+d\)' -Because $name
            $m.Groups[1].Value | Should -Match "Skip-Capture -FileName '$name\.json' -ErrorRecord \`$_" -Because "$name writes an empty file, and says why, when the query fails"
        }
    }

    It 'counts each alert once, on the day it was first seen' {
        $script:collector | Should -Match 'summarize arg_min\(TimeGenerated, AlertName, ProductName, AlertSeverity, ProviderName, AlertRuleId\) by SystemAlertId'
    }

    It 'counts playbook runs per day ago within the daily span' {
        $script:collector | Should -Match 'if \(\$ago -lt 0 -or \$ago -ge \$script:DailyDays\) \{ continue \}'
    }
}

Describe 'The build carries the daily series' {
    It 'records the span, the collection time and whether cost can be re-priced' {
        $d = $script:model.daily
        $d | Should -Not -BeNullOrEmpty
        $d.span | Should -Be 30
        # ConvertFrom-Json reads the ISO time as a date.
        ([datetime]$d.asOf).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm') | Should -Be '2026-05-06T08:00'
        $d.costed | Should -BeFalse -Because 'the fixture''s estimate predates per-table rows'
        $d.rulesQueryEnabled | Should -Be 2
    }

    It 'keys the enabled Scheduled and NRT rules by id and by name' {
        @($script:model.daily.queryRules) | Should -Contain 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        @($script:model.daily.queryRules) | Should -Contain 'name:Failed logons across multiple accounts'
        # The disabled NRT rule and the Fusion rule are not query rules.
        @($script:model.daily.queryRules) | Should -Not -Contain 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
        @($script:model.daily.queryRules) | Should -Not -Contain 'cccccccc-cccc-cccc-cccc-cccccccccccc'
    }

    It 'writes each day as [days ago, values] in the order the dashboard reads them' {
        $d = $script:model.daily
        foreach ($pair in @(@('tables', 2), @('alerts', 2), @('incidents', 6), @('rules', 7), @('health', 2), @('playbooks', 3))) {
            $series = @($d.($pair[0]))
            $series.Count | Should -BeGreaterThan 0 -Because $pair[0]
            foreach ($x in $series) {
                foreach ($e in @($x.d)) {
                    @($e).Count | Should -Be $pair[1] -Because "a $($pair[0]) day entry"
                    [int]$e[0] | Should -BeGreaterOrEqual 0
                    [int]$e[0] | Should -BeLessThan 30
                }
            }
        }
    }

    It 'describes each table, alert, incident group and rule as the cards need' {
        $t = @($script:model.daily.tables | Where-Object t -eq 'SigninLogs')[0]
        $t.f | Should -Be 'Entra ID / Identity'
        $t.plan | Should -Be 'Analytics'
        $t.pl | Should -Not -BeNullOrEmpty
        $t.cov | Should -BeTrue
        $a = @($script:model.daily.alerts | Where-Object n -eq 'Anonymous IP address')[0]
        $a.pf | Should -Be 'Entra ID / Identity'
        $a.pv | Should -Be 'IPC'
        $s = @($script:model.daily.alerts | Where-Object n -eq 'Suspicious sign-in from rare country')[0]
        $s.r | Should -Be 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        $s.pf | Should -Be ''
        @($script:model.daily.incidents | Where-Object st -eq 'Closed' | Where-Object by -eq 'AutomationRule').Count | Should -BeGreaterThan 0
        $r = @($script:model.daily.rules | Where-Object id -eq 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')[0]
        $r.src | Should -Be 'Analytics rule'
        $r.n | Should -Be 'Suspicious sign-in from rare country'
    }

    It 'adds up over the whole span to the collected figures' {
        $m = $script:model; $d = $m.daily
        [math]::Round((Get-SeriesSum $d.tables 1), 1) | Should -Be ([math]::Round([double]$m.estate.totalGb, 1))
        Get-SeriesSum $d.alerts 1 | Should -Be $m.estate.alerts
        Get-SeriesSum $d.incidents 1 | Should -Be $m.estate.incidents
        Get-SeriesSum @($d.incidents | Where-Object st -eq 'Closed') 1 | Should -Be $m.estate.incidentsClosed
        Get-SeriesSum $d.health 1 | Should -Be $m.health.totalEvents
        Get-SeriesSum @($d.playbooks | Where-Object { -not $_.unavailable }) 1 | Should -Be $m.playbookHealth.runs7d
        Get-SeriesSum @($d.playbooks | Where-Object { -not $_.unavailable }) 2 | Should -Be $m.playbookHealth.failed7d
        $closedRsv = Get-SeriesSum $d.incidents 4
        [math]::Round((Get-SeriesSum $d.incidents 5) / $closedRsv, 1) | Should -Be $m.alertLifecycle.mttrMinutes
    }

    It 'names the rule id behind each detection outcome' {
        @($script:model.detectionOutcomes | Where-Object source -eq 'Sentinel' | Where-Object { -not $_.key }).Count | Should -Be 0
        @($script:model.detectionOutcomes | Where-Object source -eq 'Defender XDR' | Where-Object { $_.key }).Count | Should -Be 0
    }

    It 'prices each table from the estimate when it carries every table' {
        $m = Build-Fixture 'law-costed' {
            param($raw)
            $p = Join-Path $raw 'cost-estimate.json'
            $c = Get-Content $p -Raw | ConvertFrom-Json
            $c | Add-Member -NotePropertyName AllTablesByCost -NotePropertyValue @(
                [pscustomobject]@{ Table = 'FirewallLogs_CL'; Plan = 'Analytics'; Gb30d = 2000; MonthlyCost = 4600 },
                [pscustomobject]@{ Table = 'SecurityEvent'; Plan = 'Analytics'; Gb30d = 500; MonthlyCost = 0 }) -Force
            $c | ConvertTo-Json -Depth 10 | Set-Content $p
        }
        $m.daily.costed | Should -BeTrue
        (@($m.daily.tables | Where-Object t -eq 'FirewallLogs_CL')[0]).u | Should -Be 2.3
        (@($m.daily.tables | Where-Object t -eq 'SecurityEvent')[0]).u | Should -Be 0
    }

    It 'carries no series for a run collected before them' {
        $m = Build-Fixture 'law-nodaily' {
            param($raw)
            $p = Join-Path $raw 'run-context.json'
            $rc = Get-Content $p -Raw | ConvertFrom-Json
            $rc.PSObject.Properties.Remove('DailyDays')
            $rc | ConvertTo-Json -Depth 10 | Set-Content $p
        }
        $m.daily | Should -BeNullOrEmpty
    }

    It 'counts a fired rule only while it is an enabled Scheduled or NRT rule' {
        $m = Build-Fixture 'law-disabled' {
            param($raw)
            $p = Join-Path $raw 'alert-rules.json'
            $rules = @(Get-Content $p -Raw | ConvertFrom-Json)
            (@($rules | Where-Object name -eq 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')[0]).properties.enabled = $false
            ConvertTo-Json -InputObject $rules -Depth 20 | Set-Content $p
        }
        $m.estate.rulesFired | Should -Be 1
        $m.estate.rings.alerts.max | Should -Be 1
        $m.estate.rings.alerts.pct | Should -Be 100
        $renderer = Get-Content (Join-Path $script:engine 'Convert-SentinelInventoryToMarkdown.ps1') -Raw
        $renderer | Should -Match 'RulesFired\s+= \$firedEnabled'
    }
}

Describe 'The dashboard re-scopes its cards to the slider''s window' {
    It 'replaces the snapshot picker with a slider and its dates' {
        $script:html | Should -Match '<label class="winwrap" id="winWrap" hidden'
        $script:html | Should -Match '<input type="range" id="winRange" min="1" max="30" step="1" value="30" aria-label="Days of activity shown"'
        $script:html | Should -Match '<span class="winlab" id="winLab" aria-live="polite"><b id="winDays"></b><small id="winDates"></small></span>'
        $script:html | Should -Not -Match 'snapPick|snapBanner|snapWrap'
        $script:html | Should -Match "rng\.max=String\(span\)"
        $script:html | Should -Match "days\.textContent='Last '\+WIN\.words\(n\); dates\.textContent=winDates\(n\);"
        $script:html | Should -Match "fmtDay\(a, new Date\(a\)\.getUTCFullYear\(\)!==new Date\(asOfT\)\.getUTCFullYear\(\)\)\+' to '\+fmtDay\(asOfT, true\)"
    }

    It 'rebuilds the model before anything renders, and only for a window other than the collected one' {
        $script:html | Should -Match 'function applyWindow\(M, D, N, R\)'
        $script:html | Should -Match 'if\(want>=1 && n!==WIN\.collected\)\{ WIN\.days=n; WIN\.recent=Math\.min\(WIN\.recent, n\); applyWindow\(M, DAILY, WIN\.days, WIN\.recent\); \}'
        $script:html.IndexOf('applyWindow(M, DAILY, WIN.days, WIN.recent)') | Should -BeLessThan $script:html.IndexOf('// ---- glance stat tiles ----')
        # Cost and the flow only when the estimate priced every table.
        $script:html | Should -Match 'if\(M\.cost && D\.costed\)\{'
        foreach ($field in 'M\.flow=\{nodes, links\}', 'M\.flowTables=', 'E\.sources=', 'E\.productAlerts=', 'M\.topRules=', 'M\.health=\{', 'M\.effectiveness=', 'M\.detectionOutcomes=', 'M\.detectionOpportunities=', 'M\.playbookHealth=\{', 'M\.incidentsByClassification=', 'L\.mttrMinutes=', 'M\.usageDaily=') {
            $script:html | Should -Match $field
        }
    }

    It 'keeps the window in window.name, checks it before use and reloads to apply it' {
        $script:html | Should -Match "const m=/\^sacDash:\(\.\*\)\$/\.exec\(window\.name\|\|''\)"
        $script:html | Should -Match "saveWindow\(\{days:n, back:1, view:curView, doc:curDoc\(\)\}\);"
        $script:html | Should -Match 'location\.reload\(\);'
        # The saved view must name a view on the page; it is never put in a selector.
        $script:html | Should -Match "if\(\[\.\.\.document\.querySelectorAll\('\[data-view\]'\)\]\.some\(el=>el\.dataset\.view===view\)\) activateTab\(view\);"
        $script:html | Should -Match "\(M\.sections\|\|\[\]\)\.some\(x=>x\.num===doc\)"
        $script:html | Should -Not -Match "querySelector\('\[data-view=""'\+SAVED"
    }

    It 'draws incidents a day across the window, a line per severity, falling back to the open count and chips' {
        $script:html | Should -Match 'const incTrend=\(function\(\)\{'
        # Every incident in the window by day, one line per severity in its colour.
        $script:html | Should -Match 'pts:smooth\? ma\(raw\) : raw'
        $script:html | Should -Match 'const smooth=n>21;'
        $script:html | Should -Match 'stroke="''\+l\.col\+''"'
        $script:html | Should -Match '<svg class="lc-sev" viewBox'
        $script:html | Should -Match "<small>a day</small>"
        $script:html | Should -Match "\+num\(open\)\+' still open</div>"
        $script:html | Should -Match '<div class="k">Open incidents</div><div class="v">''\+num\(open\)\+''</div>''\+chips'
    }

    It 'labels what keeps the collected window' {
        $script:html | Should -Match "Threat intelligence by source \('\+WIN\.cd\(\)\+'\)"
        $script:html | Should -Match "configuration and '\+WIN\.cw\(\)\+' of activity"
        $script:html | Should -Not -Match "Sentinel alerts in 30 days"
    }
}
