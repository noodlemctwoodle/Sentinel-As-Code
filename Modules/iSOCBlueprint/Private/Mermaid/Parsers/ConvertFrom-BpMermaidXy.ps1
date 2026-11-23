#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertFrom-BpMermaidXy

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Parsers/ConvertFrom-BpMermaidXy.ps1
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

function ConvertFrom-BpMermaidXy {
    param([string[]] $Body, [string[]] $FullLabels)
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
    if ($FullLabels -and $FullLabels.Count -eq $x.labels.Count) { $x.labels = @($FullLabels) }
    return [ordered]@{ kind = 'xy'; title = $title; data = [ordered]@{ xAxis = $x; yAxis = $y; series = $series.ToArray() } }
}
