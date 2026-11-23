#Requires -Version 7.6

<#
.SYNOPSIS
    Write the title, workspace line and generated stamp that open a page.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Format-Banner.ps1
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

function Format-Banner {
    <#
    .SYNOPSIS
        Write the title, workspace line and generated stamp that open a page.

    .DESCRIPTION
        The workspace name comes from $script:WorkspaceName. The generated time
        (UTC, through Format-DateUtc) and the Blueprint version come from
        run-context.json; the time is blank when that file is not in the snapshot.

    .PARAMETER Title
        The page title, written as the level-one heading.

    .OUTPUTS
        [string] of Markdown: the heading, then a block quote line.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param([string]$Title)
    $run = Read-BlueprintRaw 'run-context.json'
    $started = if ($run) { Format-DateUtc $run.StartedAtUtc } else { '' }
    @"
# $Title

> **Workspace** ``$script:WorkspaceName``  ·  **Generated** $started UTC  ·  **Blueprint** v$($run.BlueprintVersion)
"@
}
