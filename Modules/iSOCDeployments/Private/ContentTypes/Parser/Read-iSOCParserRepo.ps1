#Requires -Version 7.2

<#
.SYNOPSIS
    ReadRepo handler for parsers.

.DESCRIPTION
    Replaces the reader in Deploy-CustomParsers
    (Deploy/content/Deploy-CustomContent.ps1) and the parser inventory in
    Tools/Build-DependencyManifest.ps1.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Parser/Read-iSOCParserRepo.ps1
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

function Read-iSOCParserRepo {
    <#
    .SYNOPSIS
        Read every parser file in the repository.

    .DESCRIPTION
        One item per file, in repository order, read by
        Read-iSOCYamlRepoItem. The parser's function alias is in
        Data['functionAlias'].

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER ContentType
        The parser content type.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.RepoItem.

    .EXAMPLE
        Read-iSOCParserRepo -RepoPath $repo -ContentType $parsers
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
