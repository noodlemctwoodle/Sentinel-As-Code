#Requires -Version 7.2

<#
.SYNOPSIS
    The tables, watchlists, functions and external data a KQL query
    depends on.

.DESCRIPTION
    The classification half of Get-ContentDependencies in
    Modules/Sentinel.Common/Sentinel.Common.psm1 (1.1.1), unchanged: that
    function read a file's query and classified it in one step. Reading is
    now each content type's GetQuery handler, or Get-iSOCContentKqlQuery for
    a file of any type, so the dependency manifest can walk the content
    type registry. Its answer for every file under Content/ was held to the original's on
    release/26.11.0, until Sentinel.Common was removed;
    Tests/iSOCDeployments/Kql.Tests.ps1 now holds it to the answers the
    original gave.

.NOTES
    File:         Modules/iSOCDeployments/Private/Kql/Get-iSOCQueryDependency.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-05
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCQueryDependency {
    <#
    .SYNOPSIS
        Classify what a query reads from.

    .DESCRIPTION
        Watchlists come from _GetWatchlist('alias') calls and external data
        from externaldata(...) [...] URL lists. Bare identifiers at
        data-source positions are functions when the repository defines them
        (KnownFunctions) or they follow the ASIM naming, and tables
        otherwise: tables are data, not deployable from the repository, so
        no catalogue of them is needed. Custom log tables (_CL) are tables
        like any other. There is no unclassified bucket.

    .PARAMETER Query
        The KQL. An empty query has no dependencies.

    .PARAMETER KnownFunctions
        The repository's function aliases, as hashtable keys (compared
        without regard to case); the values are not used.

    .PARAMETER ExternalFunctionPattern
        The names of Microsoft-provided functions that are not in the
        repository. Defaults to the ASIM naming.

    .OUTPUTS
        [hashtable] tables, watchlists, functions and externalData, each a
        sorted array, empty when there are none.

    .EXAMPLE
        Get-iSOCQueryDependency -Query $kql -KnownFunctions $inventory.Functions
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Query,

        [hashtable] $KnownFunctions = @{},

        [string] $ExternalFunctionPattern = '^(_?ASim|_Im_|im)\w+$'
    )

    $result = @{
        tables       = @()
        watchlists   = @()
        functions    = @()
        externalData = @()
    }

    if ([string]::IsNullOrWhiteSpace($Query)) { return $result }

    $result.watchlists   = Get-iSOCKqlWatchlistReference -Query $Query
    $result.externalData = Get-iSOCKqlExternalDataReference -Query $Query

    $bareIdentifiers = Get-iSOCKqlBareIdentifier -Query $Query
    $tableSet    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $functionSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($id in $bareIdentifiers) {
        if ($KnownFunctions.ContainsKey($id) -or $id -match $ExternalFunctionPattern) {
            [void]$functionSet.Add($id)
        }
        else {
            [void]$tableSet.Add($id)
        }
    }

    $result.tables    = @($tableSet    | Sort-Object)
    $result.functions = @($functionSet | Sort-Object)
    return $result
}
