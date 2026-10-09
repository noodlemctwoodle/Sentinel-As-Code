#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for the iSOC Blueprint SharePoint site generator: section
    families, Markdown-to-page conversion, the sync planners, the pure
    SharePoint helpers, and an end-to-end bundle build against the fixture.

.DESCRIPTION
    Nothing here needs SharePoint or PnP.PowerShell. The publisher keeps
    its decisions in pure planning functions (Get-SacSyncPlan.ps1) and the
    page conversion in ConvertTo-SharePointPageSegments.ps1, so both are
    exercised directly. The build test renders the deliberately-broken
    fixture to Markdown, adds a synthetic pre-rendered diagram, and runs
    Build-SentinelDocsSite.ps1 offline (-SkipWhatsNew) into a temp folder.

.EXAMPLE
    Invoke-Pester -Path Tests/Documenter/SharePoint-Site.Tests.ps1 -Output Detailed

    Runs the suite with per-assertion output.

.NOTES
    File:         Tests/Documenter/SharePoint-Site.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-08
    Version:      0.2.0
    Last Updated: 2026-10-09
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $sp = Join-Path $script:repoRoot 'Tools/Documenter/SharePoint'
    . (Join-Path $sp 'Private/Get-SectionFamily.ps1')
    . (Join-Path $sp 'Private/ConvertTo-SharePointPageSegments.ps1')
    . (Join-Path $sp 'Private/Get-SacSyncPlan.ps1')
    . (Join-Path $sp 'Private/SacSharePoint.ps1')

    function ConvertTo-Segments([string]$Markdown, [string]$File = '20-analytics-rules.md', [int]$Max = 500) {
        ConvertTo-SharePointPageSegments -Markdown $Markdown -FileName $File -MaxTableRows $Max
    }
    function Join-Html($Result) { ($Result.Segments | Where-Object { $_.type -eq 'html' } | ForEach-Object { $_.html }) -join "`n" }
}

