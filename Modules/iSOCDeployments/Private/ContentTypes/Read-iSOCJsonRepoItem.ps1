#Requires -Version 7.6

<#
.SYNOPSIS
    Read a content type's JSON files as repository items.

.DESCRIPTION
    Automation rules, summary rules and playbooks are one JSON file per
    item. Their ReadRepo handlers share this reader, as the YAML types share
    Read-iSOCYamlRepoItem.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Read-iSOCJsonRepoItem.ps1
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

function Read-iSOCJsonRepoItem {
    <#
    .SYNOPSIS
        Return one repository item per JSON file of a content type.

    .DESCRIPTION
        One item per file, in repository order, optionally filtered. A file
        that does not parse is still returned, with ParseError set and no
        Data. The item is named by the type's IdentityKey, in lower case,
        and its Name is the file's displayName, else its name, else the file
        name.

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER ContentType
        The content type.

    .PARAMETER Filter
        Keeps only the files for which it returns true; it receives the
        FileInfo.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.RepoItem: ContentType, Identity,
        Name, Path, RelativePath, Source, Data (the parsed JSON) and
        ParseError.

    .EXAMPLE
        Read-iSOCJsonRepoItem -RepoPath $repo -ContentType $automationRules
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath,

        [Parameter(Mandatory)]
        [psobject] $ContentType,

        [scriptblock] $Filter = { $true }
    )

    $key = [string]$ContentType.IdentityKey
    foreach ($file in Get-iSOCContentFile -RepoPath $RepoPath -ContentType $ContentType) {
        if (-not (& $Filter $file)) { continue }
        $relative = ConvertTo-iSOCRepoRelativePath -Path $file.FullName -RepoPath $RepoPath
        $data = $null
        $parseError = $null
        try { $data = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
        catch { $parseError = "the JSON does not parse: $($_.Exception.Message)" }

        $id = [string](Get-iSOCPropertyValue -InputObject $data -Path $key)
        $name = [string](Get-iSOCPropertyValue -InputObject $data -Path 'displayName')
        if (-not $name) { $name = [string](Get-iSOCPropertyValue -InputObject $data -Path 'name') }
        if (-not $name) { $name = $file.BaseName }

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
