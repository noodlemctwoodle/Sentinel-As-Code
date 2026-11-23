#Requires -Version 7.6

<#
.SYNOPSIS
    Write a path the way reports, results and logs show it.

.DESCRIPTION
    Replaces ConvertTo-ReportPath from Tools/Test-SentinelRuleDrift.ps1,
    unchanged in behaviour: a path inside the repository becomes relative
    to its root with forward slashes, so nothing written for others to
    read carries the machine's folder layout.

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/ConvertTo-iSOCRepoRelativePath.ps1
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

function ConvertTo-iSOCRepoRelativePath {
    <#
    .SYNOPSIS
        Make a path repository-relative with forward slashes.

    .PARAMETER Path
        The path to convert. An empty or already relative path is returned as
        given.

    .PARAMETER RepoPath
        The repository root.

    .OUTPUTS
        [string] The relative path, or only the file name for a path outside
        the repository.

    .EXAMPLE
        ConvertTo-iSOCRepoRelativePath -Path $file.FullName -RepoPath $repo
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $RepoPath
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.Path]::IsPathRooted($Path)) { return $Path }

    $base = (Resolve-Path -LiteralPath $RepoPath).ProviderPath
    $relative = [System.IO.Path]::GetRelativePath($base, $Path)
    if ($relative.StartsWith('..') -or [System.IO.Path]::IsPathRooted($relative)) {
        return [System.IO.Path]::GetFileName($Path)
    }
    $relative -replace '\\', '/'
}
