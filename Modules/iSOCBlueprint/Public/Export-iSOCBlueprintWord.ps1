#Requires -Version 7.2

<#
.SYNOPSIS
    Export-iSOCBlueprintWord: turn the Markdown report into one Word
    document.

.DESCRIPTION
    Runs Engine/Report/Convert-MarkdownToWord.ps1.

.NOTES
    File:         Modules/iSOCBlueprint/Public/Export-iSOCBlueprintWord.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+

    Needs pandoc on PATH; LibreOffice with python3-uno adds page numbers to
    the contents. See Test-iSOCBlueprintPrerequisite -Step Word.

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Export-iSOCBlueprintWord {
    <#
    .SYNOPSIS
        Combine the Markdown report into one formatted Word (.docx)
        document.

    .DESCRIPTION
        Collects the Markdown pages in the workspace folder, in order, and
        converts them with pandoc using the bundled house style (formatted
        tables, headings, finding cards). By default the contents is a real
        Word table of contents with page numbers, filled in by LibreOffice
        so the document opens without an "update fields" prompt; without
        LibreOffice it falls back to a clickable contents list.

        Charts appear only once they are images: run
        ConvertTo-iSOCBlueprintChartImage first, because pandoc drops
        Mermaid fences.

    .PARAMETER Path
        The workspace folder holding the Markdown report.

    .PARAMETER OutputPath
        The .docx to write. Defaults to <workspace>.docx beside the
        workspace folder.

    .PARAMETER Title
        Document title above the contents. Defaults to the workspace folder
        name.

    .PARAMETER ReferenceDoc
        A pandoc reference .docx with your own styles. Defaults to the
        bundled one.

    .PARAMETER NoReferenceDoc
        Use pandoc's plain styles instead of the bundled reference.

    .PARAMETER Toc
        Contents style: Baked (the default; page numbers filled in by
        LibreOffice, falling back to Styled without it), Field (a Word
        field that Word fills in on open) or Styled (a clickable list, no
        page numbers).

    .PARAMETER TocDepth
        Deepest heading level in the contents. Defaults to 2.

    .PARAMETER FrontFile
        File names placed first, ahead of the page order. Defaults to
        README.md.

    .PARAMETER ExcludeFile
        File names left out. Defaults to index.md, whose link table repeats
        the contents.

    .PARAMETER StripLinePattern
        Regular expression for lines removed from every page. Defaults to
        the provenance line repeated at the top of each page; pass an empty
        string to keep everything.

    .PARAMETER NoReformatFindings
        Leave the finding bullets as written instead of laying each one out
        as a card.

    .OUTPUTS
        [System.IO.FileInfo] The Word document, unless -WhatIf.

    .EXAMPLE
        Export-iSOCBlueprintWord -Path ./SecurityDocs/law-sentinel-prod

        Writes ./SecurityDocs/law-sentinel-prod.docx.

    .EXAMPLE
        ConvertTo-iSOCBlueprint -WorkspaceName law-sentinel-prod -Format Markdown |
            Export-iSOCBlueprintWord -Title 'law-sentinel-prod - iSOC Blueprint'

        Renders the Markdown and converts it in one line.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The engine script makes the ShouldProcess calls; -WhatIf and -Confirm are passed on to it.')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Source')]
        [string] $Path,

        [string] $OutputPath,

        [string] $Title,

        [string] $ReferenceDoc,

        [switch] $NoReferenceDoc,

        [ValidateSet('Baked', 'Field', 'Styled')]
        [string] $Toc,

        [int] $TocDepth,

        [string[]] $FrontFile,

        [string[]] $ExcludeFile,

        [AllowEmptyString()]
        [string] $StripLinePattern,

        [switch] $NoReformatFindings
    )

    process {
        $source = Resolve-iSOCBlueprintPath -Path $Path
        $default = Join-Path (Split-Path -Parent $source) ((Split-Path -Leaf $source) + '.docx')
        $document = Resolve-iSOCBlueprintPath -Path $OutputPath -Default $default
        $params = @{ Source = $source; OutputPath = $document }
        Copy-iSOCBlueprintParameter -BoundParameters $PSBoundParameters -Into $params -Name 'Title', 'Toc', 'TocDepth', 'FrontFile', 'ExcludeFile', 'StripLinePattern'
        if ($ReferenceDoc) { $params.ReferenceDoc = Resolve-iSOCBlueprintPath -Path $ReferenceDoc }
        if ($NoReferenceDoc) { $params.NoReferenceDoc = $true }
        if ($NoReformatFindings) { $params.NoReformatFindings = $true }

        $null = Invoke-iSOCBlueprintEngine -Script 'Report/Convert-MarkdownToWord.ps1' -Parameters $params -BoundParameters $PSBoundParameters

        if (-not $WhatIfPreference -and (Test-Path -LiteralPath $document -PathType Leaf)) { Get-Item -LiteralPath $document }
    }
}
