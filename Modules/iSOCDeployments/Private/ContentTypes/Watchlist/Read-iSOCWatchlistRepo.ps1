#Requires -Version 7.2

<#
.SYNOPSIS
    ReadRepo handler for watchlists.

.DESCRIPTION
    Replaces the reader in Deploy-CustomWatchlists
    (Deploy/content/Deploy-CustomContent.ps1) and the watchlist inventory in
    Tools/Build-DependencyManifest.ps1.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Watchlist/Read-iSOCWatchlistRepo.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Read-iSOCWatchlistRepo {
    <#
    .SYNOPSIS
        Read every watchlist folder in the repository.

    .DESCRIPTION
        One item per folder directly under Content/Watchlists/, in
        repository order. Data is the parsed watchlist.json. A folder
        without one is returned with no Data, and one whose watchlist.json
        does not parse with ParseError set, so deploy can skip the first and
        fail the second as it does today. The rows are not read
        here: MetadataPath and CsvPath name the two files, and ToRequest
        reads the rows when it builds the upload.

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER ContentType
        The watchlist content type.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.RepoItem: ContentType, Identity (the
        alias in lower case, or nothing), Name, Path (the folder),
        RelativePath, Source, Data, ParseError, MetadataPath, CsvPath and
        Files (the two).

    .EXAMPLE
        Read-iSOCWatchlistRepo -RepoPath $repo -ContentType $watchlists
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath,

        [Parameter(Mandatory)]
        [psobject] $ContentType
    )

    foreach ($folder in Get-iSOCContentFile -RepoPath $RepoPath -ContentType $ContentType) {
        $metadataPath = Join-Path $folder.FullName 'watchlist.json'
        $csvPath = Join-Path $folder.FullName 'data.csv'
        $data = $null
        $parseError = $null
        if (Test-Path -LiteralPath $metadataPath -PathType Leaf) {
            try { $data = Get-Content -LiteralPath $metadataPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
            catch { $parseError = "watchlist.json does not parse: $($_.Exception.Message)" }
        }

        $alias = [string](Get-iSOCPropertyValue -InputObject $data -Path 'watchlistAlias')
        $displayName = [string](Get-iSOCPropertyValue -InputObject $data -Path 'displayName')

        [pscustomobject]@{
            PSTypeName   = 'iSOCDeployments.RepoItem'
            ContentType  = $ContentType.Name
            Identity     = if ($alias) { $alias.ToLowerInvariant() } else { $null }
            Name         = if ($displayName) { $displayName } else { $folder.Name }
            Path         = $folder.FullName
            RelativePath = ConvertTo-iSOCRepoRelativePath -Path $folder.FullName -RepoPath $RepoPath
            Source       = 'Custom'
            Data         = $data
            ParseError   = $parseError
            MetadataPath = $metadataPath
            CsvPath      = $csvPath
            Files        = @($metadataPath, $csvPath)
        }
    }
}
