#Requires -Version 7.6

<#
.SYNOPSIS
    Update-iSOCDependencyManifest: rewrite dependencies.json from the
    content.

.DESCRIPTION
    Replaces Tools/Build-DependencyManifest.ps1 -Mode Generate and -Mode
    Update. It writes only when the entries differ (or the file is
    missing), and the calling pipeline still owns the commit, branch and
    pull request (MIGRATION.md edit E10).

.NOTES
    File:         Modules/iSOCDeployments/Public/Update-iSOCDependencyManifest.ps1
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

function Update-iSOCDependencyManifest {
    <#
    .SYNOPSIS
        Write the dependency manifest the content needs, when it differs
        from the one on disk.

    .DESCRIPTION
        Discovers every analytics rule's and hunting query's dependencies
        and writes dependencies.json when an entry was added, removed or
        changed, or the file is missing. The file is UTF-8 with LF line
        endings, entries in path order, so a run on any platform writes
        the same bytes. Run it after editing content and commit the
        result. With -WhatIf it reports what would change and writes
        nothing.

    .PARAMETER RepoPath
        The repository root. Defaults to the repository the current folder
        is in.

    .PARAMETER ManifestPath
        The manifest file. Defaults to dependencies.json at the root.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.ManifestResult: ManifestPath,
        Exists (before the run), HasDrift, Changed (whether the file was
        written), Entries (the count), Diff and MissingWatchlists.

    .EXAMPLE
        Update-iSOCDependencyManifest

        Rewrites the manifest of the repository the current folder is in,
        when it is out of date.

    .EXAMPLE
        Update-iSOCDependencyManifest -WhatIf

        Shows what would change without writing.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('iSOCDeployments.ManifestResult')]
    param(
        [string] $RepoPath,

        [string] $ManifestPath
    )

    Assert-iSOCPrerequisite -Step Read
    $repo = Resolve-iSOCRepoPath -RepoPath $RepoPath
    $state = Get-iSOCDependencyManifestState -RepoPath $repo -ManifestPath $ManifestPath
    $relative = ConvertTo-iSOCRepoRelativePath -Path $state.ManifestPath -RepoPath $repo

    if (-not $state.HasDrift) {
        Write-iSOCLog 'Manifest already current; nothing to write.' -Level Success
        return (New-iSOCManifestResult -State $state -Changed $false)
    }

    if ($state.Exists) {
        Write-iSOCLog 'Manifest drift detected:' -Level Warning
        foreach ($line in $state.Diff) { Write-iSOCLog "  $line" }
    }
    else {
        Write-iSOCLog "Manifest not found at $relative; writing it from the discovered entries." -Level Warning
    }

    $changed = $false
    if ($PSCmdlet.ShouldProcess($relative, "Write $($state.Entries.Count) dependency entries")) {
        Write-iSOCTextFile -Path $state.ManifestPath -Content $state.Json
        Write-iSOCLog "Wrote $relative ($($state.Entries.Count) entries). Commit it with the content change." -Level Success
        $changed = $true
    }
    New-iSOCManifestResult -State $state -Changed $changed
}
