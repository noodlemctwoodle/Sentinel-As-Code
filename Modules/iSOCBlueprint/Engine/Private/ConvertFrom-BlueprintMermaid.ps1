#Requires -Version 7.6

<#
.SYNOPSIS
    Loads the Mermaid chart parser.

.DESCRIPTION
    Dot-source this file to define ConvertFrom-BlueprintMermaid and the
    parsers it calls. They live one per file under
    Modules/iSOCBlueprint/Private/Mermaid:

      ConvertFrom-BlueprintMermaid.ps1   the entry point, with the description
                                         of what it reads and returns
      Parsers/   one parser per Mermaid diagram type
      Helpers/   text and number reading shared by the parsers

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/ConvertFrom-BlueprintMermaid.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.3.0
    Last Updated: 2026-11-13
    Requires:     PowerShell 7.6+

    This file loads functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# The parser functions (the module's own Private/Mermaid, two folders up from
# here), defined in the caller's scope.
$mermaidRoot = Join-Path $PSScriptRoot '..' '..' 'Private' 'Mermaid'
foreach ($mermaidFile in Get-ChildItem -LiteralPath $mermaidRoot -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
    . $mermaidFile.FullName
}
Remove-Variable -Name mermaidFile, mermaidRoot -WhatIf:$false
