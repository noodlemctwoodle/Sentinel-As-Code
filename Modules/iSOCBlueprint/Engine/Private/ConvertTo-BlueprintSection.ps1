#Requires -Version 7.6

<#
.SYNOPSIS
    Loads the Markdown-to-section-model converter.

.DESCRIPTION
    Dot-source this file to define ConvertTo-BlueprintSection and the
    functions it calls. They live one per file under
    Modules/iSOCBlueprint/Private/Section:

      ConvertTo-BlueprintSection.ps1   the entry point, with the description
                                       of the section model it returns
      Parsing/   the Markdig token walk, the table chunking and the
                 table block
      Inline/    text runs, links, anchors and heading slugs
      Data/      the schema version, the table chunk size and the comment
                 markers the converter reads

    The converter calls ConvertFrom-BlueprintMermaid for Mermaid fences, so
    load that file as well.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/ConvertTo-BlueprintSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.6.0
    Last Updated: 2026-11-13
    Requires:     PowerShell 7.6+, ConvertFrom-BlueprintMermaid.ps1

    This file loads functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# The converter functions (the module's own Private/Section, two folders up
# from here), defined in the caller's scope.
$sectionRoot = Join-Path $PSScriptRoot '..' '..' 'Private' 'Section'
foreach ($sectionFile in Get-ChildItem -LiteralPath $sectionRoot -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
    . $sectionFile.FullName
}
Remove-Variable -Name sectionFile, sectionRoot -WhatIf:$false
