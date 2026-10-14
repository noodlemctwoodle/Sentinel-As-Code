#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for the Blueprint section model: the Markdown-to-model converter,
    the Mermaid chart parser, and the renderer's sections/*.json output
    against the published schema.

.DESCRIPTION
    ConvertTo-BlueprintSection and ConvertFrom-BlueprintMermaid are pure, so
    they are exercised directly on small inputs. The renderer is then run
    over the fixture twice, with both output formats and with -OutputFormat
    Json, and every section file and the index are validated against
    Modules/iSOCBlueprint/Engine/Schemas.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Section-Model.Tests.ps1 -Output Detailed

.NOTES
    File:         Tests/iSOCBlueprint/Section-Model.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.2.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml (renderer)
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $private = Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Private'
    . (Join-Path $private 'ConvertFrom-BlueprintMermaid.ps1')
    . (Join-Path $private 'ConvertTo-BlueprintSection.ps1')
    $script:sectionSchema = Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Schemas/section.schema.json'
    $script:indexSchema = Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Schemas/section-index.schema.json'

    function ConvertTo-Model([string] $Markdown, [string] $Id = '20-analytics-rules') { ConvertTo-BlueprintSection -Markdown $Markdown -Id $Id }
    function Get-Chart([string] $Source) { ConvertFrom-BlueprintMermaid -Source $Source }
}

Describe 'ConvertTo-BlueprintSection' {

    Context 'title, banner and anchors' {
        BeforeAll {
            $md = "# Analytics rules`n`n> **Workspace** ``law``  ·  **Generated** 2026 UTC`n`n<a id=""sac-det-01""></a>`n### SAC-DET-01 Title`n`n## Plain heading`n`n> A real note"
            $script:m = ConvertTo-Model $md
        }
        It 'takes the H1 as the title' { $m.title | Should -Be 'Analytics rules' }
        It 'reads the order from the id' { $m.order | Should -Be 20 }
        It 'drops the metadata banner but keeps later quotes as notes' {
            @($m.blocks | Where-Object type -eq 'note').Count | Should -Be 1
            ($m | ConvertTo-Json -Depth 32) | Should -Not -Match 'Workspace'
        }
        It 'gives the heading after an anchor line that anchor' { $m.blocks[0].anchor | Should -Be 'sac-det-01' }
        It 'slugs other headings the way GitHub does' { $m.blocks[1].anchor | Should -Be 'plain-heading' }
        It 'validates against the schema' { Test-Json -Json ($m | ConvertTo-Json -Depth 64) -SchemaFile $sectionSchema | Should -BeTrue }
    }

    Context 'text runs' {
        BeforeAll {
            $script:runs = (ConvertTo-Model "# T`n`nPlain **bold** *it* ``code`` ~~gone~~ [ext](https://learn.microsoft.com/x) end.").blocks[0].text
        }
        It 'splits formatting into runs, with no Markdown left in the text' {
            ($runs | Where-Object bold).text | Should -Be 'bold'
            ($runs | Where-Object italic).text | Should -Be 'it'
            ($runs | Where-Object code).text | Should -Be 'code'
            ($runs | Where-Object strike).text | Should -Be 'gone'
            (($runs | ForEach-Object text) -join '') | Should -Not -Match '[*`~\[\]]'
        }
        It 'keeps the href and marks an external link' {
            $link = $runs | Where-Object href
            $link.href | Should -Be 'https://learn.microsoft.com/x'
            $link.target.kind | Should -Be 'external'
        }
    }

    Context 'link targets' {
        It 'recognises <Href> as <Kind>' -ForEach @(
            @{ Href = '90-gap-analysis.md#sac-log-03'; Kind = 'finding' }
            @{ Href = '#sac-gov-05'; Kind = 'finding' }
            @{ Href = '20-analytics-rules.md#volume'; Kind = 'section' }
            @{ Href = '#some-heading'; Kind = 'anchor' }
            @{ Href = '../../Content/Parsers/x.yaml'; Kind = 'repo' }
            @{ Href = 'https://example.com'; Kind = 'external' }
        ) {
            (Get-BpLinkTarget $Href).kind | Should -Be $Kind
        }
        It 'upper-cases the finding id and splits section and anchor' {
            (Get-BpLinkTarget '90-gap-analysis.md#sac-log-03').id | Should -Be 'SAC-LOG-03'
            $t = Get-BpLinkTarget '20-analytics-rules.md#volume'
            $t.section | Should -Be '20-analytics-rules'
            $t.anchor | Should -Be 'volume'
        }
    }

    Context 'tables' {
        BeforeAll {
            $script:t = (ConvertTo-Model "# T`n`n| Name | Count |`n|---|---:|`n| a<br>b | **5** |").blocks[0]
        }
        It 'keeps one row as one row of two cells' {
            @($t.rows).Count | Should -Be 1
            @($t.rows[0]).Count | Should -Be 2
        }
        It 'carries column alignment' { $t.columns[1].align | Should -Be 'right' }
        It 'turns <br> in a cell into a break run' { @($t.rows[0][0] | Where-Object { $_.Contains('break') }).Count | Should -Be 1 }
        It 'keeps formatting in cells' { $t.rows[0][1][0].bold | Should -BeTrue }
    }

    Context 'lists, code and rules' {
        BeforeAll {
            $script:b = (ConvertTo-Model "# T`n`n- one`n  - nested`n- two`n`n3. third`n`n``````kusto`nSigninLogs | take 1`n```````n`n---").blocks
        }
        It 'nests a sub-list under its item' {
            $b[0].type | Should -Be 'list'
            @($b[0].items).Count | Should -Be 2
            $b[0].items[0].blocks[0].type | Should -Be 'list'
        }
        It 'keeps an ordered list''s start number' { $b[1].start | Should -Be 3 }
        It 'keeps a non-Mermaid fence as code' { $b[2].type | Should -Be 'code'; $b[2].language | Should -Be 'kusto' }
        It 'keeps a horizontal rule' { $b[3].type | Should -Be 'rule' }
    }

    Context 'charts' {
        BeforeAll { $script:c = (ConvertTo-Model "# T`n`n``````mermaid`npie showData title Severity`n    ""High"" : 2`n```````n").blocks[0] }
        It 'turns a Mermaid fence into a chart block with data and source' {
            $c.type | Should -Be 'chart'
            $c.kind | Should -Be 'pie'
            $c.title | Should -Be 'Severity'
            $c.data.slices[0].value | Should -Be 2
            $c.source | Should -Match '^pie showData'
        }
    }
}

