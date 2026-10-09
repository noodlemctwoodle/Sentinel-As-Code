#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for the Sentinel-As-Code maturity assessment engine.

.DESCRIPTION
    Three groups:

      - The fixture run: Get-SentinelGap over the sample fixture supplies
        the rule outcomes, Get-SentinelMaturity scores them, and the
        result is checked against the statuses the fixture was built to
        produce and against the committed _raw/maturity.json.
      - Synthetic criteria on TestDrive: scoring arithmetic, weights,
        Unknown handling, confidence bands, target gap, roadmap order,
        quick wins and the allOf / anyOf truth tables, with outcomes
        passed straight in so every case is exact.
      - Schema guards over the real criteria file: every gap rule exists
        in best-practices.json, every metric is one the engine computes,
        every CSF id is in the reference, no em-dash in the text.

.EXAMPLE
    Invoke-Pester -Path Tests/Documenter/Get-SentinelMaturity.Tests.ps1 -Output Detailed

.NOTES
    File:         Tests/Documenter/Get-SentinelMaturity.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-09
    Version:      0.1.0
    Last Updated: 2026-10-09
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $script:repoRoot     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:fixtureRaw   = Join-Path $script:repoRoot 'Tests/Documenter/Fixtures/sample/_raw'
    $script:resourcesDir = Join-Path $script:repoRoot 'Tools/Documenter/Private/Resources'
    $script:criteriaPath = Join-Path $script:resourcesDir 'maturity-criteria.json'
    $script:rulesPath    = Join-Path $script:resourcesDir 'best-practices.json'

    . (Join-Path $script:repoRoot 'Tools/Documenter/Private/Get-SentinelGap.ps1')
    . (Join-Path $script:repoRoot 'Tools/Documenter/Private/Get-SentinelMaturity.ps1')

    $script:outcomes = [System.Collections.Generic.List[object]]::new()
    $null = Get-SentinelGap -InputRoot $script:fixtureRaw -ResourcesRoot $script:resourcesDir `
        -RulesPath $script:rulesPath -GapChecksPath (Join-Path $script:repoRoot 'Tools/Documenter/Private/GapChecks.ps1') `
        -OutcomeCollector $script:outcomes

    $script:maturity = Get-SentinelMaturity -InputRoot $script:fixtureRaw -ResourcesRoot $script:resourcesDir `
        -CriteriaPath $script:criteriaPath -GapOutcomes $script:outcomes.ToArray() -TargetLevel 3

    $script:criterionById = @{}
    foreach ($a in $script:maturity.areas) { foreach ($c in $a.criteria) { $script:criterionById[$c.id] = $c } }

    # A criteria document with one area and the CSF reference the engine
    # validates against, for the synthetic cases.
    function New-SyntheticCriteria {
        param([object[]]$Criteria, [string]$Path)
        $doc = [ordered]@{
            version     = '0.0.1'
            methodology = @{ name = 'test'; version = '0'; scaleNote = '' }
            levels      = @(0..5 | ForEach-Object { @{ level = $_; name = "L$_" } })
            confidence  = @{ good = 6; moderate = 4 }
            csf         = @{ source = 't'; functions = @{ DE = 'Detect' }; subcategories = @{ 'DE.AE-02' = 'x' } }
            areas       = @(@{ id = 'ONE'; name = 'Area one' }, @{ id = 'TWO'; name = 'Area two' })
            outOfScope  = @()
            criteria    = $Criteria
        }
        $doc | ConvertTo-Json -Depth 12 | Set-Content -Path $Path -Encoding UTF8
        return $Path
    }
    function New-GapCriterion {
        param([string]$Id, [string]$Rule, [double]$Weight = 1, [string]$Effort = 'Low', [string]$Area = 'ONE')
        return @{ id = $Id; area = $Area; kind = 'practice'; name = $Id; weight = $Weight; effort = $Effort; impact = 'i'; guidance = 'g'; csf = @('DE.AE-02'); source = @{ kind = 'gapRule'; rule = $Rule } }
    }
    function New-Outcome {
        param([string]$Id, [string]$Outcome)
        return [pscustomobject]@{ Id = $Id; Check = 'Test-X'; Outcome = $Outcome; Message = $null }
    }
    function Invoke-Synthetic {
        param([object[]]$Criteria, [object[]]$Outcomes, [int]$Target = 3)
        $dir = Join-Path $TestDrive ("synthetic-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $raw = Join-Path $dir '_raw'
        New-Item -ItemType Directory -Path $raw -Force | Out-Null
        $criteriaFile = New-SyntheticCriteria -Criteria $Criteria -Path (Join-Path $dir 'criteria.json')
        return Get-SentinelMaturity -InputRoot $raw -ResourcesRoot $script:resourcesDir -CriteriaPath $criteriaFile -GapOutcomes $Outcomes -TargetLevel $Target
    }
}

Describe 'Maturity assessment over the sample fixture' {

    It 'assesses all eleven areas and sixty criteria' {
        $maturity.areas.Count | Should -Be 11
        $maturity.totals.criteria | Should -Be 60
        ($maturity.totals.met + $maturity.totals.gap + $maturity.totals.unknown) | Should -Be 60
    }

    It 'names the methodology without any third-party model' {
        $maturity.methodology.name | Should -Be 'Sentinel-As-Code maturity assessment'
        $maturity.methodology.name | Should -Not -Match 'CMM'
    }

    It 'reports the target as level 3, Established, and not met' {
        $maturity.targetLevel | Should -Be 3
        $maturity.targetLevelName | Should -Be 'Established'
        $maturity.targetMet | Should -BeFalse
        $maturity.areasBelowTarget.Count | Should -BeGreaterThan 0
    }

    It 'scores every assessed area between 0 and 5 with a matching level' {
        foreach ($a in $maturity.areas) {
            if ($null -eq $a.score) { continue }
            $a.score | Should -BeGreaterOrEqual 0
            $a.score | Should -BeLessOrEqual 5
            $a.level | Should -Be ([math]::Floor($a.score))
            $a.evaluated | Should -Be ($a.met + $a.gap)
        }
        $maturity.overall.score | Should -BeGreaterOrEqual 0
        $maturity.overall.score | Should -BeLessOrEqual 5
    }

    It 'resolves gap-rule criteria from the outcomes (daily cap fires, lock is present)' {
        $criterionById['SAC-LOG-03'].status | Should -Be 'Gap'
        $criterionById['SAC-LOG-03'].evidence | Should -Match 'dailyQuotaGb'
        $criterionById['SAC-GOV-03'].status | Should -Be 'Met'
    }

    It 'resolves metric criteria from the captures (MTTA 95.5 min is Met, no hunting queries is Gap)' {
        $criterionById['SAC-INC-03'].status | Should -Be 'Met'
        $criterionById['SAC-INC-03'].evidence | Should -Match '95\.5 minutes'
        $criterionById['SAC-HNT-03'].status | Should -Be 'Gap'
        $criterionById['SAC-TI-04'].status | Should -Be 'Met'
        $criterionById['SAC-TI-04'].evidence | Should -Match '1,512'
        $criterionById['SAC-PLT-04'].status | Should -Be 'Met'
    }

    It 'resolves the combined criteria (content current is Gap via SENT-054, MDTI is Met via the connector)' {
        $criterionById['SAC-DET-07'].status | Should -Be 'Gap'
        $criterionById['SAC-TI-06'].status | Should -Be 'Met'
        $criterionById['SAC-INV-03'].status | Should -Be 'Gap'
    }

    It 'exposes the computed metrics' {
        $maturity.metrics.enabledRules | Should -Be 4
        $maturity.metrics.customRules | Should -Be 1
        $maturity.metrics.tacticsCovered | Should -Be 2
        $maturity.metrics.highPrivilegeAssignments | Should -Be 2
        $maturity.metrics.sentinelRoleAssignments | Should -Be 1
        $maturity.metrics.connectorFailures7d | Should -Be 8
        $maturity.metrics.tablesWithCustomRetention | Should -Be 2
    }

    It 'orders the roadmap by overall lift, then effort, then id, with a rising projection' {
        $r = @($maturity.roadmap)
        $r.Count | Should -Be $maturity.totals.gap
        for ($i = 1; $i -lt $r.Count; $i++) {
            $prev = $r[$i - 1]; $cur = $r[$i]
            $cur.priority | Should -Be ($prev.priority + 1)
            $cur.overallLift | Should -BeLessOrEqual $prev.overallLift
            $cur.projectedScore | Should -BeGreaterOrEqual $prev.projectedScore
        }
        $r[0].projectedScore | Should -BeGreaterThan $maturity.overall.score
    }

    It 'picks at most five Low-effort quick wins in roadmap order' {
        $maturity.quickWins.Count | Should -BeLessOrEqual 5
        foreach ($q in $maturity.quickWins) { $q.effort | Should -Be 'Low' }
        $priorities = @($maturity.quickWins | ForEach-Object priority)
        ($priorities | Sort-Object) | Should -Be $priorities
    }

    It 'rolls up to the six NIST CSF functions and the referenced subcategories' {
        @($maturity.csf.functions | ForEach-Object id) | Should -Be @('GV', 'ID', 'PR', 'DE', 'RS', 'RC')
        ($maturity.csf.functions | Where-Object id -eq 'DE').criteria | Should -BeGreaterThan 10
        $maturity.csf.subcategories.Count | Should -Be 34
        foreach ($s in $maturity.csf.subcategories) { $s.outcome | Should -Not -BeNullOrEmpty }
    }

    It 'matches the committed fixture maturity.json on statuses and scores' {
        $expected = Get-Content (Join-Path $fixtureRaw 'maturity.json') -Raw | ConvertFrom-Json -Depth 16
        $expected.overall.score | Should -Be $maturity.overall.score
        foreach ($a in $expected.areas) {
            $actual = $maturity.areas | Where-Object id -eq $a.id
            $actual.score | Should -Be $a.score -Because "area $($a.id)"
            foreach ($c in $a.criteria) {
                $criterionById[$c.id].status | Should -Be $c.status -Because "criterion $($c.id)"
            }
        }
    }

    It 'falls back to gap-checks.json when no outcomes are passed' {
        # The fixture carries no gap-checks.json (the collector writes it at
        # run time), so give a copy the file the gap engine produces today.
        $copy = Join-Path $TestDrive 'fallback-raw'
        New-Item -ItemType Directory -Path $copy -Force | Out-Null
        Get-ChildItem $fixtureRaw -File | Copy-Item -Destination $copy
        $outcomes.ToArray() | ConvertTo-Json -Depth 4 -AsArray | Set-Content (Join-Path $copy 'gap-checks.json') -Encoding UTF8
        $fromFile = Get-SentinelMaturity -InputRoot $copy -ResourcesRoot $resourcesDir -CriteriaPath $criteriaPath -TargetLevel 3
        $fromFile.totals.unknown | Should -Be $maturity.totals.unknown
        $fromFile.overall.score | Should -Be $maturity.overall.score
    }

    It 'marks every rule-backed criterion Unknown when there are no outcomes and no captures' {
        $empty = Join-Path $TestDrive 'empty-raw'
        New-Item -ItemType Directory -Path $empty -Force | Out-Null
        $m = Get-SentinelMaturity -InputRoot $empty -ResourcesRoot $resourcesDir -CriteriaPath $criteriaPath
        $m.totals.unknown | Should -Be 60
        $m.overall.score | Should -BeNullOrEmpty
        $m.overall.levelName | Should -Be 'Not assessed'
        $m.targetMet | Should -BeFalse
        $m.roadmap.Count | Should -Be 0
        foreach ($a in $m.areas) { $a.confidence | Should -Be 'Not assessed' }
    }
}

Describe 'Maturity scoring with synthetic criteria' {

    It 'scores two Met of three equal criteria as 3.33, level 3' {
        $m = Invoke-Synthetic -Criteria @((New-GapCriterion 'SAC-ONE-01' 'SENT-001'), (New-GapCriterion 'SAC-ONE-02' 'SENT-002'), (New-GapCriterion 'SAC-ONE-03' 'SENT-003')) `
            -Outcomes @((New-Outcome 'SENT-001' 'Passed'), (New-Outcome 'SENT-002' 'Passed'), (New-Outcome 'SENT-003' 'Fired'))
        $one = $m.areas | Where-Object id -eq 'ONE'
        $one.score | Should -Be 3.33
        $one.level | Should -Be 3
        $one.levelName | Should -Be 'L3'
        $m.overall.score | Should -Be 3.33
    }

    It 'weights a 1.5 criterion more heavily' {
        $m = Invoke-Synthetic -Criteria @((New-GapCriterion 'SAC-ONE-01' 'SENT-001' -Weight 1.5), (New-GapCriterion 'SAC-ONE-02' 'SENT-002')) `
            -Outcomes @((New-Outcome 'SENT-001' 'Fired'), (New-Outcome 'SENT-002' 'Passed'))
        ($m.areas | Where-Object id -eq 'ONE').score | Should -Be 2
    }

    It 'leaves Errored, Undefined and missing outcomes out of the denominator' {
        $m = Invoke-Synthetic -Criteria @((New-GapCriterion 'SAC-ONE-01' 'SENT-001'), (New-GapCriterion 'SAC-ONE-02' 'SENT-002'), (New-GapCriterion 'SAC-ONE-03' 'SENT-003'), (New-GapCriterion 'SAC-ONE-04' 'SENT-004')) `
            -Outcomes @((New-Outcome 'SENT-001' 'Passed'), (New-Outcome 'SENT-002' 'Errored'), (New-Outcome 'SENT-003' 'Undefined'))
        $one = $m.areas | Where-Object id -eq 'ONE'
        $one.score | Should -Be 5
        $one.unknown | Should -Be 3
        $one.evaluated | Should -Be 1
        $one.confidence | Should -Be 'Indicative'
    }

    It 'gives an all-Unknown area no score and Not assessed' {
        $m = Invoke-Synthetic -Criteria @((New-GapCriterion 'SAC-ONE-01' 'SENT-001')) -Outcomes @()
        $one = $m.areas | Where-Object id -eq 'ONE'
        $one.score | Should -BeNullOrEmpty
        $one.level | Should -BeNullOrEmpty
        $one.levelName | Should -Be 'Not assessed'
        $one.confidence | Should -Be 'Not assessed'
    }

    It 'sets confidence Good at six evaluated, Moderate at four, Indicative below' {
        $criteria = @(1..6 | ForEach-Object { New-GapCriterion ('SAC-ONE-0' + $_) ('SENT-00' + $_) })
        $six = Invoke-Synthetic -Criteria $criteria -Outcomes @(1..6 | ForEach-Object { New-Outcome ('SENT-00' + $_) 'Passed' })
        ($six.areas | Where-Object id -eq 'ONE').confidence | Should -Be 'Good'
        $four = Invoke-Synthetic -Criteria $criteria -Outcomes @(1..4 | ForEach-Object { New-Outcome ('SENT-00' + $_) 'Passed' })
        ($four.areas | Where-Object id -eq 'ONE').confidence | Should -Be 'Moderate'
        $three = Invoke-Synthetic -Criteria $criteria -Outcomes @(1..3 | ForEach-Object { New-Outcome ('SENT-00' + $_) 'Passed' })
        ($three.areas | Where-Object id -eq 'ONE').confidence | Should -Be 'Indicative'
    }

    It 'reports the areas below target with the gap to close' {
        $m = Invoke-Synthetic -Criteria @((New-GapCriterion 'SAC-ONE-01' 'SENT-001'), (New-GapCriterion 'SAC-ONE-02' 'SENT-002'), (New-GapCriterion 'SAC-TWO-01' 'SENT-003' -Area 'TWO')) `
            -Outcomes @((New-Outcome 'SENT-001' 'Passed'), (New-Outcome 'SENT-002' 'Fired'), (New-Outcome 'SENT-003' 'Passed')) -Target 4
        $m.targetMet | Should -BeFalse
        $m.areasBelowTarget.Count | Should -Be 1
        $m.areasBelowTarget[0].id | Should -Be 'ONE'
        $m.areasBelowTarget[0].gapToTarget | Should -Be 1.5
        $m.overall.score | Should -Be 3.75
    }

    It 'reports the target as met when every assessed area reaches it' {
        $m = Invoke-Synthetic -Criteria @((New-GapCriterion 'SAC-ONE-01' 'SENT-001')) -Outcomes @((New-Outcome 'SENT-001' 'Passed')) -Target 5
        $m.targetMet | Should -BeTrue
        $m.areasBelowTarget.Count | Should -Be 0
    }

    It 'orders the roadmap by lift, then Low before Medium before High, then id' {
        $criteria = @(
            (New-GapCriterion 'SAC-ONE-01' 'SENT-001' -Weight 1.5 -Effort 'High'),
            (New-GapCriterion 'SAC-ONE-02' 'SENT-002' -Effort 'Medium'),
            (New-GapCriterion 'SAC-ONE-03' 'SENT-003' -Effort 'Low'),
            (New-GapCriterion 'SAC-ONE-04' 'SENT-004' -Effort 'Low'),
            (New-GapCriterion 'SAC-ONE-05' 'SENT-005')
        )
        $m = Invoke-Synthetic -Criteria $criteria -Outcomes @(1..5 | ForEach-Object { New-Outcome ('SENT-00' + $_) $(if ($_ -eq 5) { 'Passed' } else { 'Fired' }) })
        @($m.roadmap | ForEach-Object criterionId) | Should -Be @('SAC-ONE-01', 'SAC-ONE-03', 'SAC-ONE-04', 'SAC-ONE-02')
        $m.roadmap[0].areaLift | Should -Be 1.36
        $m.roadmap[-1].projectedScore | Should -Be 5
        @($m.quickWins | ForEach-Object criterionId) | Should -Be @('SAC-ONE-03', 'SAC-ONE-04')
    }

    It 'applies the allOf and anyOf truth tables' {
        $mk = {
            param($Id, $Kind, $Rules)
            @{ id = $Id; area = 'ONE'; kind = 'practice'; name = $Id; weight = 1; effort = 'Low'; impact = 'i'; guidance = 'g'; csf = @('DE.AE-02')
               source = @{ kind = $Kind; sources = @($Rules | ForEach-Object { @{ kind = 'gapRule'; rule = $_ } }) } }
        }
        $criteria = @(
            (& $mk 'SAC-ONE-01' 'allOf' @('SENT-001', 'SENT-002')),   # Passed + Fired   -> Gap
            (& $mk 'SAC-ONE-02' 'allOf' @('SENT-001', 'SENT-009')),   # Passed + missing -> Unknown
            (& $mk 'SAC-ONE-03' 'allOf' @('SENT-001', 'SENT-003')),   # Passed + Passed  -> Met
            (& $mk 'SAC-ONE-04' 'anyOf' @('SENT-002', 'SENT-001')),   # Fired + Passed   -> Met
            (& $mk 'SAC-ONE-05' 'anyOf' @('SENT-002', 'SENT-009')),   # Fired + missing  -> Unknown
            (& $mk 'SAC-ONE-06' 'anyOf' @('SENT-002', 'SENT-004'))    # Fired + Fired    -> Gap
        )
        $m = Invoke-Synthetic -Criteria $criteria -Outcomes @((New-Outcome 'SENT-001' 'Passed'), (New-Outcome 'SENT-002' 'Fired'), (New-Outcome 'SENT-003' 'Passed'), (New-Outcome 'SENT-004' 'Fired'))
        $by = @{}
        foreach ($c in ($m.areas | Where-Object id -eq 'ONE').criteria) { $by[$c.id] = $c.status }
        $by['SAC-ONE-01'] | Should -Be 'Gap'
        $by['SAC-ONE-02'] | Should -Be 'Unknown'
        $by['SAC-ONE-03'] | Should -Be 'Met'
        $by['SAC-ONE-04'] | Should -Be 'Met'
        $by['SAC-ONE-05'] | Should -Be 'Unknown'
        $by['SAC-ONE-06'] | Should -Be 'Gap'
    }

    It 'rejects a criteria file that names an unknown metric, area or CSF id' {
        $bad = New-GapCriterion 'SAC-ONE-01' 'SENT-001'
        $bad.source = @{ kind = 'metric'; path = 'noSuchMetric'; op = 'gt'; value = 0 }
        { Invoke-Synthetic -Criteria @($bad) -Outcomes @() } | Should -Throw '*unknown metric*'
        $badArea = New-GapCriterion 'SAC-ZZZ-01' 'SENT-001' -Area 'ZZZ'
        { Invoke-Synthetic -Criteria @($badArea) -Outcomes @() } | Should -Throw '*unknown area*'
        $badCsf = New-GapCriterion 'SAC-ONE-01' 'SENT-001'
        $badCsf.csf = @('XX.YY-99')
        { Invoke-Synthetic -Criteria @($badCsf) -Outcomes @() } | Should -Throw '*not in the reference*'
    }
}

Describe 'maturity-criteria.json schema guards' {

    BeforeAll {
        $script:doc = Get-Content $criteriaPath -Raw | ConvertFrom-Json -Depth 16
        $script:ruleIds = @((Get-Content $rulesPath -Raw | ConvertFrom-Json).rules | ForEach-Object id)
        $script:metricNames = @((New-MaturityMetrics -InputRoot $fixtureRaw -ResourcesRoot $resourcesDir).Keys)
        function Get-SourceLeaves($Source) {
            if ($Source.kind -in 'allOf', 'anyOf') { foreach ($s in $Source.sources) { Get-SourceLeaves $s } } else { $Source }
        }
    }

    It 'has unique ids in SAC-<AREA>-NN form that carry their area' {
        $ids = @($doc.criteria | ForEach-Object id)
        @($ids | Sort-Object -Unique).Count | Should -Be $ids.Count
        foreach ($c in $doc.criteria) {
            $c.id | Should -Match '^SAC-[A-Z]+-\d{2}$'
            $c.id | Should -BeLike "SAC-$($c.area)-*"
        }
    }

    It 'references only gap rules that exist in best-practices.json' {
        foreach ($c in $doc.criteria) {
            foreach ($leaf in @(Get-SourceLeaves $c.source | Where-Object kind -eq 'gapRule')) {
                $ruleIds | Should -Contain $leaf.rule -Because "$($c.id) references $($leaf.rule)"
            }
        }
    }

    It 'references only metrics the engine computes' {
        foreach ($c in $doc.criteria) {
            foreach ($leaf in @(Get-SourceLeaves $c.source | Where-Object kind -eq 'metric')) {
                $metricNames | Should -Contain $leaf.path -Because "$($c.id) references $($leaf.path)"
            }
        }
    }

    It 'maps every criterion to at least one CSF subcategory in the reference' {
        $known = @($doc.csf.subcategories.PSObject.Properties.Name)
        foreach ($c in $doc.criteria) {
            $c.csf.Count | Should -BeGreaterThan 0
            foreach ($ref in $c.csf) { $known | Should -Contain $ref }
        }
    }

    It 'uses every CSF subcategory in the reference at least once' {
        $used = @($doc.criteria | ForEach-Object csf | Sort-Object -Unique)
        foreach ($id in $doc.csf.subcategories.PSObject.Properties.Name) { $used | Should -Contain $id }
    }

    It 'carries no em-dash and no third-party model name anywhere in the file' {
        $text = Get-Content $criteriaPath -Raw
        $text | Should -Not -Match ([char]0x2014)
        $text | Should -Not -Match 'SOC-CMM'
    }

    It 'gives every criterion a non-empty impact and guidance' {
        foreach ($c in $doc.criteria) {
            $c.impact | Should -Not -BeNullOrEmpty
            $c.guidance | Should -Not -BeNullOrEmpty
        }
    }
}
