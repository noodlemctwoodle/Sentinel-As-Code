#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertFrom-BpMermaidSequence

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Parsers/ConvertFrom-BpMermaidSequence.ps1
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

function ConvertFrom-BpMermaidSequence {
    param([string[]] $Body)
    $participants = [ordered]@{}
    $steps = [System.Collections.Generic.List[object]]::new()
    $autonumber = $false
    $add = { param($id) if ($id -and -not $participants.Contains($id)) { $participants[$id] = [ordered]@{ id = $id; label = $id; kind = 'participant' } } }
    foreach ($l in $Body) {
        $t = $l.Trim()
        if (-not $t) { continue }
        if ($t -eq 'autonumber') { $autonumber = $true; continue }
        if ($t -match '^(?<kind>participant|actor)\s+(?<id>\S+)(?:\s+as\s+(?<label>.+))?$') {
            $participants[$Matches['id']] = [ordered]@{ id = $Matches['id']; label = $(if ($Matches['label']) { $Matches['label'].Trim() } else { $Matches['id'] }); kind = $Matches['kind'] }
            continue
        }
        if ($t -match '^Note\s+(?<pos>over|left of|right of)\s+(?<who>[^:]+):\s*(?<text>.*)$') {
            $steps.Add([ordered]@{ kind = 'note'; position = $Matches['pos']; over = @($Matches['who'] -split '\s*,\s*'); text = ConvertTo-BpMermaidText $Matches['text'] })
            continue
        }
        if ($t -match '^(?<block>loop|alt|else|opt|par|and|critical|break|rect)\b\s*(?<text>.*)$') {
            $steps.Add([ordered]@{ kind = 'block'; block = $Matches['block']; text = $Matches['text'] })
            continue
        }
        if ($t -eq 'end') { $steps.Add([ordered]@{ kind = 'end' }); continue }
        if ($t -match '^(?<from>[^-+<>:\s][^-<>:]*?)\s*(?<arrow>-{1,2}>>|-{1,2}>|-{1,2}x|-{1,2}\))\s*[+-]?(?<to>[^:]+?)\s*:\s*(?<text>.*)$') {
            & $add $Matches['from']; & $add $Matches['to']
            $steps.Add([ordered]@{
                    kind = 'message'; from = $Matches['from']; to = $Matches['to']
                    text = ConvertTo-BpMermaidText $Matches['text']; dashed = [bool]($Matches['arrow'] -like '--*')
                })
        }
    }
    return [ordered]@{
        kind  = 'sequence'
        title = $null
        data  = [ordered]@{ autonumber = $autonumber; participants = @($participants.Values); steps = $steps.ToArray() }
    }
}