Describe 'Long tables' {
    # Markdig refuses a pipe table of about 2,700 rows as too deeply nested
    # (a live workspace's rule effectiveness table on page 21 hit it). The
    # converter parses long tables in chunks and joins them.
    BeforeAll {
        function New-TableMarkdown([int] $Rows, [string] $Name = 'Rule') {
            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.AppendLine("| $Name | Alerts |")
            [void]$sb.AppendLine('|---|---:|')
            for ($i = 1; $i -le $Rows; $i++) { [void]$sb.AppendLine("| [$Name $i](https://example.com/$i) | $i |") }
            $sb.ToString()
        }
    }

    It 'keeps every row of a 2,728-row table in one table block' {
        $m = ConvertTo-Model ("# Page`n`nIntro.`n`n" + (New-TableMarkdown 2728) + "`nAfter.`n")
        @($m.blocks).type -join ',' | Should -Be 'paragraph,table,paragraph'
        $table = @($m.blocks | Where-Object type -EQ 'table')[0]
        @($table.rows).Count | Should -Be 2728
        @($table.columns).Count | Should -Be 2
        $table.columns[1].align | Should -Be 'right'
        $table.rows[0][0][0].text | Should -Be 'Rule 1'
        $table.rows[2727][0][0].text | Should -Be 'Rule 2728'
        $table.rows[2727][0][0].href | Should -Be 'https://example.com/2728'
    }

    It 'keeps two long tables apart' {
        $m = ConvertTo-Model ("# Page`n`n" + (New-TableMarkdown 1200 'One') + "`nBetween.`n`n" + (New-TableMarkdown 700 'Two'))
        $tables = @($m.blocks | Where-Object type -EQ 'table')
        $tables.Count | Should -Be 2
        @($tables[0].rows).Count | Should -Be 1200
        @($tables[1].rows).Count | Should -Be 700
        $tables[1].rows[0][0][0].text | Should -Be 'Two 1'
    }

    It 'leaves Markdown without a long table untouched' {
        $md = "# Page`r`n`r`n" + (New-TableMarkdown 20) + "`r`n" + '```kusto' + "`r`n| take 1`r`n" + '```' + "`r`n"
        Split-BpLongTable -Markdown $md | Should -BeExactly $md
    }

    It 'does not cut table-like lines inside a code fence' {
        $fenced = '```text' + "`n" + (New-TableMarkdown 600) + '```' + "`n"
        $m = ConvertTo-Model ("# Page`n`n" + $fenced)
        @($m.blocks | Where-Object type -EQ 'table').Count | Should -Be 0
        $code = @($m.blocks | Where-Object type -EQ 'code')[0]
        ([regex]::Matches($code.text, '(?m)^\| \[Rule \d+\]')).Count | Should -Be 600
        $code.text | Should -Not -Match 'bp:table-continues'
    }
}

