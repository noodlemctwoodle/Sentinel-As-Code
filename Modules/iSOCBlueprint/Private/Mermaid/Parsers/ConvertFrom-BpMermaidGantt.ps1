#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertFrom-BpMermaidGantt

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Parsers/ConvertFrom-BpMermaidGantt.ps1
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

function ConvertFrom-BpMermaidGantt {
    param([string[]] $Body)
    $title = $null; $dateFormat = $null; $axisFormat = $null
    $sections = [System.Collections.Generic.List[object]]::new()
    $current = $null
    foreach ($l in $Body) {
        $t = $l.Trim()
        if (-not $t) { continue }
        if ($t -match '^title\s+(.+)$') { $title = ConvertTo-BpMermaidText $Matches[1]; continue }
        if ($t -match '^dateFormat\s+(.+)$') { $dateFormat = $Matches[1].Trim(); continue }
        if ($t -match '^axisFormat\s+(.+)$') { $axisFormat = $Matches[1].Trim(); continue }
        if ($t -match '^(excludes|todayMarker|tickInterval|weekday|includes)\b') { continue }
        if ($t -match '^section\s+(.+)$') {
            $current = [ordered]@{ name = ConvertTo-BpMermaidText $Matches[1]; tasks = @() }
            $sections.Add($current)
            continue
        }
        if ($t -notmatch '^(?<label>[^:]+?)\s*:\s*(?<meta>.*)$') { continue }
        if (-not $current) { $current = [ordered]@{ name = $null; tasks = @() }; $sections.Add($current) }
        $tokens = @($Matches['meta'] -split '\s*,\s*' | Where-Object { $_ -ne '' })
        $tags = @($tokens | Where-Object { $_ -in 'done', 'active', 'crit', 'milestone' })
        $rest = @($tokens | Where-Object { $_ -notin 'done', 'active', 'crit', 'milestone' })
        $task = [ordered]@{ label = ConvertTo-BpMermaidText $Matches['label']; tags = $tags; id = $null; start = $null; length = $null }
        switch ($rest.Count) {
            { $_ -ge 3 } { $task.id = $rest[0]; $task.start = $rest[1]; $task.length = $rest[2] }
            2 { $task.start = $rest[0]; $task.length = $rest[1] }
            1 { $task.length = $rest[0] }
        }
        $current.tasks += $task
    }
    return [ordered]@{
        kind  = 'gantt'
        title = $title
        data  = [ordered]@{ dateFormat = $dateFormat; axisFormat = $axisFormat; sections = $sections.ToArray() }
    }
}
