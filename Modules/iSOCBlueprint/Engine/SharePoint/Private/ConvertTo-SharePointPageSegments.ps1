#Requires -Version 7.2

<#
.SYNOPSIS
    Convert one Blueprint section from the section model into the segments
    that make up a native SharePoint page.

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
    File:         Modules/iSOCBlueprint/Engine/SharePoint/Private/ConvertTo-SharePointPageSegments.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-08
    Version:      0.4.0
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-SacPageName {
    <#
    .SYNOPSIS
        Return the SharePoint page name (no .aspx) for a section id or file
        name.

    .PARAMETER FileName
        Section id or file name, for example '25-mitre-coverage' or
        '25-mitre-coverage.md'.

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
        Clean a section title for use as a page title.

    .DESCRIPTION
        Removes the '(TOC x.y)' suffix some renderer titles carry, which is a
        cross-reference to the formal configuration document and noise in a
        page title.

    .PARAMETER Title
        The section title.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Title)

    return ($Title -replace '\s*\(TOC[^)]*\)\s*$', '').Trim()
}

function ConvertTo-SacHtmlText {
    param([AllowEmptyString()] [AllowNull()] [string] $Text)
    if (-not $Text) { return '' }
    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

# The Markdown pages refer to one another by file name (90-gap-analysis.md),
# which suits a folder of Markdown but not the site. These turn a file name
# into the section's title: from $script:SacSectionTitles (section id ->
# title), which the site build fills before it converts any page, or the id
# made readable when the build has not.
$script:SacFileNamePattern = '(?<![\w/.-])(?<id>\d{2}-[a-z0-9-]+)\.md\b'

function Get-SacSectionName {
    <#
    .SYNOPSIS
        A section's title for a link to it: '90-gap-analysis' -> 'Gap
        Analysis' (its title), or 'Gap analysis' when the title is unknown.

    .PARAMETER SectionId
        The section id, the file name without .md.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $SectionId)

    if ($script:SacSectionTitles -and $script:SacSectionTitles.ContainsKey($SectionId)) { return [string]$script:SacSectionTitles[$SectionId] }
    $words = (($SectionId -replace '^\d+-', '') -replace '-', ' ').Trim()
    if (-not $words) { return $SectionId }
    return $words.Substring(0, 1).ToUpperInvariant() + $words.Substring(1)
}

function Get-SacSectionLinkText {
    <#
    .SYNOPSIS
        The text a link to another section shows: the section's title when
        the Markdown wrote its file name, otherwise the text as written.

    .PARAMETER Text
        The link text.

    .PARAMETER SectionId
        The section the link points at.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [AllowNull()] [string] $Text, [Parameter(Mandatory)] [AllowEmptyString()] [string] $SectionId)

    if ([string]$Text -match '^\s*(?:\./)?\d{2}-[a-z0-9-]+\.md(?:#\S*)?\s*$') { return Get-SacSectionName -SectionId $SectionId }
    return [string]$Text
}

function ConvertTo-SacFileMentionHtml {
    <#
    .SYNOPSIS
        Replace each file name (NN-name.md) in escaped plain text with the
        section's title, as a link from -Link for a section in this run and
        as text otherwise.

    .PARAMETER Html
        Escaped text with no markup.

    .PARAMETER Link
        Scriptblock taking the section id and the escaped title, returning
        the link HTML.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [AllowNull()] [string] $Html, [Parameter(Mandatory)] [scriptblock] $Link)

    if (-not $Html -or $Html -cnotmatch $script:SacFileNamePattern) { return [string]$Html }
    return $Html -creplace $script:SacFileNamePattern, {
        $id = $_.Groups['id'].Value
        $title = ConvertTo-SacHtmlText (Get-SacSectionName -SectionId $id)
        if ($script:SacSectionTitles -and $script:SacSectionTitles.ContainsKey($id)) { & $Link $id $title } else { $title }
    }
}

