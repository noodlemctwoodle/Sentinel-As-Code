#Requires -Version 7.6

<#
.SYNOPSIS
    The functions and watchlists the repository can deploy, by alias.

.DESCRIPTION
    Replaces the inventory at the top of Tools/Build-DependencyManifest.ps1.
    The parsers and watchlists are read through the content type registry,
    so the manifest sees the same files deploy does: .yml parsers as well as
    .yaml, and only the watchlist folders deploy reads. The playbook
    inventory the script built and never used is gone (MIGRATION.md edit
    E8).

.NOTES
    File:         Modules/iSOCDeployments/Private/Manifest/Get-iSOCDependencyInventory.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    Needs powershell-yaml when it runs. Import-iSOCYamlModule loads it
    then instead of #Requires, so the module imports without it.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCDependencyInventory {
    <#
    .SYNOPSIS
        Map every parser's function alias and every watchlist's alias to
        the file that defines it.

    .DESCRIPTION
        A query that calls a function in Functions depends on that parser
        deploying first; a watchlist it reads that is not in Watchlists will
        fail at deploy unless it is created another way. Files that do not
        parse are left out; their own schema suites report them. Keys
        compare without regard to case.

    .PARAMETER RepoPath
        The repository root.

    .OUTPUTS
        [pscustomobject] Functions and Watchlists, each a hashtable of alias
        to repository-relative path.

    .EXAMPLE
        $inventory = Get-iSOCDependencyInventory -RepoPath $repo
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath
    )

    $functions = @{}
    $parsers = Get-iSOCContentTypeDefinition -Name Parser
    foreach ($item in Invoke-iSOCContentTypeHandler -ContentType $parsers -Handler ReadRepo -Parameters @{ RepoPath = $RepoPath; ContentType = $parsers }) {
        $data = $item.Data
        if ($data -is [System.Collections.IDictionary] -and $data.Contains('functionAlias') -and $data['functionAlias']) {
            $functions[[string]$data['functionAlias']] = $item.RelativePath
        }
    }

    $watchlists = @{}
    $type = Get-iSOCContentTypeDefinition -Name Watchlist
    foreach ($item in Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $RepoPath; ContentType = $type }) {
        if ($item.Data -and $item.Data.PSObject.Properties['watchlistAlias']) {
            $watchlists[[string]$item.Data.watchlistAlias] = $item.RelativePath
        }
    }

    [pscustomobject]@{
        Functions  = $functions
        Watchlists = $watchlists
    }
}
