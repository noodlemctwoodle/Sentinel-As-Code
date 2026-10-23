#Requires -Version 7.2

<#
.SYNOPSIS
    The tables, watchlists, functions and external data a content file depends on.

.DESCRIPTION
    Copied from Get-ContentDependencies in Modules/Sentinel.Common/Sentinel.Common.psm1
    (1.1.1) with the helper names changed and the logic unchanged.
    Tests/iSOCDeployments/Kql.Tests.ps1 holds the two to the same answer
    for every file under Content/.

.NOTES
    File:         Modules/iSOCDeployments/Private/Kql/Get-iSOCContentFileDependency.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCContentFileDependency {
<#
.SYNOPSIS
    Discover the dependencies of a single content file by reading its
    embedded KQL and running every Get-Kql*Reference extractor against it.
    Classifies bare identifiers as either tables or functions, using the
    repo as the source of truth for what is deployable.

.DESCRIPTION
    Repo-driven classification model:

      - In-repo functions (Parsers/) -> 'functions' bucket. These must
        deploy before any rule that references them.
      - Microsoft-provided ASIM functions (matched by regex) -> 'functions'
        bucket. External, but listed for visibility.
      - Everything else at a data-source position -> 'tables' bucket. This
        is the default classification: tables are external (data plane)
        and not deployable from the repo, so we do not need a hard-coded
        catalogue to list them. Custom-log tables (suffix '_CL') fall
        into this bucket as well.

    No 'unclassified' bucket: with the bare-identifier extractor filtering
    let-bound names, lambda parameters, KQL keywords and string literals,
    every remaining identifier is a real data-source reference and is
    correctly modelled as either a function or a table.

.PARAMETER Path
    Absolute or repo-relative path to the YAML/JSON content file.

.PARAMETER KnownFunctions
    Hashtable keyed by function alias (case-insensitive). Built by the
    caller from the repo's Parsers/ folder. Values can be anything; only
    the keys are used.

.PARAMETER ExternalFunctionPattern
    Optional regex pattern for Microsoft-provided ASIM/im function names
    that don't appear in the in-repo Parsers/. Default matches the
    standard ASIM nomenclature.

.OUTPUTS
    Hashtable shaped like a dependencies.json entry - keys: tables,
    watchlists, functions, externalData. Empty arrays for absent buckets.
#>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string]$Path
        ,
        [Parameter()] [hashtable]$KnownFunctions = @{}
        ,
        [Parameter()] [string]$ExternalFunctionPattern = '^(_?ASim|_Im_|im)\w+$'
    )

    $result = @{
        tables       = @()
        watchlists   = @()
        functions    = @()
        externalData = @()
    }

    $query = Get-iSOCContentKqlQuery -Path $Path
    if ([string]::IsNullOrWhiteSpace($query)) { return $result }

    $result.watchlists   = Get-iSOCKqlWatchlistReference -Query $query
    $result.externalData = Get-iSOCKqlExternalDataReference -Query $query

    $bareIdentifiers = Get-iSOCKqlBareIdentifier -Query $query
    $tableSet    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $functionSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($id in $bareIdentifiers) {
        if ($KnownFunctions.ContainsKey($id) -or $id -match $ExternalFunctionPattern) {
            [void]$functionSet.Add($id)
        }
        else {
            # Default: anything at a data-source position that isn't a
            # function is a table. Custom-log tables (_CL suffix) follow
            # the same rule. The bare-identifier extractor is responsible
            # for not handing us false positives (column names, lambda
            # params, keywords); see Get-iSOCKqlBareIdentifier.
            [void]$tableSet.Add($id)
        }
    }

    $result.tables       = @($tableSet       | Sort-Object)
    $result.functions    = @($functionSet    | Sort-Object)
    return $result
}
