#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertFrom-BpMermaidClass

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Parsers/ConvertFrom-BpMermaidClass.ps1
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

function ConvertFrom-BpMermaidClass {
    param([string[]] $Body)
    $classes = [ordered]@{}
    $relations = [System.Collections.Generic.List[object]]::new()
    $notes = [System.Collections.Generic.List[object]]::new()
    $open = $null
    foreach ($l in $Body) {
        $t = $l.Trim()
        if ($open) {
            if ($t -eq '}') { $open = $null } elseif ($t) { $classes[$open].members += $t }
            continue
        }
        if (-not $t) { continue }
        if ($t -match '^class\s+(?<name>\S+?)\s*(?<brace>\{)?\s*$') {
            if (-not $classes.Contains($Matches['name'])) { $classes[$Matches['name']] = [ordered]@{ name = $Matches['name']; members = @() } }
            if ($Matches['brace']) { $open = $Matches['name'] }
            continue
        }
        if ($t -match '^note\s+for\s+(?<for>\S+)\s+"(?<text>[^"]*)"') { $notes.Add([ordered]@{ for = $Matches['for']; text = ConvertTo-BpMermaidText $Matches['text'] }); continue }
        if ($t -match '^note\s+"(?<text>[^"]*)"') { $notes.Add([ordered]@{ for = $null; text = ConvertTo-BpMermaidText $Matches['text'] }); continue }
        if ($t -match '^(?<from>\S+)\s*(?<kind><\|--|--\|>|\*--|--\*|o--|--o|<--|-->|\.\.\|>|<\|\.\.|\.\.>|<\.\.|--|\.\.)\s*(?<to>[^:\s]+)(?:\s*:\s*(?<label>.*))?$') {
            $relations.Add([ordered]@{ from = $Matches['from']; to = $Matches['to']; kind = $Matches['kind']; label = $(if ($Matches['label']) { $Matches['label'].Trim() } else { $null }) })
        }
    }
    return [ordered]@{
        kind  = 'class'
        title = $null
        data  = [ordered]@{ classes = @($classes.Values); relations = $relations.ToArray(); notes = $notes.ToArray() }
    }
}