Describe 'Get-SectionFamily' {

    It 'maps every section the renderer writes to a named family' {
        $renderer = Get-Content (Join-Path $repoRoot 'Tools/Documenter/Convert-SentinelInventoryToMarkdown.ps1') -Raw
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

    It 'places detection opportunities under Detection and the maturity page under Maturity, before the findings' {
        Get-SectionFamily -Number 28 | Should -Be 'Detection'
        Get-SectionFamily -Number 91 | Should -Be 'Maturity'
        $order = @(Get-SectionFamilyOrder)
        [array]::IndexOf($order, 'Maturity') | Should -Be ([array]::IndexOf($order, 'Findings & references') - 1)
    }
}

Describe 'ConvertTo-SharePointPageSegments' {

    Context 'title and banner' {
        BeforeAll {
            $md = @(
                '# Sentinel Health and Resilience  (TOC 4.8)'
                ''
                '> **Workspace** `law-x` · **Generated** 2026-10-08 06:00 UTC · **Documenter** v1.2'
                ''
                'Body text.'
            ) -join "`n"
            $script:r = ConvertTo-Segments $md '11-sentinel-health.md'
        }
        It 'uses the H1 as the title without the TOC suffix' { $r.Title | Should -Be 'Sentinel Health and Resilience' }
        It 'drops the metadata banner' { Join-Html $r | Should -Not -Match 'Documenter' }
        It 'keeps the body' { Join-Html $r | Should -Match '<p>Body text.</p>' }
        It 'does not put the H1 in the body' { Join-Html $r | Should -Not -Match '<h1' }
    }

    Context 'headings, anchors and rules' {
        BeforeAll {
            $md = "# T`n`n## Two`n`n### Three`n`n#### Four`n`n##### Five`n`n<a id=`"sent-001`"></a>`n`n---`n`ntext"
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
                '[SENT-009](90-gap-analysis.md#sent-009), [here](#sent-010), [script](../../Tools/Documenter/Export-SentinelInventory.ps1),'
                '[index](index.md) and [Learn](https://learn.microsoft.com/azure/sentinel/).'
            ) -join "`n"
            $script:html = Join-Html (ConvertTo-Segments $md '90-gap-analysis.md')
        }
        It 'points section links at the generated page' {
            $html | Should -Match 'href="~site/SitePages/sac-20-analytics-rules.aspx">rules</a>'
            $html | Should -Match 'href="~site/SitePages/sac-25-mitre-coverage.aspx">rule detail</a>'
        }
        It 'points finding links at the findings list filtered on the id' {
            $html | Should -Match 'href="~site/Lists/SentinelFindings/AllItems.aspx\?FilterField1=FindingId&amp;FilterValue1=SENT-009"'
            $html | Should -Match 'FilterValue1=SENT-010'
        }
        It 'turns repository-relative and index links into plain text' {
            $html | Should -Match '>script<|, script,| script\b'
            $html | Should -Not -Match 'Export-SentinelInventory.ps1'
            $html | Should -Not -Match 'index\.md'
        }
        It 'keeps external links' { $html | Should -Match 'href="https://learn.microsoft.com/azure/sentinel/"' }
    }

    Context 'mermaid' {
        BeforeAll {
            $md = "# T`n`n## Chart`n`n``````mermaid`npie title X`n  `"A`" : 1`n  B --> C`n```````n`nAfter."
            $script:r = ConvertTo-Segments $md '25-mitre-coverage.md'
        }
        It 'never leaks diagram source into the page' {
            $html = Join-Html $r
            $html | Should -Not -Match 'pie title'
            $html | Should -Not -Match '-->'
            $html | Should -Match 'Diagram not rendered'
        }
        It 'warns about the unrendered diagram' { $r.Warnings -join ' ' | Should -Match 'Mermaid' }
    }

    Context 'images and splitting' {
        BeforeAll {
            $md = @(
                '# T', '', 'Intro.', '', '## One', '', 'Before.', '', '![Diagram](assets/abc123def456.png)', '',
                'After.', '', '## Two', '', 'Second.', '', '![x](https://example.com/x.png)'
            ) -join "`n"
            $script:r = ConvertTo-Segments $md
        }
        It 'splits at every H2 and image, in order' {
            $types = @($r.Segments | ForEach-Object type)
            $types | Should -Be @('html', 'html', 'image', 'html', 'html')
        }
        It 'turns pre-rendered assets into image segments' {
            $img = $r.Segments | Where-Object type -eq 'image'
            $img.file | Should -Be 'abc123def456.png'
            $img.alt | Should -Be 'Diagram'
        }
        It 'leaves out images that are not pre-rendered assets, with a warning' {
            Join-Html $r | Should -Not -Match 'example.com'
            $r.Warnings -join ' ' | Should -Match 'example.com/x.png'
        }
        It 'starts each H2 segment with its heading' {
            ($r.Segments | Where-Object { $_.type -eq 'html' -and $_.html -match '^<h2>' }).Count | Should -Be 2
        }
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
            $r.Warnings -join ' ' | Should -Match 'capped at 5 rows'
        }
    }

    It 'returns an empty result for empty Markdown' {
        $r = ConvertTo-Segments ''
        $r.Title | Should -Be ''
        $r.Segments.Count | Should -Be 0
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

    It 'adds a new finding as Open with first and last seen' {
        $p = Plan @(F 'SENT-001') @() @(C 'SENT-001' 'Fired')
        $p.Action | Should -Be 'Add'
        $p.Values.Status | Should -Be 'Open'
        $p.Values.FirstSeen | Should -Be $now
        $p.Values.LastSeen | Should -Be $now
        $p.Values.Learn | Should -Be 'https://learn.microsoft.com/x, Microsoft Learn'
        $p.Values.SeverityRank | Should -Be 2
    }

    It 'updates an open finding that still fires' {
        $p = Plan @(F 'SENT-001') @(E 7 'SENT-001' 'Open') @(C 'SENT-001' 'Fired')
        $p.Action | Should -Be 'Update'
        $p.ItemId | Should -Be 7
        $p.Values.ContainsKey('FirstSeen') | Should -BeFalse
    }

    It 'reopens a resolved finding that fires again' {
        $p = Plan @(F 'SENT-001') @(E 7 'SENT-001' 'Resolved') @(C 'SENT-001' 'Fired')
        $p.Action | Should -Be 'Reopen'
        $p.Values.Status | Should -Be 'Open'
        $p.Values.ContainsKey('ResolvedOn') | Should -BeTrue
        $p.Values.ResolvedOn | Should -BeNullOrEmpty
    }

    It 'resolves an open finding whose check passed' {
        $p = Plan @() @(E 7 'SENT-001' 'Open') @(C 'SENT-001' 'Passed')
        $p.Action | Should -Be 'Resolve'
        $p.Values.Status | Should -Be 'Resolved'
        $p.Values.ResolvedOn | Should -Be $now
    }

    It 'keeps an open finding open when its check errored' {
        @(Plan @() @(E 7 'SENT-001' 'Open') @(C 'SENT-001' 'Errored')).Count | Should -Be 0
    }

    It 'retires an open finding whose rule left the rule set' {
        $p = Plan @() @(E 7 'SENT-050' 'Open') @(C 'SENT-001' 'Passed')
        $p.Action | Should -Be 'Retire'
        $p.Values.Status | Should -Be 'Retired'
    }

    It 'leaves resolved and retired items alone' {
        @(Plan @() @((E 7 'SENT-001' 'Resolved'), (E 8 'SENT-002' 'Retired')) @(C 'SENT-001' 'Passed')).Count | Should -Be 0
    }

    It 'resolves on absence when the snapshot has no per-check outcomes' {
        (Plan @() @(E 7 'SENT-001' 'Open') $null).Action | Should -Be 'Resolve'
    }

    It 'resolves nothing when the snapshot has no gap analysis' {
        @(Plan @() @(E 7 'SENT-001' 'Open') $null $false).Count | Should -Be 0
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
            Set-Content -Path (Join-Path $src 'AppManifest.xml') -Value '<?xml version="1.0" encoding="utf-8"?><App xmlns="http://schemas.microsoft.com/sharepoint/2012/app/manifest" Name="sentinel-navigator" ProductID="{7F7EB9C2-A720-45F1-AB47-7772DA011E1D}" Version="1.1.0.0"><Properties><Title>sentinel-navigator-client-side-solution</Title></Properties></App>'
            $pkg = Join-Path $dir 'test.sppkg'
            Compress-Archive -Path (Join-Path $src '*') -DestinationPath "$pkg.zip"
            Move-Item "$pkg.zip" $pkg
            $info = Get-SacAppPackageInfo -Path $pkg
            $info.ProductId | Should -Be '7f7eb9c2-a720-45f1-ab47-7772da011e1d'
            $info.Version | Should -Be '1.1.0.0'
            $info.Title | Should -Be 'sentinel-navigator-client-side-solution'
        }
        finally { Remove-Item $dir -Recurse -Force }
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

Describe 'Build-SentinelDocsSite against the fixture' {

    BeforeAll {
        $fixtureRaw = Join-Path $repoRoot 'Tests/Documenter/Fixtures/sample/_raw'
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

        & (Join-Path $repoRoot 'Tools/Documenter/Convert-SentinelInventoryToMarkdown.ps1') `
            -WorkspaceName 'law-sentinel-test' -InputRoot $ws -OutputRoot $ws `
            -ResourcesRoot (Join-Path $repoRoot 'Tools/Documenter/Private/Resources') -InformationAction SilentlyContinue *> $null

        # Simulate Convert-MermaidToImage for one section: a pre-rendered
        # asset and the image reference that replaces its fence.
        New-Item -ItemType Directory -Path (Join-Path $ws 'assets') -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $ws 'assets/0123456789ab.png'), [byte[]](0x89, 0x50, 0x4E, 0x47))
        Add-Content -Path (Join-Path $ws '25-mitre-coverage.md') -Value "`n![Diagram](assets/0123456789ab.png)`n"

        $script:mdFiles = @(Get-ChildItem $ws -Filter '*.md' | Where-Object { $_.Name -ne 'index.md' -and $_.BaseName -match '^\d+-' })
        $script:bundle = & (Join-Path $repoRoot 'Tools/Documenter/SharePoint/Build-SentinelDocsSite.ps1') -Source $ws -SkipWhatsNew 6> $null
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

    It 'copies the referenced diagram and references it from the page' {
        $site.diagrams | Should -Contain '0123456789ab.png'
        Join-Path $bundle 'diagrams/0123456789ab.png' | Should -Exist
        $page = Get-Content (Join-Path $bundle 'pages/sac-25-mitre-coverage.json') -Raw | ConvertFrom-Json
        ($page.segments | Where-Object type -eq 'image').file | Should -Be '0123456789ab.png'
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
        @($model.maturity.areas).Count | Should -Be 11
        $model.maturity.overall.score | Should -Be 1.49
        @($model.maturity.criteria).Count | Should -Be 60
        $model.detectionOpportunities[0].table | Should -Be 'FirewallLogs_CL'
        ($model.detectionOpportunities | Where-Object table -eq 'OfficeActivity').templates[0].name | Should -Be 'Data exfiltration'
        @($model.effectiveness).Count | Should -Be 2
        @($model.usageDaily).Count | Should -Be 3
        $model.playbookHealth.failed7d | Should -Be 5
        ($model.incidentsByClassification | Where-Object label -eq 'Undetermined').value | Should -Be 15
        @($model.familyOrder) | Should -Contain 'Maturity'
    }

    It 'gives the new pages a family and a headline' {
        ($site.sections | Where-Object num -eq 91).family | Should -Be 'Maturity'
        ($site.sections | Where-Object num -eq 28).family | Should -Be 'Detection'
        $model = Get-Content (Join-Path $bundle 'model.json') -Raw | ConvertFrom-Json
        ($model.sections | Where-Object num -eq 91).headline | Should -Be 'Score 1.49 / 5'
        ($model.sections | Where-Object num -eq 28).headline | Should -Be '8 tables without detection'
    }

    It 'ships the estate flow and the Maturity tab in the dashboard' {
        $html | Should -Match 'function drawEstateFlow'
        $html | Should -Match 'data-tab="maturity"'
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
        $b2 = & (Join-Path $repoRoot 'Tools/Documenter/SharePoint/Build-SentinelDocsSite.ps1') -Source $ws2 -SkipWhatsNew 6> $null
        $model = Get-Content (Join-Path $b2 'model.json') -Raw | ConvertFrom-Json
        $model.counts.rulesTotal | Should -Be 0
        $model.counts.connectors | Should -Be 0
        $model.findings.total | Should -Be 0
        @($model.health.rows).Count | Should -Be 0
        $model.dataLakeEnrolled | Should -BeFalse
        (Get-Content (Join-Path $b2 'findings.json') -Raw | ConvertFrom-Json).analysisAvailable | Should -BeFalse
        $model.maturity | Should -BeNullOrEmpty
        @($model.estate.sources).Count | Should -Be 0
        $model.estate.rings.ingestion.pct | Should -BeNullOrEmpty
        @($model.usageDaily).Count | Should -Be 0
        @($model.detectionOpportunities).Count | Should -Be 0
        $model.playbookHealth.runs7d | Should -Be 0
        ($model.sections | Where-Object num -eq 91) | Should -BeNullOrEmpty
    }

    It 'writes nothing with -WhatIf' {
        $ws3 = Join-Path $outDir 'law-whatif'
        New-Item -ItemType Directory -Path (Join-Path $ws3 '_raw') -Force | Out-Null
        Copy-Item (Join-Path $ws '_raw/run-context.json') (Join-Path $ws3 '_raw')
        & (Join-Path $repoRoot 'Tools/Documenter/SharePoint/Build-SentinelDocsSite.ps1') -Source $ws3 -SkipWhatsNew -WhatIf 6> $null | Out-Null
        Join-Path $ws3 'sharepoint' | Should -Not -Exist
    }
}
