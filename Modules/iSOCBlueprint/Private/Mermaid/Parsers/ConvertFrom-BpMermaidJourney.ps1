#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertFrom-BpMermaidJourney

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Parsers/ConvertFrom-BpMermaidJourney.ps1
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

function ConvertFrom-BpMermaidJourney {
    param([string[]] $Body)
    $title = $null
    $sections = [System.Collections.Generic.List[object]]::new()
    $current = $null
    foreach ($l in $Body) {
        $t = $l.Trim()
        if (-not $t) { continue }
        if ($t -match '^title\s+(.+)$') { $title = ConvertTo-BpMermaidText $Matches[1]; continue }
        if ($t -match '^section\s+(.+)$') {
            $current = [ordered]@{ name = ConvertTo-BpMermaidText $Matches[1]; tasks = @() }
            $sections.Add($current)
            continue
        }
        if ($t -match '^(?<label>[^:]+?)\s*:\s*(?<score>\d+)\s*(?::\s*(?<actors>.*))?$') {
            if (-not $current) { $current = [ordered]@{ name = $null; tasks = @() }; $sections.Add($current) }
            $current.tasks += [ordered]@{
                label  = ConvertTo-BpMermaidText $Matches['label']
                score  = [int]$Matches['score']
                actors = @(if ($Matches['actors']) { $Matches['actors'] -split '\s*,\s*' | Where-Object { $_ } })
            }
        }
    }
    return [ordered]@{ kind = 'journey'; title = $title; data = [ordered]@{ sections = $sections.ToArray() } }
}
