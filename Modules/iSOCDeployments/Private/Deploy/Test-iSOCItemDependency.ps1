#Requires -Version 7.2

<#
.SYNOPSIS
    Check an item's dependencies are met before it deploys.

.DESCRIPTION
    Replaces Test-ContentDependencies (Deploy/content/Deploy-CustomContent.ps1),
    reading the graph and the inventory from the run. A workspace list that
    could not be read skips its checks, where the script reported every such
    dependency missing (MIGRATION.md edit E13).

.NOTES
    File:         Modules/iSOCDeployments/Private/Deploy/Test-iSOCItemDependency.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-iSOCItemDependency {
    <#
    .SYNOPSIS
        Return whether an item's dependencies are met, and which are not.

    .DESCRIPTION
        An item without an entry in dependencies.json, or a run without a
        graph, passes. A table must be in the workspace; a watchlist or a
        function must be in the workspace or among the repository's own,
        which this run deploys first. Names compare without regard to case.

    .PARAMETER Run
        The deployment run, with its Graph and Inventory.

    .PARAMETER Item
        A repository item. Its main file names it in the graph.

    .OUTPUTS
        [hashtable] Passed ([bool]) and Missing (kind:name strings).

    .EXAMPLE
        $check = Test-iSOCItemDependency -Run $run -Item $item
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Run,

        [Parameter(Mandatory)]
        [psobject] $Item
    )

    $key = @(Get-iSOCItemFile -Item $Item -RepoPath $Run.RepoPath)[0]
    if ($Run.Graph.Count -eq 0 -or -not $Run.Graph.ContainsKey($key)) { return @{ Passed = $true; Missing = @() } }

    $deps = $Run.Graph[$key]
    $inventory = $Run.Inventory
    $missing = [System.Collections.Generic.List[string]]::new()

    if ($deps.ContainsKey('tables') -and $null -ne $inventory.Tables -and @($inventory.Tables).Count -gt 0) {
        foreach ($table in $deps.tables) {
            if ($inventory.Tables -notcontains $table) { $missing.Add("table:$table") }
        }
    }
    if ($deps.ContainsKey('watchlists') -and $null -ne $inventory.Watchlists) {
        foreach ($wl in $deps.watchlists) {
            if ($inventory.Watchlists -notcontains $wl -and $inventory.RepoWatchlists -notcontains $wl) { $missing.Add("watchlist:$wl") }
        }
    }
    if ($deps.ContainsKey('functions') -and $null -ne $inventory.Functions) {
        foreach ($fn in $deps.functions) {
            if ($inventory.Functions -notcontains $fn -and $inventory.RepoFunctions -notcontains $fn) { $missing.Add("function:$fn") }
        }
    }

    @{
        Passed  = ($missing.Count -eq 0)
        Missing = $missing.ToArray()
    }
}
