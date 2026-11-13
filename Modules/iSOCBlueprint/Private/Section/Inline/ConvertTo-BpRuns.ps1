#Requires -Version 7.6

<#
.SYNOPSIS
    ConvertTo-BpRuns

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/ConvertTo-BpRuns.ps1
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

function ConvertTo-BpRuns {
    # Inline content -> runs. Adjacent runs with the same formatting merge.
    param([object] $Container)
    $out = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Container) { Add-BpInlineRuns -Inline $Container.FirstChild -Format @{} -Out $out }
    # Trim the whitespace a soft break or an anchor can leave at the edges.
    if ($out.Count -and $out[0].Contains('text')) { $out[0].text = $out[0].text.TrimStart() }
    if ($out.Count -and $out[$out.Count - 1].Contains('text')) { $out[$out.Count - 1].text = $out[$out.Count - 1].text.TrimEnd() }
    return @($out | Where-Object { -not $_.Contains('text') -or $_.text -ne '' })
}
