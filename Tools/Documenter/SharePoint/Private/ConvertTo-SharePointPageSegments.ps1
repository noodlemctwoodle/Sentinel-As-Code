#Requires -Version 7.2

<#
.SYNOPSIS
    Convert one Documenter Markdown section into the HTML segments that make
    up a native SharePoint page.

.DESCRIPTION
    A modern SharePoint page is a list of web parts. Text goes into Text web
    parts, which accept a limited HTML vocabulary (h2 to h4, paragraphs,
    lists, links, tables, blockquotes, pre). Images need their own Image web
    part. This converter turns a rendered Documenter section into that shape:

      1. Markdown to HTML with PowerShell's built-in ConvertFrom-Markdown
         (Markdig, which renders pipe tables).
      2. The H1 becomes the page title and is removed from the body, along
         with the metadata banner the renderer writes under it.
      3. The HTML is cut down to what a Text web part keeps: headings
         clamped to h2-h4, id/class attributes and anchor stubs removed,
         code blocks flattened to <pre>, horizontal rules dropped, tables
         wrapped in the responsive table markup the SharePoint editor uses.
      4. Links are rewritten for the site: links to other section files go
         to their generated page, SENT-NNN finding links go to the findings
         list filtered on that id, and repository-relative links become
         plain text (they mean nothing on SharePoint).
      5. Mermaid blocks that were not pre-rendered are replaced with a note
         rather than leaking unescaped diagram source into the page.
      6. The result is split into one segment per H2 and at every image, so
         each Text web part stays a manageable size and diagrams sit where
         they were in the Markdown.

    Links to pages and lists use a '~site/' prefix. The publisher replaces
    it with the target web's server-relative URL, so the converter has no
    SharePoint dependency and the output can be built and tested offline.

.NOTES
    File:         Tools/Documenter/SharePoint/Private/ConvertTo-SharePointPageSegments.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-08
    Version:      0.1.0
    Last Updated: 2026-10-08
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-SacPageName {
    <#
    .SYNOPSIS
        Return the SharePoint page name (no .aspx) for a section file name.

    .PARAMETER FileName
        Section file name, for example '25-mitre-coverage.md'.

    .OUTPUTS
        [string] For example 'sac-25-mitre-coverage'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $FileName)

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($FileName).ToLowerInvariant()
    $stem = ($stem -replace '[^a-z0-9-]', '-') -replace '-{2,}', '-'
    return "sac-$stem"
}

function Get-SacSectionTitle {
    <#
    .SYNOPSIS
        Clean a renderer H1 for use as a page title.

    .DESCRIPTION
        Removes the '(TOC x.y)' suffix some renderer titles carry, which is a
        cross-reference to the formal configuration document and noise in a
        page title.

    .PARAMETER Title
        The raw H1 text.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Title)

    return ($Title -replace '\s*\(TOC[^)]*\)\s*$', '').Trim()
}

