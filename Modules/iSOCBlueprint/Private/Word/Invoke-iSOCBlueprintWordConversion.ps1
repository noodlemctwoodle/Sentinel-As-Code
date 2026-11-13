#Requires -Version 7.6

<#
.SYNOPSIS
    Combine a folder of Markdown files into one formatted Word document.

.DESCRIPTION
    Entry point of the Word conversion. Runs the steps under Steps/ in order:
    check pandoc and resolve the paths, collect and order the Markdown, write
    cleaned copies, run pandoc (and LibreOffice for the table of contents page
    numbers), then report. The steps share their values through a context
    hashtable. A step that cannot go on logs why and exits, as the script
    always did; a -WhatIf run stops after listing what it would write.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Word/Invoke-iSOCBlueprintWordConversion.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, Word report
    Requires:     PowerShell 7.6+, pandoc on PATH

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>


function Invoke-iSOCBlueprintWordConversion {
    <#
    .SYNOPSIS
        Combine a folder of Markdown files into a single, formatted Word
        document with pandoc.

    .DESCRIPTION
        The parameters are those of Engine/Report/Convert-MarkdownToWord.ps1,
        whose help describes the ordering, the cleaning and the table of
        contents modes.

    .PARAMETER Source
        The folder of Markdown files.

    .PARAMETER OutputPath
        The .docx to write. Defaults to <Source>.docx beside the folder.

    .PARAMETER Title
        Document title. Defaults to the folder name.

    .PARAMETER ReferenceDoc
        A pandoc reference document for the styles.

    .PARAMETER NoReferenceDoc
        Ignore the bundled reference document.

    .PARAMETER Toc
        Baked, Field or Styled.

    .PARAMETER TocDepth
        Heading levels in the table of contents.

    .PARAMETER FrontFile
        File names to float to the top, in this order.

    .PARAMETER ExcludeFile
        File names at the source root to leave out.

    .PARAMETER StripLinePattern
        Regex for the provenance line removed from every file after the first.

    .PARAMETER NoReformatFindings
        Leave finding bullets and status words as they are.

    .PARAMETER ReportRoot
        The Engine/Report folder, which holds the templates and the LibreOffice helper.
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
    [switch]$NoReformatFindings,

        [Parameter(Mandatory = $true)]
        [string]$ReportRoot
    )

    $ErrorActionPreference = 'Stop'

    $script:WordReportRoot = $ReportRoot

    $context = @{
        Source             = $Source
        OutputPath         = $OutputPath
        Title              = $Title
        ReferenceDoc       = $ReferenceDoc
        NoReferenceDoc     = $NoReferenceDoc
        Toc                = $Toc
        TocDepth           = $TocDepth
        FrontFile          = $FrontFile
        ExcludeFile        = $ExcludeFile
        StripLinePattern   = $StripLinePattern
        NoReformatFindings = $NoReformatFindings
        reportRoot         = $ReportRoot
        stop               = $false
    }

    $steps = @(
        'Resolve-WordSource'
        'Get-WordMarkdown'
        'Build-WordInput'
        'Invoke-WordPandoc'
        'Write-WordSummary'
    )
    foreach ($step in $steps) {
        & $step -Context $context
        if ($context.stop) { break }
    }
}
