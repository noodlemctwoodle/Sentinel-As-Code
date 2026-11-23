#Requires -Version 7.6

<#
.SYNOPSIS
    Escape text that would otherwise start a Markdown list item.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/GapAnalysis/ConvertTo-BlueprintListItem.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-BlueprintListItem {
    <#
    .SYNOPSIS
        Escape text that would otherwise start a Markdown list item.

    .DESCRIPTION
        A list item that starts with a Markdown block marker (a rule named "*
        Detection ..." or "1. Test") would open a nested list, a heading or a quote
        and leave its own bullet empty; a backslash keeps it as text. A leading *,
        +, -, # or > followed by a space or the end of the text, or a leading number
        followed by . or ) in the same way, is escaped.

    .PARAMETER Text
        The text to escape.

    .OUTPUTS
        [string].
    #>
    [CmdletBinding()]
    param([string]$Text)
    return (($Text -replace '^([*+\-#>])(?=\s|$)', '\$1') -replace '^(\d+)([.)])(?=\s|$)', '$1\$2')
}
