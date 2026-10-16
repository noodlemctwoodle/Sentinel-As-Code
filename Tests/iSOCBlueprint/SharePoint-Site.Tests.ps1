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
    Version:      0.13.1
    Last Updated: 2026-10-15
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
        Get-SectionFamily -Number 36 | Should -Be 'Workspace'
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

    Context 'tables a graphic shows in full' {
        It 'leaves out a table flagged inGraphic, keeping the rest' {
            $md = "# T`n`n<!-- bp:shown-in-graphic -->`n`n| Stage | Share |`n|---|---|`n| Ingestion | 87% |`n`n| Family | GB |`n|---|---|`n| Entra | 4 |"
            $html = Join-Html (ConvertTo-Segments $md)
            $html | Should -Not -Match 'Ingestion'
            $html | Should -Match 'Entra'
        }
        It 'leaves out a line of figures flagged inGraphic' {
            $html = Join-Html (ConvertTo-Segments "# T`n`n<!-- bp:shown-in-graphic -->`n`n**71** packages  ·  **38** to update`n`nKept.")
            $html | Should -Not -Match 'packages'
            $html | Should -Match 'Kept\.'
        }
    }

    Context 'chart titles' {
        It 'drops a chart title that repeats the heading above it, and keeps the rest' {
            $md = @(
                '# T', '', '## Analyst journey', '', '```mermaid', 'journey', '    title Analyst journey', '    section A', '      Step: 5: Sentinel', '```',
                '', '## Outcomes', '', '```mermaid', 'pie title Closed by classification', '    "TP" : 3', '```'
            ) -join "`n"
            $charts = @((ConvertTo-Segments $md).Segments | Where-Object { $_.type -eq 'chart' })
            $charts.Count | Should -Be 2
            $charts[0].chart.title | Should -BeNullOrEmpty
            $charts[1].chart.title | Should -Be 'Closed by classification'
        }
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
        It 'gives the cut table whole as CSV and links it from the note' {
            @($r.Tables).Count | Should -Be 1
            $r.Tables[0].file | Should -Be '20-analytics-rules-table.csv'
            $r.Tables[0].rows | Should -Be 7
            $r.Tables[0].csv | Should -Be ("Name,Count`r`n" + ((1..7 | ForEach-Object { "r$_,$_" }) -join "`r`n") + "`r`n")
            $html | Should -Match 'Every row is in <a href="~site/BlueprintAssets/tables/20-analytics-rules-table\.csv">this table as a CSV file</a>, which opens in Excel'
            $r.Warnings -join ' ' | Should -Match 'every row is in tables/20-analytics-rules-table\.csv'
        }
    }

    It 'returns an empty result for empty Markdown' {
        $r = ConvertTo-Segments ''
        $r.Title | Should -Be ''
        $r.Segments.Count | Should -Be 0
    }
}

