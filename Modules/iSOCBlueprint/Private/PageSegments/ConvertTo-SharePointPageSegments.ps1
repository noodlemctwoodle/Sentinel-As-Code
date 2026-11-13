#Requires -Version 7.6

<#
.SYNOPSIS
    Convert one section from the section model into a page title and an ordered list of page segments.

.DESCRIPTION
    A modern SharePoint page is a list of web parts. Text goes into Text web
    parts, which accept a limited HTML vocabulary (h2 to h4, paragraphs,
    lists, links, tables, blockquotes, pre); each chart goes into the
    isoc-blueprint chart web part, which draws it from its data. This
    converter reads a section from the section model (sections/<id>.json,
    Docs/Modules/iSOCBlueprint/Section-Model.md) and writes that shape directly,
    with no Markdown involved:

      1. The section title becomes the page title, without the '(TOC x.y)'
         cross-reference some titles carry.
      2. Blocks become Text web part HTML: headings clamped to h2-h4,
         paragraphs, lists (nested), notes as blockquotes, tables in the
         responsive markup the SharePoint editor uses (capped at
         -MaxTableRows), code as <pre>. Horizontal rules are dropped. A
         table cut at -MaxTableRows is also returned whole as CSV, for the
         publisher to put in the assets library's tables/ folder, and the
         note under the cut table links to that file.
      3. Links follow each run's target: another section goes to its
         generated page, a finding to the findings list filtered on its id,
         a URL stays a link, and same-page anchors and repository paths
         become plain text (they mean nothing on SharePoint).
      4. Each chart becomes its own segment carrying the chart's kind, title
         and data for the chart web part.
      5. The HTML is split at every H2 and at every chart, so each Text web
         part stays a manageable size and charts sit where they were.

    Links to pages and lists use a '~site/' prefix. The publisher replaces
    it with the target web's server-relative URL, so the converter has no
    SharePoint dependency and the output can be built and tested offline.

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/ConvertTo-SharePointPageSegments.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, SharePoint page conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function ConvertTo-SharePointPageSegments {
    <#
    .SYNOPSIS
        Convert one section from the section model into a page title and
        an ordered list of page segments.

    .PARAMETER Section
        One section from the section model (sections/<id>.json).

    .PARAMETER FindingsListUrl
        Site-relative URL of the findings list. Defaults to
        'Lists/SentinelFindings'.

    .PARAMETER MaxTableRows
        Maximum body rows kept per table. Defaults to 500.

    .OUTPUTS
        [pscustomobject] with:
          Title    : the page title
          Segments : ordered array of hashtables, each either
                     @{ type = 'html'; html = '...' } or
                     @{ type = 'chart'; chart = @{ kind; title; data } }
                     (kind 'other' also carries source)
          Warnings : array of strings (truncated tables, charts that could
                     not be placed)
          Tables   : each table cut at -MaxTableRows, whole: file (the CSV
                     file name), heading, rows and csv (the text)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] $Section,
        [string] $FindingsListUrl = 'Lists/SentinelFindings',
        [int] $MaxTableRows = 500
    )

    $warnings = [System.Collections.Generic.List[string]]::new()
    $tables = [System.Collections.Generic.List[object]]::new()
    $id = [string]$Section.id
    $title = Get-SacSectionTitle -Title ([string]$Section.title)

    # object, not hashtable: a List[hashtable] would turn each ordered segment
    # back into an unordered one, and the page hash would change run to run.
    $segments = [System.Collections.Generic.List[object]]::new()
    $buffer = [System.Text.StringBuilder]::new()
    $flush = {
        $text = $buffer.ToString().Trim()
        if ($text) { $segments.Add([ordered]@{ type = 'html'; html = $text }) }
        [void]$buffer.Clear()
    }

    # A chart whose title repeats the heading above it shows the heading only.
    $lastHeading = ''
    foreach ($b in @($Section.blocks)) {
        if ($null -eq $b) { continue }
        if ([string]$b.type -eq 'heading') { $lastHeading = (@($b.text) | ForEach-Object { [string]$_.text }) -join '' }
        # A table or line of figures a graphic on the page shows in full is left to the exports.
        if ($b.inGraphic -eq $true) { continue }
        if ([string]$b.type -eq 'chart') {
            & $flush
            $chartTitle = $b.title
            if ($chartTitle -and ([string]$chartTitle).Trim() -ieq $lastHeading.Trim()) { $chartTitle = $null }
            $chart = [ordered]@{ kind = [string]$b.kind; title = $chartTitle; data = (ConvertTo-SacChartData -Chart $b -FindingsListUrl $FindingsListUrl) }
            if ($chart.kind -eq 'other') { $chart.source = [string]$b.source }
            $segments.Add([ordered]@{ type = 'chart'; chart = $chart })
            continue
        }
        if ([string]$b.type -eq 'heading' -and [int]$b.level -le 2) { & $flush }
        [void]$buffer.Append((ConvertTo-SacBlocksHtml -Blocks @($b) -FindingsListUrl $FindingsListUrl -MaxTableRows $MaxTableRows -Id $id -Warnings $warnings -Tables $tables -Heading $lastHeading))
    }
    & $flush

    return [pscustomobject]@{
        Title    = $title
        Segments = $segments.ToArray()
        Warnings = $warnings.ToArray()
        Tables   = $tables.ToArray()
    }
}