function ConvertTo-SacTableHtml {
    <#
    .SYNOPSIS
        Rewrite one Markdig <table> into SharePoint editor table markup,
        capping the number of body rows.

    .PARAMETER TableHtml
        A single '<table>...</table>' fragment from Markdig, attributes
        already stripped.

    .PARAMETER MaxRows
        Maximum body rows to keep. Extra rows are replaced by one note row.

    .OUTPUTS
        [pscustomobject] Html (string) and Truncated (int, rows dropped).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $TableHtml,
        [Parameter(Mandatory)] [int] $MaxRows
    )

    $rows = [regex]::Matches($TableHtml, '<tr>(.*?)</tr>', 'Singleline')
    $headerCells = 0
    $out = [System.Text.StringBuilder]::new()
    [void]$out.Append('<div class="canvasRteResponsiveTable"><div class="tableWrapper"><table title="Table"><tbody>')

    $bodyRows = 0
    $dropped = 0
    foreach ($row in $rows) {
        $inner = $row.Groups[1].Value
        $isHeader = $inner -match '<th>'
        if ($isHeader) {
            $cells = [regex]::Matches($inner, '<th>(.*?)</th>', 'Singleline')
            $headerCells = $cells.Count
            # The renderer uses '| | |' headers for key/value tables. An
            # all-empty header row would show as a blank bold band.
            if (-not ($cells | Where-Object { $_.Groups[1].Value.Trim() })) { continue }
            [void]$out.Append('<tr>')
            foreach ($c in $cells) { [void]$out.Append('<td><strong>' + $c.Groups[1].Value.Trim() + '</strong></td>') }
            [void]$out.Append('</tr>')
            continue
        }
        if ($bodyRows -ge $MaxRows) { $dropped++; continue }
        $bodyRows++
        $cells = [regex]::Matches($inner, '<td>(.*?)</td>', 'Singleline')
        [void]$out.Append('<tr>')
        foreach ($c in $cells) { [void]$out.Append('<td>' + $c.Groups[1].Value.Trim() + '</td>') }
        [void]$out.Append('</tr>')
    }

    if ($dropped -gt 0) {
        $span = [math]::Max($headerCells, 1)
        [void]$out.Append("<tr><td colspan=`"$span`"><em>$dropped more rows not shown here. The full table is in the Documenter Markdown output.</em></td></tr>")
    }
    [void]$out.Append('</tbody></table></div></div>')

    return [pscustomobject]@{ Html = $out.ToString(); Truncated = $dropped }
}

function ConvertTo-SacSiteLink {
    <#
    .SYNOPSIS
        Rewrite one href from the renderer's Markdown into a site URL, or
        return $null when the link should become plain text.

    .PARAMETER Href
        The href as Markdig emitted it.

    .PARAMETER CurrentFile
        The section file being converted, so same-page finding anchors can
        be recognised.

    .PARAMETER FindingsListUrl
        Site-relative URL of the findings list.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Href,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $CurrentFile,
        [Parameter(Mandatory)] [string] $FindingsListUrl
    )

    $decoded = [System.Net.WebUtility]::HtmlDecode($Href)

    if ($decoded -match '^(https?|mailto):') { return $Href }

    # SENT-NNN finding links: '90-gap-analysis.md#sent-009' or '#sent-009'.
    if ($decoded -match '^(?:(?<file>[^#]*\.md))?#(?<id>sent-\d+)$') {
        $id = $Matches['id'].ToUpperInvariant()
        return "~site/$FindingsListUrl/AllItems.aspx?FilterField1=FindingId&amp;FilterValue1=$id"
    }

    # Another section: 'NN-name.md' or 'NN-name.md#anchor'. SharePoint makes
    # its own heading anchors, so the fragment is dropped.
    if ($decoded -match '^(?<file>\d{2}-[A-Za-z0-9-]+\.md)(?:#.*)?$') {
        return "~site/SitePages/$(Get-SacPageName -FileName $Matches['file']).aspx"
    }

    # In-page anchors, index.md and repository-relative paths mean nothing
    # once the content lives on SharePoint.
    return $null
}

function ConvertTo-SharePointPageSegments {
    <#
    .SYNOPSIS
        Convert one section's Markdown into a title and an ordered list of
        page segments.

    .PARAMETER Markdown
        Full text of one rendered section file.

    .PARAMETER FileName
        The section file name, for example '90-gap-analysis.md'. Used to
        resolve same-page finding anchors.

    .PARAMETER FindingsListUrl
        Site-relative URL of the findings list. Defaults to
        'Lists/SentinelFindings'.

    .PARAMETER MaxTableRows
        Maximum body rows kept per table. Defaults to 500.

    .OUTPUTS
        [pscustomobject] with:
          Title    : cleaned H1, or '' when the file has none
          Segments : ordered array of hashtables, each either
                     @{ type = 'html'; html = '...' } or
                     @{ type = 'image'; file = '<name>.png'; alt = '...' }
          Warnings : array of strings (truncated tables, unrendered diagrams)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Markdown,
        [Parameter(Mandatory)] [string] $FileName,
        [string] $FindingsListUrl = 'Lists/SentinelFindings',
        [int] $MaxTableRows = 500
    )

    $warnings = [System.Collections.Generic.List[string]]::new()

    # ---- Markdown pre-processing ------------------------------------------
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($l in ($Markdown -split "`r?`n")) { $lines.Add($l) }

    $title = ''
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^#\s+(.+)$') {
            $title = Get-SacSectionTitle -Title $Matches[1]
            $lines.RemoveAt($i)
            # The renderer's metadata banner is the first blockquote after
            # the H1: '> **Workspace** `ws` · **Generated** ... · **Documenter** v...'
            $j = $i
            while ($j -lt $lines.Count -and $lines[$j] -match '^\s*$') { $j++ }
            if ($j -lt $lines.Count -and $lines[$j] -match '^>' ) {
                $end = $j
                while ($end -lt $lines.Count -and $lines[$end] -match '^>') { $end++ }
                $block = ($lines.GetRange($j, $end - $j) -join "`n")
                if ($block -match '\*\*Workspace\*\*' -and $block -match 'Documenter') {
                    $lines.RemoveRange($j, $end - $j)
                }
            }
            break
        }
    }

    # Raw finding anchors the renderer emits above each finding card.
    $body = (@($lines | Where-Object { $_ -notmatch '^\s*<a id="[^"]*"></a>\s*$' })) -join "`n"

    # ---- Markdown to HTML -------------------------------------------------
    $html = if ([string]::IsNullOrWhiteSpace($body)) { '' } else { (ConvertFrom-Markdown -InputObject $body).Html }

    # ---- HTML clean-up ------------------------------------------------------
    # Unrendered Mermaid. Markdig leaves the diagram body unescaped inside
    # <pre class="mermaid">, so it must never reach the page as-is.
    $mermaidCount = [regex]::Matches($html, '<pre class="mermaid">.*?</pre>|<pre><code class="language-mermaid">.*?</code></pre>', 'Singleline').Count
    if ($mermaidCount -gt 0) {
        $warnings.Add("$FileName : $mermaidCount Mermaid diagram(s) were not pre-rendered; run Convert-MermaidToImage.ps1 before building.")
        $html = [regex]::Replace($html, '<pre class="mermaid">.*?</pre>|<pre><code class="language-mermaid">.*?</code></pre>',
            '<p><em>Diagram not rendered for this site. Run Convert-MermaidToImage.ps1 before building to include it.</em></p>', 'Singleline')
    }

    # Decorative SVG (GitHub alert icons) and horizontal rules.
    $html = [regex]::Replace($html, '<svg\b.*?</svg>', '', 'Singleline')
    $html = [regex]::Replace($html, '<hr\s*/?>', '')

    # Code blocks: <pre><code ...>x</code></pre> -> <pre>x</pre>.
    $html = [regex]::Replace($html, '<pre><code[^>]*>(.*?)</code></pre>', '<pre>$1</pre>', 'Singleline')

    # Strip id/class/style attributes from every tag. The Text web part
    # ignores or rejects most of them, and Markdig's ids would collide with
    # SharePoint's own heading anchors.
    $html = [regex]::Replace($html, '\s(?:id|class|style)="[^"]*"', '')

    # Headings: the Text web part styles h2-h4 only. H1 is the page title.
    $html = [regex]::Replace($html, '<(/?)h([1-6])>', {
            param($m)
            $lvl = [int]$m.Groups[2].Value
            $mapped = if ($lvl -le 2) { 2 } elseif ($lvl -eq 3) { 3 } else { 4 }
            "<$($m.Groups[1].Value)h$mapped>"
        })

    # GitHub alert containers become blockquotes.
    $html = [regex]::Replace($html, '<div>\s*<p>(Note|Tip|Important|Warning|Caution)</p>(.*?)</div>',
        '<blockquote><p><strong>$1</strong></p>$2</blockquote>', 'Singleline')

    # Links.
    $html = [regex]::Replace($html, '<a href="([^"]*)"([^>]*)>(.*?)</a>', {
            param($m)
            $target = ConvertTo-SacSiteLink -Href $m.Groups[1].Value -CurrentFile $FileName -FindingsListUrl $FindingsListUrl
            if ($null -eq $target) { return $m.Groups[3].Value }
            "<a href=`"$target`">$($m.Groups[3].Value)</a>"
        }, 'Singleline')

    # Tables.
    $html = [regex]::Replace($html, '<table>.*?</table>', {
            param($m)
            $t = ConvertTo-SacTableHtml -TableHtml $m.Value -MaxRows $MaxTableRows
            if ($t.Truncated -gt 0) { $warnings.Add("$FileName : a table was capped at $MaxTableRows rows ($($t.Truncated) not shown).") }
            $t.Html
        }, 'Singleline')

    # ---- Split into segments ------------------------------------------------
    $segments = [System.Collections.Generic.List[hashtable]]::new()
    $buffer = [System.Text.StringBuilder]::new()
    $flush = {
        $text = $buffer.ToString().Trim()
        if ($text) { $segments.Add(@{ type = 'html'; html = $text }) }
        [void]$buffer.Clear()
    }

    $tokenPattern = '(?<img><p>\s*<img\s[^>]*>\s*</p>|<img\s[^>]*>)|(?<h2><h2>)'
    $pos = 0
    foreach ($m in [regex]::Matches($html, $tokenPattern, 'Singleline')) {
        [void]$buffer.Append($html.Substring($pos, $m.Index - $pos))
        $pos = $m.Index + $m.Length
        if ($m.Groups['h2'].Success) {
            & $flush
            [void]$buffer.Append('<h2>')
            continue
        }
        & $flush
        $tag = $m.Groups['img'].Value
        $src = if ($tag -match 'src="([^"]*)"') { [System.Net.WebUtility]::HtmlDecode($Matches[1]) } else { '' }
        $alt = if ($tag -match 'alt="([^"]*)"') { [System.Net.WebUtility]::HtmlDecode($Matches[1]) } else { 'Diagram' }
        if ($src -match '^(?:\./)?assets/(?<f>[A-Za-z0-9._-]+\.(?:png|jpg|jpeg|gif|svg))$') {
            $segments.Add(@{ type = 'image'; file = $Matches['f']; alt = $(if ($alt) { $alt } else { 'Diagram' }) })
        }
        else {
            $warnings.Add("$FileName : image '$src' is not a pre-rendered asset and was left out.")
        }
    }
    [void]$buffer.Append($html.Substring($pos))
    & $flush

    return [pscustomobject]@{
        Title    = $title
        Segments = $segments.ToArray()
        Warnings = $warnings.ToArray()
    }
}
