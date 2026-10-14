#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the one lookback every KQL capture reads.

.DESCRIPTION
    -LookbackDays sets the days of activity the collector reads: every
    query declares `lookback`, `recent` and `daily` ahead of its text and
    takes no number of days of its own. The window rides in run-context.json; the
    gap engine, the maturity assessment, the cost estimate, the renderer,
    the site build and both pipelines read it from there or pass it on.
    These tests hold each of those to it.

.NOTES
    File:         Tests/iSOCBlueprint/Lookback-Window.Tests.ps1
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
    $script:resourcesDir = Join-Path $script:engine 'Private/Resources'
    $script:fixtureRaw = Join-Path $repoRoot 'Tests/iSOCBlueprint/Fixtures/sample/_raw'
    $script:collector = Get-Content (Join-Path $script:engine 'Export-SentinelInventory.ps1') -Raw
    $script:renderer = Get-Content (Join-Path $script:engine 'Convert-SentinelInventoryToMarkdown.ps1') -Raw
    $script:repoRoot = $repoRoot

    # A copy of the fixture's _raw with the run's lookback set.
    function New-WindowedFixture([int]$Days) {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("bp-lookback-" + [guid]::NewGuid())
        Copy-Item -Path $script:fixtureRaw -Destination $dir -Recurse
        $rcPath = Join-Path $dir 'run-context.json'
        $rc = Get-Content $rcPath -Raw | ConvertFrom-Json
        $rc | Add-Member -NotePropertyName LookbackDays -NotePropertyValue $Days -Force
        $rc | Add-Member -NotePropertyName RecentDays -NotePropertyValue ([math]::Min(7, $Days)) -Force
        $rc | ConvertTo-Json -Depth 16 | Set-Content $rcPath -Encoding utf8
        return $dir
    }
    # A function from a script, by name, for a test to call.
    function Get-ScriptFunction([string]$Path, [string]$Name) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        return $ast.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $Name }, $true).Extent.Text
    }
}

