#Requires -Version 7.6

<#
.SYNOPSIS
    Write the comment line that carries a graphic's data.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Format-VisualLine.ps1
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

function Format-VisualLine {
    <#
    .SYNOPSIS
        Write the comment line that carries a graphic's data.

    .DESCRIPTION
        A purpose-built graphic's data on a Mermaid comment line. Mermaid ignores
        it, so the Markdown export keeps its diagram; ConvertFrom-BlueprintMermaid
        reads the kind and the JSON, and the SharePoint site and the dashboard draw
        the graphic made for that kind instead of the Mermaid. The line is indented
        four spaces and reads "%% visual", the kind, then the data as compressed
        JSON (depth 8).

    .PARAMETER Kind
        The kind of graphic, written after "visual".

    .PARAMETER Data
        The data for the graphic, converted to JSON.

    .OUTPUTS
        [string].
    #>
    [CmdletBinding()]
    param([string]$Kind, $Data)
    return "    %% visual $Kind " + ($Data | ConvertTo-Json -Compress -Depth 8)
}
