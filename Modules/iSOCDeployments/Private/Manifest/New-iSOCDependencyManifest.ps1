#Requires -Version 7.6

<#
.SYNOPSIS
    Build the dependency manifest entries from the repository's content.

.DESCRIPTION
    Replaces Build-Manifest in Tools/Build-DependencyManifest.ps1. The
    content comes from every content type with the Dependencies capability,
    read through its ReadRepo and GetQuery handlers, where the script
    walked a fixed list of folders; today those are the same analytics
    rules and hunting queries (MIGRATION.md edit E8). Entries are written
    in invariant-culture, case-insensitive order of their path, the order
    the script's sort produced, which is the same on every platform.

.NOTES
    File:         Modules/iSOCDeployments/Private/Manifest/New-iSOCDependencyManifest.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    Needs powershell-yaml when it runs. Import-iSOCYamlModule loads it
    then instead of #Requires, so the module imports without it.
#>

# Keeps the file help above from being read as the help of the function below.

function New-iSOCDependencyManifest {
    <#
    .SYNOPSIS
        Discover each content item's dependencies and the watchlists the
        repository does not have.

    .DESCRIPTION
        An item with no dependency at all gets no entry. Each entry lists
        only the buckets it has (tables, watchlists, functions,
        externalData), each sorted. Every watchlist an item reads that is
        not in the inventory is recorded with the items that read it, for
        the warning the manifest commands print. The function writes
        nothing.

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER Inventory
        The repository's functions and watchlists, from
        Get-iSOCDependencyInventory.

    .OUTPUTS
        [pscustomobject] Entries (an ordered dictionary of
        repository-relative path to entry) and MissingWatchlists (an ordered
        dictionary of alias to the paths that read it).

    .EXAMPLE
        $manifest = New-iSOCDependencyManifest -RepoPath $repo -Inventory $inventory
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds the entries in memory; Update-iSOCDependencyManifest writes them.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath,

        [Parameter(Mandatory)]
        [psobject] $Inventory
    )

    $found = [System.Collections.Generic.List[object]]::new()
    foreach ($type in Get-iSOCContentTypeRegistry | Where-Object { $_.Capabilities -contains 'Dependencies' }) {
        foreach ($item in Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $RepoPath; ContentType = $type }) {
            $found.Add([pscustomobject]@{ Type = $type; Item = $item })
        }
    }
    $found.Sort([System.Comparison[object]] { param($a, $b) [System.StringComparer]::InvariantCultureIgnoreCase.Compare($a.Item.RelativePath, $b.Item.RelativePath) })

    $entries = [ordered]@{}
    $missing = [System.Collections.Generic.SortedDictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $found) {
        $rel = $entry.Item.RelativePath
        $query = Invoke-iSOCContentTypeHandler -ContentType $entry.Type -Handler GetQuery -Parameters @{ Item = $entry.Item }
        $deps = Get-iSOCQueryDependency -Query $query -KnownFunctions $Inventory.Functions

        # The KQL helpers return nothing when there is no match and a bare
        # string when there is one, so each bucket is made a real array
        # first: under strict mode a bare value has no Count, and @($null)
        # would count as one.
        $buckets = [ordered]@{}
        foreach ($name in 'tables', 'watchlists', 'functions', 'externalData') {
            $buckets[$name] = @($deps[$name] | Where-Object { $null -ne $_ })
        }

        foreach ($w in $buckets.watchlists) {
            if (-not $Inventory.Watchlists.ContainsKey($w)) {
                if (-not $missing.ContainsKey($w)) { $missing[$w] = [System.Collections.Generic.List[string]]::new() }
                $missing[$w].Add($rel)
            }
        }

        $hasAny = ($buckets.tables.Count + $buckets.watchlists.Count + $buckets.functions.Count + $buckets.externalData.Count) -gt 0
        if (-not $hasAny) { continue }

        $manifestEntry = [ordered]@{}
        foreach ($name in $buckets.Keys) {
            if ($buckets[$name].Count -gt 0) { $manifestEntry[$name] = @($buckets[$name] | Sort-Object) }
        }
        $entries[$rel] = $manifestEntry
    }

    $missingWatchlists = [ordered]@{}
    foreach ($alias in $missing.Keys) { $missingWatchlists[$alias] = $missing[$alias].ToArray() }

    [pscustomobject]@{
        Entries           = $entries
        MissingWatchlists = $missingWatchlists
    }
}
