#Requires -Version 7.6

<#
.SYNOPSIS
    Test-iSOCDependencyManifest: check dependencies.json matches the
    content.

.DESCRIPTION
    Replaces Tools/Build-DependencyManifest.ps1 -Mode Verify. It returns a
    result with HasDrift instead of exiting, so a pipeline step decides
    what drift means (MIGRATION.md edit E10).

.NOTES
    File:         Modules/iSOCDeployments/Public/Test-iSOCDependencyManifest.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-iSOCDependencyManifest {
    <#
    .SYNOPSIS
        Compare the dependency manifest with what the content depends on
        now.

    .DESCRIPTION
        Discovers every analytics rule's and hunting query's dependencies
        from its KQL (tables, watchlists, parser functions and external
        data), compares them with dependencies.json, and reports each path
        added, removed or changed. Watchlists the content reads that the
        repository does not have are reported as warnings; they fail at
        deploy unless they are created another way. Nothing is written.

        In a pipeline: if ((Test-iSOCDependencyManifest).HasDrift) { exit 1 }

    .PARAMETER RepoPath
        The repository root. Defaults to the repository the current folder
        is in.

    .PARAMETER ManifestPath
        The manifest file. Defaults to dependencies.json at the root.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.ManifestResult: ManifestPath,
        Exists, HasDrift, Changed (always false here), Entries (the count),
        Diff (the report lines) and MissingWatchlists.

    .EXAMPLE
        Test-iSOCDependencyManifest

        Checks the manifest of the repository the current folder is in.

    .EXAMPLE
        (Test-iSOCDependencyManifest -RepoPath ~/Source/Sentinel-As-Code).Diff

        Lists what differs.
    #>
    [CmdletBinding()]
    [OutputType('iSOCDeployments.ManifestResult')]
    param(
        [string] $RepoPath,

        [string] $ManifestPath
    )

    Assert-iSOCPrerequisite -Step Read
    $repo = Resolve-iSOCRepoPath -RepoPath $RepoPath
    $state = Get-iSOCDependencyManifestState -RepoPath $repo -ManifestPath $ManifestPath

    if (-not $state.Exists) {
        Write-iSOCLog "Manifest not found at $(ConvertTo-iSOCRepoRelativePath -Path $state.ManifestPath -RepoPath $repo). Run Update-iSOCDependencyManifest first." -Level Error
    } elseif ($state.HasDrift) {
        Write-iSOCLog 'Dependency manifest is out of sync with content. Diff:' -Level Error
        foreach ($line in $state.Diff) { Write-iSOCLog "  $line" }
        Write-iSOCLog 'Fix: run Update-iSOCDependencyManifest and commit the result.' -Level Error
    } else {
        Write-iSOCLog 'Manifest matches discovered dependencies.' -Level Success
    }

    New-iSOCManifestResult -State $state -Changed $false
}
