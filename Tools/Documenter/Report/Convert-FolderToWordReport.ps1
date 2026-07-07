#
# Sentinel-As-Code/Tools/Documenter/Report/Convert-FolderToWordReport.ps1
#
# Created by noodlemctwoodle on 25/06/2026.
#

<#
.SYNOPSIS
    Render every file in a folder tree into a single, formatted Word
    (.docx) report via Pandoc.

.DESCRIPTION
    Walks -Source recursively, groups files by their top-level subfolder,
    and writes each file under its own heading:

      - .json                  pretty-printed, in a fenced code block
      - .csv / .tsv            rendered as a Markdown table (small ones)
                               or a code block (when over -TableRowLimit)
      - .kql .yaml .ps1 .xml   fenced code block with a language hint
        .bicep .sql .log .txt
      - .md                    inlined as-is (already Markdown)
      - binary / unreadable    noted and skipped (size reported)

    The assembled Markdown is then handed to pandoc, which emits a styled
    .docx with a real Word table of contents (folders at level 1, files
    at level 2).

    Cross-platform by design: pure PowerShell 7 plus the pandoc binary.
    No Word, no COM, no Office automation, so it runs on macOS, Linux and
    Windows alike. (The classic New-Object -ComObject Word.Application
    route is Windows-only and is deliberately avoided.)

    Pandoc must be installed and on PATH:

        macOS    brew install pandoc
        Windows  winget install --id JohnMacFarlane.Pandoc
        Linux    sudo apt-get install pandoc   (or distro equivalent)

    Word copes poorly with very large documents. Individual files larger
    than -MaxFileKB are truncated (with a note) so a stray multi-megabyte
    log cannot bloat the report into something Word refuses to open. Set
    -MaxFileKB 0 to disable truncation entirely.

.PARAMETER Source
    Folder whose contents become the report. Walked recursively.

.PARAMETER OutputPath
    Destination .docx. Defaults to '<Source-leaf>.docx' beside -Source.

.PARAMETER Title
    Document title (rendered above the table of contents). Defaults to
    the leaf name of -Source.

.PARAMETER ReferenceDoc
    Optional pandoc reference .docx supplying the house styles (fonts,
    heading colours, code-block style). Omit to use pandoc's defaults.

.PARAMETER MaxFileKB
    Per-file size ceiling in KB. Files larger than this are truncated in
    the report with a note. Default 1024 (1 MB). 0 disables truncation.

.PARAMETER TableRowLimit
    CSV/TSV files with at most this many data rows are rendered as a
    Markdown table; larger ones fall back to a code block. Default 200.

.PARAMETER KeepMarkdown
    Keep the intermediate Markdown file (written beside -OutputPath with
    a .md extension) instead of deleting it. Handy for debugging.

.EXAMPLE
    ./Tools/Documenter/Report/Convert-FolderToWordReport.ps1 `
        -Source '/Users/tobygoulden/Downloads/SEC-UKS-PROD-SIEM-WS 2/_raw'

    Builds '_raw.docx' beside the source folder, titled "_raw".

.EXAMPLE
    ./Tools/Documenter/Report/Convert-FolderToWordReport.ps1 `
        -Source       '/Users/tobygoulden/Downloads/SEC-UKS-PROD-SIEM-WS 2/_raw' `
        -OutputPath   "$HOME/Desktop/SIEM-Workspace-Export.docx" `
        -Title        'SEC-UKS-PROD-SIEM-WS - Raw Export'

    Custom output path and title.

