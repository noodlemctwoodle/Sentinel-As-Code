#Requires -Version 7.6

<#
.SYNOPSIS
    ToRequest handler for watchlists: the upload deploy sends.

.DESCRIPTION
    Copied from the body builder inside Deploy-CustomWatchlists
    (Deploy/content/Deploy-CustomContent.ps1), unchanged in what it sends
    for every watchlist in the repository. A watchlist.json without a
    description or a provider now gets the defaults the deployer meant to
    give it, where strict mode made the deployer fail the watchlist
    (MIGRATION.md edit E9). Tests/iSOCDeployments/Watchlist.Tests.ps1 runs
    both over every watchlist in Content/Watchlists/ and compares the
    requests.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Watchlist/ConvertTo-iSOCWatchlistRequest.ps1
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

function ConvertTo-iSOCWatchlistRequest {
    <#
    .SYNOPSIS
        Build the watchlist upload for one watchlist folder.

    .DESCRIPTION
        Builds { properties } as Deploy-CustomContent.ps1 does: the rows of
        data.csv are sent inline as Text/Csv from a local file, the
        description defaults to empty and the provider to Custom. This is
        the one ToRequest handler that reads a file: it reads the item's
        data.csv. It sends nothing.

    .PARAMETER Item
        A repository item from Read-iSOCWatchlistRepo that passed
        Test-iSOCWatchlist.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.Request: ContentType, Identity,
        ResourceName (the alias as written) and Body.

    .EXAMPLE
        $request = ConvertTo-iSOCWatchlistRequest -Item $item
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    $metadata = $Item.Data
    $csvContent = Get-Content -LiteralPath $Item.CsvPath -Raw
    $alias = Get-iSOCPropertyValue -InputObject $metadata -Path 'watchlistAlias'
    $description = Get-iSOCPropertyValue -InputObject $metadata -Path 'description'
    $provider = Get-iSOCPropertyValue -InputObject $metadata -Path 'provider'

    [pscustomobject]@{
        PSTypeName   = 'iSOCDeployments.Request'
        ContentType  = $Item.ContentType
        Identity     = $Item.Identity
        ResourceName = [string]$alias
        Body         = @{
            properties = @{
                watchlistAlias      = $alias
                displayName         = Get-iSOCPropertyValue -InputObject $metadata -Path 'displayName'
                description         = if ($description) { $description } else { "" }
                provider            = if ($provider) { $provider } else { "Custom" }
                source              = "Local File"
                sourceType          = "Local"
                itemsSearchKey      = Get-iSOCPropertyValue -InputObject $metadata -Path 'itemsSearchKey'
                contentType         = "Text/Csv"
                rawContent          = $csvContent
                numberOfLinesToSkip = 0
            }
        }
    }
}
