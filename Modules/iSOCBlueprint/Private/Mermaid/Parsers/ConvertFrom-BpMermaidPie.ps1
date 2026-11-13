#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertFrom-BpMermaidPie

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Parsers/ConvertFrom-BpMermaidPie.ps1
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
