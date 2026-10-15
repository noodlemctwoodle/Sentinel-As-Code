#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the synthetic demo workspace the dashboard and report
    are developed and shown against.

.DESCRIPTION
    Tools/New-BlueprintDemoWorkspace.ps1 writes the _raw folder the
    collector would write for a large fictitious workspace, from this
    repository's content, and can build the report and the dashboard from
    it. These tests run it once with a fixed date and seed and hold it to
    what a demo must be: every capture present, the requested volume, the
    repository's content deployed, a commitment tier, the daily series
    agreeing with the captures, the same data for the same seed, nothing carried over from
    the test fixture's names, and a dashboard with its slider data and
    maturity trend.

.NOTES
    File:         Tests/iSOCBlueprint/Demo-Workspace.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-14
    Version:      0.1.1
    Last Updated: 2026-10-14
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:repoRoot = $repoRoot
    $script:tool = Join-Path $repoRoot 'Tools/New-BlueprintDemoWorkspace.ps1'
    $script:content = Join-Path $repoRoot 'Content'
    $script:outDir = Join-Path ([System.IO.Path]::GetTempPath()) ("bp-demo-" + [guid]::NewGuid())
    $script:asOf = [datetime]::SpecifyKind([datetime]'2026-10-14T09:00:00', 'Utc')
    $script:days = 30
    $script:result = & $script:tool -OutputPath (Join-Path $script:outDir 'law-contoso-sentinel') -DailyGb 500 -LookbackDays $script:days -AsOf $script:asOf -Seed 7 -Build 6> $null 3> $null
    $script:raw = $script:result.Raw
    function Read-Demo([string]$Name) { Get-Content -LiteralPath (Join-Path $script:raw $Name) -Raw | ConvertFrom-Json -Depth 64 }
}

AfterAll {
    if ($script:outDir -and (Test-Path $script:outDir)) { Remove-Item $script:outDir -Recurse -Force }
}

