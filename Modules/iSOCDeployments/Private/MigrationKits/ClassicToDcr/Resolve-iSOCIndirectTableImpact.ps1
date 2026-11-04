#Requires -Version 7.2

<#
.SYNOPSIS
    Walk out from a classic table along parser aliases to the content that reaches it only through parsers.

.DESCRIPTION
    Breadth first from the aliases of the parsers that read the table
    directly; each level follows the aliases the last one reached.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Resolve-iSOCIndirectTableImpact.ps1
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

function Resolve-iSOCIndirectTableImpact {
    <#
    .SYNOPSIS
        Walk out from a classic table along parser aliases to the content
        that reaches it only through parsers.

    .DESCRIPTION
        Breadth first, starting from the aliases of the parsers that read
        the table directly, so the start can never disagree with the direct
        result; each level follows the aliases the last one reached.

          - an item already a direct dependent is not repeated
          - a parser is never a dependent of its own alias, and two parsers
            with one alias never depend on each other
          - the first visit wins, which also ends alias cycles
          - -MaxDepth bounds the chain; the walk ends without it, so
            reaching it means a deeper chain exists, and ChainTruncated says
            so

        A parser that reads the table, or is reached through a chain, whose
        own alias cannot be followed is an unresolved bridge: what calls it
        breaks too but cannot be listed, so it is reported with the reason
        and the content that names the alias. Aliases are compared
        ordinally and resource ids without case. Lists are sorted by depth,
        name and resource id, so the same input always gives the same
        report.

    .PARAMETER TableName
        The classic table.

    .PARAMETER Index
        The alias index, from Get-iSOCParserAliasIndex.

    .PARAMETER DirectImpact
        The table's direct dependents, by content type.

    .PARAMETER MaxDepth
        The most parser hops followed. Default 10.

    .OUTPUTS
        [pscustomobject] IndirectAnalyticsRules, IndirectHuntingQueries,
        IndirectParsers, IndirectSavedSearches, IndirectWorkbooks,
        IndirectPlaybooks, IndirectDcrs, TotalIndirect, ChainTruncated and
        UnresolvedBridges.

    .EXAMPLE
        Resolve-iSOCIndirectTableImpact -TableName MyApp_CL -Index $index -DirectImpact $direct
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $TableName,

        [Parameter(Mandatory)]
        $Index,

        [Parameter(Mandatory)]
        $DirectImpact,

        [int] $MaxDepth = 10
    )

    $aliasCmp = [System.StringComparer]::Ordinal
    $idCmp = [System.StringComparer]::OrdinalIgnoreCase
    $types = @('AnalyticsRules', 'HuntingQueries', 'Parsers', 'SavedSearches', 'Workbooks', 'Playbooks', 'Dcrs')

    $hits = [System.Collections.Generic.List[object]]::new()
    $truncated = $false
    $nodes = @($Index.Nodes)
    $severed = [System.Collections.Generic.List[object]]::new()
    $seenSever = [System.Collections.Generic.HashSet[string]]::new($aliasCmp)
    $skipByName = [System.Collections.Generic.Dictionary[string, object]]::new($aliasCmp)
    foreach ($s in @($Index.SkippedAliases)) {
        if ($s.Alias) { $skipByName[[string]$s.Alias] = $s }
    }

    if ($nodes.Count -gt 0) {
        $claimed = [System.Collections.Generic.HashSet[string]]::new($idCmp)
        foreach ($type in $types) {
            foreach ($item in @($DirectImpact.$type)) {
                [void]$claimed.Add("$type|$($item.ResourceId)|$($item.Name)")
            }
        }

        $visited = [System.Collections.Generic.HashSet[int]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new($aliasCmp)
        $chainOf = [System.Collections.Generic.Dictionary[string, object]]::new($aliasCmp)
        [void]$seen.Add($TableName)

        $recordSevered = {
            param([string] $Alias, [string] $ParserName, [string[]] $Chain)
            if (-not $Alias) { return }
            if (-not $seenSever.Add($Alias)) { return }
            $info = if ($skipByName.ContainsKey($Alias)) { $skipByName[$Alias] } else { $null }
            $severed.Add([pscustomobject]@{
                    Alias          = $Alias
                    Parser         = $ParserName
                    Reason         = if ($info) { $info.Reason } else { 'alias is not in the resolvable set' }
                    ReferenceCount = if ($info) { [int]$info.ReferenceCount } else { 0 }
                    Dependents     = if ($info) { @($info.Dependents) } else { @() }
                    ViaChain       = [string[]]@($Chain)
                })
        }

        $frontier = [System.Collections.Generic.List[string]]::new()
        foreach ($p in @($DirectImpact.Parsers)) {
            if (-not $p.FunctionAlias) { continue }
            $alias = ([string]$p.FunctionAlias).Trim()
            if (-not $Index.References.ContainsKey($alias)) {
                & $recordSevered $alias ([string]$p.Name) ([string[]]@())
                continue
            }
            if ($seen.Add($alias)) {
                $chainOf[$alias] = [string[]]@($alias)
                $frontier.Add($alias)
            }
        }

        $depth = 0
        while ($frontier.Count -gt 0) {
            if ($depth -ge $MaxDepth) { $truncated = $true; break }
            $depth++

            $terms = [string[]]@($frontier)
            if ($terms.Count -gt 1) { [array]::Sort($terms, [System.StringComparer]::Ordinal) }
            $next = [System.Collections.Generic.List[string]]::new()

            foreach ($term in $terms) {
                $postings = $Index.References[$term]
                if ($null -eq $postings -or $postings.Count -eq 0) { continue }
                $providerIds = $null
                if ($Index.ProviderIds.ContainsKey($term)) { $providerIds = $Index.ProviderIds[$term] }
                $via = [string[]]@($chainOf[$term])

                foreach ($id in $postings) {
                    if ($null -ne $providerIds -and $providerIds.Contains($id)) { continue }
                    $node = $nodes[$id]
                    if ($claimed.Contains("$($node.Type)|$($node.ResourceId)|$($node.Name)")) { continue }
                    if (-not $visited.Add($id)) { continue }

                    $hits.Add([pscustomobject]@{ Node = $node; Via = $via; Term = $term })

                    if ($node.Alias -and $Index.References.ContainsKey($node.Alias) -and $seen.Add($node.Alias)) {
                        $chainOf[$node.Alias] = [string[]](@($node.Alias) + @($via))
                        $next.Add($node.Alias)
                    }
                    elseif (-not $node.Alias -and $node.RawAlias) {
                        & $recordSevered ([string]$node.RawAlias) ([string]$node.Name) $via
                    }
                }
            }
            $frontier = $next
        }
    }

    $byType = @{}
    foreach ($type in $types) { $byType[$type] = [System.Collections.Generic.List[object]]::new() }

    foreach ($hit in $hits) {
        $node = $hit.Node
        $chain = [string[]]@($hit.Via)
        $item = [ordered]@{ Name = $node.Name }
        switch ($node.Type) {
            'AnalyticsRules' { $item['Enabled'] = $node.Enabled; $item['Severity'] = $node.Severity }
            'HuntingQueries' { $item['Category'] = $node.Category }
            'Parsers' { $item['FunctionAlias'] = $node.Alias }
            'SavedSearches' { $item['Category'] = $node.Category }
            'Workbooks' { $item['QueryCount'] = $node.MatchCounts[$hit.Term] }
            'Playbooks' { $item['State'] = $node.State }
        }
        $item['ResourceId'] = $node.ResourceId
        $item['DependencyKind'] = 'Indirect'
        $item['Via'] = $chain[0]
        $item['ViaChain'] = $chain
        $item['Depth'] = $chain.Count
        $byType[$node.Type].Add([pscustomobject]$item)
    }

    $ordering = [System.Comparison[object]] {
        param($a, $b)
        $c = [int]$a.Depth - [int]$b.Depth
        if ($c -ne 0) { return $c }
        $c = [System.StringComparer]::OrdinalIgnoreCase.Compare([string]$a.Name, [string]$b.Name)
        if ($c -ne 0) { return $c }
        [System.StringComparer]::Ordinal.Compare([string]$a.ResourceId, [string]$b.ResourceId)
    }

    $result = [ordered]@{}
    $total = 0
    foreach ($type in $types) {
        $list = [object[]]@($byType[$type])
        if ($list.Count -gt 1) { [array]::Sort($list, $ordering) }
        $result["Indirect$type"] = @($list)
        $total += $list.Count
    }

    $severedList = [object[]]@($severed)
    if ($severedList.Count -gt 1) {
        [array]::Sort($severedList, [System.Comparison[object]] {
                param($a, $b)
                [System.StringComparer]::Ordinal.Compare([string]$a.Alias, [string]$b.Alias)
            })
    }

    $result['TotalIndirect'] = $total
    $result['ChainTruncated'] = $truncated
    $result['UnresolvedBridges'] = @($severedList)

    [pscustomobject]$result
}
