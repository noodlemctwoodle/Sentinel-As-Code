#Requires -Version 7.6

<#
.SYNOPSIS
    Render the inventory and draw its charts for a New-iSOCBlueprint run.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Run/Invoke-iSOCBlueprintRunRender.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, one-command run
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Invoke-iSOCBlueprintRunRender {
    <#
    .SYNOPSIS
        Render the section model and the Markdown report the formats need,
        then, with -ChartImages, draw the Markdown's charts as images.

    .DESCRIPTION
        Without -ChartImages a Word report has no charts, so the run warns.

    .PARAMETER Run
        The run's shared state: the values New-iSOCBlueprint was called with
        and what each step has produced so far. Steps read and add to it.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Run)

    $render = @()
    if ($Run.WantMarkdown) { $render += 'Markdown' }
    if ($Run.WantJson) { $render += 'Json' }
    $null = ConvertTo-iSOCBlueprint -WorkspaceName $Run.WorkspaceName -Path $Run.Workspace -Format $render

    # Chart images look one level down: the workspaces under the root, or
    # the days under the workspace's folder.
    if ($Run.ChartImages) { $null = ConvertTo-iSOCBlueprintChartImage -Path $(if ($Run.NoDateFolder) { $Run.Root } else { $Run.WorkspaceRoot }) }
    elseif ($Run.Format -contains 'Word') {
        Write-Warning 'The Word report will have no charts: pandoc drops Mermaid charts. Add -ChartImages to draw them as images.'
    }
}