.EXAMPLE
    ./Tools/Documenter/Report/Convert-FolderToWordReport.ps1 `
        -Source       './Content' `
        -ReferenceDoc './Docs/house-style.docx' `
        -MaxFileKB    512

    Applies a branded reference template and a tighter per-file ceiling.

.NOTES
    Author:         noodlemctwoodle
    Version:        1.0.0
    Last Updated:   2026-06-25
    Repository:     Sentinel-As-Code
    Requires:       PowerShell 7.2+, pandoc on PATH

    This is a generic folder-to-Word converter. It has no Sentinel or
    Azure dependency and does not import Sentinel.Common, so it is safe
    to run anywhere.
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
    [int]$MaxFileKB = 1024,

    [Parameter(Mandatory = $false)]
    [int]$TableRowLimit = 200,

    [Parameter(Mandatory = $false)]
    [switch]$KeepMarkdown
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

function Write-Log {
    <#
    .SYNOPSIS
        Minimal levelled console logging. Mirrors the -Level vocabulary
        of the repo's Write-PipelineMessage without taking a module
        dependency, so this script stays self-contained.
    #>
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

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Test-IsTextFile {
    <#
    .SYNOPSIS
        Heuristic text/binary sniff: a NUL byte in the first 8 KB marks
        the file as binary. Empty files count as text.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [string] $Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $buffer = [byte[]]::new(8192)
        $read = $stream.Read($buffer, 0, $buffer.Length)
        for ($i = 0; $i -lt $read; $i++) {
            if ($buffer[$i] -eq 0) { return $false }
        }
        return $true
    }
    finally {
        $stream.Dispose()
    }
}

function Get-CodeLanguage {
    <#
    .SYNOPSIS
        Map a file extension to a pandoc code-block language class for
        syntax highlighting. Returns '' when there is no sensible hint
        (the block still renders, just without highlighting).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Extension)

    switch ($Extension.ToLowerInvariant()) {
        '.json'  { 'json' }
        '.kql'   { 'kusto' }
        '.kusto' { 'kusto' }
        '.yaml'  { 'yaml' }
        '.yml'   { 'yaml' }
        '.xml'   { 'xml' }
        '.html'  { 'html' }
        '.ps1'   { 'powershell' }
        '.psm1'  { 'powershell' }
        '.psd1'  { 'powershell' }
        '.bicep' { 'bicep' }
        '.sh'    { 'bash' }
        '.sql'   { 'sql' }
        '.ini'   { 'ini' }
        default  { '' }
    }
}

function Get-TildeFence {
    <#
    .SYNOPSIS
        Return a tilde code fence long enough not to collide with any
        tilde run already present in the content. Tilde fences are used
        (rather than backticks) because file content - JSON, logs, KQL -
        very commonly contains backticks but almost never tildes.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Content)

    $longest = 0
    foreach ($match in [regex]::Matches($Content, '(?m)^(~{3,})')) {
        $len = $match.Groups[1].Value.Length
        if ($len -gt $longest) { $longest = $len }
    }
    return ('~' * [Math]::Max(4, $longest + 1))
}

function Format-JsonContent {
    <#
    .SYNOPSIS
        Pretty-print JSON for readability. Returns the original text
        unchanged if it does not parse (so malformed exports still
        appear verbatim rather than being dropped).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Content)

    if ([string]::IsNullOrWhiteSpace($Content)) { return $Content }
    try {
        return ($Content | ConvertFrom-Json -Depth 64 | ConvertTo-Json -Depth 64)
    }
    catch {
        return $Content
    }
}

function ConvertTo-MarkdownTable {
    <#
    .SYNOPSIS
        Render delimited (CSV/TSV) text as a Markdown pipe table. Returns
        $null when the text does not parse into at least one column, so
        the caller can fall back to a code block.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Content,
        [Parameter(Mandatory)] [char]   $Delimiter,
        [Parameter(Mandatory)] [int]    $RowLimit
    )

    $lines = $Content -split "`r?`n" | Where-Object { $_ -ne '' }
    if ($lines.Count -lt 1) { return $null }

    try {
        $rows = $lines | ConvertFrom-Csv -Delimiter $Delimiter
    }
    catch {
        return $null
    }

    $rows = @($rows)
    if ($rows.Count -eq 0) { return $null }

    $columns = @($rows[0].PSObject.Properties.Name)
    if ($columns.Count -eq 0) { return $null }

    $escape = {
        param([object] $Value)
        $text = if ($null -eq $Value) { '' } else { [string]$Value }
        # Pipes break table cells; newlines break the row. Neutralise both.
        $text = $text -replace '\|', '\|'
        return ($text -replace '\r?\n', ' ')
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('| ' + (($columns | ForEach-Object { & $escape $_ }) -join ' | ') + ' |')
    [void]$sb.AppendLine('| ' + (($columns | ForEach-Object { '---' }) -join ' | ') + ' |')

    $shown = 0
    foreach ($row in $rows) {
        if ($shown -ge $RowLimit) { break }
        $cells = foreach ($col in $columns) { & $escape $row.$col }
        [void]$sb.AppendLine('| ' + ($cells -join ' | ') + ' |')
        $shown++
    }

    if ($rows.Count -gt $RowLimit) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("*Table truncated: showing $RowLimit of $($rows.Count) rows.*")
    }

    return $sb.ToString()
}

function ConvertTo-MarkdownHeadingText {
    <#
    .SYNOPSIS
        Make a string safe to drop into an ATX heading. File paths are
        wrapped in inline code so underscores, asterisks and the like
        are not interpreted as Markdown emphasis.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Text)

    return '`' + ($Text -replace '`', "'") + '`'
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------

