#Requires -Version 7.6

<#
.SYNOPSIS
    The watchlist content type: one folder per watchlist, with its metadata
    and its rows.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Watchlist/Get-iSOCWatchlistDefinition.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    Docs/Modules/iSOCDeployments/Architecture.md describes every key of a
    content type definition.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCWatchlistDefinition {
    <#
    .SYNOPSIS
        Return the watchlist definition.

    .DESCRIPTION
        Each folder directly under Content/Watchlists/ is one watchlist:
        watchlist.json holds the metadata and data.csv the rows, uploaded
        inline. A watchlist is named in the workspace by its alias, and
        deploys after the parsers and before the rules that read it; when
        any watchlist was uploaded, deploy waits 30 seconds for Sentinel to
        index the new columns before the rules that query them, as
        Deploy-CustomContent.ps1 does. One whose dependencies are missing is
        skipped.

    .OUTPUTS
        [hashtable] The definition.

    .EXAMPLE
        Get-iSOCWatchlistDefinition
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Name              = 'Watchlist'
        DisplayName       = 'Watchlists'
        RepoFolder        = 'Content/Watchlists'
        Layout            = 'Folder'
        Format            = 'Json'
        FilePattern       = @('watchlist.json')
        Recurse           = $false
        Endpoint          = 'Arm'
        Scope             = 'Workspace'
        CollectionPath    = '/providers/Microsoft.SecurityInsights/watchlists'
        ApiVersion        = 'SecurityInsights'
        IdentityKey       = 'watchlistAlias'
        DeployOrder       = 20
        SettleSeconds     = 30
        MissingDependency = 'Skip'
        Capabilities      = @('Deploy')
        Prerequisites     = @()
        Handlers          = @{
            ReadRepo  = 'Read-iSOCWatchlistRepo'
            Validate  = 'Test-iSOCWatchlist'
            ToRequest = 'ConvertTo-iSOCWatchlistRequest'
        }
        Fields            = @(
            @{ Name = 'properties.displayName'; Comparer = 'Exact' }
            @{ Name = 'properties.description'; Comparer = 'Whitespace' }
            @{ Name = 'properties.provider'; Comparer = 'Exact' }
            @{ Name = 'properties.itemsSearchKey'; Comparer = 'CaseInsensitive' }
        )
    }
}
