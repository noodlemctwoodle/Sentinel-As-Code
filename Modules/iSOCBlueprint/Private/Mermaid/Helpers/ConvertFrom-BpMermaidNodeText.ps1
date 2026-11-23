#Requires -Version 7.6

<#
.SYNOPSIS
    Read one Mermaid mindmap or flowchart node into its id, text and shape.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Helpers/ConvertFrom-BpMermaidNodeText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Mermaid chart parsing
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertFrom-BpMermaidNodeText {
    <#
    .SYNOPSIS
        Read one Mermaid mindmap or flowchart node into its id, text and shape.

    .DESCRIPTION
        Recognises id((text)), id[text], (text) and the other bracketed
        forms, and plain text. For a bracketed node, id is what precedes the
        opening bracket (empty when nothing does), text is what the brackets
        hold and shape is the opening bracket. For plain text, id and shape
        are $null. Text goes through ConvertTo-BpMermaidText.

    .PARAMETER Text
        The node text: one mindmap line, or one end of a flowchart edge.

    .OUTPUTS
        [hashtable] with id, text and shape.
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param([string] $Text)
    $t = $Text.Trim()
    if ($t -match
        '^(?<id>[^\[\(\{\)\>"\s]*)\s*(?<open>\(\(\(|\(\(|\[\[|\[\(|\(\[|\{\{|\)\)|\[\/|\[\\|\[|\(|\{|\)|>)(?<text>.*?)(?:\)\)\)|\)\)|\]\]|\)\]|\]\)|\}\}|\(\(|\/\]|\\\]|\]|\)|\}|\()$') {
        return @{ id = $Matches['id']; text = ConvertTo-BpMermaidText $Matches['text']; shape = $Matches['open'] }
    }
    return @{ id = $null; text = ConvertTo-BpMermaidText $t; shape = $null }
}
