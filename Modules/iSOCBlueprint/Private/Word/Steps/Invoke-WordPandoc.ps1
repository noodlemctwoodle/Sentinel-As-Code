#Requires -Version 7.6

<#
.SYNOPSIS
    Settle the table of contents mode and run pandoc, baking page numbers when asked.

.DESCRIPTION
    A step of the Word report conversion. Steps run in order and pass their results
    to later ones through the conversion context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Word/Steps/Invoke-WordPandoc.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Word report
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-WordPandoc {
    <#
    .SYNOPSIS
        Settle the table of contents mode and run pandoc, baking page numbers when asked.

    .PARAMETER Context
        The conversion context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the conversion context.
    $inputPaths = $Context.inputPaths
    $OutputPath = $Context.OutputPath
    $ReferenceDoc = $Context.ReferenceDoc
    $resourcePath = $Context.resourcePath
    $Title = $Context.Title
    $Toc = $Context.Toc
    $TocDepth = $Context.TocDepth
    $work = $Context.work

    $reader = 'gfm+fenced_divs+bracketed_spans+raw_attribute'

    # Resolve the TOC strategy. 'Baked' needs LibreOffice + python3-uno to
    # compute page numbers (present on the Ubuntu CI agent); without them, fall
    # back to the always-populated static contents.
    $soffice = $null
    if ($Toc -eq 'Baked') {
        $soffice = Get-SofficePath
        if (-not ($soffice -and (Test-UnoAvailable))) {
            Write-WordLog '  LibreOffice + python3-uno not both available - using -Toc Styled (no page numbers).' -Level Warning
            $Toc = 'Styled'
        }
    }
    $tocDesc = $Toc
    if ($Toc -eq 'Baked' -and $soffice) { $tocDesc += " (page numbers via $(Split-Path $soffice -Leaf))" }
    Write-WordLog "  TOC:       $tocDesc"

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
        Write-WordLog 'Running pandoc (contents pass)...' -Level Info
        $passAOut = & pandoc @passA 2>&1
        if ($LASTEXITCODE -ne 0) {
            foreach ($line in $passAOut) { Write-WordLog "  $line" -Level Error }
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
            throw 'pandoc contents pass failed.'
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

        Write-WordLog 'Running pandoc (docx pass)...' -Level Info
        $pandocOut = & pandoc @passB 2>&1
        $exit = $LASTEXITCODE
    } else {
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
        Write-WordLog 'Running pandoc (TOC field)...' -Level Info
        $pandocOut = & pandoc @tocArgs 2>&1
        $exit = $LASTEXITCODE

        if ($exit -eq 0 -and $Toc -eq 'Baked') {
            Write-WordLog 'Baking TOC page numbers via LibreOffice...' -Level Info
            if (-not (Invoke-LibreOfficeBake -Soffice $soffice -DocxPath $OutputPath)) {
                Write-WordLog '  LibreOffice bake failed; TOC field is present but unpopulated (open in Word, Ctrl+A then F9).' -Level Warning
            }
        }
    }

    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

    # Left in the conversion context for later steps.
    if (Get-Variable -Name 'exit' -Scope 0 -ErrorAction Ignore) { $Context.exit = $exit }
    if (Get-Variable -Name 'pandocOut' -Scope 0 -ErrorAction Ignore) { $Context.pandocOut = $pandocOut }
}
