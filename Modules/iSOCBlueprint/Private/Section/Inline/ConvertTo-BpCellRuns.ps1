#Requires -Version 7.6

<#
.SYNOPSIS
    Convert one Markdown table cell into a list of runs

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/ConvertTo-BpCellRuns.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Section model conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-BpCellRuns {
    <#
    .SYNOPSIS
        Convert one Markdown table cell into a list of runs.

    .DESCRIPTION
        Only the cell's paragraph blocks are read, each through ConvertTo-BpRuns.
        A break entry separates one paragraph's runs from the next, and blocks
        of any other kind are skipped.

    .PARAMETER Cell
        The Markdig table cell, enumerated as the blocks it holds.

    .OUTPUTS
        The runs, written to the pipeline one by one.
    #>
    [CmdletBinding()]
    param([object] $Cell)
    $first = $true
    foreach ($block in $Cell) {
        if ($block.GetType().Name -ne 'ParagraphBlock') { continue }
        if (-not $first) { [ordered]@{ break = $true } }
        ConvertTo-BpRuns -Container $block.Inline
        $first = $false
    }
}
