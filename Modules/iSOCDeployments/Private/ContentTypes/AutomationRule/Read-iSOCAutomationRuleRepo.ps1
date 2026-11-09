#Requires -Version 7.6

<#
.SYNOPSIS
    ReadRepo handler for automation rules.

.DESCRIPTION
    Replaces the reader in Deploy-CustomAutomationRules
    (Deploy/content/Deploy-CustomContent.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AutomationRule/Read-iSOCAutomationRuleRepo.ps1
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

function Read-iSOCAutomationRuleRepo {
    <#
    .SYNOPSIS
        Read every automation rule file in the repository.

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER ContentType
        The automation rule content type.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.RepoItem, one per file, from
        Read-iSOCJsonRepoItem.

    .EXAMPLE
        Read-iSOCAutomationRuleRepo -RepoPath $repo -ContentType $automationRules
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
