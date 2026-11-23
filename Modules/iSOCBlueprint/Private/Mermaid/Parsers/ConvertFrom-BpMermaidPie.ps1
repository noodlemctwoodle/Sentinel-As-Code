#Requires -Version 7.6

<#
.SYNOPSIS
    Parse a Mermaid pie chart into its title and slices.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Parsers/ConvertFrom-BpMermaidPie.ps1
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

function ConvertFrom-BpMermaidPie {
    <#
    .SYNOPSIS
        Parse a Mermaid pie chart into its title and slices.

    .DESCRIPTION
        A slice line is a double-quoted label, a colon and a number. The
        title comes from the header line or from a title line in the body.

    .PARAMETER Header
        The diagram's first line, which can carry showData and a title.

    .PARAMETER Body
        The diagram's lines after its header line.

    .OUTPUTS
        [ordered] kind ('pie'), the chart's title and data: showData (true
        when the header names it) and slices (label and value).
    #>
    [CmdletBinding()]
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
