#Requires -Version 7.6

<#
.SYNOPSIS
    Get-iSOCContentDependency: what a content file's KQL depends on.

.DESCRIPTION
    Replaces Get-ContentDependencies from Modules/Sentinel.Common, which
    took the function lookup from its caller; this command builds it from
    the repository's parsers itself.

.NOTES
    File:         Modules/iSOCDeployments/Public/Get-iSOCContentDependency.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCContentDependency {
    <#
    .SYNOPSIS
        List the tables, watchlists, functions and external data a content
        file's query reads.

    .DESCRIPTION
        Reads the KQL embedded in an analytics rule, hunting query, parser,
        summary rule or Defender custom detection (the query, or
        queryCondition.queryText) and classifies what it reads: watchlists
        from _GetWatchlist calls, URLs from externaldata, and every
        identifier at a data-source position as a function, when a parser
        in the repository defines it or it follows the ASIM naming, or a
        table otherwise. A file without a query depends on nothing.

    .PARAMETER Path
        One or more content files, absolute or relative to the current
        folder. Takes pipeline input, including the files Get-ChildItem
        returns.

    .PARAMETER RepoPath
        The repository whose parsers define the known functions. Defaults
        to the repository the current folder is in.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.ContentDependency, one per file:
        Path (repository-relative), Tables, Watchlists, Functions and
        ExternalData.

    .EXAMPLE
        Get-iSOCContentDependency -Path Content/AnalyticalRules/MicrosoftEntraID/AuthenticationAttemptNewCountryDetectionRule.yaml

        Lists what one rule reads.

    .EXAMPLE
        Get-ChildItem Content/HuntingQueries -Recurse -Filter *.yaml | Get-iSOCContentDependency | Where-Object Watchlists

        Lists the hunting queries that read a watchlist.
    #>
    [CmdletBinding()]
    [OutputType('iSOCDeployments.ContentDependency')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]] $Path,

        [string] $RepoPath
    )

    begin {
        Assert-iSOCPrerequisite -Step Read
        $repo = Resolve-iSOCRepoPath -RepoPath $RepoPath
        $functions = (Get-iSOCDependencyInventory -RepoPath $repo).Functions
        $here = (Get-Location).ProviderPath
    }

    process {
        foreach ($p in $Path) {
            $full = [System.IO.Path]::GetFullPath($p, $here)
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Content file '$p' was not found." }
            $deps = Get-iSOCQueryDependency -Query (Get-iSOCContentKqlQuery -Path $full) -KnownFunctions $functions
            [pscustomobject]@{
                PSTypeName   = 'iSOCDeployments.ContentDependency'
                Path         = ConvertTo-iSOCRepoRelativePath -Path $full -RepoPath $repo
                Tables       = @($deps.tables | Where-Object { $null -ne $_ })
                Watchlists   = @($deps.watchlists | Where-Object { $null -ne $_ })
                Functions    = @($deps.functions | Where-Object { $null -ne $_ })
                ExternalData = @($deps.externalData | Where-Object { $null -ne $_ })
            }
        }
    }
}
