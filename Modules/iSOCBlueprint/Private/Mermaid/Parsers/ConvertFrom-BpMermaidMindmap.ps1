#Requires -Version 7.6

<#
.SYNOPSIS
    Parse the body of a Mermaid mindmap into a tree of nodes.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Parsers/ConvertFrom-BpMermaidMindmap.ps1
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

function ConvertFrom-BpMermaidMindmap {
    <#
    .SYNOPSIS
        Parse the body of a Mermaid mindmap into a tree of nodes.

    .DESCRIPTION
        A line is the child of the nearest earlier line indented less than
        it; the first line is the root. Blank lines and lines starting with
        :: are skipped.

    .PARAMETER Body
        The diagram's lines after its header line.

    .OUTPUTS
        [ordered] kind ('mindmap'), title ($null) and data: root, a node with
        text and children.
    #>
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [CmdletBinding()]
    param([string[]] $Body)
    $root = $null
    $stack = [System.Collections.Generic.List[object]]::new()
    foreach ($l in $Body) {
        if ([string]::IsNullOrWhiteSpace($l) -or $l.Trim().StartsWith('::')) { continue }
        $indent = $l.Length - $l.TrimStart().Length
        $node = [ordered]@{ text = (ConvertFrom-BpMermaidNodeText $l).text; children = @() }
        $entry = @{ indent = $indent; node = $node }
        while ($stack.Count -and $stack[$stack.Count - 1].indent -ge $indent) { $stack.RemoveAt($stack.Count - 1) }
        if ($stack.Count -eq 0) { if (-not $root) { $root = $node } }
        else { $stack[$stack.Count - 1].node.children += $node }
        $stack.Add($entry)
    }
    return [ordered]@{ kind = 'mindmap'; title = $null; data = [ordered]@{ root = $root } }
}
