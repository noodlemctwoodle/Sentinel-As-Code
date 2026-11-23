#Requires -Version 7.6

<#
.SYNOPSIS
    Find the Sentinel-As-Code repository a command works on.

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/Resolve-iSOCRepoPath.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Resolve-iSOCRepoPath {
    <#
    .SYNOPSIS
        Return the full path of the repository root.

    .DESCRIPTION
        The root is the folder that holds Content/. Given -RepoPath, that
        folder is checked and returned; without it the current location and
        each folder above it are tried in turn, so a command run anywhere
        inside a clone finds the clone. Configuration, deployment state,
        reports and the dependency manifest all resolve under the root.

    .PARAMETER RepoPath
        The repository root, absolute or relative to the current location.

    .OUTPUTS
        [string] The full path, without a trailing separator.

    .EXAMPLE
        Resolve-iSOCRepoPath -RepoPath ~/Source/Sentinel-As-Code
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $RepoPath
    )

    $here = (Get-Location).ProviderPath
    $trim = {
        param($p)
        $t = $p.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        if ($t) { $t } else { $p }
    }

    if ($RepoPath) {
        $full = & $trim ([System.IO.Path]::GetFullPath($RepoPath, $here))
        if (-not (Test-Path -LiteralPath (Join-Path $full 'Content') -PathType Container)) {
            throw "'$RepoPath' is not a Sentinel-As-Code repository: it has no Content folder."
        }
        return $full
    }

    $dir = & $trim $here
    while ($dir) {
        if (Test-Path -LiteralPath (Join-Path $dir 'Content') -PathType Container) { return $dir }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    throw "No Sentinel-As-Code repository found at or above '$here'. Run the command inside the repository or pass -RepoPath."
}