function ConvertTo-SacSiteLink {
    <#
    .SYNOPSIS
        Turn a run's link target into a site URL, or $null when the link
        should become plain text.

    .PARAMETER Run
        One text run from the section model, with href and target.

    .PARAMETER FindingsListUrl
        Site-relative URL of the findings list.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Run,
        [Parameter(Mandatory)] [string] $FindingsListUrl
    )
    $target = $Run.target
    switch ([string]$target.kind) {
        'external' { return [string]$Run.href }
        'finding' { return "~site/$FindingsListUrl/AllItems.aspx?FilterField1=FindingId&amp;FilterValue1=$([string]$target.id)" }
        'section' {
            # SharePoint makes its own heading anchors, so the anchor is dropped;
            # the contents page has no page of its own.
            if ([string]$target.section -eq 'index') { return $null }
            return "~site/SitePages/$(Get-SacPageName -FileName ([string]$target.section)).aspx"
        }
        default { return $null }
    }
}

function ConvertTo-SacRunsHtml {
    <#
    .SYNOPSIS
        HTML for a list of text runs, for a Text web part.

    .PARAMETER Runs
        Text runs from the section model.

    .PARAMETER FindingsListUrl
        Site-relative URL of the findings list.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()] [AllowEmptyCollection()] [object[]] $Runs,
        [Parameter(Mandatory)] [string] $FindingsListUrl
    )
    $sb = [System.Text.StringBuilder]::new()
    foreach ($r in @($Runs)) {
        if ($null -eq $r) { continue }
        if ($r.break) { [void]$sb.Append('<br>'); continue }
        # A link or mention by file name shows the section's title.
        $text = [string]$r.text
        if ($r.href -and [string]$r.target.kind -eq 'section') { $text = Get-SacSectionLinkText -Text $text -SectionId ([string]$r.target.section) }
        $fileOnly = (-not $r.href) -and $text -match '^\s*\d{2}-[a-z0-9-]+\.md\s*$'
        $h = ConvertTo-SacHtmlText $text
        if (-not $r.href) { $h = ConvertTo-SacFileMentionHtml -Html $h -Link { param($id, $title) "<a href=`"~site/SitePages/$(Get-SacPageName -FileName $id).aspx`">$title</a>" } }
        if ($r.code -and -not $fileOnly) { $h = "<code>$h</code>" }
        if ($r.strike) { $h = "<s>$h</s>" }
        if ($r.italic) { $h = "<em>$h</em>" }
        if ($r.bold) { $h = "<strong>$h</strong>" }
        if ($r.href) {
            $url = ConvertTo-SacSiteLink -Run $r -FindingsListUrl $FindingsListUrl
            if ($url) { $h = "<a href=`"$url`">$h</a>" }
        }
        [void]$sb.Append($h)
    }
    return $sb.ToString()
}

# Where the publisher puts a cut table's CSV: the tables/ folder of the
# assets library (SacSharePoint.ps1, $script:SacAssetsLibraryUrl).
$script:SacTablesUrl = '~site/BlueprintAssets/tables'

function Get-SacRunsText {
    <#
    .SYNOPSIS
        The plain text of a list of text runs, for a CSV cell: a section
        link shows its section's title, a line break becomes a space.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [AllowEmptyCollection()] [object[]] $Runs)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($r in @($Runs)) {
        if ($null -eq $r) { continue }
        if ($r.break) { [void]$sb.Append(' '); continue }
        $text = [string]$r.text
        if ($r.href -and [string]$r.target.kind -eq 'section') { $text = Get-SacSectionLinkText -Text $text -SectionId ([string]$r.target.section) }
        [void]$sb.Append($text)
    }
    return ($sb.ToString() -replace '\s+', ' ').Trim()
}

function ConvertTo-SacCsvField {
    <#
    .SYNOPSIS
        One CSV field: quoted when it holds a comma, quote or line break,
        and kept from being read as a formula.

    .DESCRIPTION
        A cell can carry text from the workspace (a rule name, an incident
        title) that someone outside the SOC influenced. Excel runs a cell
        that starts with =, +, -, @, a tab or a carriage return as a
        formula, so such a field is prefixed with an apostrophe, which Excel
        shows as text. A plain negative number is left alone.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Value)
    $v = $Value
    if ($v -match '^[=+\-@\t\r]' -and $v -notmatch '^-\d+(\.\d+)?$') { $v = "'" + $v }
    if ($v -match '[",\r\n]') { $v = '"' + $v.Replace('"', '""') + '"' }
    return $v
}

