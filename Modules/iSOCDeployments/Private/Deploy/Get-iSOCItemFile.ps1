#Requires -Version 7.6

<#
.SYNOPSIS
    The repository files behind one content item.

.NOTES
    File:         Modules/iSOCDeployments/Private/Deploy/Get-iSOCItemFile.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCItemFile {
    <#
    .SYNOPSIS
        Return the repository-relative paths an item is made of.

    .DESCRIPTION
        Most items are one file, their Path. An item a folder holds lists
        the files that stand for it in Files: a watchlist's watchlist.json
        and data.csv, a workbook's workbook.json. The deployment state, the
        exclusions and smart deployment's changed-file check see those
        files, as they did in Deploy-CustomContent.ps1, so a state file the
        script wrote still applies. The first file names the item in the
        dependency graph.

    .PARAMETER Item
        A repository item.

    .PARAMETER RepoPath
        The repository root.

    .OUTPUTS
        [string[]] Forward-slash paths, the item's main file first.

    .EXAMPLE
        Get-iSOCItemFile -Item $item -RepoPath $repo
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item,

        [Parameter(Mandatory)]
        [string] $RepoPath
    )

    $paths = if ($Item.PSObject.Properties['Files']) { @($Item.Files) } else { @($Item.Path) }
    foreach ($path in $paths) { ConvertTo-iSOCRepoRelativePath -Path $path -RepoPath $RepoPath }
}
