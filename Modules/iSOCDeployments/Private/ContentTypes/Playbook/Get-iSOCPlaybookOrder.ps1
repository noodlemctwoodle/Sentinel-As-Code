#Requires -Version 7.6

<#
.SYNOPSIS
    Order handler for playbooks: modules first, in dependency order.

.DESCRIPTION
    Copied from the dependency sort in Deploy-CustomPlaybooks
    (Deploy/content/Deploy-CustomContent.ps1). The script started its sort
    from a hashtable, so modules that did not depend on each other came out
    in no set order; here ties keep repository order, so every run deploys
    in the same order (MIGRATION.md edit E15).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookOrder.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCPlaybookOrder {
    <#
    .SYNOPSIS
        Return the playbooks in the order they must deploy.

    .DESCRIPTION
        A template that names Microsoft.Logic/workflows/<name> depends on
        that workflow. Playbooks in a folder named Module are known as
        Module-<file name>, the rest as <folder>-<file name>. The modules
        deploy first, each after the modules it names (Kahn's algorithm),
        then every other playbook in repository order. References to
        modules the repository does not have are warned about, and modules
        caught in a cycle deploy after the rest of the modules, in
        repository order, with a warning.

    .PARAMETER Item
        The playbook repository items, in repository order.

    .OUTPUTS
        [pscustomobject] The same items, reordered.

    .EXAMPLE
        $ordered = Get-iSOCPlaybookOrder -Item $items
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [psobject[]] $Item
    )

    $logicalNameOf = { param($Entry) if ($Entry.Category -eq 'Module') { "Module-$($Entry.BaseName)" } else { "$($Entry.Category)-$($Entry.BaseName)" } }
    $modules = @($Item | Where-Object { $_.Category -eq 'Module' })
    $others = @($Item | Where-Object { $_.Category -ne 'Module' })

    $nameToItem = @{}
    $dependencyMap = [ordered]@{}
    $availableModules = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($module in $modules) { [void]$availableModules.Add((& $logicalNameOf $module)) }

    foreach ($entry in $Item) {
        $logicalName = & $logicalNameOf $entry
        $nameToItem[$logicalName] = $entry
        $content = Get-Content -LiteralPath $entry.Path -Raw
        $baseName = $entry.BaseName
        $dependencyMap[$logicalName] = @([regex]::Matches($content, 'Microsoft\.Logic/workflows/([^"''\]\s]+)') |
            ForEach-Object { $_.Groups[1].Value } |
            Where-Object { $_ -ne $logicalName -and $_ -ne $baseName } |
            Select-Object -Unique)
    }

    $missingDeps = foreach ($key in $dependencyMap.Keys) {
        foreach ($dep in $dependencyMap[$key]) {
            if (-not $availableModules.Contains($dep) -and -not $availableModules.Contains("Module-$dep")) { "  $key -> $dep" }
        }
    }
    if (@($missingDeps).Count -gt 0) {
        Write-iSOCLog 'Warning: The following playbooks reference modules not found in the repo:' -Level Warning
        foreach ($line in $missingDeps) { Write-iSOCLog $line -Level Warning }
    }

    $inDegree = [ordered]@{}
    $adjList = @{}
    foreach ($module in $modules) {
        $name = & $logicalNameOf $module
        if (-not $inDegree.Contains($name)) { $inDegree[$name] = 0 }
        if (-not $adjList.ContainsKey($name)) { $adjList[$name] = [System.Collections.Generic.List[string]]::new() }
    }
    foreach ($module in $modules) {
        $name = & $logicalNameOf $module
        foreach ($dep in $dependencyMap[$name]) {
            $depKey = if ($availableModules.Contains($dep)) { $dep } elseif ($availableModules.Contains("Module-$dep")) { "Module-$dep" } else { $null }
            if ($depKey -and $inDegree.Contains($depKey)) {
                $adjList[$depKey].Add($name)
                $inDegree[$name]++
            }
        }
    }

    $moduleOrder = [System.Collections.Generic.List[object]]::new()
    $queue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($name in @($inDegree.Keys)) { if ($inDegree[$name] -eq 0) { $queue.Enqueue($name) } }
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        $moduleOrder.Add($nameToItem[$current])
        foreach ($dependent in $adjList[$current]) {
            $inDegree[$dependent]--
            if ($inDegree[$dependent] -eq 0) { $queue.Enqueue($dependent) }
        }
    }

    $sorted = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $moduleOrder) { [void]$sorted.Add((& $logicalNameOf $entry)) }
    $unsorted = @($modules | Where-Object { -not $sorted.Contains((& $logicalNameOf $_)) })
    if ($unsorted.Count -gt 0) {
        Write-iSOCLog "Warning: Circular dependency detected among $($unsorted.Count) module(s); deploying in file order." -Level Warning
        foreach ($entry in $unsorted) { $moduleOrder.Add($entry) }
    }

    if ($modules.Count -gt 0) {
        $leafCount = @($moduleOrder | Where-Object { @($dependencyMap[(& $logicalNameOf $_)]).Count -eq 0 }).Count
        $depCount = $moduleOrder.Count - $leafCount
        Write-iSOCLog "  Deploying $($modules.Count) Module playbook(s) first ($leafCount leaf, $depCount dependent) in dependency order."
    }

    @($moduleOrder) + @($others)
}
