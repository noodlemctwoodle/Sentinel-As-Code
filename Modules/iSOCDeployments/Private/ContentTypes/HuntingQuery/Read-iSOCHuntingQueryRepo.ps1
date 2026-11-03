#Requires -Version 7.2

<#
.SYNOPSIS
    ReadRepo handler for hunting queries.

.DESCRIPTION
    Replaces the reader in Deploy-CustomHuntingQueries
    (Deploy/content/Deploy-CustomContent.ps1) and the hunting query walk in
    Tools/Build-DependencyManifest.ps1.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/HuntingQuery/Read-iSOCHuntingQueryRepo.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    Needs powershell-yaml when it runs. Import-iSOCYamlModule loads it
    then instead of #Requires, so the module imports without it.
#>

# Keeps the file help above from being read as the help of the function below.

function Read-iSOCHuntingQueryRepo {
    <#
    .SYNOPSIS
        Read every hunting query file in the repository.

    .DESCRIPTION
        One item per file, in repository order, read by
        Read-iSOCYamlRepoItem.

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER ContentType
        The hunting query content type.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.RepoItem.

    .EXAMPLE
        Read-iSOCHuntingQueryRepo -RepoPath $repo -ContentType $hunting
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
