#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for the iSOC Blueprint SharePoint site generator: section
    families, section-model-to-page conversion, the sync planners, the
    SharePoint helpers and the publisher's page and chart placement, and an
    end-to-end bundle build against the fixture.

.DESCRIPTION
    Nothing here needs SharePoint or PnP.PowerShell: the functions that
    call PnP are tested against stand-in functions. The publisher keeps
    its decisions in pure planning functions (Get-SacSyncPlan.ps1) and the
    page conversion in ConvertTo-SharePointPageSegments.ps1, so both are
    exercised directly. The build test renders the deliberately-broken
    fixture (the section model, and Markdown alone for an older snapshot)
    and runs Build-SentinelDocsSite.ps1 offline (-SkipWhatsNew) into a temp
    folder.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/SharePoint-Site.Tests.ps1 -Output Detailed

    Runs the suite with per-assertion output.

.NOTES
    File:         Tests/iSOCBlueprint/SharePoint-Site.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-08
    Version:      0.4.1
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $sp = Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint'
    . (Join-Path $sp 'Private/Get-SectionFamily.ps1')
    . (Join-Path $sp 'Private/ConvertTo-SharePointPageSegments.ps1')
    . (Join-Path $sp 'Private/Get-SacSyncPlan.ps1')
    . (Join-Path $sp 'Private/SacSharePoint.ps1')
    . (Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Private/ConvertFrom-BlueprintMermaid.ps1')
    . (Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Private/ConvertTo-BlueprintSection.ps1')

    # Pages are built from the section model; these tests write the section
    # as Markdown for readability and convert it the way the renderer does.
    function ConvertTo-Segments([string]$Markdown, [string]$File = '20-analytics-rules.md', [int]$Max = 500) {
        $section = ConvertTo-BlueprintSection -Markdown $Markdown -Id ([System.IO.Path]::GetFileNameWithoutExtension($File))
        ConvertTo-SharePointPageSegments -Section $section -MaxTableRows $Max
    }
    function Join-Html($Result) { ($Result.Segments | Where-Object { $_.type -eq 'html' } | ForEach-Object { $_.html }) -join "`n" }

    # Stand-ins for PnP.PowerShell cmdlets. Functions win over cmdlets of the
    # same name, so these apply whether or not PnP.PowerShell is installed,
    # and Mock replaces them. Keys are cmdlet names, values their parameters.
    function Install-PnPStub([System.Collections.IDictionary] $Stubs) {
        foreach ($name in $Stubs.Keys) {
            Set-Item -Path "function:global:$name" -Value ([scriptblock]::Create("[CmdletBinding()] param($($Stubs[$name]))"))
        }
        @($Stubs.Keys)
    }
    function Remove-PnPStub([string[]] $Names) {
        foreach ($name in $Names) { Remove-Item -Path "function:global:$name" -ErrorAction SilentlyContinue }
    }
}

Describe 'Get-SectionFamily' {

    It 'maps every section the renderer writes to a named family' {
        $renderer = Get-Content (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Convert-SentinelInventoryToMarkdown.ps1') -Raw
        $numbers = [regex]::Matches($renderer, "'(\d{2})-[a-z0-9-]+\.md'") | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique
        $numbers.Count | Should -BeGreaterThan 20
        foreach ($n in $numbers) {
            Get-SectionFamily -Number $n | Should -Not -Be 'Other' -Because "section $n needs a family"
        }
    }

    It 'only returns families that are in the display order' {
        $order = Get-SectionFamilyOrder
        foreach ($n in 0..99) { $order | Should -Contain (Get-SectionFamily -Number $n) }
    }

    It 'keeps hunting and cost apart (no tens-digit lumping)' {
        Get-SectionFamily -Number 30 | Should -Be 'Hunting & content'
        Get-SectionFamily -Number 25 | Should -Be 'Detection'
        Get-SectionFamily -Number 84 | Should -Be 'Cost & access'
        Get-SectionFamily -Number 36 | Should -Be 'Workspace & data'
    }

    It 'places detection opportunities under Detection, and the findings and maturity together under Assessment, before the references' {
        Get-SectionFamily -Number 28 | Should -Be 'Detection'
        Get-SectionFamily -Number 90 | Should -Be 'Assessment'
        Get-SectionFamily -Number 91 | Should -Be 'Assessment'
        Get-SectionFamily -Number 96 | Should -Be 'References'
        Get-SectionFamily -Number 99 | Should -Be 'References'
        Get-SectionFamily -Number 92 | Should -Be 'Assessment' -Because 'an unmapped 9x page below 96 falls back to Assessment'
        $order = @(Get-SectionFamilyOrder)
        [array]::IndexOf($order, 'Assessment') | Should -Be ([array]::IndexOf($order, 'References') - 1)
        $order | Should -Not -Contain 'Maturity'
    }
}

Describe 'ConvertTo-SharePointPageSegments' {

    Context 'title and banner' {
        BeforeAll {
            $md = @(
                '# Sentinel Health and Resilience  (TOC 4.8)'
                ''
                '> **Workspace** `law-x` · **Generated** 2026-10-08 06:00 UTC · **Blueprint** v1.2'
                ''
                'Body text.'
            ) -join "`n"
            $script:r = ConvertTo-Segments $md '11-sentinel-health.md'
        }
        It 'uses the H1 as the title without the TOC suffix' { $r.Title | Should -Be 'Sentinel Health and Resilience' }
        It 'drops the metadata banner' { Join-Html $r | Should -Not -Match 'Blueprint' }
        It 'keeps the body' { Join-Html $r | Should -Match '<p>Body text.</p>' }
        It 'does not put the H1 in the body' { Join-Html $r | Should -Not -Match '<h1' }
    }

    Context 'headings, anchors and rules' {
        BeforeAll {
            $md = "# T`n`n## Two`n`n### Three`n`n#### Four`n`n##### Five`n`n<a id=`"sac-log-03`"></a>`n`n---`n`ntext"
            $script:html = Join-Html (ConvertTo-Segments $md)
        }
        It 'clamps headings to h2-h4' {
            $html | Should -Match '<h2>Two</h2>'
            $html | Should -Match '<h3>Three</h3>'
            $html | Should -Match '<h4>Four</h4>'
            $html | Should -Match '<h4>Five</h4>'
            $html | Should -Not -Match '<h5|<h6'
        }
        It 'strips ids and anchor stubs' {
            $html | Should -Not -Match '\sid="'
            $html | Should -Not -Match '<a id='
        }
        It 'drops horizontal rules' { $html | Should -Not -Match '<hr' }
    }

    Context 'links' {
        BeforeAll {
            $md = @(
                '# T'
                ''
                'See [rules](20-analytics-rules.md), [rule detail](25-mitre-coverage.md#heatmap),'
                '[SAC-GOV-06](90-gap-analysis.md#sac-gov-06), [here](#sac-plt-08), [script](../../Modules/iSOCBlueprint/Engine/Export-SentinelInventory.ps1),'
                '[index](index.md) and [Learn](https://learn.microsoft.com/azure/sentinel/).'
            ) -join "`n"
            $script:html = Join-Html (ConvertTo-Segments $md '90-gap-analysis.md')
        }
        It 'points section links at the generated page' {
            $html | Should -Match 'href="~site/SitePages/sac-20-analytics-rules.aspx">rules</a>'
            $html | Should -Match 'href="~site/SitePages/sac-25-mitre-coverage.aspx">rule detail</a>'
        }
        It 'points finding links at the findings list filtered on the id' {
            $html | Should -Match 'href="~site/Lists/SentinelFindings/AllItems.aspx\?FilterField1=FindingId&amp;FilterValue1=SAC-GOV-06"'
            $html | Should -Match 'FilterValue1=SAC-PLT-08'
        }
        It 'turns repository-relative and index links into plain text' {
            $html | Should -Match '>script<|, script,| script\b'
            $html | Should -Not -Match 'Export-SentinelInventory.ps1'
            $html | Should -Not -Match 'index\.md'
        }
        It 'keeps external links' { $html | Should -Match 'href="https://learn.microsoft.com/azure/sentinel/"' }
    }

    Context 'charts' {
        BeforeAll {
            $md = "# T`n`n## Chart`n`n``````mermaid`npie title X`n  `"A`" : 1`n```````n`nAfter."
            $script:r = ConvertTo-Segments $md '25-mitre-coverage.md'
        }
        It 'turns a chart into a chart segment carrying its data' {
            $c = ($r.Segments | Where-Object type -eq 'chart').chart
            $c.kind | Should -Be 'pie'
            $c.title | Should -Be 'X'
            $c.data.slices[0].label | Should -Be 'A'
        }
        It 'never puts chart source in the page HTML' {
            Join-Html $r | Should -Not -Match 'pie title'
            Join-Html $r | Should -Match 'After\.'
            $r.Warnings | Should -BeNullOrEmpty
        }
        It 'maps a flowchart node''s link to the site, with a raw ampersand for the web part' {
            $flow = ConvertTo-Segments "# T`n`n``````mermaid`nflowchart LR`n    A[Group] --> B[Owner] --> C[Parser]`n    click A href `"90-gap-analysis.md#sac-gov-06`"`n    click B href `"20-analytics-rules.md#volume`"`n    click C href `"../../Content/Parsers/x.yaml`"`n```````n"
            $nodes = @(($flow.Segments | Where-Object type -eq 'chart').chart.data.nodes)
            ($nodes | Where-Object id -eq 'A').href | Should -Be '~site/Lists/SentinelFindings/AllItems.aspx?FilterField1=FindingId&FilterValue1=SAC-GOV-06'
            ($nodes | Where-Object id -eq 'B').href | Should -Be '~site/SitePages/sac-20-analytics-rules.aspx'
            ($nodes | Where-Object id -eq 'C').href | Should -BeNullOrEmpty
        }
        It 'keeps the Mermaid source only for a chart kind it cannot draw' {
            ($r.Segments | Where-Object type -eq 'chart').chart.Contains('source') | Should -BeFalse
            $other = ConvertTo-Segments "# T`n`n``````mermaid`nquadrantChart`n    title Q`n```````n"
            ($other.Segments | Where-Object type -eq 'chart').chart.source | Should -Match 'quadrantChart'
        }
    }

    Context 'splitting' {
        BeforeAll {
            $md = @(
                '# T', '', 'Intro.', '', '## One', '', 'Before.', '', '```mermaid', 'pie title P', '    "A" : 1', '```', '',
                'After.', '', '## Two', '', 'Second.'
            ) -join "`n"
            $script:r = ConvertTo-Segments $md
        }
        It 'splits at every H2 and chart, in order' {
            $types = @($r.Segments | ForEach-Object type)
            $types | Should -Be @('html', 'html', 'chart', 'html', 'html')
        }
        It 'starts each H2 segment with its heading' {
            ($r.Segments | Where-Object { $_.type -eq 'html' -and $_.html -match '^<h2>' }).Count | Should -Be 2
        }
    }

    Context 'lists, notes and code' {
        BeforeAll {
            $script:html = Join-Html (ConvertTo-Segments "# T`n`n- one`n  - nested`n`n3. third`n`n> A note with **bold**`n`n``````kusto`nT | take 1`n```````n")
        }
        It 'nests a sub-list inside its item' { $html | Should -Match '<ul><li>one<ul><li>nested</li></ul></li></ul>' }
        It 'keeps an ordered list''s start' { $html | Should -Match '<ol start="3"><li>third</li></ol>' }
        It 'renders a note as a blockquote' { $html | Should -Match '<blockquote><p>A note with <strong>bold</strong></p></blockquote>' }
        It 'escapes code into pre' { $html | Should -Match '<pre>T \| take 1' }
    }

    Context 'tables' {
        BeforeAll {
            $rows = 1..7 | ForEach-Object { "| r$_ | $_ |" }
            $md = (@('# T', '', '| | |', '|---|---:|', '| Key | Value |', '', '| Name | Count |', '|---|---:|') + $rows) -join "`n"
            $script:r = ConvertTo-Segments $md '20-analytics-rules.md' 5
            $script:html = Join-Html $r
        }
        It 'uses the SharePoint editor table markup' {
            $html | Should -Match '<div class="canvasRteResponsiveTable"><div class="tableWrapper"><table title="Table"><tbody>'
            $html | Should -Not -Match '<thead|<th>'
        }
        It 'bolds the header row' { $html | Should -Match '<td><strong>Name</strong></td>' }
        It 'drops an all-empty header row' { $html | Should -Not -Match '<td><strong></strong></td>' }
        It 'caps long tables and says so' {
            $html | Should -Match 'r5'
            $html | Should -Not -Match '>r6<'
            $html | Should -Match '2 more rows not shown'
            $html | Should -Match 'href="~site/SitePages/Dashboard.aspx"'
            $r.Warnings -join ' ' | Should -Match 'capped at 5 rows'
        }
    }

    It 'returns an empty result for empty Markdown' {
        $r = ConvertTo-Segments ''
        $r.Title | Should -Be ''
        $r.Segments.Count | Should -Be 0
    }
}

Describe 'ConvertTo-SacChartFallbackHtml' {

    It 'writes a one-slice pie as one row of label and value' {
        $html = ConvertTo-SacChartFallbackHtml -Chart @{ kind = 'pie'; title = 'Rules'; data = @{ slices = @(@{ label = 'Scheduled'; value = 3 }) } }
        $html | Should -Match '<p><strong>Rules</strong></p>'
        $html | Should -Match '<tr><td>Scheduled</td><td>3</td></tr>'
        ([regex]::Matches($html, '<tr>')).Count | Should -Be 1
    }

    It 'writes every sankey link and every xy label, joining the series' {
        $sankey = ConvertTo-SacChartFallbackHtml -Chart @{ kind = 'sankey'; data = @{ links = @(@{ source = 'A'; target = 'B'; value = 2 }, @{ source = 'B'; target = 'C'; value = 1 }) } }
        ([regex]::Matches($sankey, '<tr>')).Count | Should -Be 2
        $sankey | Should -Match '<td>A to B</td><td>2</td>'
        $xy = ConvertTo-SacChartFallbackHtml -Chart @{ kind = 'xy'; data = @{ xAxis = @{ labels = @('Mon', 'Tue') }; series = @(@{ values = @(1, 2) }, @{ values = @(5, 6) }) } }
        $xy | Should -Match '<td>Tue</td><td>2 / 6</td>'
    }

    It 'says what draws a chart it cannot tabulate, and escapes the title' {
        $html = ConvertTo-SacChartFallbackHtml -Chart @{ kind = 'flowchart'; title = 'A <b> B'; data = @{ nodes = @() } }
        $html | Should -Match 'A &lt;b&gt; B'
        $html | Should -Match 'chart web part'
        $html | Should -Not -Match '<table'
    }
}

Describe 'Get-SacPageName' {
    It 'prefixes and lower-cases the file stem' { Get-SacPageName -FileName '25-MITRE-coverage.md' | Should -Be 'sac-25-mitre-coverage' }
}

Describe 'Get-PageSyncPlan' {
    BeforeAll {
        $desired = @(
            [pscustomobject]@{ Name = 'sac-00-overview'; Hash = 'a' }
            [pscustomobject]@{ Name = 'sac-10-data'; Hash = 'b2' }
            [pscustomobject]@{ Name = 'sac-20-new'; Hash = 'c' }
        )
        $script:plan = Get-PageSyncPlan -Desired $desired -ExistingNames @('sac-00-overview', 'sac-10-data', 'sac-99-gone') `
            -PublishedHashes @{ 'sac-00-overview' = 'a'; 'sac-10-data' = 'b1' }
        function ActionFor($n) { ($plan | Where-Object Name -eq $n).Action }
    }
    It 'skips pages whose hash matches the last publish' { ActionFor 'sac-00-overview' | Should -Be 'Skip' }
    It 'updates pages whose hash changed' { ActionFor 'sac-10-data' | Should -Be 'Update' }
    It 'creates pages that do not exist' { ActionFor 'sac-20-new' | Should -Be 'Create' }
    It 'deletes generated pages the bundle no longer has' { ActionFor 'sac-99-gone' | Should -Be 'Delete' }
    It 'updates an existing page with no recorded hash' {
        $p = Get-PageSyncPlan -Desired @([pscustomobject]@{ Name = 'sac-x'; Hash = 'h' }) -ExistingNames @('sac-x') -PublishedHashes @{}
        $p.Action | Should -Be 'Update'
    }
}

Describe 'Get-FindingSyncPlan' {
    BeforeAll {
        $script:now = [datetime]::SpecifyKind([datetime]'2026-10-08T06:00:00', [System.DateTimeKind]::Utc)
        function F($id, $sev = 'Warning') { [pscustomobject]@{ id = $id; title = "t $id"; severity = $sev; category = 'Cost'; evidence = 'e'; remediation = 'r'; learn = 'https://learn.microsoft.com/x' } }
        function E($item, $id, $status) { [pscustomobject]@{ ItemId = $item; FindingId = $id; Status = $status } }
        function C($id, $o) { [pscustomobject]@{ Id = $id; Outcome = $o } }
        function Plan($current, $existing, $checks, $available = $true) {
            Get-FindingSyncPlan -Current $current -Existing $existing -Checks $checks -AnalysisAvailable $available -NowUtc $now
        }
    }

    It 'updates an item filed under the legacy id in place and moves it to the new id' {
        $cur = F 'SAC-LOG-03'; $cur | Add-Member -NotePropertyName legacyId -NotePropertyValue 'SENT-001'
        $p = Plan @($cur) @(E 7 'SENT-001' 'Open') @(C 'SAC-LOG-03' 'Fired')
        @($p).Count | Should -Be 1
        $p.Action | Should -Be 'Update'
        $p.ItemId | Should -Be 7
        $p.FindingId | Should -Be 'SAC-LOG-03'
        $p.Values.FindingId | Should -Be 'SAC-LOG-03'
    }

    It 'reopens a resolved legacy item under the new id rather than adding a duplicate' {
        $cur = F 'SAC-LOG-03'; $cur | Add-Member -NotePropertyName legacyId -NotePropertyValue 'SENT-001'
        $p = Plan @($cur) @(E 7 'SENT-001' 'Resolved') @(C 'SAC-LOG-03' 'Fired')
        $p.Action | Should -Be 'Reopen'
        $p.ItemId | Should -Be 7
    }

    It 'adds a new finding as Open with first and last seen' {
        $p = Plan @(F 'SAC-LOG-03') @() @(C 'SAC-LOG-03' 'Fired')
        $p.Action | Should -Be 'Add'
        $p.Values.Status | Should -Be 'Open'
        $p.Values.FirstSeen | Should -Be $now
        $p.Values.LastSeen | Should -Be $now
        $p.Values.Learn | Should -Be 'https://learn.microsoft.com/x, Microsoft Learn'
        $p.Values.SeverityRank | Should -Be 2
    }

    It 'updates an open finding that still fires' {
        $p = Plan @(F 'SAC-LOG-03') @(E 7 'SAC-LOG-03' 'Open') @(C 'SAC-LOG-03' 'Fired')
        $p.Action | Should -Be 'Update'
        $p.ItemId | Should -Be 7
        $p.Values.ContainsKey('FirstSeen') | Should -BeFalse
    }

    It 'reopens a resolved finding that fires again' {
        $p = Plan @(F 'SAC-LOG-03') @(E 7 'SAC-LOG-03' 'Resolved') @(C 'SAC-LOG-03' 'Fired')
        $p.Action | Should -Be 'Reopen'
        $p.Values.Status | Should -Be 'Open'
        $p.Values.ContainsKey('ResolvedOn') | Should -BeTrue
        $p.Values.ResolvedOn | Should -BeNullOrEmpty
    }

    It 'resolves an open finding whose check passed' {
        $p = Plan @() @(E 7 'SAC-LOG-03' 'Open') @(C 'SAC-LOG-03' 'Passed')
        $p.Action | Should -Be 'Resolve'
        $p.Values.Status | Should -Be 'Resolved'
        $p.Values.ResolvedOn | Should -Be $now
    }

    It 'keeps an open finding open when its check errored' {
        @(Plan @() @(E 7 'SAC-LOG-03' 'Open') @(C 'SAC-LOG-03' 'Errored')).Count | Should -Be 0
    }

    It 'retires an open finding whose rule left the rule set' {
        $p = Plan @() @(E 7 'SAC-TI-02' 'Open') @(C 'SAC-LOG-03' 'Passed')
        $p.Action | Should -Be 'Retire'
        $p.Values.Status | Should -Be 'Retired'
    }

    It 'leaves resolved and retired items alone' {
        @(Plan @() @((E 7 'SAC-LOG-03' 'Resolved'), (E 8 'SAC-LOG-07' 'Retired')) @(C 'SAC-LOG-03' 'Passed')).Count | Should -Be 0
    }

    It 'resolves on absence when the snapshot has no per-check outcomes' {
        (Plan @() @(E 7 'SAC-LOG-03' 'Open') $null).Action | Should -Be 'Resolve'
    }

    It 'resolves nothing when the snapshot has no gap analysis' {
        @(Plan @() @(E 7 'SAC-LOG-03' 'Open') $null $false).Count | Should -Be 0
    }
}

Describe 'Get-NavigationPlan' {
    BeforeAll {
        $sections = @(
            [pscustomobject]@{ num = 25; page = 'sac-25-mitre'; title = 'MITRE'; family = 'Detection' }
            [pscustomobject]@{ num = 20; page = 'sac-20-rules'; title = 'Rules'; family = 'Detection' }
            [pscustomobject]@{ num = 0; page = 'sac-00-overview'; title = 'Overview'; family = 'Overview' }
            [pscustomobject]@{ num = 84; page = 'sac-84-cost'; title = 'Cost'; family = 'Cost & access' }
        )
        $script:nav = Get-NavigationPlan -Sections $sections -ExistingPages @('sac-25-mitre', 'sac-20-rules', 'sac-00-overview') `
            -FamilyOrder (Get-SectionFamilyOrder) -DashboardPage 'Dashboard' -FindingsListUrl 'Lists/SentinelFindings'
    }
    It 'starts with the dashboard and ends with the findings list' {
        $nav.Nodes[0].title | Should -Be 'Dashboard'
        $nav.Nodes[0].url | Should -Be '~site/SitePages/Dashboard.aspx'
        $nav.Nodes[-1].url | Should -Be '~site/Lists/SentinelFindings/AllItems.aspx'
    }
    It 'groups pages under families in display order, sorted by section number' {
        @($nav.Nodes | ForEach-Object title) | Should -Be @('Dashboard', 'Overview', 'Detection', 'Findings')
        @(($nav.Nodes | Where-Object title -eq 'Detection').children | ForEach-Object title) | Should -Be @('Rules', 'MITRE')
    }
    It 'leaves out pages that do not exist and families left empty' {
        $nav.Nodes.title | Should -Not -Contain 'Cost & access'
    }
    It 'gives family headings no URL' { ($nav.Nodes | Where-Object title -eq 'Detection').url | Should -BeNullOrEmpty }
    It 'produces a signature that matches the same tree read back from SharePoint' {
        $readBack = @(
            [pscustomobject]@{ Title = 'Dashboard'; Url = '/sites/isoc/SitePages/Dashboard.aspx'; Children = @() }
            [pscustomobject]@{ Title = 'Overview'; Url = 'http://linkless.header/'; Children = @([pscustomobject]@{ Title = 'Overview'; Url = 'https://contoso.sharepoint.com/sites/isoc/SitePages/sac-00-overview.aspx'; Children = @() }) }
            [pscustomobject]@{ Title = 'Detection'; Url = 'http://linkless.header/'; Children = @(
                    [pscustomobject]@{ Title = 'Rules'; Url = '/sites/isoc/SitePages/sac-20-rules.aspx'; Children = @() }
                    [pscustomobject]@{ Title = 'MITRE'; Url = '/sites/isoc/SitePages/sac-25-mitre.aspx'; Children = @() }) }
            [pscustomobject]@{ Title = 'Findings'; Url = '/sites/isoc/Lists/SentinelFindings/AllItems.aspx'; Children = @() }
        )
        $tree = ConvertTo-SacNavigationTree -Nodes $readBack -WebServerRelativeUrl '/sites/isoc'
        Get-NavigationSignature -Nodes $tree | Should -Be $nav.Signature
    }
}

Describe 'Get-NavigationPlan with the Assessment family' {
    BeforeAll {
        $sections = @(
            [pscustomobject]@{ num = 91; page = 'sac-91-maturity'; title = 'Maturity Assessment'; family = 'Assessment' }
            [pscustomobject]@{ num = 90; page = 'sac-90-gaps'; title = 'Gap Analysis'; family = 'Assessment' }
            [pscustomobject]@{ num = 99; page = 'sac-99-references'; title = 'References'; family = 'References' }
        )
        $script:navA = Get-NavigationPlan -Sections $sections -ExistingPages @('sac-91-maturity', 'sac-90-gaps', 'sac-99-references') `
            -FamilyOrder (Get-SectionFamilyOrder) -DashboardPage 'Dashboard' -FindingsListUrl 'Lists/SentinelFindings'
    }
    It 'puts the gap analysis, the maturity assessment and the findings list under one Assessment heading' {
        @($navA.Nodes | ForEach-Object title) | Should -Be @('Dashboard', 'Assessment', 'References')
        $assessment = $navA.Nodes | Where-Object title -eq 'Assessment'
        @($assessment.children | ForEach-Object title) | Should -Be @('Gap Analysis', 'Maturity Assessment', 'Findings list')
        $assessment.children[-1].url | Should -Be '~site/Lists/SentinelFindings/AllItems.aspx'
    }
    It 'adds no separate Findings node when the list sits under Assessment' {
        @($navA.Nodes | Where-Object { $_.url -eq '~site/Lists/SentinelFindings/AllItems.aspx' }).Count | Should -Be 0
    }
}

Describe 'Get-AssetPrunePlan' {
    It 'returns only files the bundle no longer uses' {
        Get-AssetPrunePlan -DesiredFiles @('a.png', 'b.png') -ExistingFiles @('B.PNG', 'c.png', 'a.png') | Should -Be @('c.png')
    }
}

Describe 'SharePoint helpers' {
    It 'resolves ~site/ against the web URL' {
        Resolve-SacSiteUrl -Text '<a href="~site/SitePages/x.aspx">' -WebServerRelativeUrl '/sites/isoc/' | Should -Be '<a href="/sites/isoc/SitePages/x.aspx">'
    }

    It 'reads the product id and version from an .sppkg' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) "sppkg-$(New-Guid)"
        New-Item -ItemType Directory -Path $dir | Out-Null
        try {
            $src = Join-Path $dir 'src'; New-Item -ItemType Directory -Path $src | Out-Null
            Set-Content -Path (Join-Path $src 'AppManifest.xml') -Value '<?xml version="1.0" encoding="utf-8"?><App xmlns="http://schemas.microsoft.com/sharepoint/2012/app/manifest" Name="isoc-blueprint" ProductID="{7F7EB9C2-A720-45F1-AB47-7772DA011E1D}" Version="1.1.0.0"><Properties><Title>isoc-blueprint-client-side-solution</Title></Properties></App>'
            $pkg = Join-Path $dir 'test.sppkg'
            Compress-Archive -Path (Join-Path $src '*') -DestinationPath "$pkg.zip"
            Move-Item "$pkg.zip" $pkg
            $info = Get-SacAppPackageInfo -Path $pkg
            $info.ProductId | Should -Be '7f7eb9c2-a720-45f1-ab47-7772da011e1d'
            $info.Version | Should -Be '1.1.0.0'
            $info.Title | Should -Be 'isoc-blueprint-client-side-solution'
        }
        finally { Remove-Item $dir -Recurse -Force }
    }
}

Describe 'Web part package' {

    BeforeAll {
        $script:wp = Join-Path $repoRoot 'Modules/iSOCBlueprint/WebParts'
        # SPFx config and manifests allow // comments, which ConvertFrom-Json does not.
        function Read-Jsonc([string] $Path) {
            (Get-Content -LiteralPath $Path -Raw) -replace '(?m)^\s*//.*$', '' -replace '(?m)\s+//[^"\r\n]*$', '' | ConvertFrom-Json
        }
        $script:bundled = @((Read-Jsonc (Join-Path $wp 'config/config.json')).bundles.PSObject.Properties.Value |
                ForEach-Object { $_.components })
    }

    It 'carries one version in package.json, its lock file and the solution' {
        $version = (Get-Content (Join-Path $wp 'package.json') -Raw | ConvertFrom-Json).version
        $lock = Get-Content (Join-Path $wp 'package-lock.json') -Raw | ConvertFrom-Json -AsHashtable
        $lock.version | Should -Be $version
        $lock.packages[''].version | Should -Be $version
        $solution = (Read-Jsonc (Join-Path $wp 'config/package-solution.json')).solution
        $solution.version | Should -Be "$version.0"
        @($solution.features)[0].version | Should -Be "$version.0"
    }

    It 'bundles every web part from its source and manifest' {
        $bundled.Count | Should -BeGreaterOrEqual 2
        foreach ($c in $bundled) {
            Test-Path (Join-Path $wp $c.manifest) | Should -BeTrue -Because $c.manifest
            $source = ($c.entrypoint -replace '^\./lib/', 'src/') -replace '\.js$', '.ts'
            Test-Path (Join-Path $wp $source) | Should -BeTrue -Because $source
        }
    }

    It 'declares the component ids the publisher looks for, without custom script' {
        $manifests = @($bundled | ForEach-Object { Read-Jsonc (Join-Path $wp $_.manifest) })
        $ids = @($manifests | ForEach-Object { ([string]$_.id).ToLowerInvariant() })
        $ids | Should -Contain $script:SacWebPartComponentId
        $ids | Should -Contain $script:SacChartWebPartComponentId
        $manifests | ForEach-Object { $_.requiresCustomScript | Should -BeFalse -Because $_.alias }
    }
}

Describe 'Add-SacMaturityHistoryEntry' {

    BeforeAll {
        function New-HistoryEntry([string]$Built, [double]$Score) {
            @{ publishedUtc = "$Built"; bundleBuiltUtc = $Built; targetLevel = 3; overall = @{ score = $Score; level = [int][math]::Floor($Score) }; areas = @() }
        }
    }

    It 'appends a new entry to an empty history' {
        $h = Add-SacMaturityHistoryEntry -History @{ entries = @() } -Entry (New-HistoryEntry '2026-10-01 06:00 UTC' 1.49)
        @($h.entries).Count | Should -Be 1
        $h.entries[0].overall.score | Should -Be 1.49
    }

    It 'keeps older entries first and the new one last' {
        $h = @{ entries = @((New-HistoryEntry '2026-10-01 06:00 UTC' 1.49), (New-HistoryEntry '2026-10-02 06:00 UTC' 1.6)) }
        $h2 = Add-SacMaturityHistoryEntry -History $h -Entry (New-HistoryEntry '2026-10-03 06:00 UTC' 1.8)
        @($h2.entries | ForEach-Object { $_.bundleBuiltUtc }) | Should -Be @('2026-10-01 06:00 UTC', '2026-10-02 06:00 UTC', '2026-10-03 06:00 UTC')
        @($h.entries).Count | Should -Be 2 -Because 'the input is not changed'
    }

    It 'replaces the entry for a bundle that is published again' {
        $h = @{ entries = @((New-HistoryEntry '2026-10-01 06:00 UTC' 1.49), (New-HistoryEntry '2026-10-02 06:00 UTC' 1.6)) }
        $h2 = Add-SacMaturityHistoryEntry -History $h -Entry (New-HistoryEntry '2026-10-02 06:00 UTC' 1.65)
        @($h2.entries).Count | Should -Be 2
        $h2.entries[-1].overall.score | Should -Be 1.65
    }

    It 'drops the oldest entries past the cap' {
        $h = @{ entries = @(1..5 | ForEach-Object { New-HistoryEntry "2026-10-0$_ 06:00 UTC" $_ }) }
        $h2 = Add-SacMaturityHistoryEntry -History $h -Entry (New-HistoryEntry '2026-10-06 06:00 UTC' 6) -MaxEntries 3
        @($h2.entries | ForEach-Object { $_.overall.score }) | Should -Be @(4, 5, 6)
    }
}

Describe 'Test-SacFullWidthProperty' {
    It 'is true only when isFullWidth is the boolean true' {
        Test-SacFullWidthProperty -PropertiesJson '{"fileRelativeUrl":"x","isFullWidth":true}' | Should -BeTrue
        Test-SacFullWidthProperty -PropertiesJson '{"fileRelativeUrl":"x","isFullWidth":false}' | Should -BeFalse
        Test-SacFullWidthProperty -PropertiesJson '{"fileRelativeUrl":"x"}' | Should -BeFalse
    }
    It 'is false for empty or unreadable JSON' {
        Test-SacFullWidthProperty -PropertiesJson '' | Should -BeFalse
        Test-SacFullWidthProperty -PropertiesJson '{not json' | Should -BeFalse
    }
}

Describe 'Publish-SacDashboardPage' {

    BeforeAll {
        $script:pnpStubs = Install-PnPStub ([ordered]@{
            'Get-PnPPage'                    = '$Identity'
            'Get-PnPPageComponent'           = '$Page'
            'Add-PnPPage'                    = '$Name, $LayoutType, $Title'
            'Set-PnPPage'                    = '$Identity, $HeaderType, $Title, [switch] $Publish'
            'Set-PnPPageWebPart'             = '$Page, $Identity, $PropertiesJson'
            'Add-PnPPageSection'             = '$Page, $SectionTemplate, $Order'
            'Get-PnPAvailablePageComponents' = '$Page'
            'Add-PnPPageWebPart'             = '$Page, $Component, $WebPartProperties, $Section, $Column'
            'Set-PnPHomePage'                = '$RootFolderRelativeUrl'
            'Remove-PnPPage'                 = '$Identity, [switch] $Recycle, [switch] $Force'
        })
        # SharePoint can return the component id in braces and upper case.
        $script:dashboardComponent = [pscustomobject]@{ Id = '{A2FD5AA3-01C5-431E-8C98-66F76C89803A}'; Name = 'IsocBlueprintWebPart' }
    }
    AfterAll { Remove-PnPStub $script:pnpStubs }
    BeforeEach {
        Mock Get-PnPPageComponent { }
        Mock Add-PnPPage { }
        Mock Set-PnPPage { }
        Mock Set-PnPPageWebPart { }
        Mock Add-PnPPageSection { }
        Mock Add-PnPPageWebPart { }
        Mock Set-PnPHomePage { }
        Mock Remove-PnPPage { }
        Mock Start-Sleep { }
        Mock Write-Host { }
        Mock Get-PnPAvailablePageComponents { $script:dashboardComponent }
    }

    It 'passes the component object, not its id, even when SharePoint returns the id in braces' {
        Mock Get-PnPPage { $null }
        Publish-SacDashboardPage -PageName 'sac-dashboard' -Title 'iSOC Blueprint' -FileRelativeUrl 'BlueprintAssets/dashboard/index.html'
        Should -Invoke Add-PnPPageSection -Times 1 -Exactly -ParameterFilter { $SectionTemplate -eq 'OneColumnFullWidth' }
        Should -Invoke Add-PnPPageWebPart -Times 1 -Exactly -ParameterFilter { [object]::ReferenceEquals($Component, $script:dashboardComponent) -and $Section -eq 1 }
        Should -Invoke Set-PnPHomePage -Times 1 -Exactly
    }

    It 'stores isFullWidth with the web part, so PnP can save the page again later' {
        Mock Get-PnPPage { $null }
        Publish-SacDashboardPage -PageName 'sac-dashboard' -Title 'iSOC Blueprint' -FileRelativeUrl 'BlueprintAssets/dashboard/index.html'
        Should -Invoke Add-PnPPageWebPart -Times 1 -Exactly -ParameterFilter { $WebPartProperties.isFullWidth -eq $true -and $WebPartProperties.fileRelativeUrl -eq 'BlueprintAssets/dashboard/index.html' }
    }

    It 'rebuilds a page whose dashboard web part was placed without isFullWidth' {
        Mock Get-PnPPage { [pscustomobject]@{ Sections = @([pscustomobject]@{ Type = 'OneColumnFullWidth' }) } }
        Mock Get-PnPPageComponent { [pscustomobject]@{ WebPartId = 'a2fd5aa3-01c5-431e-8c98-66f76c89803a'; InstanceId = 'i1'; PropertiesJson = '{"fileRelativeUrl":"BlueprintAssets/dashboard/index.html"}' } }
        Publish-SacDashboardPage -PageName 'sac-dashboard' -Title 'iSOC Blueprint' -FileRelativeUrl 'BlueprintAssets/dashboard/index.html'
        Should -Invoke Remove-PnPPage -Times 1 -Exactly -ParameterFilter { $Identity -eq 'sac-dashboard' -and $Recycle -and $Force }
        Should -Invoke Add-PnPPage -Times 1 -Exactly
        Should -Invoke Add-PnPPageSection -Times 1 -Exactly
        Should -Invoke Add-PnPPageWebPart -Times 1 -Exactly
        Should -Invoke Set-PnPPageWebPart -Times 0 -Exactly
    }

    It 'updates a web part that already carries isFullWidth in place' {
        Mock Get-PnPPage { [pscustomobject]@{ Sections = @([pscustomobject]@{ Type = 'OneColumnFullWidth' }) } }
        Mock Get-PnPPageComponent { [pscustomobject]@{ WebPartId = '{A2FD5AA3-01C5-431E-8C98-66F76C89803A}'; InstanceId = 'i1'; PropertiesJson = '{"fileRelativeUrl":"old.html","isFullWidth":true}' } }
        Publish-SacDashboardPage -PageName 'sac-dashboard' -Title 'iSOC Blueprint' -FileRelativeUrl 'BlueprintAssets/dashboard/index.html'
        Should -Invoke Remove-PnPPage -Times 0 -Exactly
        Should -Invoke Add-PnPPageWebPart -Times 0 -Exactly
        Should -Invoke Set-PnPPageWebPart -Times 1 -Exactly -ParameterFilter { $Identity -eq 'i1' -and $PropertiesJson -match '"isFullWidth":true' -and $PropertiesJson -match 'BlueprintAssets/dashboard/index.html' }
    }

    It 'reuses the full-width section a failed run left behind instead of adding another' {
        Mock Get-PnPPage { [pscustomobject]@{ Sections = @([pscustomobject]@{ Type = 'OneColumn' }, [pscustomobject]@{ Type = 'OneColumnFullWidth' }) } }
        Publish-SacDashboardPage -PageName 'sac-dashboard' -Title 'iSOC Blueprint' -FileRelativeUrl 'BlueprintAssets/dashboard/index.html'
        Should -Invoke Add-PnPPageSection -Times 0 -Exactly
        Should -Invoke Add-PnPPageWebPart -Times 1 -Exactly -ParameterFilter { $Section -eq 2 }
    }

    It 'says the web part is missing, without adding an empty one, when it never appears' {
        Mock Get-PnPPage { $null }
        Mock Get-PnPAvailablePageComponents { [pscustomobject]@{ Id = '{11111111-2222-3333-4444-555555555555}' } }
        { Publish-SacDashboardPage -PageName 'sac-dashboard' -Title 'iSOC Blueprint' -FileRelativeUrl 'x' -WebPartWaitSeconds 0 } |
            Should -Throw '*not in the site*component list*'
        Should -Invoke Add-PnPPageWebPart -Times 0 -Exactly
    }
}

Describe 'Read-SacStateText' {

    BeforeAll { $script:pnpStubs = Install-PnPStub ([ordered]@{ 'Get-PnPFile' = '$Url, [switch] $AsString' }) }
    AfterAll { Remove-PnPStub $script:pnpStubs }

    It 'reads the Blueprint Assets library first' {
        Mock Get-PnPFile { if ($Url -like 'BlueprintAssets/*') { '{"new":1}' } else { '{"old":1}' } }
        Read-SacStateText -FileName 'publish-state.json' | Should -Be '{"new":1}'
    }

    It 'falls back to the library''s pre-Blueprint name' {
        Mock Get-PnPFile { if ($Url -like 'BlueprintAssets/*') { throw 'File Not Found' } else { '{"old":1}' } }
        Read-SacStateText -FileName 'publish-state.json' | Should -Be '{"old":1}'
        Should -Invoke Get-PnPFile -Times 1 -Exactly -ParameterFilter { $Url -eq 'DocumenterAssets/_state/publish-state.json' }
    }

    It 'returns nothing when neither library has the file' {
        Mock Get-PnPFile { throw 'File Not Found' }
        Read-SacStateText -FileName 'maturity-history.json' | Should -BeNullOrEmpty
    }
}

Describe 'Get-SacCatalogApp' {

    BeforeAll { $script:pnpStubs = Install-PnPStub ([ordered]@{ 'Invoke-PnPSPRestMethod' = '$Method, $Url' }) }
    AfterAll { Remove-PnPStub $script:pnpStubs }

    It 'reads the catalog item id, product id and validity, without braces and in lower case' {
        Mock Invoke-PnPSPRestMethod {
            [pscustomobject]@{ value = @(
                    [pscustomobject]@{ ID = '{AAAA0000-0000-0000-0000-000000000001}'; ProductId = '{7F7EB9C2-A720-45F1-AB47-7772DA011E1D}'; Title = 'isoc-blueprint-client-side-solution'; AppCatalogVersion = '1.2.0.0'; CanUpgrade = $false; IsValidAppPackage = $false; ErrorMessage = 'duplicate' }
                ) }
        }
        $app = @(Get-SacCatalogApp)[0]
        $app.Id | Should -Be 'aaaa0000-0000-0000-0000-000000000001'
        $app.ProductId | Should -Be '7f7eb9c2-a720-45f1-ab47-7772da011e1d'
        $app.Valid | Should -BeFalse
        $app.Error | Should -Be 'duplicate'
    }

    It 'leaves the product id empty and treats the package as valid when the response omits them' {
        Mock Invoke-PnPSPRestMethod { [pscustomobject]@{ value = @([pscustomobject]@{ ID = 'b'; Title = 't'; AppCatalogVersion = '1.0.0.0' }) } }
        $app = @(Get-SacCatalogApp)[0]
        $app.ProductId | Should -Be ''
        $app.Valid | Should -BeTrue
    }

    It 'returns an empty list for an empty catalog' {
        Mock Invoke-PnPSPRestMethod { [pscustomobject]@{ value = @() } }
        @(Get-SacCatalogApp).Count | Should -Be 0
    }
}

Describe 'Publish-SacSectionPage' {

    BeforeAll {
        $script:pnpStubs = Install-PnPStub ([ordered]@{ 'Get-PnPPage' = '$Identity'; 'Add-PnPPage' = '$Name, $LayoutType, $Title' })
        # A stand-in for the PnP Core page object: records the controls it is
        # given and counts component lookups.
        function New-FakePage([object[]] $Components) {
            $page = [pscustomobject]@{
                PageTitle  = ''
                Sections   = @([pscustomobject]@{ Columns = @('column') })
                Components = $Components
                Lookups    = 0
                Controls   = [System.Collections.Generic.List[object]]::new()
                Published  = $false
            }
            $page | Add-Member ScriptMethod ClearPage { $this.Controls.Clear() }
            $page | Add-Member ScriptMethod AddSection { param($Template, $Order, $Zone) }
            $page | Add-Member ScriptMethod AvailablePageComponents { param($Name) $this.Lookups++; $this.Components }
            $page | Add-Member ScriptMethod NewWebPart { param($Component) [pscustomobject]@{ Kind = 'webpart'; Component = $Component; PropertiesJson = $null } }
            $page | Add-Member ScriptMethod NewTextPart { param($Html) [pscustomobject]@{ Kind = 'text'; Html = $Html } }
            $page | Add-Member ScriptMethod AddControl { param($Control, $Column, $Order, $Zone) $this.Controls.Add($Control) }
            $page | Add-Member ScriptMethod Save { param($Name) $Name }
            $page | Add-Member ScriptMethod Publish { param($Comment) $this.Published = $true }
            $page
        }
        $script:chartComponent = [pscustomobject]@{ Id = '{4AE8707C-CA6F-40CB-A974-C94D023DE6E5}'; Name = 'IsocBlueprintChartWebPart' }
        $script:pageDoc = [pscustomobject]@{
            name     = 'sac-25-mitre-coverage'
            title    = 'MITRE coverage'
            segments = @(
                [pscustomobject]@{ type = 'html'; html = '<p><a href="~site/SitePages/sac-20-analytics-rules.aspx">Rules</a></p>' }
                [pscustomobject]@{ type = 'chart'; chart = [pscustomobject]@{ kind = 'pie'; title = 'By tactic'; data = [pscustomobject]@{ slices = @([pscustomobject]@{ label = 'Execution'; value = 4 }) } } }
                [pscustomobject]@{ type = 'chart'; chart = [pscustomobject]@{ kind = 'flowchart'; title = 'Flow'; data = [pscustomobject]@{ nodes = @([pscustomobject]@{ id = 'a'; label = 'A'; href = '~site/SitePages/sac-00-overview.aspx' }) } } }
            )
        }
    }
    AfterAll { Remove-PnPStub $script:pnpStubs }

    It 'places every chart as the chart web part, looking the component up once per page' {
        $script:fake = New-FakePage @([pscustomobject]@{ Id = 'other' }, $script:chartComponent)
        Mock Get-PnPPage { $script:fake }
        $native = Publish-SacSectionPage -PageDoc $script:pageDoc -WebServerRelativeUrl '/sites/isoc' -ChartComponentAvailable
        $native | Should -BeTrue
        $fake.Lookups | Should -Be 1
        @($fake.Controls | Where-Object Kind -eq 'webpart').Count | Should -Be 2
        $fake.Controls[1].Component | Should -Be $script:chartComponent
        $fake.Published | Should -BeTrue
    }

    It 'stores the chart as JSON in the chartJson property, with site links resolved' {
        $script:fake = New-FakePage @($script:chartComponent)
        Mock Get-PnPPage { $script:fake }
        Publish-SacSectionPage -PageDoc $script:pageDoc -WebServerRelativeUrl '/sites/isoc' -ChartComponentAvailable | Out-Null
        $pie = ($fake.Controls[1].PropertiesJson | ConvertFrom-Json).chartJson | ConvertFrom-Json
        $pie.kind | Should -Be 'pie'
        $pie.data.slices[0].label | Should -Be 'Execution'
        $flow = ($fake.Controls[2].PropertiesJson | ConvertFrom-Json).chartJson | ConvertFrom-Json
        $flow.data.nodes[0].href | Should -Be '/sites/isoc/SitePages/sac-00-overview.aspx'
        $fake.Controls[0].Html | Should -Match 'href="/sites/isoc/SitePages/sac-20-analytics-rules.aspx"'
    }

    It 'writes charts as tables, and says so, when the chart web part is not available' {
        $script:fake = New-FakePage @($script:chartComponent)
        Mock Get-PnPPage { $script:fake }
        $native = Publish-SacSectionPage -PageDoc $script:pageDoc -WebServerRelativeUrl '/sites/isoc'
        $native | Should -BeFalse
        $fake.Lookups | Should -Be 0
        @($fake.Controls | Where-Object Kind -eq 'webpart').Count | Should -Be 0
        $fake.Controls[1].Html | Should -Match '<td>Execution</td><td>4</td>'
    }

    It 'falls back to tables when the page cannot find the component' {
        $script:fake = New-FakePage @([pscustomobject]@{ Id = 'other' })
        Mock Get-PnPPage { $script:fake }
        Publish-SacSectionPage -PageDoc $script:pageDoc -WebServerRelativeUrl '/sites/isoc' -ChartComponentAvailable | Should -BeFalse
        @($fake.Controls | Where-Object Kind -eq 'text').Count | Should -Be 3
    }

    It 'reports a page with no charts as complete without looking for the component' {
        $script:fake = New-FakePage @()
        Mock Get-PnPPage { $script:fake }
        $doc = [pscustomobject]@{ name = 'sac-00-overview'; title = 'Overview'; segments = @([pscustomobject]@{ type = 'html'; html = '<p>x</p>' }) }
        Publish-SacSectionPage -PageDoc $doc -WebServerRelativeUrl '/sites/isoc' -ChartComponentAvailable | Should -BeTrue
        $fake.Lookups | Should -Be 0
    }
}

Describe 'Test-SacPageComponent and Wait-SacPageComponent' {

    BeforeAll { $script:pnpStubs = Install-PnPStub ([ordered]@{ 'Get-PnPAvailablePageComponents' = '$Page' }) }
    AfterAll { Remove-PnPStub $script:pnpStubs }
    BeforeEach {
        Mock Start-Sleep { }
        Mock Write-Host { }
    }

    It 'finds a component SharePoint lists in braces and upper case, through an existing page' {
        Mock Get-PnPAvailablePageComponents { [pscustomobject]@{ Id = '{4AE8707C-CA6F-40CB-A974-C94D023DE6E5}' } }
        Test-SacPageComponent -ComponentId '4ae8707c-ca6f-40cb-a974-c94d023de6e5' -PageName 'sac-11-sentinel-health' | Should -BeTrue
        Should -Invoke Get-PnPAvailablePageComponents -Times 1 -Exactly -ParameterFilter { $Page -eq 'sac-11-sentinel-health' }
    }

    It 'returns false when the component is not listed, and throws when the lookup fails' {
        Mock Get-PnPAvailablePageComponents { [pscustomobject]@{ Id = 'a2fd5aa3-01c5-431e-8c98-66f76c89803a' } }
        Test-SacPageComponent -ComponentId '4ae8707c-ca6f-40cb-a974-c94d023de6e5' -PageName 'p' | Should -BeFalse
        Mock Get-PnPAvailablePageComponents { throw 'Forbidden' }
        { Test-SacPageComponent -ComponentId '4ae8707c-ca6f-40cb-a974-c94d023de6e5' -PageName 'p' } | Should -Throw '*Forbidden*'
    }

    It 'keeps looking until a freshly deployed component appears' {
        $script:calls = 0
        Mock Get-PnPAvailablePageComponents {
            $script:calls++
            if ($script:calls -ge 3) { [pscustomobject]@{ Id = '4ae8707c-ca6f-40cb-a974-c94d023de6e5' } }
        }
        Wait-SacPageComponent -ComponentId '4ae8707c-ca6f-40cb-a974-c94d023de6e5' -PageName 'p' -WaitSeconds 300 | Should -BeTrue
        Should -Invoke Start-Sleep -Times 2 -Exactly
    }

    It 'shows a failing lookup instead of taking it for a slow deployment' {
        Mock Get-PnPAvailablePageComponents { throw 'The remote server returned an error: (400) Bad Request.' }
        Wait-SacPageComponent -ComponentId '4ae8707c-ca6f-40cb-a974-c94d023de6e5' -PageName 'p' -WaitSeconds 0 | Should -BeFalse
        Should -Invoke Write-Host -Times 1 -ParameterFilter { "$Object" -match 'Could not read the component list through p\.aspx: .*400' }
    }

    It 'looks once and gives up when there is no time to wait' {
        Mock Get-PnPAvailablePageComponents { }
        Wait-SacPageComponent -ComponentId '4ae8707c-ca6f-40cb-a974-c94d023de6e5' -PageName 'p' -WaitSeconds 0 | Should -BeFalse
        Should -Invoke Get-PnPAvailablePageComponents -Times 1 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }
}

Describe 'Invoke-SacCreateList' {

    BeforeAll { $script:pnpStubs = Install-PnPStub ([ordered]@{ 'Get-PnPList' = '$Identity' }) }
    AfterAll { Remove-PnPStub $script:pnpStubs }
    BeforeEach {
        Mock Start-Sleep { }
        Mock Write-Host { }
    }

    It 'returns the list a create call made' {
        Mock Get-PnPList { [pscustomobject]@{ Title = 'Blueprint Assets' } }
        (Invoke-SacCreateList -Url 'BlueprintAssets' -Create { 'created' }).Title | Should -Be 'Blueprint Assets'
    }

    It 'carries on when the create call timed out but the list exists afterwards' {
        $script:looks = 0
        Mock Get-PnPList { $script:looks++; if ($script:looks -ge 2) { [pscustomobject]@{ Title = 'Blueprint Assets' } } }
        $list = Invoke-SacCreateList -Url 'BlueprintAssets' -Create { throw 'The request was canceled due to the configured HttpClient.Timeout of 100 seconds elapsing.' }
        $list.Title | Should -Be 'Blueprint Assets'
        Should -Invoke Write-Host -Times 1 -ParameterFilter { "$Object" -match 'but it exists' }
    }

    It 'raises the original error when the list never appears' {
        Mock Get-PnPList { }
        { Invoke-SacCreateList -Url 'BlueprintAssets' -Create { throw 'Access denied' } } | Should -Throw '*Access denied*'
        Should -Invoke Start-Sleep -Times 6 -Exactly
    }
}

Describe 'Publish-SacAppPackage' {

    BeforeAll {
        $script:pnpStubs = Install-PnPStub ([ordered]@{
            'Add-PnPApp'    = '$Path, $Scope, [switch] $Overwrite, [switch] $Publish, [switch] $SkipFeatureDeployment'
            'Remove-PnPApp' = '$Identity, $Scope'
        })
        $script:productId = '7f7eb9c2-a720-45f1-ab47-7772da011e1d'
        function New-CatalogApp([string] $Id, [string] $Title, [string] $Version, [bool] $Valid = $true, [string] $ProductId = $script:productId) {
            [pscustomobject]@{ Id = $Id; ProductId = $ProductId; Title = $Title; Version = $Version; CanUpgrade = $false; Valid = $Valid; Error = $(if ($Valid) { '' } else { 'A package with this id already exists' }) }
        }
        $script:oldApp = New-CatalogApp 'old-item' 'old-name-client-side-solution' '1.1.0.0'
        $script:failedNew = New-CatalogApp 'new-item' 'isoc-blueprint-client-side-solution' '1.2.0.0' -Valid $false
    }
    AfterAll { Remove-PnPStub $script:pnpStubs }
    BeforeEach {
        Mock Get-SacAppPackageInfo { [pscustomobject]@{ ProductId = $script:productId; Version = '1.2.0.0'; Title = 'isoc-blueprint-client-side-solution' } }
        Mock Add-PnPApp { }
        Mock Remove-PnPApp { $script:removed = $true }
        Mock Write-Host { }
        $script:removed = $false
    }

    It 'removes the package deployed under the old solution name, then adds the new one' {
        # A renamed solution: the old package deployed and a rejected upload
        # of the new one next to it.
        Mock Get-SacCatalogApp { if ($script:removed) { $script:failedNew } else { $script:oldApp; $script:failedNew } }
        Publish-SacAppPackage -Path 'isoc-blueprint.sppkg' | Should -Be '1.2.0.0'
        Should -Invoke Remove-PnPApp -Times 1 -Exactly -ParameterFilter { $Identity -eq 'old-item' -and $Scope -eq 'Site' }
        Should -Invoke Add-PnPApp -Times 1 -Exactly
    }

    It 'matches the package by title when the catalog reports no product id' {
        $noProduct = New-CatalogApp 'new-item' 'isoc-blueprint-client-side-solution' '1.2.0.0' -ProductId ''
        Mock Get-SacCatalogApp { $noProduct }
        Publish-SacAppPackage -Path 'isoc-blueprint.sppkg' | Should -Be '1.2.0.0'
        Should -Invoke Add-PnPApp -Times 0 -Exactly -Because 'the same version is already deployed'
        Should -Invoke Remove-PnPApp -Times 0 -Exactly
    }

    It 'stops with a clear message when the old package cannot be removed' {
        Mock Get-SacCatalogApp { $script:oldApp }
        { Publish-SacAppPackage -Path 'isoc-blueprint.sppkg' } | Should -Throw '*remove it by hand*'
        Should -Invoke Add-PnPApp -Times 0 -Exactly
    }

    It 'upgrades the same solution in place without removing anything' {
        Mock Get-SacCatalogApp { New-CatalogApp 'new-item' 'isoc-blueprint-client-side-solution' '1.1.0.0' }
        Publish-SacAppPackage -Path 'isoc-blueprint.sppkg' | Out-Null
        Should -Invoke Remove-PnPApp -Times 0 -Exactly
        Should -Invoke Add-PnPApp -Times 1 -Exactly
    }

    It 'does nothing when the same version is already deployed' {
        Mock Get-SacCatalogApp { New-CatalogApp 'new-item' 'isoc-blueprint-client-side-solution' '1.2.0.0' }
        Publish-SacAppPackage -Path 'isoc-blueprint.sppkg' | Should -Be '1.2.0.0'
        Should -Invoke Add-PnPApp -Times 0 -Exactly
        Should -Invoke Remove-PnPApp -Times 0 -Exactly
    }

    It 'ignores other solutions in the catalog' {
        Mock Get-SacCatalogApp { New-CatalogApp 'other' 'someone-elses-solution' '3.0.0.0' -ProductId '11111111-2222-3333-4444-555555555555' }
        Publish-SacAppPackage -Path 'isoc-blueprint.sppkg' | Out-Null
        Should -Invoke Remove-PnPApp -Times 0 -Exactly
        Should -Invoke Add-PnPApp -Times 1 -Exactly
    }
}

Describe 'Site navigation' {

    BeforeAll {
        $script:pnpStubs = Install-PnPStub ([ordered]@{
            'Get-PnPNavigationNode'    = '$Location, $Id, [switch] $Tree'
            'Remove-PnPNavigationNode' = '$Identity, [switch] $Force'
            'Add-PnPNavigationNode'    = '$Location, $Title, $Url, $Parent'
        })
        $script:web = '/sites/isoc-blueprint'
    }
    AfterAll { Remove-PnPStub $script:pnpStubs }

    Context 'reading it' {
        BeforeAll {
            Mock Get-PnPNavigationNode -ParameterFilter { $Location } {
                [pscustomobject]@{ Id = 1; Title = 'Home'; Url = '/sites/isoc-blueprint/SitePages/sac-dashboard.aspx' }
                [pscustomobject]@{ Id = 2; Title = 'Detection'; Url = 'http://linkless.header/' }
            }
            Mock Get-PnPNavigationNode -ParameterFilter { $Id -eq 1 } { [pscustomobject]@{ Id = 1; Title = 'Home'; Url = 'https://contoso.sharepoint.com/sites/isoc-blueprint/SitePages/sac-dashboard.aspx'; Children = @() } }
            Mock Get-PnPNavigationNode -ParameterFilter { $Id -eq 2 } {
                [pscustomobject]@{ Id = 2; Title = 'Detection'; Url = 'http://linkless.header/'; Children = @(
                        [pscustomobject]@{ Title = 'Analytics rules'; Url = '/sites/isoc-blueprint/SitePages/sac-20-analytics-rules.aspx' }
                    ) }
            }
            $script:navRead = Get-SacNavigation -WebServerRelativeUrl $script:web
        }
        It 'reads nodes, not the printed -Tree text' { Should -Invoke Get-PnPNavigationNode -Scope Context -Times 0 -ParameterFilter { $Tree.IsPresent } }
        It 'loads each top-level node by id to get its children' { Should -Invoke Get-PnPNavigationNode -Scope Context -Times 2 -Exactly -ParameterFilter { $Id } }
        It 'returns the planner shape with site-relative links and headings' {
            @($script:navRead).Count | Should -Be 2
            $script:navRead[0].title | Should -Be 'Home'
            $script:navRead[0].url | Should -Be '~site/SitePages/sac-dashboard.aspx'
            $script:navRead[1].url | Should -BeNullOrEmpty
            $script:navRead[1].children[0].title | Should -Be 'Analytics rules'
            $script:navRead[1].children[0].url | Should -Be '~site/SitePages/sac-20-analytics-rules.aspx'
        }
    }

    Context 'replacing it' {
        BeforeAll {
            Mock Get-PnPNavigationNode { [pscustomobject]@{ Id = 7; Title = 'Old' }; [pscustomobject]@{ Id = 8; Title = 'Older' } }
            Mock Remove-PnPNavigationNode { }
            Mock Add-PnPNavigationNode { [pscustomobject]@{ Id = 100 } }
            $nodes = @(
                [ordered]@{ title = 'Home'; url = '~site/SitePages/sac-dashboard.aspx'; children = @() },
                [ordered]@{ title = 'Detection'; url = $null; children = @([ordered]@{ title = 'Analytics rules'; url = '~site/SitePages/sac-20-analytics-rules.aspx' }) }
            )
            Set-SacNavigation -Nodes $nodes -WebServerRelativeUrl $script:web
        }
        It 'removes the existing top-level nodes one by one, by id, without prompting' {
            Should -Invoke Remove-PnPNavigationNode -Scope Context -Times 2 -Exactly -ParameterFilter { $Identity -in 7, 8 -and $Force }
        }
        It 'adds headings as linkless nodes and resolves page links' {
            Should -Invoke Add-PnPNavigationNode -Scope Context -Times 1 -Exactly -ParameterFilter { $Title -eq 'Detection' -and $Url -eq 'http://linkless.header/' }
            Should -Invoke Add-PnPNavigationNode -Scope Context -Times 1 -Exactly -ParameterFilter { $Title -eq 'Home' -and $Url -eq '/sites/isoc-blueprint/SitePages/sac-dashboard.aspx' }
        }
        It 'attaches children to the node it just added' {
            Should -Invoke Add-PnPNavigationNode -Scope Context -Times 1 -Exactly -ParameterFilter { $Title -eq 'Analytics rules' -and $Parent -eq 100 }
        }
    }
}

Describe 'Build-SentinelDocsSite against the fixture' {

    BeforeAll {
        $fixtureRaw = Join-Path $repoRoot 'Tests/iSOCBlueprint/Fixtures/sample/_raw'
        $script:outDir = Join-Path ([System.IO.Path]::GetTempPath()) "sharepoint-site-test-$(New-Guid)"
        $script:ws = Join-Path $script:outDir 'law-sentinel-test'
        New-Item -ItemType Directory -Path (Join-Path $ws '_raw') -Force | Out-Null
        Copy-Item -Path (Join-Path $fixtureRaw '*.json') -Destination (Join-Path $ws '_raw')

        # A finding whose evidence tries to close the embedded JSON block.
        $gapPath = Join-Path $ws '_raw/gap-analysis.json'
        $gap = @(Get-Content $gapPath -Raw | ConvertFrom-Json)
        $gap[0].Evidence = 'evil </script><script>alert(1)</script>'
        ConvertTo-Json -InputObject $gap -Depth 10 | Set-Content $gapPath
        # Per-check outcomes, as the current collector writes them.
        @(@{ Id = $gap[0].Id; Check = 'x'; Outcome = 'Fired'; Message = $null }) | ConvertTo-Json -AsArray | Set-Content (Join-Path $ws '_raw/gap-checks.json')

        & (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Convert-SentinelInventoryToMarkdown.ps1') `
            -WorkspaceName 'law-sentinel-test' -InputRoot $ws -OutputRoot $ws `
            -ResourcesRoot (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Resources') -InformationAction SilentlyContinue *> $null

        $script:mdFiles = @(Get-ChildItem $ws -Filter '*.md' | Where-Object { $_.Name -ne 'index.md' -and $_.BaseName -match '^\d+-' })
        $script:bundle = & (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1') -Source $ws -SkipWhatsNew 6> $null
        $script:site = Get-Content (Join-Path $bundle 'site.json') -Raw | ConvertFrom-Json
        $script:findingsDoc = Get-Content (Join-Path $bundle 'findings.json') -Raw | ConvertFrom-Json
        $script:html = Get-Content (Join-Path $bundle 'index.html') -Raw
    }

    AfterAll {
        if ($script:outDir -and (Test-Path $script:outDir)) { Remove-Item $script:outDir -Recurse -Force }
    }

    It 'writes the bundle into <Source>/sharepoint' {
        $bundle | Should -Be (Join-Path $ws 'sharepoint')
        foreach ($f in 'index.html', 'model.json', 'site.json', 'findings.json') { Join-Path $bundle $f | Should -Exist }
    }

    It 'gives every page the same hash when built again in a fresh process' {
        # .NET randomises string hashing per process, so anything that leans
        # on hashtable order (a tie in a sort, an unordered dictionary in a
        # page) changes a page's hash between runs and republishes it.
        $again = Join-Path $outDir 'again/law-sentinel-test'
        New-Item -ItemType Directory -Path $again -Force | Out-Null
        Copy-Item -Path (Join-Path $ws '_raw') -Destination $again -Recurse
        $render = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Convert-SentinelInventoryToMarkdown.ps1'
        $build = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1'
        $resources = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Resources'
        $command = "& '$render' -WorkspaceName 'law-sentinel-test' -InputRoot '$again' -OutputRoot '$again' -ResourcesRoot '$resources' *> `$null; " +
            "& '$build' -Source '$again' -SkipWhatsNew *> `$null"
        & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command $command
        $other = Get-Content (Join-Path $again 'sharepoint/site.json') -Raw | ConvertFrom-Json
        @($other.sections).Count | Should -Be @($site.sections).Count
        foreach ($s in $site.sections) {
            ($other.sections | Where-Object page -eq $s.page).hash | Should -Be $s.hash -Because $s.page
        }
    }

    It 'writes one page per section file' {
        $site.sections.Count | Should -Be $mdFiles.Count
        foreach ($s in $site.sections) { Join-Path $bundle "pages/$($s.page).json" | Should -Exist }
    }

    It 'gives every section a known family and a hash' {
        foreach ($s in $site.sections) {
            $s.family | Should -Not -Be 'Other'
            $s.hash | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'places every chart in the section model as a chart segment' {
        $chartBlocks = 0
        foreach ($f in Get-ChildItem (Join-Path $ws 'sections') -Filter '*.json' | Where-Object Name -ne 'index.json') {
            $chartBlocks += ([regex]::Matches((Get-Content $f.FullName -Raw), '"type":\s*"chart"')).Count
        }
        $segments = 0
        foreach ($p in Get-ChildItem (Join-Path $bundle 'pages') -Filter '*.json') {
            $segments += @((Get-Content $p.FullName -Raw | ConvertFrom-Json).segments | Where-Object type -eq 'chart').Count
        }
        $segments | Should -Be $chartBlocks
        $segments | Should -BeGreaterThan 0
        @($site.diagrams).Count | Should -Be 0
    }

    It 'builds the same pages with no Markdown, and from Markdown alone for an older snapshot' {
        # Section model only: delete every Markdown file first.
        $jsonOnly = Join-Path $outDir 'json-only/law-sentinel-test'
        New-Item -ItemType Directory -Path $jsonOnly -Force | Out-Null
        Copy-Item -Path (Join-Path $ws '_raw'), (Join-Path $ws 'sections') -Destination $jsonOnly -Recurse
        $b1 = & (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1') -Source $jsonOnly -SkipWhatsNew 6> $null
        # Markdown only: an artefact rendered before the section model.
        $mdOnly = Join-Path $outDir 'md-only/law-sentinel-test'
        New-Item -ItemType Directory -Path $mdOnly -Force | Out-Null
        Copy-Item -Path (Join-Path $ws '_raw') -Destination $mdOnly -Recurse
        Copy-Item -Path (Join-Path $ws '*.md') -Destination $mdOnly
        $b2 = & (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1') -Source $mdOnly -SkipWhatsNew 6> $null

        $hashes = { param($b) (Get-Content (Join-Path $b 'site.json') -Raw | ConvertFrom-Json).sections | ForEach-Object { "$($_.page)=$($_.hash)" } }
        $h0 = @(& $hashes $bundle); $h1 = @(& $hashes $b1); $h2 = @(& $hashes $b2)
        $h1 | Should -Be $h0
        $h2 | Should -Be $h0
    }

    It 'never leaks Mermaid source into page HTML' {
        foreach ($p in Get-ChildItem (Join-Path $bundle 'pages') -Filter '*.json') {
            (Get-Content $p.FullName -Raw) | Should -Not -Match 'class=\\"mermaid\\"'
        }
    }

    It 'embeds the model so data cannot close the script block' {
        # The template has exactly two closing script tags (model block and
        # main script); the hostile evidence must not add a third.
        ([regex]::Matches($html, '</script>')).Count | Should -Be 2
        $html | Should -Match '\\u003c/script\\u003e'
    }

    It 'carries the product name into the dashboard model and descriptor' {
        $site.product | Should -Be 'iSOC Blueprint'
        $html | Should -Match '"product":"iSOC Blueprint"'
    }

    It 'carries the estate, maturity, effectiveness and opportunity models' {
        $model = Get-Content (Join-Path $bundle 'model.json') -Raw | ConvertFrom-Json
        $model.estate.rings.ingestion.max | Should -BeGreaterThan 0
        $model.estate.rings.incidents.pct | Should -Be 80
        @($model.estate.sources).Count | Should -BeGreaterThan 0
        $model.estate.uncoveredGb | Should -BeGreaterThan 0
        # every table receiving data travels with the model so the flow can list them on click
        @($model.estate.tables).Count | Should -BeGreaterThan 0
        # first-party product alerts per family, Sentinel's own rules excluded
        ($model.estate.productAlerts | Where-Object family -eq 'Entra ID / Identity').alerts | Should -Be 40
        ($model.estate.productAlerts | Where-Object product -match 'Sentinel') | Should -BeNullOrEmpty
        $model.estate.rings.detection.label | Should -Match 'Sentinel rule or custom detection'
        # Defender XDR custom detections from the Graph capture
        $model.estate.customDetections.captured | Should -BeTrue
        $model.estate.customDetections.total | Should -Be 2
        $model.estate.customDetections.enabled | Should -Be 1
        ($model.estate.tables | Where-Object table -eq 'SigninLogs').covered | Should -BeTrue
        ($model.estate.tables | Where-Object table -eq 'SigninLogs').rules | Should -BeGreaterThan 0
        ($model.estate.tables | Where-Object table -eq 'FirewallLogs_CL').covered | Should -BeFalse
        $html | Should -Match 'function showEstateDetail'
        @($model.maturity.areas).Count | Should -Be 11
        $model.maturity.overall.score | Should -Be 1.59
        @($model.maturity.criteria).Count | Should -Be 60
        $model.detectionOpportunities[0].table | Should -Be 'FirewallLogs_CL'
        ($model.detectionOpportunities | Where-Object table -eq 'OfficeActivity').templates[0].name | Should -Be 'Data exfiltration'
        @($model.effectiveness).Count | Should -Be 2
        # Lists are carried in full; the dashboard shows the first few with a
        # "Show all" control instead of dropping the rest.
        ($model.detectionOpportunities | Where-Object table -eq 'OfficeActivity').PSObject.Properties.Name | Should -Not -Contain 'more'
        @($model.flowTables).Count | Should -Be 0
        $html | Should -Match 'function moreWrap'
        @($model.usageDaily).Count | Should -Be 3
        $model.playbookHealth.failed7d | Should -Be 5
        ($model.incidentsByClassification | Where-Object label -eq 'Undetermined').value | Should -Be 15
        @($model.familyOrder) | Should -Contain 'Assessment'
    }

    It 'carries the data lake model from the shared tier profile' {
        $model = Get-Content (Join-Path $bundle 'model.json') -Raw | ConvertFrom-Json
        $model.dataLakeEnrolled | Should -BeTrue
        $model.dataLake.enrolled | Should -BeTrue
        $model.dataLake.signals.resource | Should -BeTrue
        $model.dataLake.signals.unifiedBilling | Should -BeFalse
        $model.dataLake.tiers.MirroredOnly | Should -BeGreaterThan 0
        $model.dataLake.tiers.AnalyticsOnly | Should -Be 0
        $model.dataLake.tiers.LakeOnly | Should -Be 0
        $model.dataLake.extendedCount | Should -Be 0
        $model.dataLake.operationalTables | Should -Be ($model.dataLake.tiers.MirroredOnly + $model.dataLake.tiers.MirroredExtended + $model.dataLake.tiers.LakeOnly + $model.dataLake.tiers.AnalyticsOnly)
        $html | Should -Match 'id="dataLakePanel"'
    }

    It 'gives the new pages a family and a headline' {
        ($site.sections | Where-Object num -eq 91).family | Should -Be 'Assessment'
        ($site.sections | Where-Object num -eq 90).family | Should -Be 'Assessment'
        ($site.sections | Where-Object num -eq 28).family | Should -Be 'Detection'
        $model = Get-Content (Join-Path $bundle 'model.json') -Raw | ConvertFrom-Json
        ($model.sections | Where-Object num -eq 91).headline | Should -Be 'Score 1.59 / 5'
        $logCap = $model.findings.items | Where-Object id -eq 'SAC-LOG-03'
        $logCap.maturity[0].criterionId | Should -Be 'SAC-LOG-03'
        $logCap.maturity[0].status | Should -Be 'Gap'
        $logCap.maturity[0].lift | Should -BeGreaterThan 0
        @(($model.findings.items | Where-Object id -eq 'SAC-LOG-07').maturity).Count | Should -Be 0
        $html | Should -Match 'data-tabs="maturity findings"'
        $html | Should -Match 'id="matSelect"'
        ($model.sections | Where-Object num -eq 28).headline | Should -Be '8 tables without detection'
    }

    It 'ships the estate flow and the Assessment tab, maturity and findings behind one switch, in the dashboard' {
        $html | Should -Match 'function drawEstateFlow'
        $html | Should -Match 'data-tab="maturity" data-tabs="maturity findings" role="tab">.*Assessment</div>'
        $html | Should -Not -Match 'data-tab="findings"'
        $html | Should -Match 'class="subtab" data-sub="maturity"[\s\S]*class="subtab" data-sub="findings"'
        $html | Should -Match 'id="estateRings"'
        $html | Should -Match 'id="maturityBoard"'
    }

    It 'writes the findings and the per-check outcomes' {
        $findingsDoc.analysisAvailable | Should -BeTrue
        @($findingsDoc.items).Count | Should -BeGreaterThan 0
        @($findingsDoc.checks).Count | Should -Be 1
    }

    It 'counts an absent raw file as zero, not one' {
        $ws2 = Join-Path $outDir 'law-sparse'
        New-Item -ItemType Directory -Path (Join-Path $ws2 '_raw') -Force | Out-Null
        Copy-Item (Join-Path $ws '_raw/run-context.json') (Join-Path $ws2 '_raw')
        $b2 = & (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1') -Source $ws2 -SkipWhatsNew 6> $null
        $model = Get-Content (Join-Path $b2 'model.json') -Raw | ConvertFrom-Json
        $model.counts.rulesTotal | Should -Be 0
        $model.counts.connectors | Should -Be 0
        $model.findings.total | Should -Be 0
        @($model.health.rows).Count | Should -Be 0
        $model.dataLakeEnrolled | Should -BeFalse
        $model.estate.customDetections.captured | Should -BeFalse
        $model.dataLake.enrolled | Should -BeFalse
        $model.dataLake.operationalTables | Should -Be 0
        (Get-Content (Join-Path $b2 'findings.json') -Raw | ConvertFrom-Json).analysisAvailable | Should -BeFalse
        $model.maturity | Should -BeNullOrEmpty
        @($model.estate.sources).Count | Should -Be 0
        $model.estate.rings.ingestion.pct | Should -BeNullOrEmpty
        @($model.usageDaily).Count | Should -Be 0
        @($model.detectionOpportunities).Count | Should -Be 0
        $model.playbookHealth.runs7d | Should -Be 0
        ($model.sections | Where-Object num -eq 91) | Should -BeNullOrEmpty
    }

    It 'names the lake tier in the billing flow when the workspace is enrolled' {
        $ws4 = Join-Path $outDir 'law-lake'
        New-Item -ItemType Directory -Path (Join-Path $ws4 '_raw') -Force | Out-Null
        Copy-Item (Join-Path $ws '_raw/*') (Join-Path $ws4 '_raw') -Recurse -Force
        $costPath = Join-Path $ws4 '_raw/cost-estimate.json'
        $costDoc = Get-Content $costPath -Raw | ConvertFrom-Json
        $costDoc | Add-Member -NotePropertyName AllTablesByCost -NotePropertyValue @(
            [pscustomobject]@{ Table = 'FirewallLogs_CL'; Plan = 'Analytics'; Gb30d = 2000.0; MonthlyCost = 4600.0 },
            [pscustomobject]@{ Table = 'SecurityEvent';   Plan = 'Analytics'; Gb30d = 500.0;  MonthlyCost = 0.0 },
            [pscustomobject]@{ Table = 'Syslog';          Plan = 'Analytics'; Gb30d = 280.0;  MonthlyCost = 644.0 },
            [pscustomobject]@{ Table = 'ColdStore_CL';    Plan = 'DataLake';  Gb30d = 120.0;  MonthlyCost = 6.0 }
        ) -Force
        $costDoc | ConvertTo-Json -Depth 16 | Set-Content -Path $costPath
        $b4 = & (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1') -Source $ws4 -SkipWhatsNew 6> $null
        $model = Get-Content (Join-Path $b4 'model.json') -Raw | ConvertFrom-Json
        $model.dataLake.enrolled | Should -BeTrue
        $plans = @($model.flow.nodes | Where-Object col -eq 2)
        $plans.label | Should -Contain 'Analytics + Lake mirror'
        $plans.label | Should -Contain 'Data lake only'
        $plans.label | Should -Not -Contain 'Analytics plan'
        ($plans | Where-Object label -eq 'Data lake only').lake | Should -BeTrue
        ($plans | Where-Object label -eq 'Data lake only').value | Should -Be 120
        $tableGb = (@($model.flow.nodes | Where-Object col -eq 1) | Measure-Object -Property value -Sum).Sum
        ($plans | Measure-Object -Property value -Sum).Sum | Should -Be $tableGb
        $outcomes = @($model.flow.nodes | Where-Object col -eq 3)
        ($outcomes | Where-Object label -eq 'Free benefit').value | Should -Be 500
        ($outcomes | Where-Object label -eq 'Billed').value | Should -Be 2400
        @($model.flow.links | Where-Object { $_.source -eq 't:ColdStore_CL' -and $_.target -eq 'p:Data lake only' }).Count | Should -Be 1
        # Every ingesting table travels with the model so the dashboard can
        # rebuild the flow per family or for every table on click.
        @($model.flowTables).Count | Should -Be 4
        $model.flowTables[0].table | Should -Be 'FirewallLogs_CL'
        $model.flowTables[0].family | Should -Be 'Custom logs'
        $model.flowTables[0].billedGb | Should -Be 2000
        ($model.flowTables | Where-Object table -eq 'SecurityEvent').billedGb | Should -Be 0
        ($model.flowTables | Where-Object table -eq 'ColdStore_CL').plan | Should -Be 'Data lake only'
        @($model.cost.allTables).Count | Should -Be 4
        $html | Should -Match 'id="flowFilter"'
        $html | Should -Match 'function buildFlowGraph'
    }

    It 'writes nothing with -WhatIf' {
        $ws3 = Join-Path $outDir 'law-whatif'
        New-Item -ItemType Directory -Path (Join-Path $ws3 '_raw') -Force | Out-Null
        Copy-Item (Join-Path $ws '_raw/run-context.json') (Join-Path $ws3 '_raw')
        & (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1') -Source $ws3 -SkipWhatsNew -WhatIf 6> $null | Out-Null
        Join-Path $ws3 'sharepoint' | Should -Not -Exist
    }
}