Describe 'The collector reads one lookback' {
    It 'takes -LookbackDays from 1 to 730, 30 by default' {
        $script:collector | Should -Match '\[ValidateRange\(1, 730\)\]\s+\[int\]\$LookbackDays = 30'
    }

    It 'gives no query a window of its own beyond the last day and the one-hour duplicate sample' {
        $fixed = @([regex]::Matches($script:collector, 'ago\((\d+[dh])\)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
        $fixed -join ',' | Should -Be '1d,1d,1h'
        $script:collector | Should -Match 'ago\(lookback\)'
        $script:collector | Should -Match 'ago\(recent\)'
    }

    It 'runs every query with the window declared' {
        $script:collector | Should -Not -Match '-Query \$kql\w* -ErrorAction'
        ([regex]::Matches($script:collector, '-Query \(Add-BpWindow \$kql\w*\)')).Count | Should -Be ([regex]::Matches($script:collector, 'Invoke-AzOperationalInsightsQuery -WorkspaceId')).Count
    }

    It 'declares lookback, recent and daily ahead of the query text' {
        . ([scriptblock]::Create((Get-ScriptFunction (Join-Path $script:engine 'Export-SentinelInventory.ps1') 'Add-BpWindow')))
        $script:LookbackDays = 14; $script:RecentDays = 7; $script:DailyDays = 14
        Add-BpWindow 'Usage | take 1' | Should -Be "let lookback = 14d;`nlet recent = 7d;`nlet daily = 14d;`nUsage | take 1"
    }

    It 'reads playbook runs over the lookback and records the window in run-context.json' {
        $script:collector | Should -Match 'AddDays\(-\$script:LookbackDays\)'
        $script:collector | Should -Match 'LookbackDays\s+= \$script:LookbackDays'
        $script:collector | Should -Match 'RecentDays\s+= \$script:RecentDays'
        $script:collector | Should -Match '\$script:RecentDays\s+= \[math\]::Min\(7, \$LookbackDays\)'
    }
}

Describe 'The gap engine judges the window it was given' {
    BeforeAll {
        . (Join-Path $script:engine 'Private/GapChecks.ps1')
        . (Join-Path $script:engine 'Private/Get-SentinelGap.ps1')
    }

    It 'reads 30 days and 7 from a run that carries no window' {
        $w = _Window $null
        $w.Days | Should -Be 30
        $w.RecentDays | Should -Be 7
    }

    It 'compares a per-30-day threshold as a 30-day rate' {
        $inv = [pscustomobject]@{ Window = [pscustomobject]@{ Days = 14; RecentDays = 7 } }
        _Per30 14 $inv | Should -Be 30
        _Days 1 | Should -Be '1 day'
    }

    It 'names the window in a finding''s evidence' {
        $inv = [pscustomobject]@{ Window = [pscustomobject]@{ Days = 14; RecentDays = 7 }; IncidentsMttr = @([pscustomobject]@{ ClosedCount = 3; MTTRMinutes = 3000 }) }
        (Test-IncidentMttrThreshold -Inventory $inv).Evidence | Should -Match 'over the last 14 days'
    }

    It 'fills {lookback} and {recent} in titles and remediation, and the inventory carries the window' {
        $raw = New-WindowedFixture 14
        try {
            $findings = Get-SentinelGap -InputRoot $raw -ResourcesRoot $script:resourcesDir -RulesPath (Join-Path $script:resourcesDir 'best-practices.json') -GapChecksPath (Join-Path $script:engine 'Private/GapChecks.ps1')
            @($findings).Count | Should -BeGreaterThan 0
            ($findings | ConvertTo-Json -Depth 8) | Should -Not -Match '\{lookback\}|\{recent\}'
            (New-InventoryFromRaw -InputRoot $raw -ResourcesRoot $script:resourcesDir).Window.Days | Should -Be 14
        } finally { Remove-Item $raw -Recurse -Force }
    }

    It 'writes the window as tokens in the catalogue, not fixed days' {
        $catalogue = Get-Content (Join-Path $script:resourcesDir 'best-practices.json') -Raw
        $catalogue | Should -Match 'Orphan table: schema deployed but no data in the last \{lookback\}'
        $catalogue | Should -Match 'Silent table: data in the last \{lookback\} but nothing in the last \{recent\}'
        $catalogue | Should -Not -Match 'in the last (7|30|90) days'
    }
}

Describe 'The maturity assessment and the cost estimate follow the window' {
    BeforeAll {
        . (Join-Path $script:engine 'Private/Get-SentinelMaturity.ps1')
        . (Join-Path $script:engine 'Private/Get-SentinelCostEstimate.ps1')
    }

    It 'names the window in a criterion''s text' {
        Format-MaturityWindow -Text 'Rows in {lookback}, Entra in {recent}' -Window ([pscustomobject]@{ Days = 1; RecentDays = 1 }) | Should -Be 'Rows in 1 day, Entra in 1 day'
        (Get-Content (Join-Path $script:resourcesDir 'maturity-criteria.json') -Raw) | Should -Not -Match '\b(7|12|14|30) days\b'
    }

    It 'scores with the run''s window and leaves no token behind' {
        $raw = New-WindowedFixture 21
        try {
            $m = Get-SentinelMaturity -InputRoot $raw -ResourcesRoot $script:resourcesDir -CriteriaPath (Join-Path $script:resourcesDir 'maturity-criteria.json') -TargetLevel 3
            $m.methodology.lookbackDays | Should -Be 21
            $m.methodology.scaleNote | Should -Match '21 days of activity'
            ($m | ConvertTo-Json -Depth 12) | Should -Not -Match '\{lookback\}|\{recent\}'
        } finally { Remove-Item $raw -Recurse -Force }
    }

    It 'projects a month from the window: half the days, twice the monthly cost' {
        $raw = New-WindowedFixture 15
        try {
            $thirty = Get-SentinelCostEstimate -InputRoot $script:fixtureRaw -ResourcesRoot $script:resourcesDir
            $fifteen = Get-SentinelCostEstimate -InputRoot $raw -ResourcesRoot $script:resourcesDir
            $thirty.WindowDays | Should -Be 30
            $fifteen.WindowDays | Should -Be 15
            $thirty.MonthlyTotal | Should -BeGreaterThan 0
            [math]::Round($fifteen.MonthlyTotal / $thirty.MonthlyTotal, 1) | Should -Be 2
        } finally { Remove-Item $raw -Recurse -Force }
    }
}

Describe 'The renderer names the window it read' {
    It 'fills the window tokens from run-context.json' {
        function Read-Raw { param($Name) [pscustomobject]@{ LookbackDays = 1; RecentDays = 1 } }
        . ([scriptblock]::Create((Get-ScriptFunction (Join-Path $script:engine 'Convert-SentinelInventoryToMarkdown.ps1') 'Get-BpWindow')))
        . ([scriptblock]::Create((Get-ScriptFunction (Join-Path $script:engine 'Convert-SentinelInventoryToMarkdown.ps1') 'Resolve-BpWindowText')))
        $script:BpWindow = $null
        Resolve-BpWindowText 'last {lookback} ({lookback-d}), recent {recent} ({recent-d})' | Should -Be 'last 1 day (1d), recent 1 day (1d)'
    }

    It 'writes headings, labels and chart titles as window tokens' {
        $script:renderer | Should -Match '## CEF devices \(last \{lookback-d\}\)'
        $script:renderer | Should -Match '## Incident metrics \(last \{recent-d\}\)'
        $script:renderer | Should -Match 'title "Top tables by billable GB \(\{lookback-d\}\)"'
        $script:renderer | Should -Match "Gb30d = 'GB \(\{lookback-d\}\)'"
        $script:renderer | Should -Match '\$body = Resolve-BpWindowText \$body'
        $script:renderer | Should -Not -Match '\(last (7|30)d\)'
    }
}

Describe 'The pipelines set the lookback' {
    It 'Azure DevOps takes lookbackDays and passes it to the collector' {
        $ado = Get-Content (Join-Path $script:repoRoot 'Pipelines/Sentinel-Blueprint.yml') -Raw
        $ado | Should -Match '- name: lookbackDays\s+displayName: "[^"]+"\s+type: number\s+default: 30'
        $ado.Contains('$params[''LookbackDays''] = [int]"${{ parameters.lookbackDays }}"') | Should -BeTrue
    }

    It 'GitHub takes lookback-days, or the BLUEPRINT_LOOKBACK_DAYS variable on a schedule' {
        $gh = Get-Content (Join-Path $script:repoRoot '.github/workflows/sentinel-blueprint.yml') -Raw
        $gh | Should -Match 'lookback-days:\s+description: "[^"]+"\s+type: number\s+default: 30'
        $gh.Contains("[int]'`${{ inputs.lookback-days || vars.BLUEPRINT_LOOKBACK_DAYS || '30' }}'") | Should -BeTrue
        $gh | Should -Match '-LookbackDays\s+\$lookbackDays'
    }
}

Describe 'The site names the window on every card' {
    It 'the build carries the window into the model and the estate' {
        $build = Get-Content (Join-Path $script:engine 'SharePoint/Build-SentinelDocsSite.ps1') -Raw
        $build | Should -Match '\$window = \[ordered\]@\{ days = \$lookbackDays; recentDays = \$recentDays \}'
        $build | Should -Match 'window\s+= \$window'
        $build | Should -Match 'window\s+= "\$\(\$lookbackDays\)d"'
    }

    It 'the dashboard reads it once and labels from it' {
        $html = Get-Content (Join-Path $script:engine 'SharePoint/templates/sharepoint-dashboard.html') -Raw
        $html.Contains("const days=(M.window&&+M.window.days>0)? +M.window.days : 30;") | Should -BeTrue
        $html.Contains("const paintWindow=()=>document.querySelectorAll('[data-win]')") | Should -BeTrue
        ([regex]::Matches($html, 'data-win="')).Count | Should -BeGreaterOrEqual 6
        $html | Should -Not -Match "\(30d\)</h3>|'Alerts \(30d\)'|over the last 30 days"
    }
}
