#Requires -Version 7.2

<#
.SYNOPSIS
    Convert one rendered Blueprint section into the section model: typed
    blocks, structured text runs and charts as data.

.DESCRIPTION
    The section model (Modules/iSOCBlueprint/Engine/Schemas/section.schema.json) is what
    every consumer reads: the SharePoint site, and anyone building on
    sections/*.json. No Markdown reaches it. Text is a list of runs
    (@{ text; bold; italic; code; strike; href; target }) and a line break is
    @{ break = $true }. Links carry a target that says what they point at:
    another section, a gap-analysis finding, an anchor on the same page, an
    external URL or a path in the repository.

    The renderer composes each section as Markdown, and this converter
    parses it with Markdig (the parser behind ConvertFrom-Markdown) into the
    model. The H1 becomes the title, the metadata banner under it is
    dropped (the renderer passes the same facts as -Meta), a raw
    <a id="..."></a> line becomes the anchor of the heading after it, and
    Mermaid fences become chart blocks through ConvertFrom-BlueprintMermaid.

    Markdig refuses a pipe table of a few thousand rows ("Markdown elements
    in the input are too deeply nested"). A table longer than
    $script:BpTableChunkRows rows is therefore parsed in chunks, each with
    the header repeated, and the chunks are joined back into one table
    block, so the model holds every row.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/ConvertTo-BlueprintSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.4.0
    Last Updated: 2026-10-14
    Requires:     PowerShell 7.2+, ConvertFrom-BlueprintMermaid.ps1

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

$script:BpSectionSchemaVersion = 1

# The longest pipe table Markdig is given at once. It refuses one of about
# 2,700 short rows as too deeply nested; 500 leaves room for long cells.
$script:BpTableChunkRows = 500
$script:BpTableContinues = '<!-- bp:table-continues -->'
# Before a table or a line of figures a purpose-built graphic on the same
# page shows in full: it keeps its place in the Markdown and Word exports,
# and is flagged inGraphic so the SharePoint pages and the dashboard do not
# show it twice.
$script:BpShownInGraphic = '<!-- bp:shown-in-graphic -->'

function ConvertTo-BlueprintSection {
    <#
    .SYNOPSIS
        Parse one section's Markdown into the section model.

    .PARAMETER Markdown
        The section as the renderer composed it.

    .PARAMETER Id
        The section id: the file name without .md, for example
        '20-analytics-rules'.

    .PARAMETER Meta
        Facts about the run the section came from (workspace, generatedUtc,
        blueprintVersion). Copied into the model as-is.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] schemaVersion, id,
        order, title, meta, blocks.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Markdown,
        [Parameter(Mandatory)] [string] $Id,
        [System.Collections.IDictionary] $Meta
    )

    $context = @{ title = $null; anchor = $null; content = $false }
    # @() around the whole if: an if statement unrolls a one-item array.
    $blocks = @(if (-not [string]::IsNullOrWhiteSpace($Markdown)) {
            $doc = (ConvertFrom-Markdown -InputObject (Split-BpLongTable -Markdown $Markdown)).Tokens
            Join-BpTableChunk -Blocks @(ConvertTo-BpBlockList -Blocks $doc -Context $context)
        })
    return [ordered]@{
        schemaVersion = $script:BpSectionSchemaVersion
        id            = $Id
        order         = $(if ($Id -match '^(\d+)-') { [int]$Matches[1] } else { $null })
        title         = $context.title
        meta          = $(if ($Meta) { $Meta } else { [ordered]@{} })
        blocks        = $blocks
    }
}

function Split-BpLongTable {
    <#
    .SYNOPSIS
        Cut every pipe table longer than $script:BpTableChunkRows rows into
        chunks Markdig can parse.

    .DESCRIPTION
        Each chunk after the first repeats the table's header and separator
        lines and follows a $script:BpTableContinues line, which
        Join-BpTableChunk uses to join the chunks back into one table.
        Lines inside a fenced code block are left alone, and so are tables
        that fit; Markdown with no long table comes back unchanged.

    .PARAMETER Markdown
        The section's Markdown.

    .OUTPUTS
        [string] The Markdown, with long tables cut.
    #>
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Markdown)

    $lines = $Markdown -split '\r?\n'
    $out = [System.Collections.Generic.List[string]]::new()
    $inFence = $false
    $cut = $false
    $i = 0
    while ($i -lt $lines.Count) {
        $line = $lines[$i]
        if ($line -match '^\s*(```|~~~)') { $inFence = -not $inFence; $out.Add($line); $i++; continue }
        $isTable = -not $inFence -and $line -match '^\|' -and ($i + 1) -lt $lines.Count -and
            $lines[$i + 1] -match '^\|(\s*:?-+:?\s*\|)+\s*$'
        if (-not $isTable) { $out.Add($line); $i++; continue }

        $header = $line
        $separator = $lines[$i + 1]
        $j = $i + 2
        $body = [System.Collections.Generic.List[string]]::new()
        while ($j -lt $lines.Count -and $lines[$j] -match '^\|') { $body.Add($lines[$j]); $j++ }
        if ($body.Count -gt $script:BpTableChunkRows) { $cut = $true }
        for ($start = 0; $start -lt [Math]::Max($body.Count, 1); $start += $script:BpTableChunkRows) {
            if ($start -gt 0) {
                $out.Add('')
                $out.Add($script:BpTableContinues)
                $out.Add('')
            }
            $out.Add($header)
            $out.Add($separator)
            $end = [Math]::Min($start + $script:BpTableChunkRows, $body.Count)
            for ($k = $start; $k -lt $end; $k++) { $out.Add($body[$k]) }
        }
        $i = $j
    }
    if (-not $cut) { return $Markdown }
    return ($out -join "`n")
}

function Join-BpTableChunk {
    <#
    .SYNOPSIS
        Join the table chunks Split-BpLongTable made back into one table.

    .PARAMETER Blocks
        The section's top-level blocks.

    .OUTPUTS
        The blocks, with each table followed by a seam and another table
        merged into one, and the seams removed.
    #>
    param([object[]] $Blocks)

    $out = [System.Collections.Generic.List[object]]::new()
    $joinNext = $false
    foreach ($b in $Blocks) {
        if ($b -is [System.Collections.IDictionary] -and $b.type -eq 'tableContinues') { $joinNext = $true; continue }
        $last = if ($out.Count) { $out[$out.Count - 1] } else { $null }
        if ($joinNext -and $b.type -eq 'table' -and $last -and $last.type -eq 'table') {
            $last.rows = @($last.rows) + @($b.rows)
        }
        else { $out.Add($b) }
        $joinNext = $false
    }
    return $out.ToArray()
}

function ConvertTo-BpBlockList {
    param([object] $Blocks, [hashtable] $Context)
    foreach ($b in $Blocks) {
        $type = $b.GetType().Name
        switch ($type) {
            'HeadingBlock' {
                $runs = @(ConvertTo-BpRuns -Container $b.Inline)
                if ($b.Level -eq 1 -and -not $Context.title) { $Context.title = Get-BpPlainText $runs; break }
                $block = [ordered]@{ type = 'heading'; level = [int]$b.Level; text = $runs; anchor = $Context.anchor }
                if (-not $block.anchor) { $block.anchor = Get-BpSlug (Get-BpPlainText $runs) }
                $Context.anchor = $null
                $Context.content = $true
                $block
            }
            'ParagraphBlock' {
                $anchor = Get-BpAnchorOnly -Container $b.Inline
                if ($anchor) { $Context.anchor = $anchor; break }
                $runs = @(ConvertTo-BpRuns -Container $b.Inline)
                if ($runs.Count -eq 0) { break }
                $Context.content = $true
                $para = [ordered]@{ type = 'paragraph'; text = $runs }
                if ($Context.inGraphic) { $para.inGraphic = $true; $Context.inGraphic = $false }
                $para
            }
            'QuoteBlock' {
                $inner = @(ConvertTo-BpBlockList -Blocks $b -Context @{ title = 'nested'; anchor = $null; content = $true })
                $plain = (@($inner | Where-Object { $_.type -eq 'paragraph' } | Select-Object -First 1 | ForEach-Object { Get-BpPlainText $_.text }) -join '')
                # The metadata banner directly under the title; the renderer
                # passes the same facts as -Meta.
                if (-not $Context.content -and $plain -match '^\s*Workspace\b') { break }
                $Context.content = $true
                [ordered]@{ type = 'note'; blocks = $inner }
            }
            'ListBlock' {
                $items = foreach ($item in $b) {
                    $children = @($item)
                    $first = $children | Select-Object -First 1
                    $text = @()
                    $rest = $children
                    if ($first -and $first.GetType().Name -eq 'ParagraphBlock') {
                        $text = @(ConvertTo-BpRuns -Container $first.Inline)
                        $rest = @($children | Select-Object -Skip 1)
                    }
                    [ordered]@{ text = $text; blocks = @(ConvertTo-BpBlockList -Blocks $rest -Context @{ title = 'nested'; anchor = $null; content = $true }) }
                }
                $Context.content = $true
                $list = [ordered]@{ type = 'list'; ordered = [bool]$b.IsOrdered; items = @($items) }
                if ($b.IsOrdered -and $b.OrderedStart -and $b.OrderedStart -ne '1') { $list.start = [int]$b.OrderedStart }
                $list
            }
            'Table' {
                $Context.content = $true
                $table = ConvertTo-BpTable -Table $b
                if ($Context.inGraphic) { $table.inGraphic = $true; $Context.inGraphic = $false }
                $table
            }
            'FencedCodeBlock' {
                $Context.content = $true
                $text = $b.Lines.ToString()
                $info = [string]$b.Info
                if ($info -eq 'mermaid') {
                    $chart = ConvertFrom-BlueprintMermaid -Source $text
                    # A flowchart node's click link gets a target, the same as a text run's.
                    if ($chart.kind -eq 'flowchart' -and $chart.data) {
                        foreach ($n in @($chart.data.nodes)) { $n.target = $(if ($n.href) { Get-BpLinkTarget $n.href } else { $null }) }
                    }
                    [ordered]@{ type = 'chart'; kind = $chart.kind; title = $chart.title; data = $chart.data; source = $text }
                }
                else { [ordered]@{ type = 'code'; language = $(if ($info) { $info } else { $null }); text = $text } }
            }
            'CodeBlock' {
                $Context.content = $true
                [ordered]@{ type = 'code'; language = $null; text = $b.Lines.ToString() }
            }
            'ThematicBreakBlock' { [ordered]@{ type = 'rule' } }
            'HtmlBlock' {
                $html = $b.Lines.ToString().Trim()
                if ($html -match '^<a\s+id="([^"]+)"\s*>\s*</a>$') { $Context.anchor = $Matches[1]; break }
                # Split-BpLongTable's seam; Join-BpTableChunk removes it.
                if ($html -eq $script:BpTableContinues) { [ordered]@{ type = 'tableContinues' }; break }
                if ($html -eq $script:BpShownInGraphic) { $Context.inGraphic = $true; break }
                $Context.content = $true
                [ordered]@{ type = 'html'; html = $html }
            }
            'LinkReferenceDefinitionGroup' { }
            default {
                # Unknown block types keep their text rather than vanish.
                $Context.content = $true
                [ordered]@{ type = 'paragraph'; text = @([ordered]@{ text = $b.ToString() }) }
            }
        }
    }
}

function ConvertTo-BpTable {
    param([object] $Table)
    $rows = @($Table)
    $header = $rows | Where-Object { $_.IsHeader } | Select-Object -First 1
    $defs = @($Table.ColumnDefinitions)
    $columns = @()
    if ($header) {
        $i = 0
        $columns = foreach ($cell in $header) {
            $align = if ($i -lt $defs.Count -and $null -ne $defs[$i].Alignment) { ([string]$defs[$i].Alignment).ToLowerInvariant() } else { $null }
            $i++
            [ordered]@{ text = @(ConvertTo-BpCellRuns -Cell $cell); align = $align }
        }
    }
    # Lists, not pipeline output: a one-row table or a one-cell row would
    # otherwise unroll into the wrong shape.
    $body = [System.Collections.Generic.List[object]]::new()
    # @(): a single TableRow left bare would be enumerated as its cells.
    foreach ($row in @($rows | Where-Object { -not $_.IsHeader })) {
        $cells = [System.Collections.Generic.List[object]]::new()
        foreach ($cell in $row) { $cells.Add(@(ConvertTo-BpCellRuns -Cell $cell)) }
        $body.Add($cells.ToArray())
    }
    return [ordered]@{ type = 'table'; columns = @($columns); rows = $body.ToArray() }
}

function ConvertTo-BpCellRuns {
    param([object] $Cell)
    $first = $true
    foreach ($block in $Cell) {
        if ($block.GetType().Name -ne 'ParagraphBlock') { continue }
        if (-not $first) { [ordered]@{ break = $true } }
        ConvertTo-BpRuns -Container $block.Inline
        $first = $false
    }
}

function ConvertTo-BpRuns {
    # Inline content -> runs. Adjacent runs with the same formatting merge.
    param([object] $Container)
    $out = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Container) { Add-BpInlineRuns -Inline $Container.FirstChild -Format @{} -Out $out }
    # Trim the whitespace a soft break or an anchor can leave at the edges.
    if ($out.Count -and $out[0].Contains('text')) { $out[0].text = $out[0].text.TrimStart() }
    if ($out.Count -and $out[$out.Count - 1].Contains('text')) { $out[$out.Count - 1].text = $out[$out.Count - 1].text.TrimEnd() }
    return @($out | Where-Object { -not $_.Contains('text') -or $_.text -ne '' })
}

function Add-BpInlineRuns {
    param([object] $Inline, [hashtable] $Format, [System.Collections.Generic.List[object]] $Out)
    for ($i = $Inline; $null -ne $i; $i = $i.NextSibling) {
        switch ($i.GetType().Name) {
            'LiteralInline' { Add-BpRun -Out $Out -Text $i.Content.ToString() -Format $Format }
            'CodeInline' { $f = $Format.Clone(); $f.code = $true; Add-BpRun -Out $Out -Text ([string]$i.Content) -Format $f }
            'EmphasisInline' {
                $f = $Format.Clone()
                if ($i.DelimiterChar -eq '~') { $f.strike = $true }
                elseif ($i.DelimiterCount -ge 2) { $f.bold = $true }
                else { $f.italic = $true }
                Add-BpInlineRuns -Inline $i.FirstChild -Format $f -Out $Out
            }
            'LinkInline' {
                if ($i.IsImage) { Add-BpRun -Out $Out -Text (Get-BpInlineText $i.FirstChild) -Format $Format; break }
                $f = $Format.Clone(); $f.href = [string]$i.Url
                Add-BpInlineRuns -Inline $i.FirstChild -Format $f -Out $Out
            }
            'AutolinkInline' { $f = $Format.Clone(); $f.href = [string]$i.Url; Add-BpRun -Out $Out -Text ([string]$i.Url) -Format $f }
            'LineBreakInline' { if ($i.IsHard) { $Out.Add([ordered]@{ break = $true }) } else { Add-BpRun -Out $Out -Text ' ' -Format $Format } }
            'HtmlInline' { if ([string]$i.Tag -match '^<br\s*/?>$') { $Out.Add([ordered]@{ break = $true }) } }
            'HtmlEntityInline' { Add-BpRun -Out $Out -Text $i.Transcoded.ToString() -Format $Format }
            default {
                if ($i.PSObject.Properties['FirstChild']) { Add-BpInlineRuns -Inline $i.FirstChild -Format $Format -Out $Out }
                else { Add-BpRun -Out $Out -Text $i.ToString() -Format $Format }
            }
        }
    }
}