Describe 'Cut tables as CSV files' {
    It 'quotes a field with a comma, quote or line break' {
        ConvertTo-SacCsvField 'a,b' | Should -Be '"a,b"'
        ConvertTo-SacCsvField 'say "hi"' | Should -Be '"say ""hi"""'
        ConvertTo-SacCsvField 'plain' | Should -Be 'plain'
    }

    It 'keeps a cell from being read as a formula, but not a negative number' {
        ConvertTo-SacCsvField '=HYPERLINK("x")' | Should -Be '"''=HYPERLINK(""x"")"'
        ConvertTo-SacCsvField '+1' | Should -Be "'+1"
        ConvertTo-SacCsvField '@SUM(A1)' | Should -Be "'@SUM(A1)"
        ConvertTo-SacCsvField '-cmd' | Should -Be "'-cmd"
        ConvertTo-SacCsvField '-5' | Should -Be '-5'
        ConvertTo-SacCsvField '-2.5' | Should -Be '-2.5'
    }

    It 'names the file from the section and the heading, unique within the section' {
        Get-SacTableFileName -Id '21-rule-performance' -Heading 'Rule effectiveness (last 90d)' | Should -Be '21-rule-performance-rule-effectiveness-last-90d.csv'
        Get-SacTableFileName -Id '21-rule-performance' -Heading 'Rule effectiveness (last 90d)' -Taken '21-rule-performance-rule-effectiveness-last-90d.csv' | Should -Be '21-rule-performance-rule-effectiveness-last-90d-2.csv'
        Get-SacTableFileName -Id '15-incidents' -Heading '' | Should -Be '15-incidents-table.csv'
    }

    It 'writes each cell as its text, with formatting and line breaks dropped' {
        Get-SacRunsText -Runs @([pscustomobject]@{ text = 'Bold'; bold = $true }, [pscustomobject]@{ break = $true }, [pscustomobject]@{ text = 'next' }) | Should -Be 'Bold next'
    }

    It 'links to the folder the publisher keeps in the assets library' {
        $script:SacTablesUrl | Should -Be "~site/$script:SacAssetsLibraryUrl/tables"
        (Get-Command Initialize-SacSiteStructure).Definition | Should -Match '''dashboard'', ''diagrams'', ''tables'', ''_state'''
    }

    It 'has the publisher upload every CSV the bundle lists, and prune the rest' {
        $publisher = Get-Content (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/Publish-SentinelDocsSite.ps1') -Raw
        $publisher | Should -Match 'Send-SacFile -Path \$csvPath -Folder ''tables'''
        $publisher | Should -Match 'Get-AssetPrunePlan -DesiredFiles \$siteTables -ExistingFiles \(Get-SacFolderFileNames -Folder ''tables''\)'
        $publisher | Should -Match 'Remove-PnPFile -SiteRelativeUrl "\$script:SacAssetsLibraryUrl/tables/\$file" -Force -Recycle'
        $publisher | Should -Match '\$siteTables = @\(if \(\$site\.PSObject\.Properties\[''tables''\]\)'
    }
}

Describe 'Build-SentinelDocsSite with tables cut on their pages' {
    BeforeAll {
        $fixtureRaw = Join-Path $repoRoot 'Tests/iSOCBlueprint/Fixtures/sample/_raw'
        $script:cutDir = Join-Path ([System.IO.Path]::GetTempPath()) "sharepoint-cut-test-$(New-Guid)"
        $script:cutWs = Join-Path $script:cutDir 'law-sentinel-test'
        New-Item -ItemType Directory -Path (Join-Path $script:cutWs '_raw') -Force | Out-Null
        Copy-Item -Path (Join-Path $fixtureRaw '*.json') -Destination (Join-Path $script:cutWs '_raw')
        & (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Convert-SentinelInventoryToMarkdown.ps1') `
            -WorkspaceName 'law-sentinel-test' -InputRoot $script:cutWs -OutputRoot $script:cutWs -OutputFormat Json `
            -ResourcesRoot (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Resources') -InformationAction SilentlyContinue *> $null
        $script:cutLog = (& (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1') -Source $script:cutWs -MaxTableRows 3 -HistoryDays 0 6>&1 | Out-String)
        $script:cutBundle = Join-Path $script:cutWs 'sharepoint'
        $script:cutSite = Get-Content (Join-Path $script:cutBundle 'site.json') -Raw | ConvertFrom-Json
    }

    AfterAll {
        if ($script:cutDir -and (Test-Path $script:cutDir)) { Remove-Item $script:cutDir -Recurse -Force }
    }

    It 'writes every cut table to tables/ and lists it in site.json' {
        $files = @(Get-ChildItem (Join-Path $script:cutBundle 'tables') -Filter '*.csv' | ForEach-Object Name | Sort-Object)
        $files.Count | Should -BeGreaterThan 3
        @($script:cutSite.tables | Sort-Object) | Should -Be $files
    }

    It 'writes UTF-8 with a byte order mark, the header first, then every row' {
        $first = Get-ChildItem (Join-Path $script:cutBundle 'tables') -Filter '*.csv' | Select-Object -First 1
        $bytes = [System.IO.File]::ReadAllBytes($first.FullName)
        @($bytes[0..2]) | Should -Be @(0xEF, 0xBB, 0xBF)
        @(Get-Content $first.FullName).Count | Should -BeGreaterThan 4
    }

    It 'links each page''s note to its CSV' {
        $file = [string]$script:cutSite.tables[0]
        $pageText = (Get-ChildItem (Join-Path $script:cutBundle 'pages') -Filter '*.json' | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
        $pageText | Should -Match ([regex]::Escape("~site/BlueprintAssets/tables/$file"))
    }

    It 'notes the long tables once, with where every row is' {
        $script:cutLog | Should -Match 'Long tables: \d+ table\(s\) longer than 3 rows show their first 3 on the native pages'
        $script:cutLog | Should -Match 'Every row is in a CSV file under tables/'
        $script:cutLog | Should -Not -Match 'a table was capped at 3 rows'
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

    It 'tabulates the incident lifecycle''s stages, leaving out a figure the capture lacks' {
        $html = ConvertTo-SacChartFallbackHtml -Chart @{ kind = 'incident-lifecycle'; data = @{ raised = 40; new = 5; active = 3; closed = 32; unacknowledged = $null } }
        $html | Should -Match '<tr><td>Raised</td><td>40</td></tr>'
        $html | Should -Match '<tr><td>Closed</td><td>32</td></tr>'
        ([regex]::Matches($html, '<tr>')).Count | Should -Be 4
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

Describe 'Add-SacSnapshotEntry' {

    BeforeAll {
        function New-Snap([string]$Date, [int]$Findings = 3) { @{ date = $Date; file = "$Date.html"; findings = $Findings; score = 1.5 } }
    }

    It 'starts a list with the first day' {
        $r = Add-SacSnapshotEntry -Index @{ entries = @() } -Entry (New-Snap '2026-10-01')
        @($r.entries).Count | Should -Be 1
        @($r.removed).Count | Should -Be 0
    }

    It 'keeps the newest day first, and the input unchanged' {
        $ix = @{ entries = @((New-Snap '2026-10-02'), (New-Snap '2026-10-01')) }
        $r = Add-SacSnapshotEntry -Index $ix -Entry (New-Snap '2026-10-03')
        @($r.entries.date) | Should -Be @('2026-10-03', '2026-10-02', '2026-10-01')
        @($ix.entries).Count | Should -Be 2
    }

    It 'replaces a day published again' {
        $ix = @{ entries = @((New-Snap '2026-10-02' 3), (New-Snap '2026-10-01' 3)) }
        $r = Add-SacSnapshotEntry -Index $ix -Entry (New-Snap '2026-10-02' 9)
        @($r.entries).Count | Should -Be 2
        $r.entries[0].findings | Should -Be 9
    }

    It 'grows with each day until the window is full, then drops the oldest days and names their files' {
        $ix = @{ entries = @() }
        foreach ($d in 1..5) { $ix = Add-SacSnapshotEntry -Index @{ entries = $ix.entries } -Entry (New-Snap ('2026-10-0' + $d)) -Days 3 }
        @($ix.entries.date) | Should -Be @('2026-10-05', '2026-10-04', '2026-10-03')
        $r = Add-SacSnapshotEntry -Index @{ entries = @((New-Snap '2026-10-02'), (New-Snap '2026-10-01')) } -Entry (New-Snap '2026-10-04') -Days 3
        @($r.removed) | Should -Be @('2026-10-01.html')
    }

    It 'keeps 90 days by default, counting back from the newest' {
        $ix = @{ entries = @(0..95 | ForEach-Object { New-Snap ((Get-Date '2026-10-01').AddDays(-$_).ToString('yyyy-MM-dd')) }) }
        $r = Add-SacSnapshotEntry -Index $ix -Entry (New-Snap '2026-10-01')
        @($r.entries).Count | Should -Be 90
        $r.entries[-1].date | Should -Be '2026-07-04'
        @($r.removed).Count | Should -Be 6
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

Describe 'Detection outcomes and template solutions in the site build' {
    BeforeAll {
        $fixtureRaw = Join-Path $repoRoot 'Tests/iSOCBlueprint/Fixtures/sample/_raw'
        $script:doDir = Join-Path ([System.IO.Path]::GetTempPath()) "sharepoint-do-$(New-Guid)"
        $wsd = Join-Path $script:doDir 'law-do'
        New-Item -ItemType Directory -Path (Join-Path $wsd '_raw') -Force | Out-Null
        Copy-Item -Path (Join-Path $fixtureRaw '*.json') -Destination (Join-Path $wsd '_raw')
        # Two run-failure rows: with more than one, the list must still be read row by row.
        @(
            @{ RuleName = 'Suspicious sign-in from rare country'; Status = 'Failure'; Failures = 3; LastFailure = '2026-05-06T06:15:00Z'; Reason = 'timeout' }
            @{ RuleName = 'Lateral movement detected'; Status = 'Failure'; Failures = 2; LastFailure = '2026-05-05T06:15:00Z'; Reason = 'timeout' }
        ) | ConvertTo-Json -AsArray | Set-Content (Join-Path $wsd '_raw/rule-health.json')
        # A live solution and a deprecated one, as the catalogue lists them.
        $dep = { param($id) @{ criteria = @(@{ contentId = $id; kind = 'AnalyticsRule' }) } }
        @(
            @{ properties = @{ contentId = 'm365'; displayName = 'Microsoft 365'; isDeprecated = 'false'; dependencies = (& $dep 'tmpl-data-exfiltration') } }
            @{ properties = @{ contentId = 'ti-old'; displayName = 'Threat Intelligence'; isDeprecated = 'true'; dependencies = (& $dep 'tmpl-low-noise') } }
            @{ properties = @{ contentId = 'ti-new'; displayName = 'Threat Intelligence (NEW)'; isDeprecated = 'false' } }
        ) | ConvertTo-Json -Depth 10 -AsArray | Set-Content (Join-Path $wsd '_raw/content-product-packages.json')
        # A finding from an older snapshot, with "?" for unnamed principals.
        $gp = Join-Path $wsd '_raw/gap-analysis.json'
        $g = @(Get-Content $gp -Raw | ConvertFrom-Json)
        $g[0].Evidence = '3 service principal(s) hold Owner or Contributor at workspace scope: ?; App one; ?.'
        ConvertTo-Json -InputObject $g -Depth 10 | Set-Content $gp
        $script:doGapId = $g[0].Id
        & (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Convert-SentinelInventoryToMarkdown.ps1') -WorkspaceName 'law-do' -InputRoot $wsd -OutputRoot $wsd `
            -ResourcesRoot (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Resources') -OutputFormat Json -InformationAction SilentlyContinue *> $null
        $b = & (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1') -Source $wsd -SkipWhatsNew 6> $null
        $script:doModel = Get-Content (Join-Path $b 'model.json') -Raw | ConvertFrom-Json
        $script:doHtml = Get-Content (Join-Path $b 'index.html') -Raw
        $script:doFindings = Get-Content (Join-Path $b 'findings.json') -Raw | ConvertFrom-Json
    }
    AfterAll { if ($script:doDir -and (Test-Path $script:doDir)) { Remove-Item $script:doDir -Recurse -Force } }

    It 'carries every enabled rule and custom detection that reads a table, with its health and classified incidents' {
        $o = @($script:doModel.detectionOutcomes)
        # Fusion and the incident-creation rule read no table; the disabled rule and detection are left out.
        @($o.name) | Should -Be @('Suspicious sign-in from rare country', 'Failed logons across multiple accounts', 'Suspicious LSASS access')
        $s = $o[0]
        $s.health | Should -Be 'Failing'
        $s.failures | Should -Be 3
        $s.alerts | Should -Be 412
        @($s.tables) | Should -Be @('AuditLogs', 'SigninLogs')
        $s.incidents, $s.tp, $s.fp, $s.bp, $s.undetermined, $s.unclassified, $s.open | Should -Be @(30, 3, 19, 1, 1, 0, 6)
        $o[1].health | Should -Be 'Working'
        $o[1].open | Should -Be 2
        $o[2].kind | Should -Be 'Custom detection'
        $o[2].source | Should -Be 'Defender XDR'
        $o[2].health | Should -Be 'Silent'
    }

    It 'names each template''s solution and leaves out one only a deprecated solution ships' {
        $office = $script:doModel.detectionOpportunities | Where-Object table -eq 'OfficeActivity'
        $office.templates[0].solution | Should -Be 'Microsoft 365'
        $sec = $script:doModel.detectionOpportunities | Where-Object table -eq 'SecurityEvent'
        @($sec.templates.name) | Should -Not -Contain 'Low-severity noise'
    }

    It 'words an older snapshot''s "?" for an unnamed principal in the findings' {
        $f = @($script:doFindings.items) + @($script:doFindings) | Where-Object { $_ -and $_.PSObject.Properties['id'] -and $_.id -eq $script:doGapId } | Select-Object -First 1
        $f.evidence | Should -Be '3 service principal(s) hold Owner or Contributor at workspace scope: Unnamed (no name in this snapshot); App one; Unnamed (no name in this snapshot).'
    }

    It 'maps every table the rules read to its source family, for the matrix''s columns' {
        $f = $script:doModel.detectionTableFamily
        $f.SigninLogs | Should -Be 'Entra ID / Identity'
        $f.AuditLogs | Should -Be 'Entra ID / Identity'
        $f.DeviceProcessEvents | Should -Be 'Defender XDR'
        @($f.PSObject.Properties).Count | Should -Be 5
    }

    It 'draws the detection matrix on the Data flow tab, between the estate flow and the ingest and billing flow' {
        $script:doHtml | Should -Match '(?s)<h2>Estate flow</h2>.*?<h2>Detection matrix</h2>.*?<h2>Ingest &amp; billing flow</h2>'
        $script:doHtml | Should -Not -Match 'id="detFlow"'
        # Rows run Failing, Working, Silent; the first 25 show and the header's chevron shows the rest.
        $script:doHtml.Contains("const FIRST=25, HEALTH=[['Failing','var(--red)'],['Working','var(--green)'],['Silent','var(--slate)']];") | Should -BeTrue
        $script:doHtml.Contains("h+='<tr'+(ri>=FIRST? ' data-mr hidden':'')+'>") | Should -BeTrue
        $script:doHtml.Contains("<th class=""dm-n"">'+WIN.w()+(rows.length>FIRST? moreChev(rows.length,'rules') : '')") | Should -BeTrue
        $script:doHtml | Should -Match '<div class="dm-scroll morewrap" id="dmBox">'
        # Filters: source, health with All, and family or table columns; a search box.
        $script:doHtml.Contains("chip('health','all','All',base.length,!st.health)") | Should -BeTrue
        $script:doHtml.Contains("chip('mode','family','By source family',null,st.mode==='family')+chip('mode','table','Every table',null,st.mode==='table')") | Should -BeTrue
        $script:doHtml | Should -Match 'id="dmQ"'
        # A numbered bubble's ink is whichever of white or near-black contrasts more; the glow is dark-only.
        $script:doHtml.Contains("const inkOn=hex=>{ const L=lum(hex); return 1.05/(L+0.05) >= (L+0.05)/0.0567 ? '#ffffff' : '#0b1220'; };") | Should -BeTrue
        $script:doHtml | Should -Match 'html\[data-theme="dark"\] \.dm td\.dm-c i\{box-shadow:0 0 9px var\(--g\)\}'
        # Family names share a two-line box, so the column heads line up.
        $script:doHtml | Should -Match '\.dm thead th\.dm-fcol \.dm-fn\{display:flex;align-items:center;justify-content:center;min-height:2\.6em\}'
        # Every table's angled names get the room the longest needs.
        $script:doHtml.Contains("const labH=Math.ceil(Math.max(1,...cols.map(c=>c.label.length))*6.9*Math.sin(64*Math.PI/180))+30;") | Should -BeTrue
        # The last names lean past the last column: a spacer column of that width keeps them clear of Health.
        $script:doHtml.Contains("const over=st.mode==='table'? Math.max(0,Math.ceil(Math.max(...cols.map((c,i)=>i*40+33+c.label.length*6.9*Math.cos(64*Math.PI/180)))-cols.length*40)) : 0;") | Should -BeTrue
        $script:doHtml.Contains('colspan="''+(cols.length+(over?1:0))+''"') | Should -BeTrue
        $script:doHtml.Contains('h+=spacer;') | Should -BeTrue
        # Tables on screen together with the same columns share measured widths, so they line up.
        $script:doHtml.Contains('function alignTables(scope){') | Should -BeTrue
        $script:doHtml.Contains("if(!t.offsetParent || !t.tHead) return;") | Should -BeTrue
        $script:doHtml.Contains("const px=need.map((x,i)=>flex[i]? Math.max(180, Math.floor(flexNeed? left*x/flexNeed : 0)) : x);") | Should -BeTrue
        $script:doHtml.Contains('alignTables(panes[i]);') | Should -BeTrue
        $script:doHtml.Contains('realign(panes[i]);') | Should -BeTrue
        # The verdict cell reads incidents and the true-positive share of the closed ones.
        $script:doHtml.Contains("Math.round(100*n0(r.tp)/closed)+'% TP'") | Should -BeTrue
        $script:doHtml | Should -Match '\.dm-scroll::-webkit-scrollbar\{width:8px;height:8px\}|\.dm-scroll::-webkit-scrollbar\{'
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

    It 'carries every section chart for the Report tab, with the diagram''s source as a fallback' {
        $model = Get-Content (Join-Path $bundle 'model.json') -Raw | ConvertFrom-Json
        $charts = @($model.sections | ForEach-Object { @($_.blocks) } | Where-Object { $_.t -eq 'chart' })
        $charts.Count | Should -BeGreaterThan 0
        # Pie and xy the dashboard draws itself; the rest carry their data and
        # their Mermaid source for the chart web part's renderers.
        @($charts | Where-Object { $_.kind -in 'pie', 'xy' -and $_.PSObject.Properties.Name -contains 'source' }).Count | Should -Be 0
        # A graphic carried on a bp:visual comment has no Mermaid behind it.
        @($charts | Where-Object { $_.kind -notin 'pie', 'xy', 'finding-cards' -and -not $_.source }).Count | Should -Be 0
        # The maturity page's area scores, which the dashboard used to drop
        # and replace with a chart of the Areas table's last number column.
        $area = @($model.sections | Where-Object num -EQ 91 | ForEach-Object { @($_.blocks) } | Where-Object { $_.t -eq 'chart' })[0]
        $area.kind | Should -Be 'xy'
        $area.data.yAxis.max | Should -Be 5
        @(@($area.data.series)[0].values).Count | Should -Be @($area.data.xAxis.labels).Count
    }

    It 'makes links to sections and findings dashboard links rather than bold text' {
        $model = Get-Content (Join-Path $bundle 'model.json') -Raw | ConvertFrom-Json
        $text = ($model.sections | ConvertTo-Json -Depth 32 -Compress) -replace '\\"', '"'
        $text | Should -Not -Match '<span class="xref">'
        $text | Should -Match '<a class="xref" href="#" data-xsec="\d+">'
        # A finding link names the page its anchor is on, for when the finding
        # is not in this run's list.
        $text | Should -Match '<a class="xref" href="#" data-xfind="SAC-[A-Z]+-\d{2}" data-xsec="90">'
    }

    It 'shows no id from before the SAC scheme on a finding card' {
        # The search still matches an old id; the card no longer shows it.
        $card = [regex]::Match($script:html, '(?s)function findingCard\(f\)\{.*?\n  \}').Value
        $card | Should -Not -BeNullOrEmpty
        $card | Should -Not -Match 'legacyId'
    }

    It 'scrolls with scrollIntoView, which moves the SharePoint page around the iframe' {
        # window.scrollTo inside the auto-height iframe moves nothing; the
        # only call left is the fallback inside bringTop.
        $script:html | Should -Match 'function bringTop\('
        ([regex]::Matches($script:html, 'window\.scrollTo\(')).Count | Should -Be 1
    }

    It 'charts a table only from a column that clearly holds an amount' {
        $script:html | Should -Not -Match 'valCol=numCols\[numCols\.length-1\]'
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
        # The page has exactly three closing script tags (the chart renderers,
        # the model block and the main script); the hostile evidence must not
        # add a fourth.
        ([regex]::Matches($html, '</script>')).Count | Should -Be 3
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
        # Alerts from every product, as the incidents are; the rules' own beside them.
        $model.estate.alerts | Should -Be 565
        $model.estate.ruleAlerts | Should -Be 507
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
        # A template only a deprecated Content Hub solution ships is left out, as on the report page.
        $build = Get-Content (Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1') -Raw
        $build.Contains("-not (Test-TemplateRetired -Map `$tplSolutions -TemplateId ([string]`$_.TemplateId))") | Should -BeTrue
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
        $html | Should -Match 'class="subcount"'
        $html | Should -Match 'id="estateRings"'
        $html | Should -Match 'id="maturityBoard"'
    }

    It 'gives the findings view a summary with click-through to the list, and an area filter' {
        $html | Should -Match 'id="findingsBoard"[\s\S]*class="filters"'
        $html | Should -Match 'id="areaSelect"'
        $html | Should -Match 'id="findClear"'
        $html | Should -Match "h2>Score impact</h2>"
        $html | Should -Match 'data-fk='
    }

    It 'carries what the maturity score is based on and what it covers, and shows both' {
        # The fixture's maturity.json predates them; the build reads the criteria file instead.
        $model = Get-Content (Join-Path $bundle 'model.json') -Raw | ConvertFrom-Json
        $model.maturity.methodology.basis | Should -Match 'based on the SOC-CMM framework'
        $model.maturity.methodology.scope | Should -Match 'People \(staffing, skills, roles\)'
        $html | Should -Match 'class="matscope"'
        $html | Should -Match 'people and processes were not assessed'
        # Two matching tiles, without the amber side bar.
        $html | Should -Match '<div class="ms"><div class="msh">''\+ICON\.scale\+''Basis</div>'
        $html | Should -Match '<div class="ms"><div class="msh">''\+ICON\.crosshair\+''Scope</div>'
        $html | Should -Not -Match '\.matscope\{[^}]*border-left:3px solid var\(--amber\)'
    }

    It 'carries the alert lifecycle: closures by who closed them, open incidents by severity and MTTR' {
        $model = Get-Content (Join-Path $bundle 'model.json') -Raw | ConvertFrom-Json
        $model.alertLifecycle.closedBy.AutomationRule | Should -Be 14
        $model.alertLifecycle.closedBy.Analyst | Should -Be 11
        $model.alertLifecycle.closedBy.DefenderXdr | Should -Be 5
        $model.alertLifecycle.closedBy.Other | Should -Be 2
        ($model.alertLifecycle.closedBy.PSObject.Properties.Value | Measure-Object -Sum).Sum | Should -Be $model.estate.incidentsClosed
        $model.alertLifecycle.openBySeverity.High | Should -Be 2
        $model.alertLifecycle.openBySeverity.Informational | Should -Be 0
        ($model.alertLifecycle.openBySeverity.PSObject.Properties.Value | Measure-Object -Sum).Sum | Should -Be $model.estate.incidentsOpen
        $model.alertLifecycle.mttrMinutes | Should -Be 1620
        # Sentinel's alerts and Defender XDR's, which together feed the incidents.
        $model.estate.alertsSentinel | Should -Be 525
        $model.estate.alertsXdr | Should -Be 40
        ($model.estate.alertsSentinel + $model.estate.alertsXdr) | Should -Be $model.estate.alerts
        $html.Contains("const aSen=E.alertsSentinel!=null? n0(E.alertsSentinel) : alerts, aXdr=n0(E.alertsXdr), split=aXdr>0;") | Should -BeTrue
        $html.Contains("bigNode(ax,aSen,'SENTINEL ALERTS','Open the alerts page',") | Should -BeTrue
        $html.Contains("bigNode(ax,aXdr,'DEFENDER XDR ALERTS','Open the alerts page',") | Should -BeTrue
        # Split, the nodes sit further left so their figures clear the core's rings.
        $html.Contains("const ax=split? 424 : 436, jx=Math.round(ax-half(split? Math.max(aSen,aXdr) : alerts)-22);") | Should -BeTrue
        # Figures are centred on their node's line, and the incidents junction keeps clear of its figure.
        $html.Contains("mk('text',{x:x,y:y+11,'text-anchor':'middle','font-size':'32',class:'lc-num'},num(value),g);") | Should -BeTrue
        $html.Contains("const ix=Math.round(764+half(incidents)+18);") | Should -BeTrue
        # Exact counts, never abbreviated (14,226, not 14.2k).
        $html.Contains("const num=v=>n0(v).toLocaleString('en-GB');") | Should -BeTrue
        $html | Should -Not -Match "notation:'compact'"

        # A strand per family into Defender XDR's alerts, from the products that raised them.
        $html.Contains("const xa=split? n0(xdrByFam[s.category]) : 0;") | Should -BeTrue
        # The estate flow splits after detection: Defender XDR's alerts above the
        # line, Sentinel's below, merging into the incidents.
        $html.Contains("const xdr=(E&&+E.alertsXdr)||0, splitY=xdr>0? 90 : 0, poolDrop=xdr>0? 26 : 0;") | Should -BeTrue
        $html.Contains("{k:'alerts',x:770,y:cy+splitY,label:xdr>0? 'Sentinel alerts' : 'Alerts'}") | Should -BeTrue
        $html.Contains("xx=al.x, xy=cy-splitY,") | Should -BeTrue
        $html.Contains("[curve(det.x+r,cy,xx-r,xy), curve(xx+r,xy,inc.x-r,cy)]") | Should -BeTrue
        $html.Contains("'DEFENDER XDR ALERTS');") | Should -BeTrue
        # Its strands have square ends and are drawn before the stage rings, so they do not bleed over them.
        $html.Contains("'stroke-width':xw.toFixed(1),'stroke-linecap':'butt'}),xTip);") | Should -BeTrue
        $html | Should -Match "(?s)'DEFENDER XDR ALERTS'\);.*?rings\.forEach\(rg=>\{"
        # The flow's description follows the split.
        $html | Should -Match 'Alerts split in two: Defender XDR&#39;s|Alerts split in two: Defender XDR''s'
        $html.Contains("onXdr:()=>{ const n=findSecNum(/^alerts/i,null); if(n!=null) jumpTo(n); }") | Should -BeTrue
        $html | Should -Match 'id="alertLifecycle"[\s\S]*id="lcStage"[\s\S]*id="lcStrip"'
        # Under Workspace at a glance, before the security posture cards.
        $html | Should -Match 'id="heroPills"[\s\S]*id="alertLifecycle"[\s\S]*Security posture'
        # Its own light and dark colours, and particles that follow a theme switch.
        $html | Should -Match 'html\[data-theme="dark"\] \.lifecycle\{'
        $html | Should -Match "window\.addEventListener\('sac-theme',frame\)"
        # Motion stops for anyone who asks for less of it.
        $html | Should -Match "matchMedia\('\(prefers-reduced-motion: reduce\)'\)"
    }

    It 'animates the estate flow: beads on the strands, creeping dashes, rings that draw in' {
        $html | Should -Match "const beads=\(tag,attrs,col,w,k,fam\)=>"
        $html | Should -Match 'svg\.estate \.es-beads\{[^}]*pointer-events:none'
        $html | Should -Match 'svg\.estate \.es-unc\{animation:esdash'
        $html | Should -Match "svgEl\.querySelectorAll\('\.es-beads'\)\.forEach\(el=>el\.classList\.toggle\('es-hot'"
        # The arcs draw in only when the viewer has not asked for less motion.
        $html | Should -Match "if\(!\(window\.matchMedia && matchMedia\('\(prefers-reduced-motion: reduce\)'\)\.matches\)\)\{\s*arcs\.forEach"
    }

    It 'animates the Data flow Sankey: beads on the ribbons and a reveal that fails open' {
        $html | Should -Match 'svg\.sankey \.sk-beads\{[^}]*pointer-events:none'
        $html.Contains("const bd=mk('path',{d:d,class:'sk-beads','data-fam':fam,") | Should -BeTrue
        # The clip starts full width, so a reveal that never runs hides nothing.
        $html.Contains("mk('rect',{x:0,y:0,width:W,height:H},null,clip);") | Should -BeTrue
        $html | Should -Match 'function revealSankey\(svgEl\)'
        # A frame stamped just before the start never yields a negative width.
        $html.Contains("const step=now=>{ const k=Math.max(0,Math.min(1,(now-t0)/dur)), e=1-Math.pow(1-k,3);") | Should -BeTrue
        $html | Should -Match "prefers-reduced-motion: reduce\)'\)\.matches\) \|\| !svgEl\.getBoundingClientRect\(\)\.width\) return;"
        $html | Should -Match "if\(name==='flow' && big\) revealSankey\(big\);"
    }

    It 'draws the ingest and billing flow in the lifecycle style: family dots, table pills, plan rings, outcome nodes' {
        $html | Should -Match 'function drawSankey\(svgEl, opts\)\{'
        $html.Contains("const fx=232, tx=384, tw=262, px=842, ox=1012;") | Should -BeTrue
        $html.Contains("mk('rect',{x:tx,y:n._y-12,width:tw,height:24,rx:12,fill:col,'fill-opacity':'.16'") | Should -BeTrue
        $html.Contains("const C=2*Math.PI*R, planGb=cols[2].reduce((a,n)=>a+(+n.value||0),0)||1;") | Should -BeTrue
        $html.Contains("mk('circle',{cx:ox,cy:n._y,r:7,fill:col,filter:'url(#ibGlow)'},null,g);") | Should -BeTrue
        # Strands carry GB on a square-root scale; hovering a family spotlights it.
        $html.Contains("const sw=v=>Math.max(1.5,22*Math.sqrt((+v||0)/maxGb));") | Should -BeTrue
        $html | Should -Match 'svg\.sankey\.ib-dim \.ib-hot\{opacity:1\}'
        # The family filter, every-table and Other paths still go through onNode.
        $html.Contains("dim=drawSankey(big,{graph,onNode:n=>{") | Should -BeTrue
    }

    It 'shows the estate flow on the Data flow tab, above the ingest and billing flow, and no gap analysis button' {
        $html | Should -Match '(?s)<section data-view="flow" class="hidden">\s*<div class="panel">\s*<div class="phead"><div>\s*<h2>Estate flow</h2>.*?<h2>Ingest &amp; billing flow</h2>'
        $html | Should -Not -Match '(?s)<section data-view="overview">.*?<h2>Estate flow</h2>.*?</section>\s*<!-- DATA FLOW -->'
        $html | Should -Not -Match 'id="gapBtn"'
        # The estate strip gives Defender XDR's alerts a tile of their own.
        $html.Contains("...((+E.alertsXdr||0)>0? [{k:'xdr', h:'Defender XDR alerts', unit:'of every alert ('+WIN.d()+')',") | Should -BeTrue
    }

    It 'ends with a privacy notice that names the run date and never mentions _raw' {
        $html | Should -Match '\.privnote\{display:flex;'
        $html | Should -Not -Match 'privnote\{[^}]*border-left'
        # Full width, so its line does not wrap.
        $html | Should -Not -Match 'privnote\{[^}]*max-width'
        $html.Contains("'<div><div class=""privt"">Confidential: tenant configuration</div>'") | Should -BeTrue
        $html.Contains("const genAt=String((M.workspace&&M.workspace.generatedUtc)||'').trim();") | Should -BeTrue
        $html | Should -Not -Match '_raw snapshot'
    }

    It 'gives every card the dark screen in dark mode, below hover and accent rules' {
        $html | Should -Match 'html\[data-theme="dark"\] :where\(\.hero,\.panel,\.pill,\.ipanel,\.docnav,\.docpanel,\.card,\.fcard\)'
    }

    It 'draws the estate flow in the alert lifecycle style with the same layout and links' {
        $html | Should -Match "glow\.setAttribute\('id','esGlow'\)"
        $html | Should -Match "mk\('circle',\{class:'es-src','data-fam':s\.category"
        $html | Should -Match "(?s)class:'es-arc'.{0,400}?filter:'url\(#esGlow\)'"
        $html | Should -Match "mk\('circle',\{'data-inc':b\.l"
        $html | Should -Match "svgEl\.querySelectorAll\('\[data-inc\]'\)"
    }

    It 'carries the ATT&CK grid: tactics in kill-chain order, every technique, every rule and its cells' {
        $model = Get-Content (Join-Path $bundle 'model.json') -Raw | ConvertFrom-Json
        $a = $model.attack
        @($a.tactics).Count | Should -Be 14
        $a.tactics[0].id | Should -Be 'TA0043'
        $a.tactics[13].id | Should -Be 'TA0040'
        @($a.techniques).Count | Should -BeGreaterThan 200
        @($a.techniques | Where-Object { $_.id -match '\.' }).Count | Should -Be 0
        @($a.rules).Count | Should -Be 5
        @($a.rules | Where-Object { -not $_.enabled }).name | Should -Be 'Lateral movement detected'
        # A cell only a disabled rule covers is carried, for the "Include disabled" view.
        $lateral = @($a.cells | Where-Object { $_.tactic -eq 'LateralMovement' -and $_.technique -eq 'T1021' })[0]
        $a.rules[@($lateral.rules)[0]].enabled | Should -BeFalse
        $lateral.subs[0].id | Should -Be 'T1021.001'
        $a.subNames.'T1021.001' | Should -Be 'Remote Desktop Protocol'
        # Every sub-technique is named and listed under its parent, for the
        # sub-technique view's "Every technique".
        $t1021 = @($a.techniques | Where-Object id -EQ 'T1021')[0]
        @($t1021.subs) | Should -Contain 'T1021.001'
        @($t1021.subs).Count | Should -Be $t1021.subTotal
        @($a.subNames.PSObject.Properties).Count | Should -BeGreaterThan 300
        # Brute Force sits under Credential Access only, as on the MITRE page.
        @($a.cells | Where-Object technique -EQ 'T1110').tactic | Should -Be 'CredentialAccess'
    }

    It 'links the ATT&CK grid, the MITRE page and the inventory to the report' {
        $html | Should -Match 'id="akPanel"[\s\S]*id="akGrid"'
        $html | Should -Match "function wireAttackGrid\(\)"
        $html | Should -Match 'data-ak-rules="all">Include disabled'
        $html | Should -Match 'data-ak-show="all">Every technique'
        $html | Should -Match 'data-ak-level="tech">Techniques</button><button type="button" data-ak-level="sub">Sub-techniques'
        $html | Should -Match "sbtn\('All of '\+esc\(c\.technique\),'data-ak-parent'\)"
        # The grid sits directly above Detection opportunities.
        $html | Should -Match "\{full:'Content inventory'\}[\s\S]*\{full:'Detection coverage by MITRE'\},\s*\{full:'Detection opportunities'\}"
        $html | Should -Match 'sbtn\(''Open the MITRE page'',''data-jump="''\+mitreSec\+''"'',\{go:true,cls:''ak-open''\}\)'
        # The MITRE page link is a button at the right of the grid's switches, not in the note.
        $html | Should -Match 'id="akSearch"[^>]*>''\+\s*\(mitreSec!=null\?sbtn\(''Open the MITRE page'''
        $html | Should -Match '\.ak-open\{margin-left:auto\}'
        $html | Should -Match "sbtn\('Open the ATT&amp;CK grid','data-akopen',\{go:true,cls:'dpage'\}\)"
        $html | Should -Match "\{k:'Connectors', v:c\.connectors, ic:ICON\.ingest, sec:secAt\(10\)\}"
    }

    It 'lists sub-techniques under their technique, each with its own rules, in the sub-technique view' {
        $html | Should -Match 'const list=every\? r\.subs : mapped;'
        $html | Should -Match 'class="ak-subrow '
        # Full ids, and violet for sub-techniques against green for techniques.
        $html | Should -Match '<span class="sid">''\+esc\(s\.id\)\+''</span>'
        $html | Should -Not -Match 's\.id\.slice\(s\.id\.indexOf'
        $html | Should -Match '\.ak-subrow\.h1,\.ak-key \.s1\{background:color-mix\(in srgb,var\(--ak-sub\)'
        $html | Should -Match '<i class="s1"></i><i class="s2"></i><i class="s3"></i>sub-technique'
        $html | Should -Match "const sub=s\.sub\? c\.subs\.find\(x=>x\.id===s\.sub\) : null;"
        $html | Should -Match 'const idx=sub\? sub\.rules : c\.rules;'
    }

    It 'styles the grid switches like the tabs and the Assessment switch' {
        $html | Should -Match '\.ak-seg button\.on\{color:#fff;background:var\(--btn-bg\);box-shadow:var\(--btn-shadow\)\}'
        # The Progress tab's baseline switch shares the rule.
        $html | Should -Match '\.subtab\.active,\.pgtab\.active\{color:#fff;background:var\(--btn-bg\);box-shadow:var\(--btn-shadow\)\}'
        $html | Should -Not -Match '\.ak-seg button\.on\{background:var\(--brand\);color:#fff\}'
    }

    It 'fills each Insights list card to its row and links to the report page with the whole list' {
        $html | Should -Match 'function fillCards\(\)'
        $html | Should -Match 'const FILL_MIN=8, FILL_CAP=40;'
        $html | Should -Match "sbtn\('All '\+total\.toLocaleString\(\)\+' '\+esc\(label\)\+' in the report'"
        # Each list card names the report page that holds every entry.
        $html | Should -Match "barsHtml\(tt,\{theme:'teal',fill:\{sec:secCostPage,label:'tables'\}\}\)"
        $html | Should -Match "barsHtml\(tr,\{theme:'indigo',fill:\{sec:secRulePerf,label:'rules'\}\}\)"
        $html | Should -Match "barsHtml\(pi,\{theme:'rose',fill:\{sec:secAlerts,label:'sources'\}\}\)"
        $html | Should -Match "barsHtml\(hi,\{theme:'cyan',fill:\{sec:secHealth,label:'operations'\}\}\)"
        $html | Should -Match "barsHtml\(fl,\{theme:'rose',fill:\{sec:secAutomation,label:'failing playbooks'\}\}\)"
        $html | Should -Match "secRulePerf=findSecNum\(/\^rule performance/i, null\)"
        $html | Should -Match '<tbody data-fill-list data-fill-total="''\+rows\.length\+''">'
        # No list card expands in place any more.
        $html | Should -Not -Match "show:8,label:'(tables|rules|operations|playbooks)'"
        # It runs when the Insights tab shows.
        $html | Should -Match "if\(name==='sections'\) fillCards\(\);"
        # Detection opportunities: the first twelve, then the report page.
        $html | Should -Match "fillFoot\(rows\.length,opNum,'tables',false,true\)"
        # The buttons sit at the foot of their cards, so a row's line up.
        $html | Should -Match '\.iband>\.ipanel:has\(>\.fillmore\)\{display:flex;flex-direction:column\}'
        $html | Should -Match '\.iband>\.ipanel>\.fillmore\{margin-top:auto;'
        # The data lake card keeps its button and drops the duplicate link above.
        $html | Should -Match "fill:\{sec:lakeNum,label:'tables',keep:true\}"
        $html | Should -Match "lakeNum!=null&&!ext\.length\?sbtn\('Open the data lake page'"
    }

    It 'opens a criterion from the roadmap or a quick win by filtering the criteria list' {
        $html | Should -Match '<tr class="frow" role="button" tabindex="0" data-crit="'
        $html | Should -Match '<div class="qwi" role="button" tabindex="0" data-crit="'
        $html | Should -Match "window\.showCriterion=function\(id\)\{"
        $html | Should -Match "sel\.value=''; ar\.value=''; q\.value=id; renderCriteria\(\);"
        $html | Should -Match 'id="matClear"'
        # An id on its own matches that criterion only.
        $html | Should -Match "const exact=!!s && \(MAT\.criteria\|\|\[\]\)\.some\(c=>c\.id\.toLowerCase\(\)===s\);"
        # Each criterion links to the findings behind it.
        $html | Should -Match 'function critFindingLinks\(c\)'
    }

    It 'lists every area on the Overview maturity card, weakest first, each opening its criteria' {
        $html | Should -Match 'function matAreasHtml\(areas, tg\)'
        $html | Should -Match 'matAreasHtml\(MAT\.areas\|\|\[\], tg\)\+'
        $html | Should -Match 'data-area="''\+esc\(a\.id\)\+''"'
        # Areas without a score are named, not dropped.
        $html | Should -Match 'Not assessed: '
        $html | Should -Match 'window\.showMaturityArea=function\(areaId\)\{'
        $html | Should -Match 'sel\.value=''''; q\.value=''''; ar\.value=areaId; renderCriteria\(\);'
        # The button sits at the foot of the card.
        $html | Should -Match '#maturityCard>\.btn\{margin-top:auto;'
    }

    It 'fills the quick wins to the maturity card beside them, the two buttons in line' {
        $html | Should -Match '<div class="panel" id="quickWinsCard">'
        $html | Should -Match 'function fillQuickWins\(\)\{'
        $html | Should -Match 'const QW_MIN=3, QW_STACKED=5;'
        # As many as fit without growing past the maturity card.
        $html | Should -Match 'while\(n<items\.length\)\{ set\(n\+1\); if\(card\.offsetHeight>target\)\{ set\(n\); break; \} n\+\+; \}'
        # The rest behind Show all; when all fit, the button opens the roadmap.
        $html | Should -Match 'more\.hidden=n>=items\.length; road\.hidden=n<items\.length;'
        $html | Should -Match 'window\.showRoadmap=function\(\)\{'
        $html | Should -Match '<div class="panel" id="matRoadmap">'
        $html | Should -Match '#quickWins \.qwfoot\{margin-top:auto;align-self:flex-start\}'
        $html | Should -Match "if\(name==='overview'\) fillQuickWins\(\);"
    }

    It 'shows only the critical findings on the Overview, with a button to every finding' {
        $html | Should -Match "topF = allF\.filter\(f=>f\.severity==='Critical'\)"
        $html | Should -Match 'sbtn\(''All ''\+allF\.length\.toLocaleString\(\)\+'' findings in the assessment'',''data-go="findings"'''
        $html | Should -Match 'No critical findings in this run\.'
        $html | Should -Not -Match "rowsMore\(topF\.map\(findingCard\),6,'div'\)"
    }

    It 'shows the data lake on the billing plan card when the lake is enrolled' {
        $html | Should -Match "label:'Data lake plan',value:lakeGb"
        $html | Should -Match 'if\(activePlans\.length>=2 \|\| \(lakeOn && activePlans\.length\)\)'
        $html | Should -Match 'mirrored to it at no extra ingestion charge'
        $html | Should -Match '\.bar\.lake \.bf\{background:linear-gradient'
    }

    It 'sorts any Report table by a column title: ascending, descending, then the page order' {
        $html | Should -Match 'aria-sort="none"><button type="button" class="thsort" title="Sort by this column">'
        $html | Should -Match 'function sortTable\(table, th\)\{'
        $html | Should -Match "const next=\{none:'ascending',ascending:'descending',descending:'none'\}"
        # Numbers with a unit sort by value (KB to TB scaled); text sorts naturally.
        $html | Should -Match 'const SORT_UNITS=\{kb:1e3,mb:1e6,gb:1e9,tb:1e12\};'
        $html | Should -Match 'new Intl\.Collator\(undefined,\{numeric:true,sensitivity:''base''\}\)'
        # Wired on every rendered table.
        $html | Should -Match "content\.querySelectorAll\('table\.doct thead th'\)\.forEach"
        $html | Should -Match 'table\.doct th\[aria-sort="ascending"\] \.sorti'
    }

    It 'keeps every Report page within the contents list: tabs when taller, then smaller tables, then a scroll' {
        $html | Should -Match 'const DOC_TAB_SMALL=20, DOC_TABLE_MIN=200, DOC_STRIP=76, lastDocTab=\{\};'
        $html | Should -Match 'function layoutDoc\(\)\{'
        # Fits: one page, tables grow into the space. Taller: tabs.
        $html | Should -Match 'if\(end\(\)<=limit\+1 \|\| secEls\.length<2\)\{ alignTables\(body\); fitTables\(body, limit, end\); contain\(body, limit, end\); realign\(body\); return done\(\); \}'
        # A big section starts a tab; a small one joins while it fits.
        $html | Should -Match 'if\(!cur \|\| \(it\.big && cur\.items\.length\) \|\| cur\.h\+it\.h>cap\)\{'
        $html | Should -Match "t\.full=t\.items\[0\]\.big\? t\.items\[0\]\.label : \(i===0\? 'Overview' : t\.items\[0\]\.label\);"
        # Too tall: the tallest tables shrink first, then the tab scrolls.
        $html | Should -Match 'function fitTables\(scope, limit, end\)\{'
        $html | Should -Match 'function contain\(scope, limit, end\)\{'
        # The ARIA tablist, arrow keys and short labels; no All tab.
        $html | Should -Match "strip\.setAttribute\('role','tablist'\)"
        $html | Should -Match 'ArrowRight:\(i\+1\)%tabsDef\.length'
        $html | Should -Match 'const shortLabel=l=>'
        $html | Should -Not -Match '>All</button>'
        # Run on page and tab changes, resize, the contents search and the tab showing.
        $html | Should -Match "if\(name==='sectionsdoc' && window\.layoutDoc\) window\.layoutDoc\(\);"
        $html | Should -Match 'wireNav\(\); layoutDoc\(\);'
        $html | Should -Match '\.doccontent\{min-width:0;align-self:stretch;display:flex;flex-direction:column\}'
        $html | Should -Match '\.docpane,\.docsec,\.docintro\{display:flow-root\}'
        $html | Should -Not -Match 'fitDocTables'
    }

    It 'draws the inner tabs as underlined page tabs, not a switch track' {
        $html | Should -Match '\.doctabs\{display:flex;flex-wrap:wrap;gap:2px 24px;margin:20px 0 16px;border-bottom:1px solid var\(--line\)\}'
        $html | Should -Match '\.doctab\[aria-selected="true"\]::after\{background:var\(--btn-bg\)\}'
        $html | Should -Not -Match '\.doctabs\{[^}]*background:var\(--chip\)'
    }

    It 'shows a line of figures in a Report page as aligned tiles' {
        $html | Should -Match 'function kvTiles\(html\)\{'
        $html | Should -Match "if\(b\.t==='p'\) return kvTiles\(b\.html\) \|\| refLinks\(b\.html\) \|\| '<p>'\+b\.html\+'</p>';"
        # Minutes become days and hours; a text-only line stays text.
        $html | Should -Match "return d\? d\+'d '\+h\+'h' : h\? h\+'h '\+mi\+'m' : mi\+' min';"
        $html | Should -Match '\.length\*2 < tiles\.length\) return '''';'
        # Adjacent lines share one grid; the tiles line up through subgrid.
        # Only a tile grid's marked end joins the next, never a chart card's.
        $html.Contains('.replace(/<\/div><!--\/kv--><div class="kvtiles">/g,'''')') | Should -BeTrue
        $html.Contains("+'</div><!--/kv-->';") | Should -BeTrue
        $html.Contains('<\/div><\/div><div class="kvtiles">') | Should -BeFalse
        $html | Should -Match '\.kvt\{display:grid;grid-row:span 3;grid-template-rows:subgrid;'
    }

    It 'keeps a page''s description under its title, above any tabs' {
        $html | Should -Match 'if\(intro\.length && intro\[0\]\.t===''p'' && !kvTiles\(intro\[0\]\.html\) && !refLinks\(intro\[0\]\.html\)\)\{ desc=''<p class="docdesc">'''
        $html | Should -Match '\.kvc\{[^}]*overflow-wrap:anywhere\}'
    }

    It 'shows a long list in a Report table cell as chips with Show all, and template solutions on the card' {
        $html | Should -Match 'const CELL_CHIPS=3;'
        $html | Should -Match 'function listCell\(c, head\)\{'
        $html | Should -Match "const chips=c\? listCell\(c, head\) : ''; if\(chips\) return chips;"
        $html | Should -Match '\.cellchips \.tagpill\.inst\{'
        $html | Should -Match "t\.installed===true\?' \(installed\)'"
        $model = Get-Content (Join-Path $bundle 'model.json') -Raw | ConvertFrom-Json
        @($model.detectionOpportunities | ForEach-Object { $_.templates } | Where-Object { $_ }) | ForEach-Object { $_.PSObject.Properties.Name | Should -Contain 'solution' }
    }

    It 'opens the rest of a table, or of a cell''s chips, with a chevron held at the top right' {
        $html | Should -Match 'function moreChev\(total,label,cls\)\{'
        $html | Should -Match '\.morechev\[aria-expanded="true"\] svg\{transform:rotate\(180deg\)\}'
        # In a table's header row; under the table only when it has no header.
        $html | Should -Match 'table\.tbl thead th \.morechev\{float:right;'
        $html.Contains("inner.replace(/<\/th>(\s*)<\/tr>(\s*)<\/thead>/, ()=>moreChev(total,label)+'</th></tr></thead>')") | Should -BeTrue
        # Chips wrap on the left; the chevron sits beside them, not after them.
        $html | Should -Match '\.oppl>\.morechev,\.cellchips>\.morechev\{flex:none\}'
        $html.Contains("'<div class=""morewrap cellchips""><div class=""chipl"">'") | Should -BeTrue
        $html.Contains("(items.length>CELL_CHIPS? moreChev(items.length) : '')") | Should -BeTrue
        $html.Contains("(o.templates.length>PILLS?moreChev(o.templates.length,'templates'):'')") | Should -BeTrue
        # Every table that hides rows uses moreTable; moreWrap is left for lists.
        $html | Should -Not -Match 'moreWrap\((''<table|head\+trRows)'
        ([regex]::Matches($html, 'moreTable\(')).Count | Should -BeGreaterThan 6
        $html | Should -Not -Match 'morepill'
        # The chevron keeps its label as tooltip and accessible name.
        $html.Contains("if(b.classList.contains('morechev')){ b.setAttribute('aria-label',label); b.title=label;") | Should -BeTrue
    }

    It 'tints a chip whose templates are ready to enable, Built-in included, and keys the colours as filters' {
        $html.Contains("const readyChip=x=>/,\s*installed\)$/.test(x) || /^Built-in \(\d+\)$/.test(") | Should -BeTrue
        # The key is the filter chips with the legend's swatches and a row count each.
        $html | Should -Match 'function chipKey\(tid,nReady,nNot\)\{'
        $html.Contains("k('ready','Installed or built in',nReady,") | Should -BeTrue
        $html.Contains("k('notinst','Not installed',nNot,") | Should -BeTrue
        $html | Should -Match '\.chipkey \.fchip i\{display:inline-block;width:11px;height:11px;border-radius:4px'
        $html.Contains("const key=nReady ? chipKey(tid, nReady, kinds.filter(k=>k.notinst).length) : '';") | Should -BeTrue
        # Rows carry their chip kinds; the search box and the key filter together.
        $html.Contains("'<tr'+(kinds[ri].ready?' data-ready=""1""':'')+(kinds[ri].notinst?' data-notinst=""1""':'')") | Should -BeTrue
        $html.Contains("const m=words.every(w=>txt.includes(w)) && (!want || tr.dataset[want]==='1') && pinned(tr) && grouped(tr);") | Should -BeTrue
        # With the key on, each row's chips narrow to that kind (all of them), and the chevron hides.
        $html.Contains("ch.hidden=want? (want==='ready'? !ready : ready) : (ch.hasAttribute('data-mr') && !w.classList.contains('open'));") | Should -BeTrue
        $html.Contains("if(chev) chev.hidden=!!want;") | Should -BeTrue
        # A single solution in a From solutions cell is a chip too, so it shows its colour.
        $html | Should -Match 'const solCol=/\^from solutions\?\$/i'
    }

    It 'lets a solution chip list its templates and open the template list filtered to them' {
        $html | Should -Match 'function linkSolutionChips\(\)\{'
        $html.Contains("return h.includes('template') && h.includes('solution') && h.includes('tables');") | Should -BeTrue
        $html.Contains("const names=tpl.filter(x=>x.sol===m[1] && x.tables.includes(tbl.toLowerCase())).map(x=>x.name);") | Should -BeTrue
        $html | Should -Match 'function openTemplates\(sol, tbl\)\{'
        # Pinned to the solution and table exactly, not a text match, with a chip to clear it.
        $html.Contains("list.dataset.pinSol=sol; list.dataset.pinTbl=tbl;") | Should -BeTrue
        $html.Contains("tr.children[iS].textContent.trim()===pin.sol && tr.children[iTb].textContent.toLowerCase().split(',')") | Should -BeTrue
        $html.Contains("chip.onclick=()=>{ delete list.dataset.pinSol; delete list.dataset.pinTbl; chip.remove(); docFilter(list.id); };") | Should -BeTrue
        # The renderer's tables carry the columns this joins on.
        $md = Get-Content (Join-Path $ws 'sections/28-detection-opportunities.json') -Raw
        foreach ($col in 'Table', 'From solutions', 'Template', 'Solution', 'Tables') { $md | Should -Match ('"text": "' + $col + '"') -Because $col }
    }

    It 'lets a summary value open the rows behind it in the bigger table it groups' {
        $html | Should -Match 'function linkGroupRows\(\)\{'
        $html | Should -Match 'linkSolutionChips\(\);\s*linkGroupRows\(\);'
        # The summary's first column names a column of a bigger table that repeats its values; the summary's own values are unique.
        $html.Contains("if(vals.length<=sumRows.length || new Set(vals).size===vals.length) return;") | Should -BeTrue
        $html.Contains("if(new Set(sumVals).size!==sumVals.length) return;") | Should -BeTrue
        # Opening pins that table to the value, exactly, with a chip to clear it.
        $html | Should -Match 'function openGroup\(detId, col, val\)\{'
        $html.Contains("det.dataset.pinCol=String(col); det.dataset.pinVal=val;") | Should -BeTrue
        $html.Contains("const grouped=tr=>!gp || (!!tr.children[gp.i] && tr.children[gp.i].textContent.trim().toLowerCase()===gp.v);") | Should -BeTrue
        $html.Contains("chip.onclick=()=>{ delete det.dataset.pinCol; delete det.dataset.pinVal; chip.remove(); docFilter(det.id); };") | Should -BeTrue
        # Keyboard as well as pointer, and its tooltip names the table by its section heading.
        $html.Contains("const g=e.target.closest('.grouplink'); if(g && (e.key==='Enter' || e.key===' '))") | Should -BeTrue
        $html.Contains("sec=el.closest('.docsec'), h=sec && sec.querySelector('.dsech');") | Should -BeTrue
        # The plans page carries the summary and the table it groups.
        $md = Get-Content (Join-Path $ws 'sections/81-table-plans-retention.json') -Raw
        $md | Should -Match '"text": "Summary by plan"'
        $md | Should -Match '"text": "Operational tables"'
    }

    It 'shows status words in report cells as pills and puts a chart''s key above its bars' {
        $html | Should -Match 'const STATUS_PILL=\{''Up to date'':''Met'',''Current'':''Met'',''Update available'':''Warn'''
        $html | Should -Match '\.st\.Warn\{background:var\(--amber\)\}'
        $html | Should -Match 'class="legend top"'
    }

    It 'draws every chart kind, the diagrams through the chart web part''s bundled renderers' {
        # The site build puts the bundle in place of the placeholder.
        $html | Should -Not -Match '/\*__SAC_CHARTS__\*/'
        $html | Should -Match 'window\.SacCharts=\{ renderChart: rc\.renderChart'
        $html | Should -Match "const chartHtml=b=> b\.kind==='pie'\? pieChartHtml\(b\) : b\.kind==='xy'\? xyChartHtml\(b\) : wpChartHtml\(b\);"
        $html | Should -Match "window\.addEventListener\('sac-theme',\(\)=>\{\s*if\(!window\.SacCharts\) return;"
        # A diagram link to a section or a finding opens it in the dashboard.
        $html | Should -Match '/#sac-\(section\|finding\)-\(\.\+\)\$/'
        $model = Get-Content (Join-Path $bundle 'model.json') -Raw | ConvertFrom-Json
        $kinds = @($model.sections | ForEach-Object { $_.blocks } | Where-Object { $_.t -eq 'chart' } | ForEach-Object kind | Sort-Object -Unique)
        @($kinds | Where-Object { $_ -notin 'pie', 'xy' }).Count | Should -BeGreaterThan 0
    }

    It 'draws the incident lifecycle graphic and drops a diagram title that repeats its heading' {
        $model = Get-Content (Join-Path $bundle 'model.json') -Raw | ConvertFrom-Json
        $inc = @($model.sections | Where-Object { $_.num -eq 15 })[0]
        $charts = @($inc.blocks | Where-Object { $_.t -eq 'chart' })
        @($charts.kind) | Should -Be @('incident-lifecycle', 'journey', 'pie')
        $charts[0].data.raised | Should -Be 40
        $charts[1].title | Should -BeNullOrEmpty
        $charts[2].title | Should -Be 'Closed incidents by classification (30d)'
        # Show all in a graphic is the site's button after the whole list, not a disclosure.
        $html.Contains('class="sbtn morebtn" data-more data-all="') | Should -BeTrue
        $html | Should -Not -Match '<summary style="display:inline-block;cursor:pointer;margin:6px 0 4px'
        # The figures line a graphic shows is left out of the dashboard.
        $ch = @($model.sections | Where-Object { $_.num -eq 70 })[0]
        @($ch.blocks | Where-Object { $_.t -eq 'p' -and $_.html -match 'Content Hub package\(s\) installed' }).Count | Should -Be 0
        # The overview's stage table is in the estate graphic, so the dashboard leaves it out.
        $ov = @($model.sections | Where-Object { $_.num -eq 0 })[0]
        @($ov.blocks | Where-Object { $_.t -eq 'table' -and (@($_.headers) -join ' ') -match 'Rating' }).Count | Should -Be 0
        $html | Should -Match 'function renderIncidentLifecycle\(data, theme\)'
        foreach ($fn in 'renderMeters', 'renderRuleKinds', 'renderResponseChain', 'renderTopology', 'renderCostBreakdown', 'renderAccess', 'renderLake', 'renderEstate', 'renderRunway', 'renderWorkspaceAge') {
            $html | Should -Match ('function ' + $fn + '\(data, theme\)')
        }
    }

    It 'marks report headings and callouts without a coloured edge bar' {
        $html | Should -Match '\.docbody h3::after\{content:'''';flex:1 1 auto;'
        $html | Should -Not -Match '\.docbody h3\{[^}]*border-left'
        $html | Should -Not -Match '\.docnote\{[^}]*border-left'
        $html | Should -Match '\.docnote\{position:relative;margin:16px 0;padding:10px 14px;border-radius:12px;'
    }

    It 'shows a paragraph or list of links only as a card of link tiles' {
        $html.Contains('function refLinks(html, heading){') | Should -BeTrue
        $html.Contains("if(b.t==='p') return kvTiles(b.html) || refLinks(b.html) || '<p>'+b.html+'</p>';") | Should -BeTrue
        $html.Contains("if(b.t==='ul') return refLinks((b.items||[]).join(' · ')) ||") | Should -BeTrue
        # A lead-in (See, Reference:) and the separators between links are all a links-only paragraph may hold.
        $html.Contains(".replace(/^(see also|see|references?|docs|further reading|read more)\s*:?/i,'').replace(/\band\b|&middot;|[·,;.:\s]/gi,'');") | Should -BeTrue
        $html.Contains("const head=heading || (items.every(x=>x.learn)? 'Microsoft Learn' : 'Further reading');") | Should -BeTrue
        $html | Should -Match '\.refl\{display:grid;grid-template-columns:repeat\(auto-fill,minmax\(300px,1fr\)\);gap:8px\}'
        $html | Should -Not -Match '\.refa\{[^}]*border-left'
    }

    It 'opens a matrix rule in Rule Performance, filtered to it' {
        # The rule name is a button, and the row passes its alert and incident counts.
        $html.Contains('<button type="button" class="dm-open" data-rule="''+esc(r.name)+''" data-alerts="''+n0(r.alerts)+''" data-incidents="''+inc+''"') | Should -BeTrue
        $html.Contains("window.openRuleReport(b.dataset.rule, {alerts:+b.dataset.alerts||0, incidents:+b.dataset.incidents||0})") | Should -BeTrue
        $html.Contains('window.openRuleReport = function(name, counts){') | Should -BeTrue
        $html.Contains("const sec=secs.find(x=>/^rule performance$/i.test(cleanTitle(x.title||'')));") | Should -BeTrue
        # Each table is filtered to the rule; the incidents table wins when it lists it.
        $html.Contains("if(inp){ inp.value='`"'+want+'`"'; docFilter(t.id); }") | Should -BeTrue
        $html.Contains('if(hit && (!best || (inc && !best.inc))) best={t, tr:hit, inc};') | Should -BeTrue
        $html.Contains("note.innerHTML='<span>Rule Performance for <b>'+esc(want)+'</b>.'+esc(why)+'</span>'+sbtn('Show every rule','data-unpin-rule');") | Should -BeTrue
        $html | Should -Match 'Select a rule to open it in Rule Performance\.'
    }

    It 'colours callouts by tone and severity in the Defender XDR colours' {
        $html.Contains("const NOTE_TONE={info:'', success:'Good news', warning:'Warning', critical:'Critical'};") | Should -BeTrue
        $html.Contains("return '<div class=`"docnote dn t-'+tone+'`">") | Should -BeTrue
        $html | Should -Match '\.docnote\.t-warning\{background:color-mix\(in srgb,var\(--amber\)'
        $html | Should -Match '\.docnote\.t-critical\{background:color-mix\(in srgb,var\(--red\)'
        $html | Should -Not -Match '\.docnote[^{]*\{[^}]*border-left'
        # Severity: High orange-red, Medium amber, Low yellow, Informational grey.
        $html.Contains("const SEV=[['High','H','#ff4d1f'],['Medium','M','#ffaa00'],['Low','L','#fff100'],['Informational','I','#8a8886']];") | Should -BeTrue
        $html.Contains("const SEVC={High:'#ff4d1f',Medium:'#ffaa00',Low:'#fff100',Informational:'#8a8886'") | Should -BeTrue
        $html | Should -Match '\.sev\.High\{background:#ff4d1f;color:#0b1220\}'
        # The confidentiality footer is red.
        $html | Should -Match '\.privnote\{[^}]*color-mix\(in srgb,var\(--red\) 10%'
    }

    It 'puts a card''s single table chevron in the card''s top-right corner' {
        $html.Contains("const card=ch.closest('.ipanel, .panel'); if(!card || card.querySelectorAll('table thead .morechev').length!==1) return;") | Should -BeTrue
        $html.Contains("if(head) head.appendChild(ch); else { ch.classList.add('abs'); card.classList.add('has-cardchev'); card.appendChild(ch); }") | Should -BeTrue
        $html.Contains("const wrap=b.dataset.wrap? document.getElementById(b.dataset.wrap) : b.closest('.morewrap');") | Should -BeTrue
        $html.Contains('new MutationObserver(()=>{ if(liftQueued) return;') | Should -BeTrue
    }

    It 'wraps a long table column as a whole and code at its slashes' {
        $html.Contains("formatted.some(r=>String(r[ci]==null?'':r[ci]).replace(/<[^>]+>/g,'').length>28)") | Should -BeTrue
        $html.Contains("c.innerHTML=c.textContent.split(/(?<=[\/.?=&])/).map(esc).join('<wbr>');") | Should -BeTrue
        $html | Should -Match 'table\.doct th code\{background:none;border:0;padding:0;font:inherit;color:inherit\}'
        $html | Should -Not -Match 'table\.doct td\.wrap[^{]*\{[^}]*overflow-wrap:anywhere'
    }

    It 'colours a criterion chip by its state, as the maturity view does' {
        $html.Contains('const CRIT_STATE=/^(SAC-[A-Z]{2,4}-\d{2})\s+(met|gap|unknown|not assessed)$/i;') | Should -BeTrue
        $html.Contains("const CRIT_CLS={met:'c-met', gap:'c-gap', unknown:'c-unknown', 'not assessed':'c-na'};") | Should -BeTrue
        $html | Should -Match '\.tagpill\.crit\.c-met\{background:var\(--green\)\} \.tagpill\.crit\.c-gap\{background:var\(--red\)\}'
        # The state stays in the tooltip and for a screen reader; one criterion is still a chip.
        $html.Contains('<span class="vh">, ''+esc(st)+''</span></span>') | Should -BeTrue
        $html.Contains("if(!solCol && !critCol && (items.length<2") | Should -BeTrue
        $html.Contains('items.map((x,i)=>critChip(x, i>=CELL_CHIPS) ||') | Should -BeTrue
    }

    It 'pins a page''s References under its tabs and opens a page on its first tab' {
        $html.Contains("const refIx=groups.findIndex(g=>/^references$/i.test(label(g))") | Should -BeTrue
        $html.Contains("(refsCard? '<div class=`"docrefs`">'+refsCard+'</div>' : '');") | Should -BeTrue
        @([regex]::Matches($html, [regex]::Escape("const refs=body.querySelector(':scope > .docrefs'); if(refs) body.appendChild(refs);"))).Count | Should -Be 2
        $html.Contains('if(s.num!==curDocNum) delete lastDocTab[s.num];') | Should -BeTrue
        # Readable headers still mark their columns to wrap.
        $html.Contains('data ?types') | Should -BeTrue
        $html.Contains('applies ?to') | Should -BeTrue
    }

    It 'keeps numeric report columns to their content and chart labels whole' {
        # A numeric column shrinks to fit, so a Level column sits beside its Name.
        $html | Should -Match 'table\.doct th\.num\{width:1%\}'
        # A report bar chart's rows share one grid whose label column fits the longest label.
        $html | Should -Match '\.cbars\{display:grid;grid-template-columns:fit-content\(50%\) minmax\(80px,1fr\) auto;'
        $html | Should -Match '\.cbar\{grid-column:1/-1;display:grid;grid-template-columns:subgrid;'
        $html.Contains('+''<div class="cbars">''+rows+''</div></div>'';') | Should -BeTrue
    }

    It 'gives a flowchart node an in-dashboard link to its section or finding' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1'), [ref]$null, [ref]$null)
        . ([scriptblock]::Create($ast.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq 'ConvertTo-DashboardChartData' }, $true).Extent.Text))
        $chart = @{ kind = 'flowchart'; data = @{ nodes = @(
                    @{ id = 'a'; label = 'Gap'; href = '90-gap-analysis.md'; target = @{ kind = 'section'; section = '90-gap-analysis' } }
                    @{ id = 'b'; label = 'F'; href = '90-gap-analysis.md#sac-gov-05'; target = @{ kind = 'finding'; id = 'SAC-GOV-05' } }
                    @{ id = 'c'; label = 'Learn'; href = 'https://learn.microsoft.com/x'; target = @{ kind = 'external' } }
                    @{ id = 'd'; label = 'Repo'; href = 'Docs/x.md'; target = @{ kind = 'repo'; path = 'Docs/x.md' } }
                ) } }
        $data = ConvertTo-DashboardChartData -Chart $chart
        @($data.nodes).href | Should -Be @('/#sac-section-90', '/#sac-finding-SAC-GOV-05', 'https://learn.microsoft.com/x', $null)
    }

    It 'shows What''s new as a report page and makes no network call in the build' {
        $html | Should -Not -Match 'M\.whatsNew'
        $html | Should -Not -Match 'class="wnitem"'
        $html.Contains("'Generally available':'Met','Preview':'Info','Retiring':'Gap','Action needed':'Warn'") | Should -BeTrue
        $build = Get-Content -LiteralPath (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1') -Raw
        $build | Should -Not -Match 'Invoke-RestMethod|Invoke-WebRequest'
        $model = Get-Content (Join-Path $bundle 'model.json') -Raw | ConvertFrom-Json
        $wn = @($model.sections | Where-Object { $_.num -eq 3 })
        $wn.Count | Should -Be 1
        $wn[0].family | Should -Be 'Overview'
        # Two or three short items in a cell are chips too; the button only past three.
        $html | Should -Match 'items\.length<4 && items\.some\(x=>x\.replace\(/<\[\^>\]\+>/g,''''\)\.length>60\)'
    }

    It 'links each finding card to its finding: in the dashboard, and on SharePoint through the findings list' {
        $model = Get-Content (Join-Path $bundle 'model.json') -Raw | ConvertFrom-Json
        $ov = @($model.sections | Where-Object { $_.num -eq 0 })[0]
        $fc = @($ov.blocks | Where-Object { $_.t -eq 'chart' -and $_.kind -eq 'finding-cards' })[0]
        foreach ($c in @($fc.data.cards)) { $c.href | Should -Be ('/#sac-finding-' + $c.id) }
        $page = ConvertTo-SacChartData -Chart ([pscustomobject]@{ kind = 'finding-cards'; data = [pscustomobject]@{ cards = @([pscustomobject]@{ id = 'SAC-LOG-03'; href = '90-gap-analysis.md#sac-log-03' }) } }) -FindingsListUrl 'Lists/SentinelFindings'
        $page.cards[0].href | Should -Be '~site/Lists/SentinelFindings/AllItems.aspx?FilterField1=FindingId&FilterValue1=SAC-LOG-03'
        # The web part resolves ~site/ links against its own site.
        $html | Should -Match 'function setSiteUrl\(url\)'
        $wp = Get-Content -LiteralPath (Join-Path $repoRoot 'Modules/iSOCBlueprint/WebParts/src/webparts/isocBlueprintChart/IsocBlueprintChartWebPart.ts') -Raw
        $wp | Should -Match 'setSiteUrl\(this\.context\.pageContext\.web\.serverRelativeUrl\)'
        # The Overview no longer ends with a contents card per family.
        $html | Should -Not -Match 'id="contents"'
        $html | Should -Not -Match 'class="ctcard"'
    }

    It 'carries the earlier days of a run written to day folders, for the date picker' {
        $days = Join-Path $script:outDir 'days'
        $today = Join-Path $days '2026-10-02'
        New-Item -ItemType Directory -Path $today -Force | Out-Null
        Copy-Item -Path (Join-Path $ws '_raw'), (Join-Path $ws 'sections') -Destination $today -Recurse
        # An earlier day's own bundle, and one outside the window.
        foreach ($d in '2026-10-01', '2026-06-01') {
            $b = Join-Path $days "$d/sharepoint"
            New-Item -ItemType Directory -Path $b -Force | Out-Null
            "<html><!-- $d --></html>" | Set-Content (Join-Path $b 'index.html')
            @{ generatedUtc = "$d 06:00 UTC"; summary = @{ findings = 4; critical = 1; score = 2.5 } } | ConvertTo-Json | Set-Content (Join-Path $b 'site.json')
        }
        $built = & (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1') -Source $today -HistoryDays 30 6> $null
        $ix = Get-Content (Join-Path $built 'history/index.json') -Raw | ConvertFrom-Json
        @($ix.entries.date) | Should -Be @('2026-10-02', '2026-10-01')
        Test-Path (Join-Path $built 'history/2026-10-02.html') | Should -BeTrue
        (Get-Content (Join-Path $built 'history/2026-10-01.html') -Raw) | Should -Match '<!-- 2026-10-01 -->'
        $ix.entries[1].findings | Should -Be 4
        $ix.entries[1].score | Should -Be 2.5
        # This day's own figures come from its site descriptor's summary.
        $site = Get-Content (Join-Path $built 'site.json') -Raw | ConvertFrom-Json
        $ix.entries[0].findings | Should -Be $site.summary.findings
        # A run not in a day's folder carries no history.
        Test-Path (Join-Path $bundle 'history') | Should -BeFalse
    }

    It 'reads files beside the dashboard the way SharePoint allows' {
        # The date range took the snapshot picker's place in the top bar.
        $html | Should -Not -Match 'snapPick|snapBanner'
        $html | Should -Match '<div class="winbox" id="winWrap" hidden>'
        # A snapshot served as a file finds the live folder one level up.
        $html | Should -Match 'root=/\\/history\\/\$/\.test\(here\.pathname\)\? new URL\(''\.\.'',here\) : here;'
        # The maturity trend reads through the same path; about:srcdoc has no folder.
        $html | Should -Match "SNAP\.read\('maturity-history\.json'\)"
        $html | Should -Not -Match "new URL\('maturity-history\.json', window\.location\.href\)"
        $wp = Get-Content -LiteralPath (Join-Path $repoRoot 'Modules/iSOCBlueprint/WebParts/src/webparts/isocBlueprint/IsocBlueprintWebPart.ts') -Raw
        $wp | Should -Match 'sacSnapshot\?: ISnapshotHost \}\)\.sacSnapshot = snapshot;'
        $wp.IndexOf('.sacSnapshot = snapshot') | Should -BeLessThan $wp.IndexOf('.eval(extracted.script)')
        $wp | Should -Match 'read: \(file: string\): Promise<string> => this\._fetchHtml\(folder \+'
        # The publisher keeps the day's copy and prunes past -HistoryDays.
        $pub = Get-Content -LiteralPath (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/Publish-SentinelDocsSite.ps1') -Raw
        $pub | Should -Match '\[int\]\$HistoryDays = 90'
        $pub | Should -Match 'Send-SacSnapshot -Path \(Join-Path \$Bundle ''index\.html''\) -FileName \$snapFile'
        $pub | Should -Match '\$siteIndex = Read-SacSnapshotIndex'
        $pub | Should -Match 'Add-SacSnapshotEntry -Index \$siteIndex -Entry \$snapEntry -Days \$HistoryDays'
        # Days the bundle carries that the site lacks go up first.
        $pub | Should -Match 'Send-SacSnapshot -Path \$file -FileName \(\[string\]\$e\.file\)'
        $pub | Should -Match 'foreach \(\$old in @\(\$snapshots\.removed\)\) \{ Remove-SacSnapshot -FileName \$old \}'
    }

    It 'gives the chart web part the site''s button and its Show all toggle' {
        $wp = Get-Content -LiteralPath (Join-Path $repoRoot 'Modules/iSOCBlueprint/WebParts/src/webparts/isocBlueprintChart/IsocBlueprintChartWebPart.ts') -Raw
        $wp | Should -Match "'<style>' \+ chartStyles\(SCOPE, theme\) \+ '</style>'"
        $wp | Should -Match "closest\('\[data-more\]'\)"
        $wp | Should -Match "button\.dataset\.less \|\| 'Show fewer'"
    }

    It 'keeps the bundled renderers in step with the web part''s chart sources' {
        $charts = Join-Path $repoRoot 'Modules/iSOCBlueprint/WebParts/src/webparts/isocBlueprintChart/charts'
        $names = [string[]]@(Get-ChildItem -LiteralPath $charts -Filter '*.ts' -File | ForEach-Object Name)
        [Array]::Sort($names, [StringComparer]::Ordinal)
        $sb = [System.Text.StringBuilder]::new()
        foreach ($n in $names) {
            $text = (Get-Content -LiteralPath (Join-Path $charts $n) -Raw -Encoding utf8) -replace "`r`n", "`n"
            [void]$sb.Append($n).Append("`n").Append($text).Append("`n")
        }
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hash = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sb.ToString())))).Replace('-', '').ToLowerInvariant()
        $bundleText = Get-Content -LiteralPath (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/templates/dashboard-charts.js') -Raw
        $bundleText | Should -Match "sources-sha256: $hash" -Because 'a chart source changed: run ./Modules/iSOCBlueprint/WebParts/Build-DashboardCharts.ps1'
        $bundleText | Should -Not -Match '(?i)</script'
    }

    It 'shows the NIST CSF rollup above the roadmap' {
        $html.IndexOf('NIST CSF 2.0 rollup</h2>') | Should -BeGreaterThan 0
        $html.IndexOf('NIST CSF 2.0 rollup</h2>') | Should -BeLessThan $html.IndexOf('<h2>Roadmap</h2>')
    }

    It 'shows section titles, not Markdown file names, in the Report tab' {
        $model = Get-Content (Join-Path $bundle 'model.json') -Raw | ConvertFrom-Json
        # Text blocks only: a diagram's Mermaid source, shown only when it cannot
        # be drawn, keeps the Markdown links it was written with.
        $text = ($model.sections | ForEach-Object { $_.blocks } | Where-Object { $_.t -ne 'chart' } | ConvertTo-Json -Depth 32 -Compress)
        $text | Should -Not -Match '\b\d{2}-[a-z0-9-]+\.md\b'
        $text | Should -Match 'data-xsec=\\"90\\">Gap Analysis</a>'
    }

    It 'turns a file name into the section title on the native pages too' {
        $script:SacSectionTitles = @{ '90-gap-analysis' = 'Gap Analysis'; '84-cost-estimate' = 'Estimated Monthly Cost' }
        try {
            $runs = @(
                [pscustomobject]@{ text = '90-gap-analysis.md'; href = '90-gap-analysis.md'; target = [pscustomobject]@{ kind = 'section'; section = '90-gap-analysis' } }
                [pscustomobject]@{ text = ' lists every one; see ' }
                [pscustomobject]@{ text = '84-cost-estimate.md'; code = $true }
                [pscustomobject]@{ text = ' and 12-soc-optimization.md, not docs/84-cost-estimate.md' }
            )
            $out = ConvertTo-SacRunsHtml -Runs $runs -FindingsListUrl 'Lists/Findings'
            $out | Should -Match '<a href="~site/SitePages/sac-90-gap-analysis\.aspx">Gap Analysis</a> lists every one'
            $out | Should -Match 'see <a href="~site/SitePages/sac-84-cost-estimate\.aspx">Estimated Monthly Cost</a>'
            $out | Should -Not -Match '<code>'
            # A section not in this run reads as words; a path is left alone.
            $out | Should -Match 'and Soc optimization, not docs/84-cost-estimate\.md'
            Get-SacSectionLinkText -Text 'data connectors' -SectionId '10-data-connectors' | Should -Be 'data connectors'
        } finally { $script:SacSectionTitles = $null }
    }

    It 'gives every action button one look, the brand gradient, in light and dark' {
        # One gradient, defined per theme.
        $html | Should -Match '--btn-bg:linear-gradient\(135deg,var\(--brand\),var\(--accent\)\);'
        $html | Should -Match '--btn-bg:linear-gradient\(135deg,#2a63d6,#5b45c9\);'
        # One button class, .sbtn, carries the look; sbtn() makes every button.
        $html | Should -Match '\.sbtn\{display:inline-flex;[^}]*border-radius:10px;[^}]*background:var\(--btn-bg\);color:#fff;'
        $html | Should -Match '\.sbtn\.icon\{width:30px;height:30px;padding:0;'
        $html | Should -Match 'function sbtn\(label, attrs, opts\)\{'
        # Show all, Expand, the report buttons, Clear filters, zoom, the
        # finding links and the page links are all made with it.
        $html | Should -Match "const btn = total>shown \? sbtn\('Show all '"
        $html | Should -Match "sbtn\('Expand','data-ltx',\{cls:'ltx-btn'\}\)"
        $html | Should -Match '<button type="button" class="sbtn" id="findClear" hidden>'
        $html | Should -Match '<button type="button" class="sbtn" id="matClear" hidden>'
        $html | Should -Match '<button type="button" class="sbtn icon" id="zoomOut"'
        $html | Should -Match 'class="sbtn icon fc-expand" data-fcx'
        $html | Should -Match 'sbtn\(''Open as a page'',''target="_top"'',\{go:true,cls:''dpage'',href:pageUrl\}\)'
        $html | Should -Match "sbtn\('Close','data-esd-close'\)"
        # The classes those buttons used to carry only place them now.
        $html | Should -Not -Match 'class="link-muted"'
        $html | Should -Not -Match '\.morebtn\{[^}]*background'
        $html | Should -Not -Match '\.btn\{[^}]*padding'
        $html | Should -Not -Match '<a data-(esd|ak)-close>'
        # Selected filter chips match the selected switches.
        $html | Should -Match '\.fchip\.active\{background:var\(--btn-bg\);'
    }

    It 'links the Overview top alerting rules to the report after eight' {
        $html | Should -Match "sec=findSecNum\(/\^rule performance/i, null\)"
        $html | Should -Match "rows\.slice\(0,8\)\.join\(''\)"
        $html | Should -Match "sbtn\('All '\+rows\.length\.toLocaleString\(\)\+' rules in the report'"
    }

    It 'gives every tactic header the same height so the cells start level' {
        $html | Should -Match '\.ak-th b\{display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;height:2\.4em;'
        $html | Should -Match '\.ak-th span\{display:block;[^}]*white-space:nowrap;'
    }

    It 'themes the grid, report table and data flow scrollbars for light and dark' {
        $html | Should -Match 'color-scheme:light;'
        $html | Should -Match 'color-scheme:dark;'
        $html | Should -Match '\.ak-scroll,\.doctscroll,\.flowbox,\.dm-scroll\{scrollbar-width:thin;scrollbar-color:var\(--scroll-thumb\) transparent\}'
    }

    It 'gives a tactic outside the Enterprise matrix (an ICS one) a grid column of its own' {
        . (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Get-AttackCoverage.ps1')
        $catalogue = Get-Content (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Resources/mitre-attack.json') -Raw | ConvertFrom-Json
        $rule = [pscustomobject]@{ name = 'ics'; kind = 'Scheduled'; properties = [pscustomobject]@{
                displayName = 'Process control tampering'; enabled = $true; severity = 'High'
                tactics = @('ImpairProcessControl'); techniques = @('T0831') } }
        $cov = Get-AttackCoverage -Rules @($rule) -Catalogue $catalogue
        @($cov.Cells.Keys) | Should -Be @('ImpairProcessControl')
        @($cov.Cells['ImpairProcessControl'].Keys) | Should -Be @('T0831')
        # The dashboard appends columns for such tactics and sizes the grid to fit.
        $html | Should -Match 'const extra=\[\.\.\.new Set\(A\.cells\.map\(c=>c\.tactic\)\.filter\(t=>!known\.has\(t\)\)\)\]'
        $html | Should -Match "grid\.style\.gridTemplateColumns='repeat\('\+cols\.length"
    }

    It 'shows the pipeline figures as a strip inside the estate flow card, not as separate cards' {
        $html | Should -Match 'id="estateLegend"></div>\s*<div class="lc-strip es-strip" id="estateRings"></div>'
        $html | Should -Not -Match 'Estate pipeline \(30 days\)'
        $html | Should -Match 'class="lc-kpi es-kpi"''\+\(d\.sec!=null\?'' role="button"'
    }

    It 'leaves the closure split out for a snapshot collected before it' {
        $ws5 = Join-Path $outDir 'law-before-closedby'
        New-Item -ItemType Directory -Path (Join-Path $ws5 '_raw') -Force | Out-Null
        Copy-Item -Path (Join-Path $ws '_raw/*.json') -Destination (Join-Path $ws5 '_raw')
        $inc = @(Get-Content (Join-Path $ws5 '_raw/incidents-summary.json') -Raw | ConvertFrom-Json)
        $inc[0].PSObject.Properties.Remove('ClosedBy')
        $inc[0].PSObject.Properties.Remove('OpenBySeverity')
        ConvertTo-Json -InputObject $inc -Depth 10 | Set-Content (Join-Path $ws5 '_raw/incidents-summary.json')
        $b5 = & (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1') -Source $ws5 -SkipWhatsNew 6> $null
        $model = Get-Content (Join-Path $b5 'model.json') -Raw | ConvertFrom-Json
        $model.alertLifecycle.closedBy | Should -BeNullOrEmpty
        $model.alertLifecycle.openBySeverity | Should -BeNullOrEmpty
        $model.estate.incidentsClosed | Should -Be 32
        $model.alertLifecycle.mttrMinutes | Should -Be 1620
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
        ($outcomes | Where-Object label -eq 'Grant eligible').value | Should -Be 500
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

Describe 'Dashboard figures and labels' {
    BeforeAll {
        $script:dash = Get-Content (Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/templates/sharepoint-dashboard.html') -Raw
    }

    It 'writes the data flow''s ring and incident figures with thousands separators' {
        ([regex]::Matches($script:dash, [regex]::Escape("Number(d.value).toLocaleString()+' of '+Number(d.max).toLocaleString()"))).Count | Should -Be 2
        $script:dash.Contains("style:'fill:var(--ink)'},b.v.toLocaleString()),incTip);") | Should -BeTrue
        $script:dash | Should -Not -Match '\+d\.value\+'' of ''\+d\.max'
    }

    It 'labels the area badge as the confidence in the score, not the score' {
        $script:dash.Contains("const confText=c=>!c||c==='Not assessed'? (c||'n/a') : c+' confidence';") | Should -BeTrue
        $script:dash.Contains('esc(confText(a.confidence))') | Should -BeTrue
    }

    It 'labels the data flow''s source volumes with the window shown, not a fixed 30 days' {
        $script:dash.Contains("'SOURCE FAMILY (GB / '+WIN.d().toUpperCase()+')'") | Should -BeTrue
        $script:dash | Should -Not -Match 'SOURCE FAMILY \(GB / 30D\)'
    }

    It 'says the lifecycle''s GB a day counts billable and free, and splits it' {
        $script:dash.Contains("fmtGb(avg)+'<small>GB a day</small>'") | Should -BeTrue
        $script:dash.Contains("fmtGb(avgOf('billable'))+' billable and '+fmtGb(avgOf('free'))+' free</div>'") | Should -BeTrue
    }

    It 'says which window a re-scoped or fixed figure covers' {
        # The cost tile follows the slider and says so; the TI card does not and says so.
        $script:dash.Contains("s:cost? 'projected from '+WIN.span() : ''") | Should -BeTrue
        $script:dash.Contains("(WIN.days!==WIN.collected||WIN.ago>0)? ', over the collected '+WIN.cw()+': the dates chosen at the top do not re-scope this card'") | Should -BeTrue
    }

    It 'writes figures, money, dates and names in one style' {
        $script:dash.Contains("const fmtGb = n =>") | Should -BeTrue
        $script:dash.Contains("const MONTHS=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];") | Should -BeTrue
        $script:dash.Contains("(w.generatedUtc? '<span>'+ICON.history+'Collected '+esc(fmtDate(w.generatedUtc,{time:true}))+'</span>' : '')") | Should -BeTrue
        $script:dash.Contains("uksouth:'UK South'") | Should -BeTrue
        $script:dash.Contains("label:apiWords(i.label)") | Should -BeTrue
        # No currency code before an amount, and no locale-dependent month names.
        $script:dash | Should -Not -Match "esc\(DL\.cost\.currency\)\+' '"
        $script:dash | Should -Not -Match "toLocaleDateString\('en-GB'"
    }

    It 'sorts report tables by date and by amount in any currency' {
        $script:dash.Contains('const SORT_DATE=/^(\d{1,2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{4})(?: (\d{2}):(\d{2}))?(?: UTC)?$/;') | Should -BeTrue
        $script:dash.Contains('const NUM_PREFIX=/^-?\s*(?:[A-Z]{2,3}\$|[A-Z]{3} |[£$€¥₹₩]|<)\s*/;') | Should -BeTrue
    }

    It 'heads the page with the workspace, what the view covers and how it stands' {
        # The workspace's name (the product is the top bar's), where it lives
        # above it and when it was collected below.
        $script:dash | Should -Match '<h1 id="title"></h1>'
        $script:dash.Contains("document.getElementById('title').textContent = w.name||PRODUCT;") | Should -BeTrue
        $script:dash.Contains("['Sentinel workspace', w.region? regionName(w.region) : '', w.resourceGroup||'']") | Should -BeTrue
        # The lead sentence follows the tab: the days shown, as collected, or
        # (Progress) the runs compared.
        $script:dash.Contains('    curView=name; paintHeroCtx();') | Should -BeTrue
        $script:dash.Contains("'Showing activity in <b>'+esc(WIN.span())+'</b>'") | Should -BeTrue
        # The maturity ring (amber below target) and the findings by severity open their views.
        $script:dash | Should -Match '<button type="button" class="hkpi" data-go="maturity"'
        $script:dash | Should -Match '<button type="button" class="hkpi" data-go="findings"'
        $script:dash.Contains("+hMat.level<+hTarget? 'var(--amber)' : 'var(--brand)'") | Should -BeTrue
        $script:dash.Contains("heroFacts.addEventListener('click',e=>{ const b=e.target.closest('[data-go]'); if(b && !b.disabled && activateTab) activateTab(b.dataset.go); });") | Should -BeTrue
        $script:dash | Should -Not -Match 'class="fact '
    }

    It 'gives a key/value table no header row to sort by, as the site''s pages do' {
        $script:dash.Contains("const thead=b.headers.every(h=>plain(h)==='')? '' : '<thead><tr>'") | Should -BeTrue
    }
}
