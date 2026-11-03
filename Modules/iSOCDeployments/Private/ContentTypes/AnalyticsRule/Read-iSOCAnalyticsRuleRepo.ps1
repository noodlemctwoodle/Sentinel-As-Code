#Requires -Version 7.2

<#
.SYNOPSIS
    ReadRepo handler for analytics rules.

.DESCRIPTION
    Replaces the readers in Deploy-CustomDetections
    (Deploy/content/Deploy-CustomContent.ps1) and Get-RepoAnalyticsRuleYamls
    (Tools/Test-SentinelRuleDrift.ps1), which read the same files two ways.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Read-iSOCAnalyticsRuleRepo.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.2.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    Needs powershell-yaml when it runs. Import-iSOCYamlModule loads it
    then instead of #Requires, so the module imports without it.

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Read-iSOCAnalyticsRuleRepo {
    <#
    .SYNOPSIS
        Read every analytics rule file in the repository.

    .DESCRIPTION
        One item per file, in repository order, read by Read-iSOCYamlRepoItem.
        A file that does not parse is still returned, with ParseError set and
        no Data, so each caller decides what an unreadable file means (deploy
        fails it, drift skips it). A rule under a Community folder is marked
        Source Community; the folder is matched in the repository-relative
        path, so a clone that itself sits in a folder called Community is not
        mistaken for one (MIGRATION.md edit E5).

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER ContentType
        The analytics rule content type.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.RepoItem: ContentType, Identity (the
        id in lower case, or nothing), Name, Path, RelativePath, Source
        (Custom or Community), Data (the parsed YAML) and ParseError.

    .EXAMPLE
        Read-iSOCAnalyticsRuleRepo -RepoPath $repo -ContentType $rules
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath,

        [Parameter(Mandatory)]
        [psobject] $ContentType
    )

    Read-iSOCYamlRepoItem -RepoPath $RepoPath -ContentType $ContentType
}
