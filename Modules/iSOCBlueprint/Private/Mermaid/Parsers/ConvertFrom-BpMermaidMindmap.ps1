#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertFrom-BpMermaidMindmap

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Parsers/ConvertFrom-BpMermaidMindmap.ps1
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

function ConvertFrom-BpMermaidMindmap {
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
