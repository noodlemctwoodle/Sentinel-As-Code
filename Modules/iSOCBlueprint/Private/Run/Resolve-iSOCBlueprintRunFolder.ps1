#Requires -Version 7.6

<#
.SYNOPSIS
    Work out where a New-iSOCBlueprint run writes.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Run/Resolve-iSOCBlueprintRunFolder.ps1
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

function Resolve-iSOCBlueprintRunFolder {
    <#
    .SYNOPSIS
        Resolve the output root, the workspace's folder and the run's folder.

    .DESCRIPTION
        The run's folder is today's under the workspace's folder, or, with
        -SkipCollection, the newest day already there; the workspace's folder
        itself with -NoDateFolder.

    .PARAMETER Run
        The run's shared state: the values New-iSOCBlueprint was called with
        and what each step has produced so far. Steps read and add to it.
        Adds Root, WorkspaceRoot and Workspace.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Run)

    $root = Resolve-iSOCBlueprintPath -Path $Run.OutputPath -Default 'SecurityDocs'
    $workspaceRoot = Join-Path $root $Run.WorkspaceName
    $Run.Root = $root
    $Run.WorkspaceRoot = $workspaceRoot
    $Run.Workspace = if ($Run.NoDateFolder) { $workspaceRoot }
        elseif ($Run.SkipCollection) { Resolve-iSOCBlueprintRunPath -Path $workspaceRoot }
        else { Join-Path $workspaceRoot (Get-iSOCBlueprintRunFolderName) }
}