Write-Log 'Folder to Word report' -Level Section

$pandoc = Get-Command pandoc -ErrorAction SilentlyContinue
if (-not $pandoc) {
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
$sourceLeaf = $sourceItem.Name

if (-not $Title) { $Title = $sourceLeaf }

if (-not $OutputPath) {
    $OutputPath = Join-Path $sourceItem.Parent.FullName ($sourceLeaf + '.docx')
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

if ($ReferenceDoc -and -not (Test-Path -LiteralPath $ReferenceDoc)) {
    Write-Log "Reference document not found: $ReferenceDoc" -Level Error
    exit 1
}

Write-Log "  Source:      $sourceFull"
Write-Log "  Output:      $OutputPath"
Write-Log "  Title:       $Title"
Write-Log "  Max file KB: $(if ($MaxFileKB -le 0) { 'unlimited' } else { $MaxFileKB })"
if ($ReferenceDoc) { Write-Log "  Reference:   $ReferenceDoc" }

# ---------------------------------------------------------------------------
# Enumerate
# ---------------------------------------------------------------------------

$rawFiles = @(Get-ChildItem -LiteralPath $sourceFull -Recurse -File)
if ($rawFiles.Count -eq 0) {
    Write-Log 'Source folder contains no files. Nothing to do.' -Level Warning
    exit 0
}
Write-Log "  Files found: $($rawFiles.Count)"

$sep = [System.IO.Path]::DirectorySeparatorChar
$maxBytes = if ($MaxFileKB -gt 0) { $MaxFileKB * 1024 } else { [long]::MaxValue }

# Project each file to its relative path and top-level group, then sort
# by (group, path). Sorting on the computed group - rather than the raw
# FullName - guarantees every file in a folder is contiguous, so each
# group heading is emitted exactly once.
$files = @(
    $rawFiles | ForEach-Object {
        $relative = $_.FullName.Substring($sourceFull.Length).TrimStart($sep)
        $relativeDir = $_.DirectoryName.Substring($sourceFull.Length).TrimStart($sep)
        $group = if ([string]::IsNullOrEmpty($relativeDir)) { '(root)' } else { ($relativeDir -split [regex]::Escape([string]$sep))[0] }
        [pscustomobject]@{
            Item            = $_
            Group           = $group
            RelativeDisplay = ($relative -replace '\\', '/')
        }
    } | Sort-Object Group, RelativeDisplay
)

# ---------------------------------------------------------------------------
# Build Markdown
# ---------------------------------------------------------------------------

$md = [System.Text.StringBuilder]::new()
[void]$md.AppendLine("Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') from ``$sourceFull`` ($($files.Count) files).")
[void]$md.AppendLine()

$counters = @{ Rendered = 0; Truncated = 0; Skipped = 0 }
$currentGroup = $null

foreach ($entry in $files) {
    $file = $entry.Item
    $group = $entry.Group
    $relativeDisplay = $entry.RelativeDisplay

    # Top-level subfolder (or '(root)' for files directly under Source)
    # becomes a level-1 heading so the table of contents reads
    # folder -> file.
    if ($group -ne $currentGroup) {
        $currentGroup = $group
        [void]$md.AppendLine()
        [void]$md.AppendLine('# ' + (ConvertTo-MarkdownHeadingText $group))
        [void]$md.AppendLine()
    }

    [void]$md.AppendLine('## ' + (ConvertTo-MarkdownHeadingText $relativeDisplay))
    [void]$md.AppendLine()

    # Binary or unreadable files: note and move on.
    if (-not (Test-IsTextFile -Path $file.FullName)) {
        [void]$md.AppendLine("*Binary file, $([math]::Round($file.Length / 1KB, 1)) KB - not rendered.*")
        [void]$md.AppendLine()
        $counters.Skipped++
        continue
    }

    $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { $content = '' }

    # Truncate oversized files so Word stays openable.
    $truncated = $false
    if ($file.Length -gt $maxBytes) {
        $content = $content.Substring(0, [Math]::Min($maxBytes, $content.Length))
        $truncated = $true
    }

    $ext = $file.Extension.ToLowerInvariant()

    if ($ext -eq '.md') {
        # Already Markdown: inline verbatim.
        [void]$md.AppendLine($content)
    }
    elseif ($ext -in @('.csv', '.tsv')) {
        $delimiter = if ($ext -eq '.tsv') { "`t" } else { ',' }
        $table = ConvertTo-MarkdownTable -Content $content -Delimiter $delimiter -RowLimit $TableRowLimit
        if ($table) {
            [void]$md.AppendLine($table)
        }
        else {
            $fence = Get-TildeFence $content
            [void]$md.AppendLine($fence)
            [void]$md.AppendLine($content)
            [void]$md.AppendLine($fence)
        }
    }
    else {
        $body = if ($ext -eq '.json') { Format-JsonContent $content } else { $content }
        $lang = Get-CodeLanguage $ext
        $fence = Get-TildeFence $body
        $opener = if ($lang) { "$fence {.$lang}" } else { $fence }
        [void]$md.AppendLine($opener)
        [void]$md.AppendLine($body)
        [void]$md.AppendLine($fence)
    }

    if ($truncated) {
        [void]$md.AppendLine()
        [void]$md.AppendLine("*File truncated to $MaxFileKB KB (original $([math]::Round($file.Length / 1KB, 1)) KB).*")
        $counters.Truncated++
    }

    [void]$md.AppendLine()
    $counters.Rendered++
}

# ---------------------------------------------------------------------------
# Write Markdown + run pandoc
# ---------------------------------------------------------------------------

$mdPath = if ($KeepMarkdown) {
    [System.IO.Path]::ChangeExtension($OutputPath, '.md')
}
else {
    Join-Path ([System.IO.Path]::GetTempPath()) ("folder-report-{0}.md" -f ([guid]::NewGuid().ToString('N')))
}

Set-Content -LiteralPath $mdPath -Value $md.ToString() -Encoding utf8

$pandocArgs = @(
    $mdPath
    '--from', 'markdown'
    '--to', 'docx'
    '--output', $OutputPath
    '--standalone'
    '--toc'
    '--toc-depth=2'
    '--metadata', "title=$Title"
)
if ($ReferenceDoc) {
    $pandocArgs += @('--reference-doc', (Get-Item -LiteralPath $ReferenceDoc).FullName)
}

if ($PSCmdlet.ShouldProcess($OutputPath, 'Write Word document via pandoc')) {
    Write-Log "Running pandoc ($($files.Count) files)..." -Level Info
    & pandoc @pandocArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Log "pandoc exited with code $LASTEXITCODE." -Level Error
        if (-not $KeepMarkdown) { Remove-Item -LiteralPath $mdPath -ErrorAction SilentlyContinue }
        exit 1
    }
}

if (-not $KeepMarkdown) {
    Remove-Item -LiteralPath $mdPath -ErrorAction SilentlyContinue
}
elseif ($PSCmdlet.ShouldProcess($mdPath, 'Keep intermediate Markdown')) {
    Write-Log "  Markdown kept: $mdPath"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Log 'Summary' -Level Section
Write-Log "  Rendered:  $($counters.Rendered)"
Write-Log "  Truncated: $($counters.Truncated)"
Write-Log "  Skipped:   $($counters.Skipped) (binary/unreadable)"

if (Test-Path -LiteralPath $OutputPath) {
    $sizeKb = [math]::Round((Get-Item -LiteralPath $OutputPath).Length / 1KB, 1)
    Write-Log "  Output:    $OutputPath ($sizeKb KB)" -Level Success
}
