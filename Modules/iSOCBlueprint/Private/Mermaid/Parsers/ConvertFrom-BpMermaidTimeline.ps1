#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertFrom-BpMermaidTimeline

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Parsers/ConvertFrom-BpMermaidTimeline.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Mermaid chart parsing
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertFrom-BpMermaidTimeline {
    param([string[]] $Body)
    $title = $null
    $section = $null
    $periods = [System.Collections.Generic.List[object]]::new()
    foreach ($l in $Body) {
        $t = $l.Trim()
        if (-not $t) { continue }
        if ($t -match '^title\s+(.+)$') { $title = ConvertTo-BpMermaidText $Matches[1]; continue }
        if ($t -match '^section\s+(.+)$') { $section = ConvertTo-BpMermaidText $Matches[1]; continue }
        $parts = @($t -split '\s+:\s+|^:\s*' | Where-Object { $_ -ne '' })
        if ($t.StartsWith(':')) {
            if ($periods.Count) { foreach ($p in $parts) { $periods[$periods.Count - 1].events += (ConvertTo-BpMermaidText $p) } }
            continue
        }
        $periods.Add([ordered]@{
                label   = ConvertTo-BpMermaidText $parts[0]
                section = $section
                events  = @($parts | Select-Object -Skip 1 | ForEach-Object { ConvertTo-BpMermaidText $_ })
            })
    }
    return [ordered]@{ kind = 'timeline'; title = $title; data = [ordered]@{ periods = $periods.ToArray() } }
}
