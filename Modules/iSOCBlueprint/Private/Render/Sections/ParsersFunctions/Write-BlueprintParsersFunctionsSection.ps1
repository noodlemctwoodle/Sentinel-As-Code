#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 35-parsers-functions.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/ParsersFunctions/Write-BlueprintParsersFunctionsSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintParsersFunctionsSection {
    <#
    .SYNOPSIS
        Build the figures for and write 35-parsers-functions.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $c = $Context.c
    $cat = $Context.cat
    $m = $Context.m
    $n = $Context.n
    $parsers = $Context.parsers
    $q = $Context.q

    $parserRows = $parsers | ForEach-Object {
        [pscustomobject]@{
            Name = $_.properties.displayName
            Alias = $_.properties.functionAlias
            Category = $_.properties.category
        }
    }

    # Pie of parsers/functions by category.
    $parserByCat = @{}
    foreach ($p in $parserRows) {
        $c = if ($p.Category) { [string]$p.Category } else { 'Uncategorised' }
        if (-not $parserByCat.ContainsKey($c)) { $parserByCat[$c] = 0 }
        $parserByCat[$c]++
    }
    $parserPieRows = Format-PieSlices -Counts $parserByCat -Limit 8
    $parserChartBlock = if ($parserRows.Count -gt 0 -and $parserPieRows.Count -gt 0) {
        @"

## Parsers by category

``````mermaid
pie showData title Parsers and functions by category
$($parserPieRows -join [Environment]::NewLine)
``````

$(Format-BlueprintPlural $parserRows.Count 'parser or function' 'parsers and functions'). Each entry is a `let`-style KQL definition reusable across rules and hunting queries.
"@
    } else { '' }

    # Saved searches that are neither hunting queries nor parsers: queries
    # saved from Logs under categories such as Log Management.
    $otherSavedRows = @(Read-BlueprintRawArray 'kql-savedsearches.json' | Where-Object { $_ } | ForEach-Object {
        $p = Get-BlueprintRawProperty $_ 'properties'
        $cat = [string](Get-BlueprintRawProperty $p 'category' '')
        if ($cat -eq 'Hunting Queries' -or $cat -eq 'Functions' -or [string](Get-BlueprintRawProperty $p 'functionAlias' '')) { return }
        $q = [string](Get-BlueprintRawProperty $p 'query' '')
        [pscustomobject]@{
            Category   = $(if ($cat) { $cat } else { 'Uncategorised' })
            Name       = [string](Get-BlueprintRawProperty $p 'displayName' (Get-BlueprintRawProperty $_ 'name' ''))
            QueryLines = $(if ($q) { @($q -split "\r?\n").Count } else { 0 })
        }
    } | Sort-Object Category, Name)

    Write-BlueprintSection '35-parsers-functions.md' (@"
$(Format-Banner -Title "Parsers and Functions")
$parserChartBlock

$(Format-BlueprintTable -Items $parserRows -Columns 'Name','Alias','Category')

## Other saved searches

Saved searches in the workspace that are neither hunting queries ([30-hunting-queries.md](30-hunting-queries.md)) nor parsers: queries saved from Logs under categories such as Log Management or General Exploration. Ones nobody owns are clutter; the ones worth keeping belong in source control as hunting queries or functions.

$(Format-BlueprintTable -Items $otherSavedRows -Columns 'Category','Name','QueryLines' -EmptyMessage (Get-BlueprintEmptyMessage 'kql-savedsearches.json' '_None: every saved search is a hunting query or a parser._'))
"@)

    # Left in the render context for later sections.
    if (Get-Variable -Name 'c' -Scope 0 -ErrorAction Ignore) { $Context.c = $c }
    $Context.p = $p
}