function ConvertTo-SacTableCsv {
    <#
    .SYNOPSIS
        A table block as CSV text: the header row, then every body row.
        Lines end in CRLF, as RFC 4180 has it.

    .PARAMETER Table
        A table block from the section model.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] $Table)
    $sb = [System.Text.StringBuilder]::new()
    $columns = @($Table.columns)
    $headers = @($columns | ForEach-Object { Get-SacRunsText -Runs @($_.text) })
    [void]$sb.Append((@($headers | ForEach-Object { ConvertTo-SacCsvField $_ }) -join ',') + "`r`n")
    foreach ($row in @($Table.rows)) {
        $cells = @(@($row) | ForEach-Object { ConvertTo-SacCsvField (Get-SacRunsText -Runs @($_)) })
        [void]$sb.Append(($cells -join ',') + "`r`n")
    }
    return $sb.ToString()
}

function Get-SacTableFileName {
    <#
    .SYNOPSIS
        The CSV file name for a cut table: the section id and the heading
        above the table, lower case, letters, digits and hyphens only, with
        -2, -3 and so on when the section has more than one under a heading.

    .PARAMETER Taken
        File names already given out in this section.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Id,
        [AllowEmptyString()] [string] $Heading,
        [AllowEmptyCollection()] [string[]] $Taken = @()
    )
    $slug = ($Heading.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($slug.Length -gt 60) { $slug = $slug.Substring(0, 60).TrimEnd('-') }
    $stem = if ($slug) { "$Id-$slug" } else { "$Id-table" }
    $name = "$stem.csv"
    $n = 2
    while ($Taken -contains $name) { $name = "$stem-$n.csv"; $n++ }
    return $name
}

function ConvertTo-SacTableHtml {
    <#
    .SYNOPSIS
        SharePoint editor table markup for one table block, capping the
        number of body rows.

    .PARAMETER Table
        A table block from the section model.

    .PARAMETER MaxRows
        Maximum body rows to keep. Extra rows are replaced by one note row.

    .PARAMETER FindingsListUrl
        Site-relative URL of the findings list.

    .PARAMETER CsvUrl
        Where the whole table is as CSV, for the note under a cut table.

    .OUTPUTS
        [pscustomobject] Html (string) and Truncated (int, rows dropped).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] $Table,
        [Parameter(Mandatory)] [int] $MaxRows,
        [Parameter(Mandatory)] [string] $FindingsListUrl,
        [string] $CsvUrl
    )

    $out = [System.Text.StringBuilder]::new()
    [void]$out.Append('<div class="canvasRteResponsiveTable"><div class="tableWrapper"><table title="Table"><tbody>')

    $columns = @($Table.columns)
    $headers = @($columns | ForEach-Object { ConvertTo-SacRunsHtml -Runs @($_.text) -FindingsListUrl $FindingsListUrl })
    # The renderer uses '| | |' headers for key/value tables. An all-empty
    # header row would show as a blank bold band.
    if (@($headers | Where-Object { $_.Trim() }).Count) {
        [void]$out.Append('<tr>')
        foreach ($h in $headers) { [void]$out.Append("<td><strong>$h</strong></td>") }
        [void]$out.Append('</tr>')
    }

    $rows = @($Table.rows)
    $dropped = [math]::Max(0, $rows.Count - $MaxRows)
    foreach ($row in ($rows | Select-Object -First $MaxRows)) {
        [void]$out.Append('<tr>')
        foreach ($cell in @($row)) { [void]$out.Append('<td>' + (ConvertTo-SacRunsHtml -Runs @($cell) -FindingsListUrl $FindingsListUrl) + '</td>') }
        [void]$out.Append('</tr>')
    }
    if ($dropped -gt 0) {
        $span = [math]::Max($columns.Count, 1)
        $csvText = if ($CsvUrl) { "Every row is in <a href=`"$CsvUrl`">this table as a CSV file</a>, which opens in Excel, and in" } else { 'The full table, with a filter, is in' }
        [void]$out.Append("<tr><td colspan=`"$span`"><em>$dropped more rows not shown here. $csvText this section on the <a href=`"~site/SitePages/Dashboard.aspx`">dashboard</a>'s Sections tab$(if ($CsvUrl) { ', with a filter' }).</em></td></tr>")
    }
    [void]$out.Append('</tbody></table></div></div>')
    return [pscustomobject]@{ Html = $out.ToString(); Truncated = $dropped }
}

