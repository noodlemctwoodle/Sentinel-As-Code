#Requires -Version 7.6

<#
.SYNOPSIS
    Watchlist alias to the enabled analytics rules that read it through _GetWatchlist('alias') in...

.DESCRIPTION
    One of the helpers beside Get-WatchlistFreshness.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Get-WatchlistRuleUse.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-WatchlistRuleUse {
    <#
    .SYNOPSIS
        Watchlist alias to the enabled analytics rules that read it through
        _GetWatchlist('alias') in their query.

    .PARAMETER Rules
        alertRules objects as the collector saves them.

    .OUTPUTS
        [hashtable] Alias, lower-case, to an array of rule display names.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowNull()] [AllowEmptyCollection()] [object[]] $Rules)

    $use = @{}
    foreach ($r in @($Rules)) {
        if (-not $r -or -not $r.properties) { continue }
        $p = $r.properties
        if (-not ($p.PSObject.Properties.Name -contains 'enabled' -and $p.enabled -eq $true)) { continue }
        $q = if ($p.PSObject.Properties.Name -contains 'query') { [string]$p.query } else { '' }
        if (-not $q) { continue }
        $name = if ($p.PSObject.Properties.Name -contains 'displayName') { [string]$p.displayName } else { [string]$r.name }
        foreach ($m in [regex]::Matches($q, '_GetWatchlist\s*\(\s*[''"]([^''"]+)[''"]')) {
            $a = $m.Groups[1].Value.ToLowerInvariant()
            if (-not $use.ContainsKey($a)) { $use[$a] = [System.Collections.Generic.List[string]]::new() }
            if (-not $use[$a].Contains($name)) { $use[$a].Add($name) }
        }
    }
    $out = @{}
    foreach ($k in $use.Keys) { $out[$k] = $use[$k].ToArray() }
    return $out
}
