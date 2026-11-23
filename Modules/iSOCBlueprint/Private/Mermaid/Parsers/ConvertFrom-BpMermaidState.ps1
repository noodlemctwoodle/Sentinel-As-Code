#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertFrom-BpMermaidState

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Parsers/ConvertFrom-BpMermaidState.ps1
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

function ConvertFrom-BpMermaidState {
    param([string[]] $Body)
    $transitions = [System.Collections.Generic.List[object]]::new()
    $notes = [System.Collections.Generic.List[object]]::new()
    $states = [ordered]@{}
    $parents = [System.Collections.Generic.List[string]]::new()
    $note = $null
    foreach ($l in $Body) {
        $t = $l.Trim()
        if ($note) {
            if ($t -eq 'end note') { $notes.Add($note); $note = $null } else { $note.text = (@($note.text, $t) | Where-Object { $_ }) -join "`n" }
            continue
        }
        if (-not $t) { continue }
        $parent = if ($parents.Count) { $parents[$parents.Count - 1] } else { $null }
        if ($t -match '^note\s+(?<pos>right|left)\s+of\s+(?<state>[^:]+?)(?:\s*:\s*(?<text>.*))?$') {
            $n = [ordered]@{ state = $Matches['state'].Trim(); position = $Matches['pos']; text = $(if ($Matches['text']) { ConvertTo-BpMermaidText $Matches['text'] } else { '' }) }
            if ($Matches['text']) { $notes.Add($n) } else { $note = $n }
            continue
        }
        if ($t -match '^state\s+"(?<label>[^"]*)"\s+as\s+(?<id>\S+)') { $states[$Matches['id']] = [ordered]@{ id = $Matches['id']; label = $Matches['label']; parent = $parent }; continue }
        if ($t -match '^state\s+(?<id>\S+)\s*\{\s*$') {
            if (-not $states.Contains($Matches['id'])) { $states[$Matches['id']] = [ordered]@{ id = $Matches['id']; label = $Matches['id']; parent = $parent } }
            $parents.Add($Matches['id']); continue
        }
        if ($t -eq '}') { if ($parents.Count) { $parents.RemoveAt($parents.Count - 1) }; continue }
        if ($t -match '^(?<from>\S+)\s*-->\s*(?<to>[^:\s]+)(?:\s*:\s*(?<label>.*))?$') {
            foreach ($s in $Matches['from'], $Matches['to']) {
                if ($s -ne '[*]' -and -not $states.Contains($s)) { $states[$s] = [ordered]@{ id = $s; label = $s; parent = $parent } }
            }
            $transitions.Add([ordered]@{
                    from = $Matches['from']; to = $Matches['to']; parent = $parent
                    label = $(if ($Matches['label']) { ConvertTo-BpMermaidText $Matches['label'] } else { $null })
                })
        }
    }
    return [ordered]@{
        kind  = 'state'
        title = $null
        data  = [ordered]@{ states = @($states.Values); transitions = $transitions.ToArray(); notes = $notes.ToArray() }
    }
}
