#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 50-watchlists.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Watchlists/Write-BlueprintWatchlistsSection.ps1
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
function Write-BlueprintWatchlistsSection {
    <#
    .SYNOPSIS
        Build the figures for and write 50-watchlists.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $a = $Context.a
    $m = $Context.m
    $n = $Context.n
    $p = $Context.p
    $rulesByWatchlistAlias = $Context.rulesByWatchlistAlias
    $watchlists = $Context.watchlists

    # Freshness from the shared helper (the gap check SAC-DET-15 reads the
    # same): stale and read by enabled rules first, then stale, current, and
    # the watchlists Content Hub solutions ship.
    $wlFresh = @(Get-WatchlistFreshness -Watchlists @($watchlists) -RuleUse (Get-WatchlistRuleUse -Rules @(Read-BlueprintRawArray 'alert-rules.json')))
    $wlFreshByAlias = @{}
    foreach ($f in $wlFresh) { if ($f.Alias) { $wlFreshByAlias[$f.Alias] = $f } }
    $wlStatusRank = @{ 'Stale, used by rules' = 0; 'Stale' = 1; 'Current' = 2; 'Content Hub' = 3 }
    $wlRows = @($watchlists | Where-Object { $_ -and $_.properties } | ForEach-Object {
            $alias = $_.properties.watchlistAlias
            $f = if ($alias -and $wlFreshByAlias.ContainsKey($alias)) { $wlFreshByAlias[$alias] } else { $null }
            [pscustomobject]@{
                Name            = $_.properties.displayName
                Freshness       = $(if ($f) { $f.Status } else { '' })
                'Age (days)'    = $(if ($f -and $null -ne $f.AgeDays) { $f.AgeDays } else { '' })
                Updated         = Format-DateUtc $_.properties.updated
                'Enabled rules' = $(if ($f) { $f.EnabledRules } else { 0 })
                'Maintained by' = $(if ($f) { $f.MaintainedBy } else { '' })
                'Search key'    = $_.properties.itemsSearchKey
                Provider        = if ($_.properties.provider) { [string]$_.properties.provider } else { '' }
                Description     = if ($_.properties.description) { [string]$_.properties.description } else { '' }
                _Rank           = $(if ($f) { $wlStatusRank[$f.Status] } else { 9 })
                _Age            = $(if ($f -and $null -ne $f.AgeDays) { $f.AgeDays } else { -1 })
            }
        } | Sort-Object _Rank, @{ Expression = '_Age'; Descending = $true }, Name)
    $wlOwn = @($wlFresh | Where-Object MaintainedBy -EQ 'Workspace').Count
    $wlStale = @($wlFresh | Where-Object { $_.Status -like 'Stale*' }).Count
    $wlStaleUsed = @($wlFresh | Where-Object Status -EQ 'Stale, used by rules').Count
    $wlHub = @($wlFresh | Where-Object MaintainedBy -EQ 'Content Hub').Count
    $wlDescRows = @($wlRows | Where-Object { $_.Description } | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Description = $_.Description } })

    # Detailed rule-by-watchlist mapping rendered as a separate subsection.
    # Orphan watchlists (zero rule references) are surfaced explicitly —
    # they may still be used by hunting queries, workbooks, or analyst
    # KQL, but the absence of any analytics-rule reference is a useful
    # signal that the watchlist might be stale.
    $wlUsageRows = New-Object System.Collections.Generic.List[object]
    foreach ($wl in $watchlists) {
        $alias = $wl.properties.watchlistAlias
        if (-not $alias) { continue }
        $ruleNames = if ($rulesByWatchlistAlias.ContainsKey($alias)) { @($rulesByWatchlistAlias[$alias]) } else { @() }
        $wlUsageRows.Add([pscustomobject]@{
                Alias     = $alias
                RuleCount = $ruleNames.Count
                Rules     = if ($ruleNames.Count -gt 0) { ($ruleNames | Sort-Object -Unique) -join '; ' } else { '_(no analytics rule references)_' }
            })
    }

    # Watchlist aliases referenced by rules but NOT present in the captured
    # watchlist set. These are 'broken' references — the rule queries will
    # fail at runtime. Surfaced as a separate subsection only when present.
    $wlAliasSet = @{}
    foreach ($wl in $watchlists) {
        $a = $wl.properties.watchlistAlias
        if ($a) { $wlAliasSet[$a] = $true }
    }
    $brokenWatchlistRefs = New-Object System.Collections.Generic.List[object]
    foreach ($alias in $rulesByWatchlistAlias.Keys) {
        if (-not $wlAliasSet.ContainsKey($alias)) {
            $brokenWatchlistRefs.Add([pscustomobject]@{
                    MissingAlias = $alias
                    RuleCount    = $rulesByWatchlistAlias[$alias].Count
                    Rules        = ($rulesByWatchlistAlias[$alias] | Sort-Object -Unique) -join '; '
                })
        }
    }

    # Watchlists by provider for the headline pie (was "by source", but the
    # source field is just the seed filename so all rows have a different
    # value — useless as a pie distribution). Provider groups by who
    # manages the watchlist (Microsoft vs first-party customer content).
    $wlByProvider = @{}
    foreach ($w in $wlRows) {
        $p = if ($w.Provider) { [string]$w.Provider } else { 'Unknown' }
        if (-not $wlByProvider.ContainsKey($p)) { $wlByProvider[$p] = 0 }
        $wlByProvider[$p]++
    }
    $wlPieRows = $wlByProvider.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | ForEach-Object {
        "    `"$($_.Key)`" : $($_.Value)"
    }

    # Pie only when 2+ provider buckets — single-slice pies are uninformative.
    $wlChartBlock = if ($wlRows.Count -gt 0 -and $wlByProvider.Count -ge 2) {
        @"

## Watchlists by provider

``````mermaid
pie showData title Watchlists by provider
$($wlPieRows -join [Environment]::NewLine)
``````

"@
    } else { '' }

    $brokenRefsBlock = if ($brokenWatchlistRefs.Count -gt 0) {
        @"

## Broken watchlist references

The analytics rules below reference watchlist aliases that don't exist in this workspace. These rule queries will fail at runtime: investigate whether the watchlist was deleted or the alias is mistyped.

$(Format-BlueprintTable -Items $brokenWatchlistRefs -Columns 'MissingAlias','RuleCount','Rules')
"@
    } else { '' }

    Write-BlueprintSection '50-watchlists.md' (@"
$(Format-Banner -Title "Watchlists")
$wlChartBlock
**$(Format-BlueprintPlural $wlRows.Count 'watchlist')**  ·  **$(Format-BlueprintCount $wlOwn)** maintained in the workspace  ·  **$(Format-BlueprintCount $wlStale)** stale (not updated in $(Format-BlueprintPlural $script:WatchlistStaleDays 'day'))  ·  **$(Format-BlueprintCount $wlStaleUsed)** stale and read by enabled rules  ·  **$(Format-BlueprintCount $wlHub)** shipped by Content Hub solutions

A watchlist is reference data (assets, VIPs, allow-lists, IP ranges) that analytics rules and hunting queries look up with ``_GetWatchlist()``, and someone has to keep it current. **Freshness** is Stale when a watchlist maintained in the workspace has not been updated in $(Format-BlueprintPlural $script:WatchlistStaleDays 'day'), and **Stale, used by rules** when an enabled analytics rule still reads it: that rule is detecting against data that may be out of date ([SAC-DET-15]). Watchlists a Content Hub solution ships are its reference data, kept current by updating the solution. Item bodies are not captured; the source of truth for their contents is the IaC repository (``Watchlists/*.csv``).

$(Format-BlueprintTable -Items $wlRows -Columns 'Name','Freshness','Age (days)','Updated','Enabled rules','Maintained by','Search key','Provider')

## Used by analytics rules

Cross-reference of every captured watchlist against every Scheduled / NRT analytics rule's KQL ``query`` field. Each row lists the rules that call ``_GetWatchlist("<alias>")`` against this watchlist. A "_(no analytics rule references)_" row doesn't necessarily mean the watchlist is orphaned (hunting queries, workbooks and ad-hoc KQL aren't scanned), but no rule reference is a useful signal that the watchlist may be stale.

$(Format-BlueprintTable -Items $wlUsageRows -Columns 'Alias','RuleCount','Rules')
$brokenRefsBlock

## Descriptions

$(Format-BlueprintTable -Items $wlDescRows -Columns 'Name','Description' -EmptyMessage '_No watchlist has a description._')

[Microsoft Sentinel watchlists overview (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/watchlists)
[``_GetWatchlist`` function reference (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/watchlists-queries)
"@)

    # Left in the render context for later sections.
    $Context.f = $f
    if (Get-Variable -Name 'p' -Scope 0 -ErrorAction Ignore) { $Context.p = $p }
}
