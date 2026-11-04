#Requires -Version 7.2

<#
.SYNOPSIS
    Read every workspace setting file in the repository.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/WorkspaceSetting/Read-iSOCWorkspaceSettingRepo.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Read-iSOCWorkspaceSettingRepo {
    <#
    .SYNOPSIS
        Read every workspace setting file in the repository.

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER ContentType
        The workspace setting content type.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.RepoItem, one per file, from
        Read-iSOCJsonRepoItem.

    .EXAMPLE
        Read-iSOCWorkspaceSettingRepo -RepoPath $repo -ContentType $settings
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath,

        [Parameter(Mandatory)]
        [psobject] $ContentType
    )

    Read-iSOCJsonRepoItem -RepoPath $RepoPath -ContentType $ContentType
}