Describe 'ConvertFrom-BlueprintMermaid' {

    It 'parses a pie' {
        $c = Get-Chart "pie showData title Open findings`n    ""Critical"" : 0`n    ""Warning""  : 2"
        $c.kind | Should -Be 'pie'; $c.data.showData | Should -BeTrue
        @($c.data.slices).Count | Should -Be 2; $c.data.slices[1].label | Should -Be 'Warning'
    }

    It 'parses a sankey after config front matter' {
        $c = Get-Chart "---`nconfig:`n  sankey:`n    width: 1200`n---`nsankey-beta`n`n""Custom logs"",""Not monitored"",2010`n""Other"",""Ingestion"",0.4"
        $c.kind | Should -Be 'sankey'
        @($c.data.links).Count | Should -Be 2
        $c.data.links[1].value | Should -Be 0.4
    }

    It 'parses an xychart with named series' {
        $c = Get-Chart "xychart-beta`n    title ""By category""`n    x-axis [""Cost"", ""Data""]`n    y-axis ""Findings"" 0 --> 3`n    bar ""Warning"" [2, 1]`n    line [1, 1]"
        $c.kind | Should -Be 'xy'; $c.title | Should -Be 'By category'
        $c.data.xAxis.labels | Should -Be @('Cost', 'Data')
        $c.data.yAxis.max | Should -Be 3
        $c.data.series[0].name | Should -Be 'Warning'; $c.data.series[1].kind | Should -Be 'line'
    }

    It 'takes the full axis labels from a %% x-labels comment' {
        $c = Get-Chart "xychart-beta`n    x-axis [""DeviceProces"", ""EmailEvents""]`n    %% x-labels [""DeviceProcessEvents"", ""EmailEvents""]`n    bar [3, 1]"
        $c.data.xAxis.labels | Should -Be @('DeviceProcessEvents', 'EmailEvents')
    }

    It 'keeps the Mermaid labels when the comment does not match them one for one' {
        $c = Get-Chart "xychart-beta`n    x-axis [""A"", ""B""]`n    %% x-labels [""Alpha""]`n    bar [3, 1]"
        $c.data.xAxis.labels | Should -Be @('A', 'B')
    }

    It 'parses a timeline with continuation events' {
        $c = Get-Chart "timeline`n    title History`n    2024-02-15 : Created`n               : First inventory`n    2025-02-01 : Degraded"
        @($c.data.periods).Count | Should -Be 2
        $c.data.periods[0].events | Should -Be @('Created', 'First inventory')
    }

    It 'parses a gantt with tags, ids and lengths' {
        $c = Get-Chart "gantt`n    title Runway`n    dateFormat YYYY-MM-DD`n    section Past`n    MMA retired :done, mma, 2024-08-31, 1d`n    section Upcoming`n    Today :milestone, today, 2026-10-13, 0d"
        @($c.data.sections).Count | Should -Be 2
        $t = $c.data.sections[0].tasks[0]
        $t.tags | Should -Be @('done'); $t.id | Should -Be 'mma'; $t.start | Should -Be '2024-08-31'; $t.length | Should -Be '1d'
    }

    It 'parses a mindmap into a tree' {
        $c = Get-Chart "mindmap`n    root((30-day billable<br/>2280 GB))`n        FirewallLogs_CL<br/>2000 GB`n        Syslog<br/>280 GB"
        $c.data.root.text | Should -Be "30-day billable`n2280 GB"
        @($c.data.root.children).Count | Should -Be 2
    }

    Context 'flowchart' {
        BeforeAll {
            $script:f = Get-Chart @'
flowchart LR
    subgraph PRIN["Principals"]
        direction TB
        P1[1 Group]
        P2[1 Group]
    end
    R1[Reader]
    R2[Owner]
    P1 --> R1
    P2 -.->|broad| R2
    SRC[Sources] --> ANA[Analytics] --> LAKE[Lake]
    ANA -. auto-mirror .-> LAKE
    classDef broadRole fill:#5b1a1a,stroke:#a33,color:#fdd
    class R2 broadRole
    click P2 href "90-gap-analysis.md#sac-gov-06" "SAC-GOV-06"
'@
        }
        It 'keeps every edge, labelled or not, and chains' {
            @($f.data.edges).Count | Should -Be 5
            ($f.data.edges | Where-Object { $_.from -eq 'P2' }).label | Should -Be 'broad'
            ($f.data.edges | Where-Object { $_.from -eq 'ANA' -and $_.style -eq 'dotted' }).label | Should -Be 'auto-mirror'
        }
        It 'puts nodes in their subgraph and takes their labels' {
            ($f.data.nodes | Where-Object id -eq 'P1').group | Should -Be 'PRIN'
            ($f.data.nodes | Where-Object id -eq 'LAKE').label | Should -Be 'Lake'
        }
        It 'applies classDef colours and click links' {
            ($f.data.nodes | Where-Object id -eq 'R2').fill | Should -Be '#5b1a1a'
            ($f.data.nodes | Where-Object id -eq 'P2').href | Should -Be '90-gap-analysis.md#sac-gov-06'
        }
        It 'gives a node''s click link a target, the same as a text run''s' {
            $md = "# T`n`n``````mermaid`nflowchart LR`n    P1[Group] --> R1[Owner]`n    click P1 href `"90-gap-analysis.md#sac-gov-06`" `"SAC-GOV-06`"`n```````n"
            $nodes = @((ConvertTo-Model $md).blocks[0].data.nodes)
            $p1 = $nodes | Where-Object id -eq 'P1'
            $p1.target.kind | Should -Be 'finding'
            $p1.target.id | Should -Be 'SAC-GOV-06'
            ($nodes | Where-Object id -eq 'R1').target | Should -BeNullOrEmpty
        }
    }

    It 'parses a sequence diagram with notes' {
        $c = Get-Chart "sequenceDiagram`n    autonumber`n    participant DS as Data source`n    DS->>DCR: Event`n    Note over DCR: ~5 min`n    DCR-->>DS: Ack"
        $c.data.autonumber | Should -BeTrue
        @($c.data.participants).Count | Should -Be 2
        @($c.data.steps | Where-Object kind -eq 'message').Count | Should -Be 2
        ($c.data.steps | Where-Object kind -eq 'note').text | Should -Be '~5 min'
    }

    It 'parses a state diagram with nested states and a block note' {
        $c = Get-Chart "stateDiagram-v2`n    [*] --> New : Alert fires`n    New --> Closed`n    state Closed {`n        [*] --> TruePositive`n    }`n    note right of New`n        40 incidents`n    end note"
        @($c.data.transitions).Count | Should -Be 3
        ($c.data.transitions | Where-Object to -eq 'TruePositive').parent | Should -Be 'Closed'
        $c.data.notes[0].text | Should -Be '40 incidents'
    }

    It 'parses a class diagram' {
        $c = Get-Chart "classDiagram`n    class AlertRule {`n        +string id`n    }`n    class NRT {`n    }`n    AlertRule <|-- NRT`n    note for NRT ""2 deployed"""
        @($c.data.classes).Count | Should -Be 2
        $c.data.classes[0].members | Should -Be @('+string id')
        $c.data.relations[0].kind | Should -Be '<|--'
        $c.data.notes[0].text | Should -Be '2 deployed'
    }

    It 'parses a user journey' {
        $c = Get-Chart "journey`n    title Analyst journey`n    section Alert created`n      Alert fires: 5: Sentinel`n      Triage: 3: Analyst, SOC"
        $c.kind | Should -Be 'journey'
        $c.data.sections[0].tasks[1].actors | Should -Be @('Analyst', 'SOC')
    }

    It 'reads a purpose-built graphic from its visual line, whatever Mermaid follows' {
        $c = Get-Chart "stateDiagram-v2`n    %% visual incident-lifecycle {""raised"":40,""new"":5,""classification"":[{""label"":""True positive"",""count"":4}]}`n    [*] --> New"
        $c.kind | Should -Be 'incident-lifecycle'
        $c.data.raised | Should -Be 40
        $c.data.classification[0].label | Should -Be 'True positive'
    }

    It 'reads the Mermaid as usual when a visual line does not parse' {
        $c = Get-Chart "stateDiagram-v2`n    %% visual incident-lifecycle {not json}`n    [*] --> New"
        $c.kind | Should -Be 'state'
    }

    It 'flags a table a graphic shows in full, and only that table' {
        $m = ConvertTo-Model "# T`n`n<!-- bp:shown-in-graphic -->`n`n| A | B |`n|---|---|`n| 1 | 2 |`n`n| C | D |`n|---|---|`n| 3 | 4 |"
        $tables = @($m.blocks | Where-Object { $_.type -eq 'table' })
        $tables.Count | Should -Be 2
        $tables[0].inGraphic | Should -BeTrue
        $tables[1].Contains('inGraphic') | Should -BeFalse
        @($m.blocks | Where-Object { $_.type -eq 'html' }).Count | Should -Be 0
        # A line of figures is flagged the same way.
        $p = ConvertTo-Model "# T`n`n<!-- bp:shown-in-graphic -->`n`n**3** a  ·  **4** b`n`nNext."
        $paras = @($p.blocks | Where-Object { $_.type -eq 'paragraph' })
        $paras[0].inGraphic | Should -BeTrue
        $paras[1].Contains('inGraphic') | Should -BeFalse
    }

    It 'reads a graphic carried on a bp:visual comment, and flags the list it shows' {
        $m = ConvertTo-Model "# T`n`n<!-- bp:visual finding-cards {""cards"":[{""id"":""SAC-LOG-03"",""severity"":""Warning"",""title"":""Cap""}]} -->`n`n<!-- bp:shown-in-graphic -->`n`n- **Warning** SAC-LOG-03 Cap`n`nAfter."
        $c = @($m.blocks | Where-Object { $_.type -eq 'chart' })
        $c.Count | Should -Be 1
        $c[0].kind | Should -Be 'finding-cards'
        $c[0].data.cards[0].id | Should -Be 'SAC-LOG-03'
        $c[0].source | Should -Be ''
        @($m.blocks | Where-Object { $_.type -eq 'list' })[0].inGraphic | Should -BeTrue
        @($m.blocks | Where-Object { $_.type -eq 'html' }).Count | Should -Be 0
        # A comment whose JSON does not parse is dropped, not shown.
        $bad = ConvertTo-Model "# T`n`n<!-- bp:visual finding-cards {nope} -->`n`nText."
        @($bad.blocks | Where-Object { $_.type -in 'chart', 'html' }).Count | Should -Be 0
    }

    It 'returns kind other, with no data, for an unknown chart' {
        $c = Get-Chart "quadrantChart`n    title X"
        $c.kind | Should -Be 'other'; $c.data | Should -BeNullOrEmpty
    }
}

