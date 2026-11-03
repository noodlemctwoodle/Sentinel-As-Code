#Requires -Version 7.2

<#
.SYNOPSIS
    Read a content type's YAML files as repository items.

.DESCRIPTION
    Analytics rules, hunting queries and parsers are all one YAML file per
    item, named by an id key. Their ReadRepo handlers share this reader, so
    the three types cannot drift apart in how a file becomes an item.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Read-iSOCYamlRepoItem.ps1
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

function Read-iSOCYamlRepoItem {
    <#
    .SYNOPSIS
        Return one repository item per YAML file of a content type.

    .DESCRIPTION
        One item per file, in repository order. A file that does not parse
        is still returned, with ParseError set and no Data, so each caller
        decides what an unreadable file means. A file under a Community
        folder is marked Source Community; the folder is matched in the
        repository-relative path (MIGRATION.md edit E5). The item is named
        by the type's IdentityKey, in lower case, and its Name is the file's
        name key, or the file name when the key is missing.

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER ContentType
        The content type.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.RepoItem: ContentType, Identity,
        Name, Path, RelativePath, Source (Custom or Community), Data (the
        parsed YAML) and ParseError.

    .EXAMPLE
        Read-iSOCYamlRepoItem -RepoPath $repo -ContentType $parsers
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath,

        [Parameter(Mandatory)]
        [psobject] $ContentType
    )

    $key = [string]$ContentType.IdentityKey
    foreach ($file in Get-iSOCContentFile -RepoPath $RepoPath -ContentType $ContentType) {
        $relative = ConvertTo-iSOCRepoRelativePath -Path $file.FullName -RepoPath $RepoPath
        $data = $null
        $parseError = $null
        try { $data = Read-iSOCYamlFile -Path $file.FullName }
        catch { $parseError = $_.Exception.Message }

        $isMapping = $data -is [System.Collections.IDictionary]
        $id = if ($isMapping -and $data.Contains($key) -and -not [string]::IsNullOrWhiteSpace([string]$data[$key])) { [string]$data[$key] } else { $null }
        $name = if ($isMapping -and $data.Contains('name') -and -not [string]::IsNullOrWhiteSpace([string]$data['name'])) { [string]$data['name'] } else { $file.BaseName }

        [pscustomobject]@{
            PSTypeName   = 'iSOCDeployments.RepoItem'
            ContentType  = $ContentType.Name
            Identity     = if ($id) { $id.ToLowerInvariant() } else { $null }
            Name         = $name
            Path         = $file.FullName
            RelativePath = $relative
            Source       = if ($relative -match '(^|/)Community/') { 'Community' } else { 'Custom' }
            Data         = $data
            ParseError   = $parseError
        }
    }
}
