#Requires -Version 7.6

<#
.SYNOPSIS
    The strings in a Logic App definition that look like KQL.

.DESCRIPTION
    Only string values, not keys, and only those shaped like a query: a pipe
    then a tabular operator, or a query opening with one.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCPlaybookKqlText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCPlaybookKqlText {
    <#
    .SYNOPSIS
        The strings in a Logic App definition that look like KQL.

    .DESCRIPTION
        The parser chains read only these from a playbook, so an alias used
        as a JSON key or in an action name is not a reference. A string
        counts when it has a pipe followed by a KQL tabular operator, or
        opens with search, find, print, union, range, datatable or
        externaldata: the shape of a Run query action. A query built by
        concatenation, or passed in another form, is not seen. Direct table
        matching still reads the whole definition.

    .PARAMETER Definition
        The workflow's properties.definition.

    .OUTPUTS
        [string[]]

    .EXAMPLE
        Get-iSOCPlaybookKqlText -Definition $logicApp.properties.definition
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowNull()]
        $Definition
    )

    $operators = 'where|project|project-away|project-keep|project-rename|project-reorder|' +
    'summarize|extend|take|limit|count|join|union|parse|parse-where|parse-kv|' +
    'mv-expand|mv-apply|distinct|top|top-nested|order|sort|render|lookup|' +
    'evaluate|make-series|serialize|invoke|sample|search|find|getschema|scan|partition'
    $looksLikeKql = [regex]::new(
        "(\|\s*(?:$operators)(?![A-Za-z0-9_-]))|(^\s*(?:search|find|print|union|range|datatable|externaldata)(?![A-Za-z0-9_-]))",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $found = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Definition) { return @($found) }

    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push($Definition)
    $guard = 0
    while ($stack.Count -gt 0 -and $guard -lt 200000) {
        $guard++
        $node = $stack.Pop()
        if ($null -eq $node) { continue }
        if ($node -is [string]) {
            if ($looksLikeKql.IsMatch($node)) { $found.Add($node) }
            continue
        }
        if ($node -is [System.Collections.IDictionary]) {
            foreach ($v in $node.Values) { $stack.Push($v) }
            continue
        }
        if ($node -is [System.Collections.IEnumerable]) {
            foreach ($v in $node) { $stack.Push($v) }
            continue
        }
        if ($node -is [psobject] -and $node.PSObject.Properties) {
            foreach ($p in $node.PSObject.Properties) { $stack.Push($p.Value) }
        }
    }
    @($found)
}
