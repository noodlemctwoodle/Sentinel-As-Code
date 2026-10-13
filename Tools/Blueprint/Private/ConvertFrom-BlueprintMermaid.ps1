#Requires -Version 7.2

<#
.SYNOPSIS
    Turn the Mermaid source of a Blueprint chart into chart data for the
    section model.

.DESCRIPTION
    The renderer writes its charts as Mermaid. The section model carries
    each chart as data instead, so a consumer (the SharePoint chart web
    part, or anyone reading sections/*.json) can draw it without Mermaid.
    This parser covers the Mermaid the renderer emits: pie, sankey-beta,
    xychart-beta, timeline, gantt, mindmap, flowchart/graph,
    sequenceDiagram, stateDiagram-v2, classDiagram and journey. Anything else comes
    back as kind 'other' with no data; the source is always kept, so
    nothing is lost.

    Labels keep the line breaks the renderer writes as <br/>, as "`n".

.NOTES
    File:         Tools/Blueprint/Private/ConvertFrom-BlueprintMermaid.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function ConvertFrom-BlueprintMermaid {
    <#
    .SYNOPSIS
        Parse one Mermaid chart into [ordered] @{ kind; title; data }.

    .PARAMETER Source
        The Mermaid source, without the code fence.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] kind is one of
        pie, sankey, xy, timeline, gantt, mindmap, flowchart, sequence,
        state, class, journey, other. title is $null when the chart has none.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Source)

    $lines = [System.Collections.Generic.List[string]]::new()
    $all = $Source -split "\r?\n"
    $i = 0
    # Front matter (---\nconfig...\n---) carries only presentation settings.
    while ($i -lt $all.Count -and [string]::IsNullOrWhiteSpace($all[$i])) { $i++ }
    if ($i -lt $all.Count -and $all[$i].Trim() -eq '---') {
        $i++
        while ($i -lt $all.Count -and $all[$i].Trim() -ne '---') { $i++ }
        $i++
    }
    for (; $i -lt $all.Count; $i++) {
        if ($all[$i].Trim().StartsWith('%%')) { continue }
        $lines.Add($all[$i])
    }
    while ($lines.Count -and [string]::IsNullOrWhiteSpace($lines[0])) { $lines.RemoveAt(0) }
    if ($lines.Count -eq 0) { return [ordered]@{ kind = 'other'; title = $null; data = $null } }

    $header = $lines[0].Trim()
    $body = @($lines | Select-Object -Skip 1)
    $keyword = ($header -split '\s+')[0]
    switch -Regex ($keyword) {
        '^pie$'              { return (ConvertFrom-BpMermaidPie -Header $header -Body $body) }
        '^sankey(-beta)?$'   { return (ConvertFrom-BpMermaidSankey -Body $body) }
        '^xychart(-beta)?$'  { return (ConvertFrom-BpMermaidXy -Body $body) }
        '^timeline$'         { return (ConvertFrom-BpMermaidTimeline -Body $body) }
        '^gantt$'            { return (ConvertFrom-BpMermaidGantt -Body $body) }
        '^mindmap$'          { return (ConvertFrom-BpMermaidMindmap -Body $body) }
        '^(flowchart|graph)$' { return (ConvertFrom-BpMermaidFlowchart -Header $header -Body $body) }
        '^sequenceDiagram$'  { return (ConvertFrom-BpMermaidSequence -Body $body) }
        '^stateDiagram(-v2)?$' { return (ConvertFrom-BpMermaidState -Body $body) }
        '^classDiagram$'     { return (ConvertFrom-BpMermaidClass -Body $body) }
        '^journey$'          { return (ConvertFrom-BpMermaidJourney -Body $body) }
    }
    return [ordered]@{ kind = 'other'; title = $null; data = $null }
}

function ConvertTo-BpMermaidText {
    # Mermaid label text: drop wrapping quotes, turn <br/> into a newline.
    param([AllowEmptyString()] [AllowNull()] [string] $Text)
    if ($null -eq $Text) { return $null }
    $t = $Text.Trim()
    if ($t.Length -ge 2 -and $t.StartsWith('"') -and $t.EndsWith('"')) { $t = $t.Substring(1, $t.Length - 2) }
    return ($t -replace '<br\s*/?>', "`n")
}