function Add-BpRun {
    param([System.Collections.Generic.List[object]] $Out, [string] $Text, [hashtable] $Format)
    if ($Text -eq '') { return }
    $last = if ($Out.Count) { $Out[$Out.Count - 1] } else { $null }
    if ($last -and $last.Contains('text') -and (Test-BpSameFormat $last $Format)) { $last.text += $Text; return }
    $run = [ordered]@{ text = $Text }
    foreach ($flag in 'bold', 'italic', 'code', 'strike') { if ($Format[$flag]) { $run[$flag] = $true } }
    if ($Format.href) { $run.href = $Format.href; $run.target = Get-BpLinkTarget $Format.href }
    $Out.Add($run)
}

function Test-BpSameFormat {
    param([System.Collections.IDictionary] $Run, [hashtable] $Format)
    foreach ($flag in 'bold', 'italic', 'code', 'strike') { if ([bool]$Run[$flag] -ne [bool]$Format[$flag]) { return $false } }
    return [string]$Run['href'] -eq [string]$Format['href']
}

function Get-BpLinkTarget {
    <#
    .SYNOPSIS
        Say what a link points at: kind section (section, anchor), finding
        (id), anchor (anchor, same page), external, or repo (path).
    #>
    param([string] $Href)
    if ($Href -match '^(?:90-gap-analysis\.md)?#(?<id>sac-[a-z]{2,4}-\d{2})$') { return [ordered]@{ kind = 'finding'; id = $Matches['id'].ToUpperInvariant() } }
    if ($Href -match '^(?:https?|mailto):') { return [ordered]@{ kind = 'external' } }
    if ($Href -match '^#(?<a>.+)$') { return [ordered]@{ kind = 'anchor'; anchor = $Matches['a'] } }
    if ($Href -match '^(?:\./)?(?<s>\d{2}-[a-z0-9-]+|index)\.md(?:#(?<a>.+))?$') {
        return [ordered]@{ kind = 'section'; section = $Matches['s']; anchor = $(if ($Matches['a']) { $Matches['a'] } else { $null }) }
    }
    return [ordered]@{ kind = 'repo'; path = $Href }
}

