#Requires -Version 7.2

<#
.SYNOPSIS
    The parser alias names that cannot be resolved by name alone.

.DESCRIPTION
    KQL keywords, operators, literals and type names, the scoping functions
    and the columns every Log Analytics table has.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCReservedAliasName.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCReservedAliasName {
    <#
    .SYNOPSIS
        The parser alias names that cannot be resolved by name alone.

    .DESCRIPTION
        A parser's alias is followed as though it were a table name, so an
        alias that appears in code position in nearly every query says
        nothing about a real dependency:

          - KQL keywords, tabular operators, literals and type names; KQL
            needs such a name bracket-quoted at every use anyway
          - the scoping functions cluster, database, workspace and app,
            which name something outside the workspace
          - the columns every Log Analytics table has

        A name clashing with a real table or column is caught by
        Get-iSOCFunctionAliasSafety instead, from the workspace's own
        tables. Names are lower case and compared without case. Only the
        parser chains are affected; direct table matching is not.

    .OUTPUTS
        [string[]]

    .EXAMPLE
        (Get-iSOCReservedAliasName) -contains 'where'
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    @(
        'and', 'asc', 'between', 'bool', 'by', 'consume', 'contains', 'count',
        'datatable', 'datetime', 'decimal', 'desc', 'distinct', 'dynamic',
        'endswith', 'evaluate', 'extend', 'externaldata', 'facet', 'false',
        'find', 'fork', 'getschema', 'guid', 'has', 'in', 'int', 'invoke', 'join',
        'let', 'limit', 'long', 'lookup', 'matches', 'materialize', 'mvexpand',
        'not', 'null', 'on', 'or', 'order', 'parse', 'partition', 'print',
        'project', 'query', 'range', 'real', 'reduce', 'render', 'restrict',
        'sample', 'scan', 'search', 'serialize', 'set', 'sort', 'source',
        'startswith', 'string', 'summarize', 'take', 'timespan', 'top',
        'toscalar', 'true', 'union', 'view', 'where',
        'app', 'cluster', 'database', 'workspace',
        'timegenerated', 'tenantid', 'sourcesystem', 'type', 'computer',
        'rawdata', 'managementgroupname'
    )
}
