#Requires -Version 7.6

<#
.SYNOPSIS
    Parse one section's Markdown into the section model.

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
    File:         Modules/iSOCBlueprint/Private/Section/ConvertTo-BlueprintSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, Section model conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

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
