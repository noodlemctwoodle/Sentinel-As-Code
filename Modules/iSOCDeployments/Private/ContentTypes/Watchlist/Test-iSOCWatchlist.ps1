#Requires -Version 7.6

<#
.SYNOPSIS
    Validate handler for watchlists.

.DESCRIPTION
    The checks Deploy-CustomWatchlists (Deploy/content/Deploy-CustomContent.ps1)
    makes before it uploads a watchlist, with the same messages.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Watchlist/Test-iSOCWatchlist.ps1
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

function Test-iSOCWatchlist {
    <#
    .SYNOPSIS
        Say why a watchlist cannot be uploaded, if it cannot.

    .DESCRIPTION
        A watchlist needs watchlist.json and data.csv in its folder, the
        metadata needs watchlistAlias, displayName and itemsSearchKey, and
        the rows must fit the 3.5 MB inline upload. A watchlist that fails
        is skipped by deploy, as it is today; one that is too large is
        uploaded by hand in the portal.

    .PARAMETER Item
        A repository item from Read-iSOCWatchlistRepo.

    .OUTPUTS
        [string] The problem; nothing when the watchlist can be uploaded.

    .EXAMPLE
        $issues = @(Test-iSOCWatchlist -Item $item)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    if (-not (Test-Path -LiteralPath $Item.MetadataPath -PathType Leaf)) { return 'watchlist.json not found.' }
    if (-not (Test-Path -LiteralPath $Item.CsvPath -PathType Leaf)) { return 'data.csv not found.' }
    if ($Item.ParseError) { return $Item.ParseError }

    $metadata = $Item.Data
    $missing = @('watchlistAlias', 'displayName', 'itemsSearchKey' | Where-Object { -not (Get-iSOCPropertyValue -InputObject $metadata -Path $_) })
    if ($missing.Count -gt 0) { return 'watchlist.json missing required fields (watchlistAlias, displayName, itemsSearchKey).' }

    $csvSize = (Get-Item -LiteralPath $Item.CsvPath).Length
    if ($csvSize -gt 3.5MB) {
        return "data.csv exceeds 3.5 MB inline upload limit ($([math]::Round($csvSize / 1MB, 2)) MB). Upload manually via portal."
    }
}
