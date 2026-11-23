#Requires -Version 7.6

<#
.SYNOPSIS
    How fresh each watchlist is, and whether a stale one is still read by
    an enabled analytics rule.

.DESCRIPTION
    A watchlist is reference data (assets, VIPs, allow-lists, IP ranges)
    that someone has to keep current; one that has not changed in months
    is usually out of date, and a rule that reads it detects against old
    data without saying so. Watchlists a Content Hub solution ships are
    the solution's reference data, kept current by updating the solution,
    so they are labelled Content Hub rather than judged by age.

    A watchlist you maintain is Current when updated in the last
    WatchlistStaleDays (90) days and Stale otherwise; Stale, used by rules
    when an enabled analytics rule reads it through _GetWatchlist().

    The renderer's watchlists page and the gap check SAC-DET-15 read
    this, so the two agree.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Get-WatchlistFreshness.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.2
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-WatchlistFreshness {
    <#
    .SYNOPSIS
        One row per watchlist: Name, Alias, MaintainedBy (Content Hub or
        Workspace), Updated, AgeDays, EnabledRules (how many enabled rules
        read it) and Status (Content Hub, Current, Stale, or Stale, used by
        rules).

    .PARAMETER Watchlists
        watchlists.json objects.

    .PARAMETER RuleUse
        From Get-WatchlistRuleUse.

    .PARAMETER Now
        The time to measure age from; the current UTC time by default.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()] [AllowEmptyCollection()] [object[]] $Watchlists,
        [AllowNull()] [hashtable] $RuleUse,
        [datetime] $Now = (Get-Date).ToUniversalTime()
    )

    foreach ($w in @($Watchlists)) {
        if (-not $w -or -not $w.properties) { continue }
        $p = $w.properties
        $prop = { param($n) if ($p.PSObject.Properties.Name -contains $n -and $null -ne $p.$n) { $p.$n } else { $null } }
        $alias = [string](& $prop 'watchlistAlias')
        $source = [string](& $prop 'source')
        $updatedRaw = & $prop 'updated'
        $updated = $null
        if ($updatedRaw) { try { $updated = ([datetime]$updatedRaw).ToUniversalTime() } catch { $updated = $null } }
        $age = if ($updated) { [int][math]::Floor(($Now - $updated).TotalDays) } else { $null }
        $rules = if ($RuleUse -and $alias -and $RuleUse.ContainsKey($alias.ToLowerInvariant())) { @($RuleUse[$alias.ToLowerInvariant()]).Count } else { 0 }
        $contentHub = $source -eq 'ContentHub'
        $status = if ($contentHub) { 'Content Hub' }
            elseif ($null -eq $age -or $age -lt $script:WatchlistStaleDays) { 'Current' }
            elseif ($rules -gt 0) { 'Stale, used by rules' }
            else { 'Stale' }
        [pscustomobject]@{
            Name         = [string](& $prop 'displayName')
            Alias        = $alias
            MaintainedBy = $(if ($contentHub) { 'Content Hub' } else { 'Workspace' })
            Updated      = $updated
            AgeDays      = $age
            EnabledRules = $rules
            Status       = $status
        }
    }
}