Describe 'The demo workspace generator' {
    It 'writes every capture the collector writes' {
        $collector = Get-Content (Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Export-SentinelInventory.ps1') -Raw
        # Three are written only in a case the demo does not have: a
        # dedicated cluster, and a bookmark list too large to fetch (its count,
        # and the list read from the HuntingBookmark table instead).
        $expected = @([regex]::Matches($collector, "Save-Json -FileName '([^']+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique |
                Where-Object { $_ -notin @('dedicated-cluster.json', 'bookmarks-count.json', 'bookmarks-from-logs.json') })
        $expected.Count | Should -BeGreaterThan 90
        foreach ($f in $expected) { Test-Path (Join-Path $script:raw $f) | Should -BeTrue -Because $f }
    }

    It 'puts its Microsoft Sentinel solution on simplified pricing' {
        $sol = @(Read-Demo 'solutions-installed.json') | Where-Object { $_.plan.product -eq 'OMSGallery/SecurityInsights' }
        $sol.properties.sku.name | Should -Be 'Unified'
        (Read-Demo 'cost-estimate.json').BilledPricingModel | Should -Be 'Simplified'
    }

    It 'ingests the requested GB a day over the last 30 days' {
        $usage = @(Read-Demo 'workspace-usage-daily.json')
        $last30 = @($usage | Select-Object -Last 30)
        $avg = (@($last30 | ForEach-Object { [double]$_.BillableGB + [double]$_.FreeGB }) | Measure-Object -Average).Average
        $avg | Should -BeGreaterThan 495
        $avg | Should -BeLessThan 505
        $script:result.Summary.AverageGbPerDay | Should -Be 500
    }

    It 'puts the workspace on the commitment tier nearest its Analytics ingest, and prices by it' {
        $ws = Read-Demo 'workspace.json'
        $ws.properties.sku.name | Should -Be 'CapacityReservation'
        $rungs = @((Get-Content (Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Private/Resources/commitment-tiers.json') -Raw | ConvertFrom-Json).rungsGbPerDay)
        $rungs | Should -Contain ([int]$ws.properties.sku.capacityReservationLevel)
        $script:result.Summary.CommitmentTierGb | Should -Be ([int]$ws.properties.sku.capacityReservationLevel)
        @((Read-Demo 'retail-prices.json').Prices.meterName) | Should -Contain 'Analytics Logs Data Ingestion'
        @(Read-Demo 'gap-analysis.json' | Where-Object Id -eq 'SAC-LOG-10').Count | Should -Be 0
        # Priced at its tier, with the grants reported, and the page says so.
        $cost = Read-Demo 'cost-estimate.json'
        $cost.PricingModel | Should -Be 'Simplified'
        $cost.CommitmentTier.Level | Should -Be ([int]$ws.properties.sku.capacityReservationLevel)
        @($cost.BenefitEligible).Count | Should -Be 2
        $page = Get-Content (Join-Path $script:result.Path '84-cost-estimate.md') -Raw
        $page | Should -Match 'GB a day commitment tier\*\*'
        $page | Should -Match '## Data grants that may reduce this'
        $page | Should -Match '4\. Commitment tier: a workspace on a tier pays its price a day'
        $page | Should -Match "Prices are in GBP, taken from the workspace's region"
        $cost.CurrencySource | Should -Be 'Region'
    }

    It 'deploys the repository''s rules, and its Community rules as Content Hub templates' {
        $files = @(Get-ChildItem (Join-Path $script:content 'AnalyticalRules') -Recurse -Filter '*.yaml')
        $community = @($files | Where-Object { $_.FullName -match '[/\\]Community[/\\]' })
        $rules = @(Read-Demo 'alert-rules.json')
        $templates = @(Read-Demo 'alert-rule-templates.json')
        $templates.Count | Should -Be $community.Count
        $fromTemplate = @($rules | Where-Object { $_.properties.PSObject.Properties['alertRuleTemplateName'] -and $_.properties.alertRuleTemplateName -and $_.kind -eq 'Scheduled' })
        $rules.Count | Should -Be ($files.Count - $community.Count + $fromTemplate.Count + 2)
        foreach ($f in @($files | Where-Object { $_.FullName -notmatch '[/\\]Community[/\\]' } | Select-Object -First 10)) {
            $id = ([string]((Get-Content $f.FullName -Raw | ConvertFrom-Yaml)['id'])).ToLowerInvariant()
            @($rules.name) | Should -Contain $id -Because $f.Name
        }
        @($rules | Where-Object kind -eq 'Fusion').Count | Should -Be 1
    }

    It 'carries the repository''s hunting queries, detections, watchlists, workbooks, automation and summary rules' {
        @(Read-Demo 'hunting-queries.json').Count | Should -Be @(Get-ChildItem (Join-Path $script:content 'HuntingQueries') -Recurse -Filter '*.yaml').Count
        @(Read-Demo 'defender-custom-detections.json').Count | Should -Be @(Get-ChildItem (Join-Path $script:content 'DefenderCustomDetections') -Recurse -Filter '*.yaml').Count
        @(Read-Demo 'watchlists.json').Count | Should -Be @(Get-ChildItem (Join-Path $script:content 'Watchlists') -Recurse -Filter 'watchlist.json').Count
        @(Read-Demo 'workbooks-saved.json').Count | Should -Be @(Get-ChildItem (Join-Path $script:content 'Workbooks') -Recurse -Filter 'metadata.json').Count
        @(Read-Demo 'summary-rules.json').Count | Should -Be @(Get-ChildItem (Join-Path $script:content 'SummaryRules') -Filter '*.json').Count
        $automation = @(Read-Demo 'automation-rules.json')
        foreach ($f in @(Get-ChildItem (Join-Path $script:content 'AutomationRules') -Filter '*.json')) {
            @($automation.properties.displayName) | Should -Contain ((Get-Content $f.FullName -Raw | ConvertFrom-Json).displayName)
        }
        # Every automation rule that runs a playbook names one the demo has.
        $playbooks = @(Read-Demo 'playbooks.json')
        @($playbooks.name | Select-Object -Unique).Count | Should -Be $playbooks.Count
        foreach ($a in @($automation | Where-Object { @($_.properties.actions | Where-Object actionType -eq 'RunPlaybook').Count })) {
            $id = @($a.properties.actions | Where-Object actionType -eq 'RunPlaybook')[0].actionConfiguration.logicAppResourceId
            @($playbooks.id) | Should -Contain $id
        }
    }

    It 'keeps the daily series in step with the captures' {
        $tables = @(Read-Demo 'tables-with-data.json')
        $usage = (@(Read-Demo 'daily-table-usage.json') | Measure-Object -Property GB -Sum).Sum
        [math]::Round($usage, 0) | Should -Be ([math]::Round((@($tables | ForEach-Object { [double]$_.BillableLast30d }) | Measure-Object -Sum).Sum, 0))
        (@(Read-Demo 'daily-alerts.json') | Measure-Object -Property Alerts -Sum).Sum | Should -Be (@(Read-Demo 'analytics-rule-volumes.json') | Measure-Object -Property Alerts -Sum).Sum
        $summary = @(Read-Demo 'incidents-summary.json')[0]
        $daily = @(Read-Demo 'daily-incidents.json')
        ($daily | Measure-Object -Property Incidents -Sum).Sum | Should -Be $summary.Count
        (@($daily | Where-Object Status -eq 'Closed') | Measure-Object -Property Incidents -Sum).Sum | Should -Be $summary.Closed
        (@(Read-Demo 'daily-health.json') | Measure-Object -Property LogCount -Sum).Sum | Should -Be (@(Read-Demo 'sentinel-health-summary.json') | Measure-Object -Property LogCount -Sum).Sum
        foreach ($p in @(Read-Demo 'playbook-runs.json')) { (@($p.Daily) | Measure-Object -Property Runs -Sum).Sum + 0 | Should -Be $p.Runs7d }
        $rc = Read-Demo 'run-context.json'
        $rc.LookbackDays | Should -Be $script:days
        $rc.DailyDays | Should -Be $script:days
        $rc.Demo | Should -BeTrue
        @(Read-Demo 'daily-table-usage.json' | Where-Object { $_.DaysAgo -ge $script:days }).Count | Should -Be 0
    }

    It 'runs the engine over it: table references, cost, gap analysis and maturity' {
        @(Read-Demo 'rule-table-references.json').Count | Should -BeGreaterThan 100
        @(Read-Demo 'template-table-references.json').Count | Should -Be @(Read-Demo 'alert-rule-templates.json').Count
        (Read-Demo 'cost-estimate.json').MonthlyTotal | Should -BeGreaterThan 0
        @(Read-Demo 'gap-analysis.json').Count | Should -BeGreaterThan 10
        (Read-Demo 'maturity.json').overall.score | Should -Not -BeNullOrEmpty
    }

    It 'writes the same inventory for the same seed and date' {
        $again = & $script:tool -OutputPath (Join-Path $script:outDir 'again') -DailyGb 500 -LookbackDays $script:days -AsOf $script:asOf -Seed 7 6> $null 3> $null
        foreach ($f in 'tables-with-data.json', 'analytics-rule-volumes.json', 'incidents-summary.json', 'playbook-runs.json', 'alert-rules.json') {
            (Get-Content (Join-Path $again.Raw $f) -Raw) | Should -BeExactly (Get-Content (Join-Path $script:raw $f) -Raw) -Because $f
        }
    }

    It 'names nothing from the test fixture' {
        foreach ($f in @(Get-ChildItem $script:raw -Filter '*.json')) {
            $text = Get-Content $f.FullName -Raw
            $text | Should -Not -Match 'law-sentinel-test|rg-sentinel-test|example\.test' -Because $f.Name
        }
    }

    It 'builds the dashboard with its slider series and a maturity trend' {
        $bundle = $script:result.Bundle
        Test-Path (Join-Path $bundle 'index.html') | Should -BeTrue
        $model = Get-Content (Join-Path $bundle 'model.json') -Raw | ConvertFrom-Json -Depth 64
        $model.daily.span | Should -Be $script:days
        $model.daily.costed | Should -BeTrue
        # The tier's size reaches the dashboard, which names it in words.
        $model.workspace.sku | Should -Be 'CapacityReservation'
        $model.workspace.skuCapacity | Should -Be $script:result.Summary.CommitmentTierGb
        $html = Get-Content (Join-Path $bundle 'index.html') -Raw
        $html | Should -Match "CapacityReservation:'Commitment tier'"
        $html | Should -Match "\{k:'Monthly cost', v:cost\? fmtMoney\(cost\.currency, cost\.monthlyTotal\)"
        $history = Get-Content (Join-Path $bundle 'maturity-history.json') -Raw | ConvertFrom-Json -Depth 16
        @($history.entries).Count | Should -Be 13
        @($history.entries)[-1].overall.score | Should -Be (Read-Demo 'maturity.json').overall.score
        # The same quarter of runs for the Progress tab, ending at today's record.
        $progress = Get-Content (Join-Path $bundle 'progress-history.json') -Raw | ConvertFrom-Json -Depth 32
        @($progress.entries).Count | Should -Be 13
        @($progress.entries)[-1].date | Should -Be $model.progress.date
        @($progress.entries)[0].metrics.findings | Should -BeGreaterThan $model.progress.metrics.findings
        @($progress.entries)[0].metrics.rulesEnabled | Should -BeLessThan $model.progress.metrics.rulesEnabled
        # The first run is 90 days back, so each baseline (90 days included) has a run.
        ([datetime]$model.progress.date - [datetime]@($progress.entries)[0].date).Days | Should -Be 90
        # Not all of it better: areas climb at their own pace and one slips;
        # one finding is new since the previous run.
        $first = @($progress.entries)[0]
        @($first.areas.PSObject.Properties | Where-Object { [double]$_.Value -lt [double]$model.progress.areas.($_.Name) }).Count | Should -BeGreaterThan 0
        @($first.areas.PSObject.Properties | Where-Object { [double]$_.Value -gt [double]$model.progress.areas.($_.Name) }).Count | Should -Be 1
        $prevIds = @(@($progress.entries)[-2].sets.findings | ForEach-Object id)
        @($model.progress.sets.findings | Where-Object { $prevIds -notcontains $_.id }).Count | Should -Be 1
    }
}