Describe 'Renderer section model output' {

    BeforeAll {
        $fixtureRaw = Join-Path $script:repoRoot 'Tests/iSOCBlueprint/Fixtures/sample/_raw'
        $renderer = Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Convert-SentinelInventoryToMarkdown.ps1'
        $resources = Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Private/Resources'
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) "blueprint-model-test-$(New-Guid)"
        $script:dirs = @{}
        foreach ($mode in 'Both', 'Json') {
            $ws = Join-Path $script:root "$mode/law-sentinel-model"
            New-Item -ItemType Directory -Path (Join-Path $ws '_raw') -Force | Out-Null
            Copy-Item -Path (Join-Path $fixtureRaw '*.json') -Destination (Join-Path $ws '_raw')
            $formats = if ($mode -eq 'Json') { @('Json') } else { @('Markdown', 'Json') }
            & $renderer -WorkspaceName 'law-sentinel-model' -InputRoot $ws -OutputRoot $ws -ResourcesRoot $resources -OutputFormat $formats -InformationAction SilentlyContinue
            $script:dirs[$mode] = $ws
        }
    }
    AfterAll { if ($script:root -and (Test-Path $script:root)) { Remove-Item -Recurse -Force $script:root -ErrorAction SilentlyContinue } }

    It 'writes a valid section file for every Markdown section but the contents page' {
        # index.md (the contents page) has no model: sections/index.json lists the sections.
        $md = @(Get-ChildItem $dirs.Both -Filter '*.md' | Where-Object BaseName -ne 'index' | ForEach-Object BaseName)
        $json = @(Get-ChildItem (Join-Path $dirs.Both 'sections') -Filter '*.json' | Where-Object Name -ne 'index.json' | ForEach-Object BaseName)
        $json | Sort-Object | Should -Be ($md | Sort-Object)
        foreach ($f in Get-ChildItem (Join-Path $dirs.Both 'sections') -Filter '*.json' | Where-Object Name -ne 'index.json') {
            Test-Json -Path $f.FullName -SchemaFile $sectionSchema -ErrorAction SilentlyContinue | Should -BeTrue -Because $f.Name
        }
    }

    It 'writes a valid index in reading order' {
        $idxPath = Join-Path $dirs.Both 'sections/index.json'
        Test-Json -Path $idxPath -SchemaFile $indexSchema | Should -BeTrue
        $ids = @((Get-Content $idxPath -Raw | ConvertFrom-Json).sections.id)
        $ids[0] | Should -Be '00-overview'
        $ids[-1] | Should -Be '99-references'
        $ids | Should -Not -Contain 'index'
    }

    It 'records the run facts as meta' {
        $meta = (Get-Content (Join-Path $dirs.Both 'sections/index.json') -Raw | ConvertFrom-Json).meta
        $meta.workspace | Should -Be 'law-sentinel-model'
        $meta.blueprintVersion | Should -Not -BeNullOrEmpty
    }

    It 'writes no Markdown with -OutputFormat Json, and the same sections' {
        @(Get-ChildItem $dirs.Json -Filter '*.md').Count | Should -Be 0
        @(Get-ChildItem (Join-Path $dirs.Json 'sections') -Filter '*.json').Count | Should -Be @(Get-ChildItem (Join-Path $dirs.Both 'sections') -Filter '*.json').Count
    }

    It 'gives the incident lifecycle its graphic''s data, keeping the Mermaid for the export' {
        $md = Get-Content (Join-Path $dirs.Both '15-incidents.md') -Raw
        $md | Should -Match '(?m)^    %% visual incident-lifecycle \{"days":30,"raised":40,'
        $md | Should -Match '(?m)^stateDiagram-v2$'
        $section = Get-Content (Join-Path $dirs.Both 'sections/15-incidents.json') -Raw | ConvertFrom-Json
        $c = @($section.blocks | Where-Object { $_.type -eq 'chart' -and $_.kind -eq 'incident-lifecycle' })
        $c.Count | Should -Be 1
        $c[0].source | Should -Match 'stateDiagram-v2'
        $d = $c[0].data
        @($d.raised, $d.new, $d.active, $d.closed, $d.acknowledged, $d.unacknowledged) | Should -Be @(40, 5, 3, 32, 12, 20)
        $d.mttaMinutes | Should -Be 95.5
        $d.mttrMinutes | Should -Be 1620
        @($d.openBySeverity.label) | Should -Be @('High', 'Medium', 'Low')
        # Verdicts first, then the closures that carry none.
        @($d.classification.label) | Should -Be @('True positive', 'Benign positive', 'False positive', 'Undetermined', 'Unclassified')
        @($d.closedBy.label) | Should -Be @('Automation rule', 'Analyst', 'Defender XDR', 'Other')
        $d.check.id | Should -Be 'SAC-INC-05'
        # 20 of 32 closed without acknowledgement: over half, so SAC-INC-05 fires.
        $d.check.fired | Should -BeTrue
    }

    It 'gives each diagram with a purpose-built graphic its kind and data' {
        $charts = { param($id) @((Get-Content (Join-Path $dirs.Both "sections/$id.json") -Raw | ConvertFrom-Json).blocks | Where-Object { $_.type -eq 'chart' }) }
        $rk = @(& $charts '20-analytics-rules')[0]
        $rk.kind | Should -Be 'rule-kinds'
        @($rk.data.kinds.kind)[0..4] | Should -Be @('Scheduled', 'NRT', 'Fusion', 'MicrosoftSecurityIncidentCreation', 'ThreatIntelligence')
        @($rk.data.common) | Should -Contain 'displayName'
        $hr = @(& $charts '28-detection-opportunities')[0]
        $hr.kind | Should -Be 'meters'
        @($hr.data.meters.title) | Should -Be @('Applicable templates', 'Ready to enable')
        # The figures the meters do not show ride with them; the figures line is left to the exports.
        @($hr.data.figures.label) | Should -Be @('Enabled analytics rules', 'Tables with data and no detection')
        foreach ($id in '28-detection-opportunities', '70-content-hub') {
            $sec = Get-Content (Join-Path $dirs.Both "sections/$id.json") -Raw | ConvertFrom-Json
            @($sec.blocks | Where-Object { $_.type -eq 'paragraph' -and $_.inGraphic }).Count | Should -Be 1 -Because $id
        }
        $rc = @(& $charts '60-automation-rules-playbooks')[0]
        $rc.kind | Should -Be 'response-chain'
        @($rc.data.phases.name) | Should -Be @('Ingest', 'Detect', 'Automate', 'Notify', 'Respond')
        @($rc.data.phases.steps).Count | Should -Be 11
        $ch = @(& $charts '70-content-hub')[0]
        $ch.kind | Should -Be 'meters'
        @($ch.data.meters[0].parts.label) | Should -Be @('Up to date', 'Update available', 'Deprecated', 'Not in catalogue', 'Not checked')
        $tp = @(& $charts '83-data-collection')[0]
        $tp.kind | Should -Be 'topology'
        @($tp.data.plans.name) | Should -Be @('Analytics', 'Basic', 'Auxiliary', 'Data Lake', 'Long-term archive')
        @($tp.data.sources).Count | Should -BeGreaterThan 0
        $cb = @(& $charts '84-cost-estimate' | Where-Object { $_.kind -ne 'xy' })
        $cb.Count | Should -Be 1 -Because 'the mind map and the compact flow repeated the cost breakdown'
        $cb[0].kind | Should -Be 'cost-breakdown'
        $tables = @($cb[0].data.sources.tables)
        $tables.Count | Should -BeGreaterThan 0
        # Every table is listed under its source, none bucketed into a tail.
        @($tables | Where-Object { $_.table -match ' tail \(' }).Count | Should -Be 0
        $ac = @(& $charts '85-rbac')[0]
        $ac.kind | Should -Be 'access'
        @($ac.data.bands.name) | Should -Be @('Broad roles', 'Microsoft Sentinel roles', 'Log Analytics and monitoring', 'Other roles')
        $lk = @(& $charts '88-sentinel-data-lake' | Where-Object { $_.kind -eq 'lake' })
        $lk.Count | Should -Be 1
        @($lk[0].data.uses.name) | Should -Contain 'KQL jobs'
        $es = @(& $charts '00-overview' | Where-Object { $_.kind -eq 'estate' })
        $es.Count | Should -Be 1
        @($es[0].data.stages.name) | Should -Be @('Ingestion', 'Detection', 'Alerts', 'Incidents')
        # The stage table the estate graphic shows in full stays in the export, flagged.
        $ov = Get-Content (Join-Path $dirs.Both 'sections/00-overview.json') -Raw | ConvertFrom-Json
        @($ov.blocks | Where-Object { $_.type -eq 'table' -and $_.inGraphic }).Count | Should -Be 1
        # 01 does not repeat 00's findings pie and estate flow.
        @(& $charts '01-live-snapshot').Count | Should -Be 0
        $rw = @(& $charts '02-deprecated-legacy-features')[0]
        $rw.kind | Should -Be 'runway'
        @($rw.data.items).Count | Should -Be 6
        $rw.data.items[4].inUse | Should -BeNullOrEmpty
        $wa = @(& $charts '80-workspace' | Where-Object { $_.kind -eq 'workspace-age' })
        $wa.Count | Should -Be 1
        # Platform deadlines are on 02, not repeated in the workspace history.
        (Get-Content (Join-Path $dirs.Both '80-workspace.md') -Raw) | Should -Not -Match 'HTTP Data Collector API retires'
        # The Markdown keeps its Mermaid; the graphic's data rides on a comment line.
        (Get-Content (Join-Path $dirs.Both '83-data-collection.md') -Raw) | Should -Match '(?m)^flowchart LR\r?\n    %% visual topology \{'
    }

    It 'writes the What''s new page from the capture, retirements first, each item tied to this report' {
        $md = Get-Content (Join-Path $dirs.Both '03-whats-new.md') -Raw
        $md | Should -Match '## Retiring and action needed'
        # The soonest deadline first.
        $md.IndexOf('2026-06-30') | Should -BeLessThan $md.IndexOf('| 2027-03')
        # An item links to the pages and criteria it touches, with this workspace's status.
        $md | Should -Match '\[UEBA\]\(26-ueba\.md\); \[?SAC-COV-05'
        $md | Should -Match '\[Data lake\]\(88-sentinel-data-lake\.md\)'
        $md | Should -Match '\[Call to action: move playbooks to the new trigger before June 30, 2026\]\(https://learn\.microsoft\.com/'
        $section = Get-Content (Join-Path $dirs.Both 'sections/03-whats-new.json') -Raw | ConvertFrom-Json
        $c = @($section.blocks | Where-Object { $_.type -eq 'chart' })[0]
        $c.kind | Should -Be 'meters'
        @($c.data.meters.title) | Should -Be @('Microsoft Sentinel', 'Microsoft Defender XDR')
        # The figures line the graphic shows is left to the exports.
        @($section.blocks | Where-Object { $_.type -eq 'paragraph' -and $_.inGraphic }).Count | Should -Be 1
    }

    It 'titles the overview SIEM Overview and draws its top findings as cards, with clean ids' {
        $ov = Get-Content (Join-Path $dirs.Both 'sections/00-overview.json') -Raw | ConvertFrom-Json
        $ov.title | Should -Be 'SIEM Overview'
        $fc = @($ov.blocks | Where-Object { $_.type -eq 'chart' -and $_.kind -eq 'finding-cards' })
        $fc.Count | Should -Be 1
        @($fc[0].data.cards).Count | Should -BeGreaterThan 0
        # The renderer links finding ids in prose; never inside a graphic's data.
        foreach ($c in @($fc[0].data.cards)) { $c.id | Should -Match '^SAC-[A-Z]{2,4}-\d{2}$' }
        @($ov.blocks | Where-Object { $_.type -eq 'list' -and $_.inGraphic }).Count | Should -Be 1
        # The live snapshot points to them rather than repeating them.
        $ls = Get-Content (Join-Path $dirs.Both '01-live-snapshot.md') -Raw
        $ls | Should -Match 'are on \[00-overview\.md\]\(00-overview\.md\)'
        $ls | Should -Not -Match '(?m)^- \*\*(Critical|Warning|Info)\*\*'
    }

    It 'carries every Mermaid chart, and every bp:visual graphic, as a chart block' {
        $fences = (Get-ChildItem $dirs.Both -Filter '*.md' | Where-Object BaseName -ne 'index' | ForEach-Object { [regex]::Matches((Get-Content $_.FullName -Raw), '(?m)^```mermaid|^<!-- bp:visual ').Count } | Measure-Object -Sum).Sum
        $charts = 0
        foreach ($f in Get-ChildItem (Join-Path $dirs.Both 'sections') -Filter '*.json' | Where-Object Name -ne 'index.json') {
            $charts += ([regex]::Matches((Get-Content $f.FullName -Raw), '"type":\s*"chart"')).Count
        }
        $charts | Should -Be $fences
    }
}
