#Requires -Version 7.6

<#
.SYNOPSIS
    Combine a folder of Markdown files into a single, formatted Word
    (.docx) report via Pandoc. Built for iSOC Blueprint output.

.DESCRIPTION
    The conversion itself is one function per file under
    Modules/iSOCBlueprint/Private/Word (Invoke-iSOCBlueprintWordConversion and
    its steps); this script loads them and runs it with the same parameters.

    Collects every .md file under -Source (recursively), concatenates
    them in path order, and hands them to pandoc to produce a styled
    .docx. By default (-Toc Baked) it emits a real Word table-of-contents
    field and uses LibreOffice to populate its page numbers, so the file
    opens as a proper, page-numbered TOC with no "update fields" prompt;
    without LibreOffice it falls back to a static clickable contents list
    (-Toc Styled). See -Toc for the alternatives. Embedded images
    (e.g. assets/*.png) are pulled into the document.

    Two pandoc settings that this script always applies, learned the
    hard way against real Blueprint output:

      -f gfm              Read as GitHub-Flavored Markdown. The default
                          'markdown' reader treats any '---' after a
                          blank line as a YAML metadata block; Blueprint
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
    Blueprint emits) is ignored, because raw JSON makes a useless
    code-block dump rather than a report.

    Cross-platform: pure PowerShell 7.6 plus the pandoc binary. No Word,
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
    Modules/iSOCBlueprint/Engine/Report/templates/sentinel-report-reference.docx - which
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
    Default 'index.md' - the Blueprint index is a link-table duplicate
    of the real --toc, so it is dropped to avoid a second contents table.

.PARAMETER StripLinePattern
    Regex (multiline) for lines to delete from every file before
    conversion. Default removes the repeated Blueprint provenance
    blockquote ('> **Workspace** ... **Blueprint** vX'), which would
    otherwise appear once per section. Pass '' to keep everything.

.PARAMETER NoReformatFindings
    By default, dense finding bullets shaped like
    '- **<severity>** [<ID>](<link>) <title> - <description>' are
    rewritten so the severity, ID and title sit on a bold lead line with
    the description as a paragraph beneath (the title is resolved from
    the matching gap-analysis heading). Pass this switch to leave the
    bullets untouched.

.EXAMPLE
    ./Modules/iSOCBlueprint/Engine/Report/Convert-MarkdownToWord.ps1 -Source ./SecurityDocs/law-sentinel-prod

    Builds 'law-sentinel-prod.docx' beside the source folder.

.EXAMPLE
    ./Modules/iSOCBlueprint/Engine/Report/Convert-MarkdownToWord.ps1 `
        -Source     ./SecurityDocs/law-sentinel-prod `
        -OutputPath ./law-sentinel-prod.docx `
        -Title      'law-sentinel-prod - Sentinel Documentation'

    Writes the report to a chosen path with the title the Blueprint
    pipeline uses.

.NOTES
    File:           Modules/iSOCBlueprint/Engine/Report/Convert-MarkdownToWord.ps1
    Repository:     Sentinel-As-Code
    Author:         noodlemctwoodle
    Website:        https://sentinel.blog
    Created:        2026-06-25
    Version:        1.1.0
    Last Updated:   2026-11-13
    Requires:       PowerShell 7.6+, pandoc on PATH
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
    [string]$StripLinePattern = '(?m)^[ \t]*>.*\bWorkspace\b.*\bBlueprint\b.*\r?\n?',

    [Parameter(Mandatory = $false)]
    [switch]$NoReformatFindings
)

$ErrorActionPreference = 'Stop'

# The conversion and its steps (the module's own Private/Word, two folders up
# from here), defined in this scope.
$wordRoot = Join-Path $PSScriptRoot '..' '..' 'Private' 'Word'
foreach ($wordFile in Get-ChildItem -LiteralPath $wordRoot -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
    . $wordFile.FullName
}
Remove-Variable -Name wordFile, wordRoot -WhatIf:$false

Invoke-iSOCBlueprintWordConversion @PSBoundParameters -ReportRoot $PSScriptRoot
