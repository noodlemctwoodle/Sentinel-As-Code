#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertFrom-BpMermaidFlowchart

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Parsers/ConvertFrom-BpMermaidFlowchart.ps1
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

function ConvertFrom-BpMermaidFlowchart {
    param([string] $Header, [string[]] $Body)
    $direction = if ($Header -match '^(?:flowchart|graph)\s+(\w+)') { $Matches[1] } else { 'TB' }
    $groups = [System.Collections.Generic.List[object]]::new()
    $nodes = [ordered]@{}
    $edges = [System.Collections.Generic.List[object]]::new()
    $classDefs = @{}
    $groupStack = [System.Collections.Generic.List[string]]::new()

    $ensure = {
        param($token)
        $n = ConvertFrom-BpMermaidNodeText ($token -replace ':::[\w-]+$', '')
        $id = if ($n.id) { $n.id } else { $n.text }
        if (-not $id) { return $null }
        if (-not $nodes.Contains($id)) {
            $nodes[$id] = [ordered]@{
                id = $id; label = $id; group = $(if ($groupStack.Count) { $groupStack[$groupStack.Count - 1] } else { $null })
                class = $null; fill = $null; stroke = $null; color = $null; href = $null; tooltip = $null
            }
        }
        if ($n.id -and $n.text) { $nodes[$id].label = $n.text }
        if ($token -match ':::([\w-]+)$') { $nodes[$id].class = $Matches[1] }
        return $id
    }

    foreach ($l in $Body) {
        $t = $l.Trim()
        if (-not $t) { continue }
        if ($t -match '^subgraph\s+(?<id>[^\s\[]+)\s*(?:\[(?<label>.*)\])?\s*$') {
            $label = if ($Matches['label']) { ConvertTo-BpMermaidText $Matches['label'] } else { ConvertTo-BpMermaidText $Matches['id'] }
            $groups.Add([ordered]@{ id = $Matches['id']; label = $label; parent = $(if ($groupStack.Count) { $groupStack[$groupStack.Count - 1] } else { $null }) })
            $groupStack.Add($Matches['id'])
            continue
        }
        if ($t -eq 'end') { if ($groupStack.Count) { $groupStack.RemoveAt($groupStack.Count - 1) }; continue }
        if ($t -match '^(direction\s|linkStyle\s)') { continue }
        if ($t -match '^classDef\s+(?<name>\S+)\s+(?<props>.+)$') {
            $className = $Matches['name']
            $props = @{}
            foreach ($kv in $Matches['props'] -split ',') { if ($kv -match '^\s*([\w-]+)\s*:\s*(.+?)\s*;?$') { $props[$Matches[1]] = $Matches[2] } }
            $classDefs[$className] = $props
            continue
        }
        if ($t -match '^class\s+(?<ids>\S+)\s+(?<name>\S+)\s*$') {
            foreach ($id in $Matches['ids'] -split ',') { if ($nodes.Contains($id)) { $nodes[$id].class = $Matches['name'] } }
            continue
        }
        if ($t -match '^style\s+(?<id>\S+)\s+(?<props>.+)$') {
            $styled = $Matches['id']
            if ($nodes.Contains($styled)) {
                foreach ($kv in $Matches['props'] -split ',') { if ($kv -match '^\s*(fill|stroke|color)\s*:\s*(.+?)\s*$') { $nodes[$styled][$Matches[1]] = $Matches[2] } }
            }
            continue
        }
        if ($t -match '^click\s+(?<id>\S+)\s+(?:href\s+)?"(?<href>[^"]*)"(?:\s+"(?<tip>[^"]*)")?') {
            if ($nodes.Contains($Matches['id'])) { $nodes[$Matches['id']].href = $Matches['href']; $nodes[$Matches['id']].tooltip = $Matches['tip'] }
            continue
        }
        # Inline edge labels -> pipe form: "A -- x --> B", "A -. x .-> B", "A == x ==> B".
        $s = $t -replace '--\s+([^>|]+?)\s+-->', '-->|$1|' -replace '-\.\s+([^>|]+?)\s+\.->', '-.->|$1|' -replace '==\s+([^>|]+?)\s+==>', '==>|$1|'
        # Walk the edge operators by position: Regex.Split leaves out groups that
        # did not match, which would put an unlabelled edge out of step.
        $ops = @([regex]::Matches($s, '\s*(<-->|-\.->|-\.-|-->|---|==>|===|--x|--o)(?:\|([^|]*)\|)?\s*'))
        if ($ops.Count -eq 0) { [void](& $ensure $s); continue }
        $pos = 0
        $ids = foreach ($m in $ops) { & $ensure $s.Substring($pos, $m.Index - $pos); $pos = $m.Index + $m.Length }
        $ids = @($ids) + @(& $ensure $s.Substring($pos))
        for ($k = 0; $k -lt $ops.Count; $k++) {
            $op = $ops[$k].Groups[1].Value
            $label = if ($ops[$k].Groups[2].Success) { $ops[$k].Groups[2].Value } else { $null }
            if ($ids[$k] -and $ids[$k + 1]) {
                $edges.Add([ordered]@{
                        from  = $ids[$k]; to = $ids[$k + 1]
                        label = $(if ($label) { ConvertTo-BpMermaidText $label } else { $null })
                        style = $(if ($op -like '-.*') { 'dotted' } elseif ($op -like '=*') { 'thick' } else { 'solid' })
                        arrow = [bool]($op -match '>$')
                    })
            }
        }
    }
    foreach ($n in $nodes.Values) {
        if ($n.class -and $classDefs.ContainsKey($n.class)) {
            foreach ($p in 'fill', 'stroke', 'color') { if (-not $n[$p] -and $classDefs[$n.class].ContainsKey($p)) { $n[$p] = $classDefs[$n.class][$p] } }
        }
    }
    return [ordered]@{
        kind  = 'flowchart'
        title = $null
        data  = [ordered]@{ direction = $direction; groups = $groups.ToArray(); nodes = @($nodes.Values); edges = $edges.ToArray() }
    }
}
