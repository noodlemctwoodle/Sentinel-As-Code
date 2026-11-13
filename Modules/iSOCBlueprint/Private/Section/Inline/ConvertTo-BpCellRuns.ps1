#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertTo-BpCellRuns

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/ConvertTo-BpCellRuns.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, Section model conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function ConvertTo-BpCellRuns {
    param([object] $Cell)
    $first = $true
    foreach ($block in $Cell) {
        if ($block.GetType().Name -ne 'ParagraphBlock') { continue }
        if (-not $first) { [ordered]@{ break = $true } }
        ConvertTo-BpRuns -Container $block.Inline
        $first = $false
    }
}
