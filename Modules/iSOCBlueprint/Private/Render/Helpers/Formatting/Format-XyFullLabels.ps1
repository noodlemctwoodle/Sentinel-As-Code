#Requires -Version 7.6

<#
.SYNOPSIS
    Write the full x-axis labels for a chart whose labels are shortened.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Format-XyFullLabels.ps1
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

function Format-XyFullLabels {
    <#
    .SYNOPSIS
        Write the full x-axis labels for a chart whose labels are shortened.

    .DESCRIPTION
        Full x-axis labels for a chart whose Mermaid labels are shortened to fit
        under the bars. Mermaid ignores a %% line; ConvertFrom-BlueprintMermaid
        reads it, so the SharePoint chart shows the whole names. The line is
        indented four spaces and reads "%% x-labels" followed by the labels, each in
        double quotes and separated by commas. A double quote inside a label is
        replaced by a single quote.

    .PARAMETER Labels
        The full label for each position on the x-axis.

    .OUTPUTS
        [string].
    #>
    [CmdletBinding()]
    param([string[]]$Labels)
    return '    %% x-labels [' + ((@($Labels) | ForEach-Object { '"' + ([string]$_ -replace '"', "'") + '"' }) -join ', ') + ']'
}
