#Requires -Version 7.6

<#
.SYNOPSIS
    Read dependencies.json for the deploy run.

.DESCRIPTION
    Copied from Initialize-DependencyGraph (Deploy/content/Deploy-CustomContent.ps1),
    unchanged in behaviour, returning the graph instead of setting script
    state.

.NOTES
    File:         Modules/iSOCDeployments/Private/Deploy/Read-iSOCDependencyGraph.ps1
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

function Read-iSOCDependencyGraph {
    <#
    .SYNOPSIS
        Return each content path's dependencies, or an empty graph.

    .DESCRIPTION
        Without dependencies.json, or when it does not parse, the graph is
        empty and everything deploys unconditionally, as it did.

    .PARAMETER RepoPath
        The repository root.

    .OUTPUTS
        [hashtable] Repository-relative path to a hashtable of tables,
        watchlists, functions, externalData and playbooks (each present only
        when the manifest lists it).

    .EXAMPLE
        $graph = Read-iSOCDependencyGraph -RepoPath $repo
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath
    )

    $graph = @{}
    $depsFile = Join-Path $RepoPath 'dependencies.json'
    if (-not (Test-Path -LiteralPath $depsFile -PathType Leaf)) {
        Write-iSOCLog 'No dependencies.json found; all content will deploy unconditionally.'
        return $graph
    }

    Write-iSOCLog 'Loading dependency graph...' -Level Section
    try {
        $depsJson = Get-Content -LiteralPath $depsFile -Raw | ConvertFrom-Json -ErrorAction Stop
        $deps = Get-iSOCPropertyValue -InputObject $depsJson -Path 'dependencies'
        if ($deps) {
            foreach ($prop in $deps.PSObject.Properties) {
                $entry = @{}
                $val = $prop.Value
                $valProps = @($val.PSObject.Properties | ForEach-Object { $_.Name })
                foreach ($bucket in 'tables', 'watchlists', 'functions', 'externalData', 'playbooks') {
                    if ($valProps -contains $bucket) { $entry[$bucket] = @($val.$bucket) }
                }
                $graph[$prop.Name] = $entry
            }
        }
        Write-iSOCLog "Loaded dependencies for $($graph.Count) content items."
    }
    catch {
        Write-iSOCLog "Failed to parse dependencies.json: $($_.Exception.Message)" -Level Warning
        Write-iSOCLog 'Continuing without dependency checks.' -Level Warning
        $graph = @{}
    }
    $graph
}
