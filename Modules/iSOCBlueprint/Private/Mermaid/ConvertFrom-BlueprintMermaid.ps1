#Requires -Version 7.6

<#
.SYNOPSIS
    Parse one Mermaid chart into [ordered] @{ kind; title; data }.

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

    A chart with a purpose-built graphic carries its data on a comment line,
    "%% visual <kind> <json>", which Mermaid ignores: the chart comes back
    as that kind with the JSON as its data (the incident lifecycle is
    kind incident-lifecycle). JSON that does not parse is ignored and the
    Mermaid is read as usual.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/ConvertFrom-BlueprintMermaid.ps1
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

function ConvertFrom-BlueprintMermaid {
    <#
    .SYNOPSIS
        Parse one Mermaid chart into [ordered] @{ kind; title; data }.

    .PARAMETER Source
        The Mermaid source, without the code fence.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] kind is one of
        pie, sankey, xy, timeline, gantt, mindmap, flowchart, sequence,
        state, class, journey, other, or a visual's kind (incident-lifecycle).
        title is $null when the chart has none.
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
    # A "%% x-labels [...]" comment carries the full axis labels of an xy
    # chart whose Mermaid labels are shortened to fit under the bars; a
    # "%% visual <kind> {...}" comment, the data of a purpose-built graphic.
    $fullLabels = $null
    $visual = $null
    for (; $i -lt $all.Count; $i++) {
        $comment = $all[$i].Trim()
        if ($comment.StartsWith('%%')) {
            if ($comment -match '^%%\s*x-labels\s+(?<list>\[.*\])\s*$') { $fullLabels = @(ConvertFrom-BpMermaidList $Matches['list']) }
            elseif (-not $visual -and $comment -match '^%%\s*visual\s+(?<kind>[a-z][a-z0-9-]*)\s+(?<json>\{.*\})\s*$') {
                try {
                    $visual = [ordered]@{ kind = $Matches['kind']; title = $null; data = ($Matches['json'] | ConvertFrom-Json -ErrorAction Stop) }
                } catch { $visual = $null }
            }
            continue
        }
        $lines.Add($all[$i])
    }
    if ($visual) { return $visual }
    while ($lines.Count -and [string]::IsNullOrWhiteSpace($lines[0])) { $lines.RemoveAt(0) }
    if ($lines.Count -eq 0) { return [ordered]@{ kind = 'other'; title = $null; data = $null } }

    $header = $lines[0].Trim()
    $body = @($lines | Select-Object -Skip 1)
    $keyword = ($header -split '\s+')[0]
    switch -Regex ($keyword) {
        '^pie$'              { return (ConvertFrom-BpMermaidPie -Header $header -Body $body) }
        '^sankey(-beta)?$'   { return (ConvertFrom-BpMermaidSankey -Body $body) }
        '^xychart(-beta)?$'  { return (ConvertFrom-BpMermaidXy -Body $body -FullLabels $fullLabels) }
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
