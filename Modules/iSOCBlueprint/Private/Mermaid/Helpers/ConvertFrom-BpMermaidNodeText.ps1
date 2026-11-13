#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertFrom-BpMermaidNodeText

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Helpers/ConvertFrom-BpMermaidNodeText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, Mermaid chart parsing
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function ConvertFrom-BpMermaidNodeText {
    # A mindmap or flowchart node: id((text)), id[text], (text), plain text.
    param([string] $Text)
    $t = $Text.Trim()
    if ($t -match '^(?<id>[^\[\(\{\)\>"\s]*)\s*(?<open>\(\(\(|\(\(|\[\[|\[\(|\(\[|\{\{|\)\)|\[\/|\[\\|\[|\(|\{|\)|>)(?<text>.*?)(?:\)\)\)|\)\)|\]\]|\)\]|\]\)|\}\}|\(\(|\/\]|\\\]|\]|\)|\}|\()$') {
        return @{ id = $Matches['id']; text = ConvertTo-BpMermaidText $Matches['text']; shape = $Matches['open'] }
    }
    return @{ id = $null; text = ConvertTo-BpMermaidText $t; shape = $null }
}