function Get-BpAnchorOnly {
    # A paragraph that is only <a id="x"></a> marks the next heading.
    param([object] $Container)
    if ($null -eq $Container) { return $null }
    $id = $null
    for ($i = $Container.FirstChild; $null -ne $i; $i = $i.NextSibling) {
        $name = $i.GetType().Name
        if ($name -eq 'HtmlInline') {
            if ([string]$i.Tag -match '^<a\s+id="([^"]+)"\s*>$') { $id = $Matches[1]; continue }
            if ([string]$i.Tag -match '^</a>$') { continue }
            return $null
        }
        if ($name -eq 'LiteralInline' -and [string]::IsNullOrWhiteSpace($i.Content.ToString())) { continue }
        if ($name -eq 'LineBreakInline') { continue }
        return $null
    }
    return $id
}

function Get-BpInlineText {
    param([object] $Inline)
    $sb = [System.Text.StringBuilder]::new()
    for ($i = $Inline; $null -ne $i; $i = $i.NextSibling) {
        if ($i.GetType().Name -eq 'LiteralInline') { [void]$sb.Append($i.Content.ToString()) }
        elseif ($i.PSObject.Properties['FirstChild']) { [void]$sb.Append((Get-BpInlineText $i.FirstChild)) }
    }
    return $sb.ToString()
}

function Get-BpPlainText {
    <#
    .SYNOPSIS
        Plain text of a list of runs; a break becomes a space.
    #>
    param([object[]] $Runs)
    return ((@($Runs) | ForEach-Object { if ($_.Contains('text')) { $_.text } else { ' ' } }) -join '').Trim()
}

function Get-BpSlug {
    # GitHub's heading anchor: lower case, punctuation dropped, spaces to '-'.
    param([string] $Text)
    $s = $Text.ToLowerInvariant() -replace '[^\p{L}\p{Nd}\s_-]', '' -replace '\s', '-'
    return $s
}
