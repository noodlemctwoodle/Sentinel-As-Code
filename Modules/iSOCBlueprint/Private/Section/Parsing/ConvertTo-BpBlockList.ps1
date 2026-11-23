#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertTo-BpBlockList

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Parsing/ConvertTo-BpBlockList.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Section model conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

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
                $note = [ordered]@{ type = 'note'; blocks = $inner }
                if ($Context.tone) { $note.tone = $Context.tone; $Context.tone = $null }
                $note
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
                if ($Context.inGraphic) { $list.inGraphic = $true; $Context.inGraphic = $false }
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
                $tone = [regex]::Match($html, $script:BpToneComment)
                if ($tone.Success) { $Context.tone = $tone.Groups['tone'].Value; break }
                $visual = [regex]::Match($html, $script:BpVisualComment)
                if ($visual.Success) {
                    $data = $null
                    try { $data = $visual.Groups['json'].Value | ConvertFrom-Json -ErrorAction Stop } catch { $data = $null }
                    if ($null -ne $data) {
                        $Context.content = $true
                        [ordered]@{ type = 'chart'; kind = $visual.Groups['kind'].Value; title = $null; data = $data; source = '' }
                    }
                    break
                }
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
