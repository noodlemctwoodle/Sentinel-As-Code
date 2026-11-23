#Requires -Version 7.6

<#
.SYNOPSIS
    Parse the body of a Mermaid user journey into sections of scored tasks.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Parsers/ConvertFrom-BpMermaidJourney.ps1
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

function ConvertFrom-BpMermaidJourney {
    <#
    .SYNOPSIS
        Parse the body of a Mermaid user journey into sections of scored
        tasks.

    .DESCRIPTION
        A task line is a label, a colon, a whole-number score and, after a
        second colon, comma-separated actors. A task before any section line
        goes in a section with a $null name.

    .PARAMETER Body
        The diagram's lines after its header line.

    .OUTPUTS
        [ordered] kind ('journey'), the chart's title and data: sections
        (name and tasks, each with label, score and actors).
    #>
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [CmdletBinding()]
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
