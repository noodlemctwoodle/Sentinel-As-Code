#Requires -Version 7.6

<#
.SYNOPSIS
    Collect the workspace for a New-iSOCBlueprint run, or check an inventory is already on disk.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Run/Invoke-iSOCBlueprintRunCollect.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, one-command run
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCBlueprintRunCollect {
    <#
    .SYNOPSIS
        Collect the workspace (Export-iSOCBlueprintInventory), or with
        -SkipCollection check the run's folder holds an inventory.

    .PARAMETER Run
        The run's shared state: the values New-iSOCBlueprint was called with
        and what each step has produced so far. Steps read and add to it.
        Replaces Workspace with the folder the collector reports.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Run)

    if (-not $Run.SkipCollection) {
        $collect = @{
            ResourceGroup = $Run.ResourceGroup; WorkspaceName = $Run.WorkspaceName; OutputPath = $Run.Root
            TargetMaturityLevel = $Run.TargetMaturityLevel; LookbackDays = $Run.LookbackDays; Currency = $Run.Currency
        }
        Copy-iSOCBlueprintParameter -BoundParameters $Run.BoundParameters -Into $collect -Name 'SubscriptionId', 'PlaybookResourceGroup'
        if ($Run.IncludePreview) { $collect.IncludePreview = $true }
        if ($Run.NoDateFolder) { $collect.NoDateFolder = $true }
        $inventory = Export-iSOCBlueprintInventory @collect
        if ($inventory -and $inventory.Path) { $Run.Workspace = $inventory.Path }
    }
    elseif (-not (Test-Path -LiteralPath (Join-Path $Run.Workspace '_raw') -PathType Container)) {
        throw "-SkipCollection needs an inventory at $(Join-Path $Run.Workspace '_raw')."
    }
}
