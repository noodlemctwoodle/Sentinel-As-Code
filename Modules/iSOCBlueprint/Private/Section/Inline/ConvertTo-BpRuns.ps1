#Requires -Version 7.6

<#
.SYNOPSIS
    Convert the inline content of a Markdown block into a list of runs

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/ConvertTo-BpRuns.ps1
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

function ConvertTo-BpRuns {
    <#
    .SYNOPSIS
        Convert the inline content of a Markdown block into a list of runs.

    .DESCRIPTION
        Adjacent runs with the same formatting merge. Whitespace is trimmed from
        the start of the first run and the end of the last run when they are
        text, and text runs left empty are dropped.

    .PARAMETER Container
        The Markdig container inline, such as the Inline of a paragraph or a
        heading. When it is $null the result is empty.

    .OUTPUTS
        The runs: ordered dictionaries holding text (with bold, italic, code,
        strike, href and target where set) or break.
    #>
    [CmdletBinding()]
    param([object] $Container)
    $out = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Container) { Add-BpInlineRuns -Inline $Container.FirstChild -Format @{} -Out $out }
    # Trim the whitespace a soft break or an anchor can leave at the edges.
    if ($out.Count -and $out[0].Contains('text')) { $out[0].text = $out[0].text.TrimStart() }
    if ($out.Count -and $out[$out.Count - 1].Contains('text')) { $out[$out.Count - 1].text = $out[$out.Count - 1].text.TrimEnd() }
    return @($out | Where-Object { -not $_.Contains('text') -or $_.text -ne '' })
}