function ConvertTo-BpNumber {
    param([string] $Text)
    $n = 0.0
    if ([double]::TryParse($Text.Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { return $n }
    return $null
}

function ConvertFrom-BpMermaidList {
    # "[a, "b c", 3]" -> @('a', 'b c', '3')
    param([string] $Text)
    $inner = $Text.Trim().TrimStart('[').TrimEnd(']')
    return @([regex]::Matches($inner, '"([^"]*)"|([^,\s][^,]*)') | ForEach-Object {
            if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value.Trim() }
        })
}

function ConvertFrom-BpMermaidPie {
    param([string] $Header, [string[]] $Body)
    $title = if ($Header -match '\btitle\s+(.+)$') { $Matches[1].Trim() } else { $null }
    $slices = foreach ($l in $Body) {
        if ($l -match '^\s*"(?<label>(?:[^"]|"")*)"\s*:\s*(?<value>[-+0-9.eE]+)\s*$') {
            [ordered]@{ label = $Matches['label']; value = (ConvertTo-BpNumber $Matches['value']) }
        }
        elseif ($l -match '^\s*title\s+(.+)$') { $title = $Matches[1].Trim() }
    }
    return [ordered]@{
        kind  = 'pie'
        title = $title
        data  = [ordered]@{ showData = [bool]($Header -match '\bshowData\b'); slices = @($slices) }
    }
}

function ConvertFrom-BpMermaidSankey {
    param([string[]] $Body)
    $links = foreach ($l in $Body) {
        $t = $l.Trim()
        if (-not $t) { continue }
        $fields = @([regex]::Matches($t, '"((?:[^"]|"")*)"|([^,]+)') | ForEach-Object {
                if ($_.Groups[1].Success) { $_.Groups[1].Value.Replace('""', '"') } else { $_.Groups[2].Value.Trim() }
            })
        if ($fields.Count -ne 3) { continue }
        $v = ConvertTo-BpNumber $fields[2]
        if ($null -eq $v) { continue }
        [ordered]@{ source = $fields[0]; target = $fields[1]; value = $v }
    }
    return [ordered]@{ kind = 'sankey'; title = $null; data = [ordered]@{ links = @($links) } }
}

function ConvertFrom-BpMermaidXy {
    param([string[]] $Body)
    $title = $null
    $x = [ordered]@{ title = $null; labels = @() }
    $y = [ordered]@{ title = $null; min = $null; max = $null }
    $series = [System.Collections.Generic.List[object]]::new()
    foreach ($l in $Body) {
        $t = $l.Trim()
        if ($t -match '^title\s+(.+)$') { $title = ConvertTo-BpMermaidText $Matches[1] }
        elseif ($t -match '^x-axis\s+(?:(?<title>"[^"]*"|[^\[\s]+)\s*)?(?<rest>.*)$') {
            if ($Matches['title']) { $x.title = ConvertTo-BpMermaidText $Matches['title'] }
            $rest = $Matches['rest'].Trim()
            if ($rest.StartsWith('[')) { $x.labels = @(ConvertFrom-BpMermaidList $rest) }
        }
        elseif ($t -match '^y-axis\s+(?:(?<title>"[^"]*"|[^\d\s"-][^\s]*)\s*)?(?:(?<min>[-+0-9.]+)\s*-->\s*(?<max>[-+0-9.]+))?\s*$') {
            if ($Matches['title']) { $y.title = ConvertTo-BpMermaidText $Matches['title'] }
            if ($Matches['min']) { $y.min = ConvertTo-BpNumber $Matches['min']; $y.max = ConvertTo-BpNumber $Matches['max'] }
        }
        elseif ($t -match '^(?<kind>bar|line)\s+(?:(?<name>"[^"]*"|[^\[\s]+)\s+)?(?<values>\[.*\])\s*$') {
            $series.Add([ordered]@{
                    kind   = $Matches['kind']
                    name   = $(if ($Matches['name']) { ConvertTo-BpMermaidText $Matches['name'] } else { $null })
                    values = @(ConvertFrom-BpMermaidList $Matches['values'] | ForEach-Object { ConvertTo-BpNumber $_ })
                })
        }
    }
    return [ordered]@{ kind = 'xy'; title = $title; data = [ordered]@{ xAxis = $x; yAxis = $y; series = $series.ToArray() } }
}

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

function ConvertFrom-BpMermaidNodeText {
    # A mindmap or flowchart node: id((text)), id[text], (text), plain text.
    param([string] $Text)
    $t = $Text.Trim()
    if ($t -match '^(?<id>[^\[\(\{\)\>"\s]*)\s*(?<open>\(\(\(|\(\(|\[\[|\[\(|\(\[|\{\{|\)\)|\[\/|\[\\|\[|\(|\{|\)|>)(?<text>.*?)(?:\)\)\)|\)\)|\]\]|\)\]|\]\)|\}\}|\(\(|\/\]|\\\]|\]|\)|\}|\()$') {
        return @{ id = $Matches['id']; text = ConvertTo-BpMermaidText $Matches['text']; shape = $Matches['open'] }
    }
    return @{ id = $null; text = ConvertTo-BpMermaidText $t; shape = $null }
}

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
