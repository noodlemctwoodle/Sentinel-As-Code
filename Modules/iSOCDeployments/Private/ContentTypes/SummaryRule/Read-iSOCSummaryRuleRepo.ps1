#Requires -Version 7.2

<#
.SYNOPSIS
    ReadRepo handler for summary rules.

.DESCRIPTION
    Replaces the reader in Deploy-CustomSummaryRules
    (Deploy/content/Deploy-CustomContent.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/SummaryRule/Read-iSOCSummaryRuleRepo.ps1
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

function Read-iSOCSummaryRuleRepo {
    <#
    .SYNOPSIS
        Read every summary rule file in the repository.

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER ContentType
        The summary rule content type.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.RepoItem, one per file, from
        Read-iSOCJsonRepoItem.

    .EXAMPLE
        Read-iSOCSummaryRuleRepo -RepoPath $repo -ContentType $summaryRules
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
