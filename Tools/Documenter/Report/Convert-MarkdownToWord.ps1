#
# Sentinel-As-Code/Tools/Documenter/Report/Convert-MarkdownToWord.ps1
#
# Created by noodlemctwoodle on 25/06/2026.
#

<#
.SYNOPSIS
    Combine a folder of Markdown files into a single, formatted Word
    (.docx) report via Pandoc. Built for Sentinel Documenter output.

.DESCRIPTION
    Collects every .md file under -Source (recursively), concatenates
    them in path order, and hands them to pandoc to produce a styled
    .docx. By default (-Toc Baked) it emits a real Word table-of-contents
    field and uses LibreOffice to populate its page numbers, so the file
    opens as a proper, page-numbered TOC with no "update fields" prompt;
    without LibreOffice it falls back to a static clickable contents list
    (-Toc Styled). See -Toc for the alternatives. Embedded images
    (e.g. assets/*.png) are pulled into the document.

    Two pandoc settings that this script always applies, learned the
    hard way against real Documenter output:

      -f gfm              Read as GitHub-Flavored Markdown. The default
                          'markdown' reader treats any '---' after a
                          blank line as a YAML metadata block; Documenter
                          uses '---' as horizontal rules, and a '* bullet'
                          inside one trips "YAML parse exception ... while
                          scanning an alias". GFM has no YAML-metadata
                          concept, so '---' stays a rule.

      --resource-path     Set to every directory under -Source, so
                          relative image links (assets/X.png) resolve
                          no matter which folder the asset store sits in.
                          pandoc otherwise resolves them against the
                          working directory and silently drops them.

    Only .md files are included; a sibling _raw/ folder of JSON (as the
    Documenter emits) is ignored, because raw JSON makes a useless
    code-block dump rather than a report.

    Cross-platform: pure PowerShell 7 plus the pandoc binary. No Word,
    no COM. Install pandoc with `brew install pandoc` (macOS),
    `winget install --id JohnMacFarlane.Pandoc` (Windows), or your
    distro's package manager (Linux).

.PARAMETER Source
    Folder containing the Markdown files. Walked recursively.

.PARAMETER OutputPath
    Destination .docx. Defaults to '<Source-leaf>.docx' beside -Source.

.PARAMETER Title
    Document title (rendered above the table of contents). Defaults to
    the leaf name of -Source.

.PARAMETER ReferenceDoc
    Pandoc reference .docx supplying house styles (table borders/shading,
    fonts, heading colours). Defaults to the bundled
    Tools/Documenter/Report/templates/sentinel-report-reference.docx - which
    gives formatted tables (grey grid, dark-blue header row, light row
    banding) - when it is present. Pass a path to override, or -NoReferenceDoc
    for plain.

.PARAMETER NoReferenceDoc
    Ignore the bundled reference template and use pandoc's plain defaults.

.PARAMETER Toc
    Table-of-contents strategy:
      Baked  (default) A real Word TOC field with page numbers, populated
                       via LibreOffice so the document opens filled-in with
                       no "update fields" prompt. Needs LibreOffice on PATH
                       (or the macOS app bundle); falls back to Styled when
                       soffice is not found. This is what a CI agent uses.
      Field            A real Word TOC field left for Word to populate
                       (Ctrl+A then F9, or the update-fields prompt on
                       open). No LibreOffice needed.
      Styled           A static, clickable contents link-list styled as a
                       TOC (indented, no page numbers). Always populated,
                       no prompt, no external tools.

.PARAMETER TocDepth
    Deepest heading level included in the contents. Default 2 (sections
    and their subsections).

.PARAMETER FrontFile
    File names (matched at the -Source root) to float to the front of
    the document ahead of the alphabetical order. Default 'README.md'.

.PARAMETER ExcludeFile
    File names (matched at the -Source root) to leave out entirely.
    Default 'index.md' - the Documenter index is a link-table duplicate
    of the real --toc, so it is dropped to avoid a second contents table.

.PARAMETER StripLinePattern
    Regex (multiline) for lines to delete from every file before
    conversion. Default removes the repeated Documenter provenance
    blockquote ('> **Workspace** ... **Documenter** vX'), which would
    otherwise appear once per section. Pass '' to keep everything.

.PARAMETER NoReformatFindings
    By default, dense finding bullets shaped like
    '- **<severity>** [<ID>](<link>) <title> - <description>' are
    rewritten so the severity, ID and title sit on a bold lead line with
    the description as a paragraph beneath (the title is resolved from
    the matching gap-analysis heading). Pass this switch to leave the
    bullets untouched.

.EXAMPLE
    ./Tools/Documenter/Report/Convert-MarkdownToWord.ps1 -Source '/private/tmp/SEC-UKS-PROD-SIEM-WS 2'

    Builds 'SEC-UKS-PROD-SIEM-WS 2.docx' beside the source folder.

.EXAMPLE
    ./Tools/Documenter/Report/Convert-MarkdownToWord.ps1 `
        -Source     '/private/tmp/SEC-UKS-PROD-SIEM-WS 2' `
        -OutputPath "$HOME/Desktop/SEC-UKS-PROD-SIEM-WS.docx" `
        -Title      'SEC-UKS-PROD-SIEM-WS - Sentinel Documentation'

.NOTES
    Author:         noodlemctwoodle
    Version:        1.0.0
    Last Updated:   2026-06-25
    Repository:     Sentinel-As-Code
    Requires:       PowerShell 7.2+, pandoc on PATH
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [string]$Title,

    [Parameter(Mandatory = $false)]
    [string]$ReferenceDoc,

    [Parameter(Mandatory = $false)]
    [switch]$NoReferenceDoc,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Baked', 'Field', 'Styled')]
    [string]$Toc = 'Baked',

    [Parameter(Mandatory = $false)]
    [int]$TocDepth = 2,

    [Parameter(Mandatory = $false)]
    [string[]]$FrontFile = @('README.md'),

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeFile = @('index.md'),

    [Parameter(Mandatory = $false)]
    [string]$StripLinePattern = '(?m)^[ \t]*>.*\bWorkspace\b.*\bDocumenter\b.*\r?\n?',

    [Parameter(Mandatory = $false)]
    [switch]$NoReformatFindings
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Message,
        [Parameter()] [ValidateSet('Info', 'Section', 'Warning', 'Error', 'Success')]
        [string] $Level = 'Info'
    )
    switch ($Level) {
        'Section' { Write-Host "`n$Message" -ForegroundColor Cyan }
        'Warning' { Write-Host $Message -ForegroundColor Yellow }
        'Error'   { Write-Host $Message -ForegroundColor Red }
        'Success' { Write-Host $Message -ForegroundColor Green }
        default   { Write-Host $Message }
    }
}

function Get-FindingTitleMap {
    <#
    .SYNOPSIS
        Build a map of finding ID -> canonical title from gap-analysis
        headings like '### [SENT-047](#sent-047) - Custom log table ...',
        so the dense overview bullets can be split into title + body
        without guessing at internal dashes.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [string[]] $Texts)

    $map = @{}
    $pattern = '(?m)^#{2,4}[ \t]+\[(?<id>[A-Za-z]+-\d+)\]\([^)]*\)[ \t]*[—–-][ \t]*(?<title>.+?)[ \t]*$'
    foreach ($t in $Texts) {
        if (-not $t) { continue }
        foreach ($m in [regex]::Matches($t, $pattern)) {
            $id = $m.Groups['id'].Value
            if (-not $map.ContainsKey($id)) { $map[$id] = $m.Groups['title'].Value.Trim() }
        }
    }
    return $map
}

function Convert-FindingBullets {
    <#
    .SYNOPSIS
        Rewrite dense finding bullets into a bold severity/ID/title lead
        line plus a description paragraph beneath.

    .DESCRIPTION
        Only lines shaped like '- **<sev>** [<ID>](<link>) <rest>' (where
        <ID> is e.g. SENT-047) are touched - everything else is returned
        verbatim. The title is split from the description using the title
        map where the ID is known, otherwise on the first ' - ' break.
        Returns the rewritten text; increments $Count by the number of
        bullets changed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]    $Text,
        [Parameter(Mandatory)] [hashtable] $TitleMap,
        [Parameter(Mandatory)] [ref]       $Count
    )

    $pattern = '(?m)^(?<ind>[ \t]*)[-*][ \t]+\*\*(?<sev>[^*]+?)\*\*[ \t]*\[(?<id>[A-Za-z]+-\d+)\]\((?<link>[^)]+)\)[ \t]*(?<rest>.*\S)[ \t]*$'
    $Count.Value += [regex]::Matches($Text, $pattern).Count

    # Severity word -> character style (defined in the reference doc) so
    # the word itself is coloured, replacing the source's coloured emoji.
    $sevStyles = @{
        'critical' = 'SevCritical'; 'high' = 'SevCritical'
        'warning'  = 'SevWarning';  'medium' = 'SevWarning'; 'moderate' = 'SevWarning'
        'low'      = 'SevLow'
        'info'     = 'SevInfo';     'informational' = 'SevInfo'
    }

    $evaluator = {
        param($m)
        $ind  = $m.Groups['ind'].Value
        $sev  = $m.Groups['sev'].Value.Trim()
        $id   = $m.Groups['id'].Value.Trim()
        $link = $m.Groups['link'].Value.Trim()
        $rest = $m.Groups['rest'].Value.Trim()

        $title = $rest
        $desc = ''
        if ($TitleMap.ContainsKey($id) -and $rest.StartsWith($TitleMap[$id])) {
            $title = $TitleMap[$id]
            $desc = $rest.Substring($title.Length).Trim()
            $desc = [regex]::Replace($desc, '^[—–-][ \t]*', '')
        }
        else {
            $sep = [regex]::Match($rest, '[ \t][—–][ \t]')
            if ($sep.Success) {
                $title = $rest.Substring(0, $sep.Index).Trim()
                $desc = $rest.Substring($sep.Index + $sep.Length).Trim()
            }
        }

        $sevWord = ([regex]::Replace($sev, '^[^\p{L}]+', '')).Trim()
        $styleName = $sevStyles[$sevWord.ToLowerInvariant()]
        $sevSeg = if ($styleName) { "[$sevWord]{custom-style=`"$styleName`"}" } else { "**$sevWord**" }

        $lead = "$ind- $sevSeg `u{00B7} **[$id]($link)** `u{00B7} **$title**"
        if ($desc) { return "$lead  `n$ind  $desc" }
        return $lead
    }.GetNewClosure()

    return [regex]::Replace($Text, $pattern, $evaluator)
}

function Convert-SeverityEmoji {
    <#
    .SYNOPSIS
        Replace a status/severity emoji followed by a word (e.g.
        '🟠 Warning', '🟢 Covered') with the word coloured via a character
        style, dropping the emoji. Catches the severity-column tables and
        coverage statuses that the bullet reformat does not touch. Colour
        is keyed off the emoji, so the word itself is unchanged.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Text,
        [Parameter(Mandatory)] [ref]    $Count
    )

    $map = @{ '🔴' = 'SevCritical'; '🟠' = 'SevWarning'; '🟡' = 'SevWarning'; '🟢' = 'SevLow'; '🔵' = 'SevInfo' }
    $pattern = '(?<e>🔴|🟠|🟡|🟢|🔵)[ \t]*(?<w>[A-Za-z]+)'
    $Count.Value += [regex]::Matches($Text, $pattern).Count

    $evaluator = {
        param($m)
        $style = $map[$m.Groups['e'].Value]
        $word = $m.Groups['w'].Value
        if ($style) { "[$word]{custom-style=`"$style`"}" } else { $m.Value }
    }.GetNewClosure()

    return [regex]::Replace($Text, $pattern, $evaluator)
}

function Get-SofficePath {
    <#
    .SYNOPSIS
        Locate the LibreOffice executable (soffice) on PATH or in the
        standard macOS app bundle. Returns $null if not found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    # Prefer the macOS app-bundle binary: the Homebrew 'soffice' on PATH is
    # a wrapper that launches asynchronously and returns before the macro
    # finishes. On Linux (CI) there is no app bundle, so the real soffice /
    # libreoffice on PATH is used.
    $mac = '/Applications/LibreOffice.app/Contents/MacOS/soffice'
    if (Test-Path -LiteralPath $mac) { return $mac }
    foreach ($name in 'soffice', 'libreoffice') {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

function Test-UnoAvailable {
    <#
    .SYNOPSIS
        True when a python3 carrying the LibreOffice 'uno' module is on
        PATH (Ubuntu: the python3-uno package). Required for the
        page-numbered TOC bake (see Update-WordToc.py).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    if (-not (Get-Command python3 -ErrorAction SilentlyContinue)) { return $false }
    & python3 -c 'import uno' 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Invoke-LibreOfficeBake {
    <#
    .SYNOPSIS
        Populate the Word TOC field's entries and page numbers in-place by
        driving LibreOffice headless through the UNO API (open hidden,
        update all indexes, save, close).

    .DESCRIPTION
        Pandoc emits a genuine Word TOC field but cannot paginate, so the
        field is empty until something computes page numbers. This delegates
        to Update-WordToc.py, which drives LibreOffice through the UNO API
        (the reliable headless method - a command-line Basic macro is
        documented as unreliable). Returns $true when the helper succeeds.

    .PARAMETER Soffice
        Path to the soffice/libreoffice executable (see Get-SofficePath).

    .PARAMETER DocxPath
        The .docx to update in place.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Soffice,
        [Parameter(Mandatory)] [string] $DocxPath
    )

    $helper = Join-Path $PSScriptRoot 'Update-WordToc.py'
    if (-not (Test-Path -LiteralPath $helper)) {
        Write-Log "  Bake helper not found: $helper" -Level Warning
        return $false
    }
    $abs = (Resolve-Path -LiteralPath $DocxPath).Path
    $out = & python3 $helper $abs $Soffice 2>&1
    $ok = ($LASTEXITCODE -eq 0)
    foreach ($line in $out) { if ("$line".Trim()) { Write-Log "  uno: $line" -Level Info } }
    return $ok
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------

Write-Log 'Markdown to Word report' -Level Section

if (-not (Get-Command pandoc -ErrorAction SilentlyContinue)) {
    Write-Log 'pandoc was not found on PATH. Install it and re-run:' -Level Error
    Write-Log '  macOS    brew install pandoc'
    Write-Log '  Windows  winget install --id JohnMacFarlane.Pandoc'
    Write-Log '  Linux    sudo apt-get install pandoc'
    exit 1
}

if (-not (Test-Path -LiteralPath $Source)) {
    Write-Log "Source path does not exist: $Source" -Level Error
    exit 1
}
$sourceItem = Get-Item -LiteralPath $Source
if (-not $sourceItem.PSIsContainer) {
    Write-Log "Source must be a folder, not a file: $Source" -Level Error
    exit 1
}
$sourceFull = $sourceItem.FullName

if (-not $Title) { $Title = $sourceItem.Name }
if (-not $OutputPath) {
    $OutputPath = Join-Path $sourceItem.Parent.FullName ($sourceItem.Name + '.docx')
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

# Default to the bundled, table-styled reference doc when present, unless
# the caller opted out or supplied their own.
if (-not $ReferenceDoc -and -not $NoReferenceDoc) {
    $bundled = Join-Path $PSScriptRoot 'templates/sentinel-report-reference.docx'
    if (Test-Path -LiteralPath $bundled) { $ReferenceDoc = $bundled }
}
if ($NoReferenceDoc) { $ReferenceDoc = $null }
if ($ReferenceDoc -and -not (Test-Path -LiteralPath $ReferenceDoc)) {
    Write-Log "Reference document not found: $ReferenceDoc" -Level Error
    exit 1
}

# ---------------------------------------------------------------------------
# Collect + order the Markdown
# ---------------------------------------------------------------------------

$allMd = @(Get-ChildItem -LiteralPath $sourceFull -Recurse -File -Filter *.md | Sort-Object FullName)
if ($allMd.Count -eq 0) {
    Write-Log "No .md files found under: $sourceFull" -Level Warning
    exit 0
}

# Drop excluded files (matched by name at the source root) - e.g. the
# index/TOC page that the real --toc replaces.
$excluded = @()
if ($ExcludeFile.Count -gt 0) {
    $excluded = @($allMd | Where-Object { $_.DirectoryName -eq $sourceFull -and ($ExcludeFile -contains $_.Name) })
    if ($excluded.Count -gt 0) {
        $allMd = @($allMd | Where-Object { $excluded -notcontains $_ })
    }
}

# Float front files (matched by name, at the source root) to the top,
# preserving the -FrontFile order. Everything else keeps path order.
$front = [System.Collections.Generic.List[object]]::new()
foreach ($name in $FrontFile) {
    $match = $allMd | Where-Object { $_.Name -ieq $name -and $_.DirectoryName -eq $sourceFull } | Select-Object -First 1
    if ($match) { $front.Add($match) }
}
$ordered = @($front) + @($allMd | Where-Object { $front -notcontains $_ })
$mdPaths = @($ordered | ForEach-Object { $_.FullName })

# Resource path = every directory under Source, so assets/*.png resolves
# wherever the asset store lives (root- or subfolder-level).
$dirs = @($sourceFull) + @((Get-ChildItem -LiteralPath $sourceFull -Recurse -Directory).FullName)
$resourcePath = $dirs -join [System.IO.Path]::PathSeparator

Write-Log "  Source:    $sourceFull"
Write-Log "  Output:    $OutputPath"
Write-Log "  Title:     $Title"
Write-Log "  Markdown:  $($mdPaths.Count) file(s)"
if ($excluded.Count -gt 0) { Write-Log "  Excluded:  $((($excluded | ForEach-Object { $_.Name }) -join ', '))" }
if ($front.Count -gt 0) { Write-Log "  Front:     $((($front | ForEach-Object { $_.Name }) -join ', '))" }
Write-Log "  Style ref: $(if ($ReferenceDoc) { Split-Path $ReferenceDoc -Leaf } else { 'pandoc default (plain tables)' })"

# ---------------------------------------------------------------------------
# Run pandoc
# ---------------------------------------------------------------------------

if (-not $PSCmdlet.ShouldProcess($OutputPath, 'Write Word document via pandoc')) {
    return
}

# Preprocess: strip the repeated provenance line from each file. Cleaned
# copies go to a temp dir; images still resolve because --resource-path
# points at the original folder, not these temp files.
# Pass 1: collect finding titles across every file, so dense bullets can
# be split into title + description reliably.
$titleMap = @{}
if (-not $NoReformatFindings) {
    $allText = foreach ($p in $mdPaths) { Get-Content -LiteralPath $p -Raw }
    $titleMap = Get-FindingTitleMap -Texts @($allText)
}

# Pass 2: strip the provenance line, reformat finding bullets, write a
# cleaned copy to the temp dir.
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("md2word-{0}" -f ([guid]::NewGuid().ToString('N')))
[void](New-Item -ItemType Directory -Path $work -Force)
$inputPaths = [System.Collections.Generic.List[string]]::new()
$stripped = 0
$reformatted = 0
$recoloured = 0
$idx = 0
foreach ($p in $mdPaths) {
    $idx++
    $text = Get-Content -LiteralPath $p -Raw
    if ($null -eq $text) { $text = '' }
    # Keep the provenance line in the first (overview) section so it
    # appears once under its heading; strip the repeats from later files.
    if ($StripLinePattern -and $idx -gt 1) {
        $cleaned = [regex]::Replace($text, $StripLinePattern, '')
        if ($cleaned -ne $text) { $stripped++; $text = $cleaned }
    }
    if (-not $NoReformatFindings) {
        $cnt = [ref]0
        $text = Convert-FindingBullets -Text $text -TitleMap $titleMap -Count $cnt
        $reformatted += $cnt.Value

        $ecnt = [ref]0
        $text = Convert-SeverityEmoji -Text $text -Count $ecnt
        $recoloured += $ecnt.Value
    }
    $dest = Join-Path $work ('{0:D4}-{1}' -f $idx, (Split-Path $p -Leaf))
    Set-Content -LiteralPath $dest -Value $text -Encoding utf8
    $inputPaths.Add($dest)
}

$reader = 'gfm+fenced_divs+bracketed_spans+raw_attribute'

# Resolve the TOC strategy. 'Baked' needs LibreOffice + python3-uno to
# compute page numbers (present on the Ubuntu CI agent); without them, fall
# back to the always-populated static contents.
$soffice = $null
if ($Toc -eq 'Baked') {
    $soffice = Get-SofficePath
    if (-not ($soffice -and (Test-UnoAvailable))) {
        Write-Log "  LibreOffice + python3-uno not both available - using -Toc Styled (no page numbers)." -Level Warning
        $Toc = 'Styled'
    }
}
$tocDesc = $Toc
if ($Toc -eq 'Baked' -and $soffice) { $tocDesc += " (page numbers via $(Split-Path $soffice -Leaf))" }
Write-Log "  TOC:       $tocDesc"

if ($Toc -eq 'Styled') {
    # Static, clickable contents in two passes so the styled severity spans
    # never pass through the gfm intermediate (which would drop them):
    #   Pass A: pandoc --toc (Markdown) -> a contents link-list with correct
    #           heading anchors.
    #   Pass B: [that list restyled as TOC paragraphs] + the ORIGINAL styled
    #           content -> docx.
    $tocProbe = Join-Path $work '_toc.md'

    $passA = @($inputPaths) + @(
    '-f', $reader, '-t', 'gfm', '--standalone'
    '--wrap=none'
    '--toc', "--toc-depth=$TocDepth"
    '-o', $tocProbe
)
Write-Log "Running pandoc (contents pass)..." -Level Info
$passAOut = & pandoc @passA 2>&1
if ($LASTEXITCODE -ne 0) {
    foreach ($line in $passAOut) { Write-Log "  $line" -Level Error }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "pandoc contents pass failed." -Level Error
    exit 1
}

# The contents list is every line before the first top-level heading.
$tocLines = [System.Collections.Generic.List[string]]::new()
foreach ($line in (Get-Content -LiteralPath $tocProbe)) {
    if ($line -match '^#\s') { break }
    $tocLines.Add($line)
}

# Turn the bullet list into TOC-styled paragraphs: each entry becomes a
# fenced div carrying a TOCEntry<level> paragraph style (indented, no
# bullet marker), so it reads as a table of contents rather than a list.
# The nesting unit is the smallest positive indent pandoc emitted.
$unit = 0
foreach ($line in $tocLines) {
    if ($line -match '^(?<i>[ \t]+)-[ \t]+\[') {
        $n = $Matches['i'].Length
        if ($unit -eq 0 -or $n -lt $unit) { $unit = $n }
    }
}
if ($unit -le 0) { $unit = 2 }

$contentsMd = [System.Collections.Generic.List[string]]::new()
$contentsMd.Add('# Contents')
$contentsMd.Add('')
foreach ($line in $tocLines) {
    if ($line -match '^(?<i>[ \t]*)-[ \t]+(?<entry>\[.*\]\(#.*\))[ \t]*$') {
        $level = [math]::Floor($Matches['i'].Length / $unit) + 1
        if ($level -gt 3) { $level = 3 }
        $contentsMd.Add("::: {custom-style=`"TOCEntry$level`"}")
        $contentsMd.Add($Matches['entry'])
        $contentsMd.Add(':::')
        $contentsMd.Add('')
    }
}
# Page break so the first section starts on a fresh page after the contents.
$contentsMd.Add('```{=openxml}')
$contentsMd.Add('<w:p><w:r><w:br w:type="page" /></w:r></w:p>')
$contentsMd.Add('```')
$contentsMd.Add('')
$contentsFile = Join-Path $work '_contents.md'
Set-Content -LiteralPath $contentsFile -Value $contentsMd -Encoding utf8

$passB = @($contentsFile) + @($inputPaths) + @(
    '-f', $reader, '-t', 'docx', '--standalone'
    '--resource-path', $resourcePath
    '--metadata', "title=$Title"
    '-o', $OutputPath
)
if ($ReferenceDoc) {
    $passB += @('--reference-doc', (Get-Item -LiteralPath $ReferenceDoc).FullName)
}

    Write-Log "Running pandoc (docx pass)..." -Level Info
    $pandocOut = & pandoc @passB 2>&1
    $exit = $LASTEXITCODE
}
else {
    # Real Word TOC field. Prepend a page break so that once the field is
    # populated, the first section still starts on a fresh page after it.
    $pageBreak = Join-Path $work '_pagebreak.md'
    Set-Content -LiteralPath $pageBreak -Encoding utf8 -Value @(
        '```{=openxml}'
        '<w:p><w:r><w:br w:type="page" /></w:r></w:p>'
        '```'
    )
    $tocArgs = @($pageBreak) + @($inputPaths) + @(
        '-f', $reader, '-t', 'docx', '--standalone'
        '--toc', "--toc-depth=$TocDepth"
        '--resource-path', $resourcePath
        '--metadata', "title=$Title"
        '-o', $OutputPath
    )
    if ($ReferenceDoc) { $tocArgs += @('--reference-doc', (Get-Item -LiteralPath $ReferenceDoc).FullName) }
    Write-Log "Running pandoc (TOC field)..." -Level Info
    $pandocOut = & pandoc @tocArgs 2>&1
    $exit = $LASTEXITCODE

    if ($exit -eq 0 -and $Toc -eq 'Baked') {
        Write-Log "Baking TOC page numbers via LibreOffice..." -Level Info
        if (-not (Invoke-LibreOfficeBake -Soffice $soffice -DocxPath $OutputPath)) {
            Write-Log "  LibreOffice bake failed; TOC field is present but unpopulated (open in Word, Ctrl+A then F9)." -Level Warning
        }
    }
}

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

# Surface missing-image warnings (pandoc leaves the alt text in place).
$missing = @($pandocOut | Select-String -Pattern 'Could not fetch resource')
foreach ($line in ($pandocOut | Where-Object { $_ -notmatch 'Could not fetch resource' })) {
    if ("$line".Trim()) { Write-Log "  pandoc: $line" -Level Info }
}

if ($exit -ne 0) {
    foreach ($line in $pandocOut) { Write-Log "  $line" -Level Error }
    Write-Log "pandoc failed (exit $exit)." -Level Error
    exit 1
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Log 'Summary' -Level Section
if ($StripLinePattern -and $stripped -gt 0) {
    Write-Log "  Provenance line stripped from $stripped file(s)."
}
if (-not $NoReformatFindings -and $reformatted -gt 0) {
    Write-Log "  Reformatted $reformatted finding bullet(s)."
}
if (-not $NoReformatFindings -and $recoloured -gt 0) {
    Write-Log "  Recoloured $recoloured severity label(s)."
}
if ($missing.Count -gt 0) {
    Write-Log "  $($missing.Count) image(s) not found on disk - left as alt text (broken links in the source)." -Level Warning
}
else {
    Write-Log "  All images resolved." -Level Info
}

if (Test-Path -LiteralPath $OutputPath) {
    $sizeKb = [math]::Round((Get-Item -LiteralPath $OutputPath).Length / 1KB, 1)
    Write-Log "  Output: $OutputPath ($sizeKb KB)" -Level Success
}