function ConvertTo-SacBlocksHtml {
    # HTML for blocks that stay inside one Text web part (lists, notes, tables).
    # A table cut at MaxTableRows is added whole to Tables as CSV, named from
    # the heading above it.
    param([object[]] $Blocks, [string] $FindingsListUrl, [int] $MaxTableRows, [string] $Id, [System.Collections.Generic.List[string]] $Warnings, [System.Collections.Generic.List[object]] $Tables, [string] $Heading = '')
    $sb = [System.Text.StringBuilder]::new()
    foreach ($b in @($Blocks)) {
        if ($null -eq $b) { continue }
        switch ([string]$b.type) {
            'heading' {
                $lvl = [int]$b.level
                $tag = if ($lvl -le 2) { 'h2' } elseif ($lvl -eq 3) { 'h3' } else { 'h4' }
                [void]$sb.Append("<$tag>" + (ConvertTo-SacRunsHtml -Runs @($b.text) -FindingsListUrl $FindingsListUrl) + "</$tag>")
            }
            'paragraph' { [void]$sb.Append('<p>' + (ConvertTo-SacRunsHtml -Runs @($b.text) -FindingsListUrl $FindingsListUrl) + '</p>') }
            'list' {
                $tag = if ($b.ordered) { 'ol' } else { 'ul' }
                $start = if ($b.ordered -and $b.start) { " start=`"$([int]$b.start)`"" } else { '' }
                [void]$sb.Append("<$tag$start>")
                foreach ($item in @($b.items)) {
                    [void]$sb.Append('<li>' + (ConvertTo-SacRunsHtml -Runs @($item.text) -FindingsListUrl $FindingsListUrl))
                    if (@($item.blocks).Count) { [void]$sb.Append((ConvertTo-SacBlocksHtml -Blocks @($item.blocks) -FindingsListUrl $FindingsListUrl -MaxTableRows $MaxTableRows -Id $Id -Warnings $Warnings -Tables $Tables -Heading $Heading)) }
                    [void]$sb.Append('</li>')
                }
                [void]$sb.Append("</$tag>")
            }
            'note' { [void]$sb.Append('<blockquote>' + (ConvertTo-SacBlocksHtml -Blocks @($b.blocks) -FindingsListUrl $FindingsListUrl -MaxTableRows $MaxTableRows -Id $Id -Warnings $Warnings -Tables $Tables -Heading $Heading) + '</blockquote>') }
            'table' {
                $csvUrl = $null
                $csvFile = $null
                if ($null -ne $Tables -and @($b.rows).Count -gt $MaxTableRows) {
                    $csvFile = Get-SacTableFileName -Id $Id -Heading $Heading -Taken @($Tables | ForEach-Object { $_.file })
                    $Tables.Add([ordered]@{ file = $csvFile; heading = $Heading; rows = @($b.rows).Count; csv = (ConvertTo-SacTableCsv -Table $b) })
                    $csvUrl = "$script:SacTablesUrl/$csvFile"
                }
                $t = ConvertTo-SacTableHtml -Table $b -MaxRows $MaxTableRows -FindingsListUrl $FindingsListUrl -CsvUrl $csvUrl
                if ($t.Truncated -gt 0) { $Warnings.Add("$Id : a table was capped at $MaxTableRows rows ($($t.Truncated) not shown)$(if ($csvFile) { "; every row is in tables/$csvFile" }).") }
                [void]$sb.Append($t.Html)
            }
            'code' { [void]$sb.Append('<pre>' + (ConvertTo-SacHtmlText ([string]$b.text)) + '</pre>') }
            'chart' { $Warnings.Add("$Id : a chart nested in a list or note is not shown.") }
            default { }
        }
    }
    return $sb.ToString()
}

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

function ConvertTo-SacChartData {
    <#
    .SYNOPSIS
        A chart's data for the chart web part. A flowchart node's link is
        mapped the way a text run's is: a site URL ('~site/...'), or none
        when the target has no page on the site. A finding card links to the
        findings list filtered to its finding. Other kinds pass through.

    .PARAMETER Chart
        A chart block from the section model.

    .PARAMETER FindingsListUrl
        Site-relative URL of the findings list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Chart,
        [Parameter(Mandatory)] [string] $FindingsListUrl
    )
    if ([string]$Chart.kind -eq 'finding-cards' -and $null -ne $Chart.data) {
        $cards = $Chart.data | ConvertTo-Json -Depth 32 | ConvertFrom-Json -AsHashtable -Depth 32
        foreach ($c in @($cards.cards)) {
            if (-not $c) { continue }
            $href = if ($c['id']) { ConvertTo-SacSiteLink -Run @{ href = $c['href']; target = @{ kind = 'finding'; id = [string]$c['id'] } } -FindingsListUrl $FindingsListUrl } else { $null }
            $c['href'] = $(if ($href) { $href.Replace('&amp;', '&') } else { $null })
        }
        return $cards
    }
    if ([string]$Chart.kind -ne 'flowchart' -or $null -eq $Chart.data) { return $Chart.data }
    # A copy, so the section model itself is left as it was read.
    $data = $Chart.data | ConvertTo-Json -Depth 32 | ConvertFrom-Json -AsHashtable -Depth 32
    foreach ($n in @($data.nodes)) {
        if ($null -eq $n) { continue }
        $href = $null
        if ($n['href'] -and $n['target']) { $href = ConvertTo-SacSiteLink -Run $n -FindingsListUrl $FindingsListUrl }
        # The web part escapes attribute values itself, so the URL is raw.
        $n['href'] = $(if ($href) { $href.Replace('&amp;', '&') } else { $null })
    }
    return $data
}

function ConvertTo-SacChartFallbackHtml {
    <#
    .SYNOPSIS
        Text web part HTML for a chart, used when the chart web part is not
        available on the site: the chart's data as a table, or its title.

    .PARAMETER Chart
        A chart segment's chart (kind, title, data).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] $Chart)

    $sb = [System.Text.StringBuilder]::new()
    if ($Chart.title) { [void]$sb.Append('<p><strong>' + (ConvertTo-SacHtmlText ([string]$Chart.title)) + '</strong></p>') }
    # @() keeps a one-row chart a list of rows rather than one row's cells.
    $rows = @(switch ([string]$Chart.kind) {
        'pie' { foreach ($s in @($Chart.data.slices)) { , @([string]$s.label, [string]$s.value) } }
        'sankey' { foreach ($l in @($Chart.data.links)) { , @("$($l.source) to $($l.target)", [string]$l.value) } }
        'incident-lifecycle' {
            $d = $Chart.data
            foreach ($f in @(@('Raised', 'raised'), @('New', 'new'), @('Active', 'active'), @('Closed', 'closed'), @('Closed without acknowledgement', 'unacknowledged'))) {
                $v = if ($d -is [System.Collections.IDictionary]) { $d[$f[1]] } elseif ($d -and $d.PSObject.Properties[$f[1]]) { $d.PSObject.Properties[$f[1]].Value } else { $null }
                if ($null -ne $v) { , @($f[0], [string]$v) }
            }
        }
        'xy' {
            $labels = @($Chart.data.xAxis.labels)
            for ($i = 0; $i -lt $labels.Count; $i++) {
                , @([string]$labels[$i], ((@($Chart.data.series) | ForEach-Object { [string]@($_.values)[$i] }) -join ' / '))
            }
        }
        default { }
    })
    if ($rows.Count) {
        [void]$sb.Append('<div class="canvasRteResponsiveTable"><div class="tableWrapper"><table title="Table"><tbody>')
        foreach ($r in $rows) { [void]$sb.Append('<tr><td>' + (ConvertTo-SacHtmlText $r[0]) + '</td><td>' + (ConvertTo-SacHtmlText $r[1]) + '</td></tr>') }
        [void]$sb.Append('</tbody></table></div></div>')
    }
    else {
        [void]$sb.Append('<p><em>This chart is drawn by the iSOC Blueprint chart web part, which is not on this site yet.</em></p>')
    }
    return $sb.ToString()
}
