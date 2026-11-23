#Requires -Version 7.6

<#
.SYNOPSIS
    Template id to its solution

.DESCRIPTION
    One of the helpers beside Get-TemplateSolution.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Get-TemplateSolutionMap.ps1
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

function Get-TemplateSolutionMap {
    <#
    .SYNOPSIS
        Template id to its solution: Solution (the package's display name),
        Installed (true when the package is installed in the workspace),
        Deprecated (true when only deprecated packages ship the template) and
        ReplacedBy (the live package that replaces a deprecated one, or
        $null).

    .DESCRIPTION
        Every package that ships a template is a candidate, chosen in this
        order: installed and live, live in the catalogue, installed but
        deprecated, deprecated in the catalogue; the first package wins a
        tie. A deprecated package's replacement is the live catalogue
        package named "<name> (NEW)", or its name without a Deprecated
        marker.

    .PARAMETER Installed
        The installed packages (content-packages.json).

    .PARAMETER Catalogue
        The Content Hub catalogue (content-product-packages.json).

    .OUTPUTS
        [hashtable] Lower-case template id to [pscustomobject] Solution,
        Installed, Deprecated, ReplacedBy.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowNull()] [AllowEmptyCollection()] [object[]] $Installed,
        [AllowNull()] [AllowEmptyCollection()] [object[]] $Catalogue
    )

    $map = @{}
    $rank = @{}
    $name = {
        param($p) if ($p -and $p.properties -and $p.properties.PSObject.Properties.Name -contains 'displayName') {
            [string]$p.properties.displayName
        } else { '' }
    }
    $cid = {
        param($p) if ($p -and $p.properties -and $p.properties.PSObject.Properties.Name -contains 'contentId') {
            ([string]$p.properties.contentId).ToLowerInvariant()
        } else { '' }
    }
    $catalogueList = @($Catalogue | Where-Object { $null -ne $_ })
    # An installed package may not carry the flag; its catalogue entry does.
    $deprecatedId = @{}
    $live = @{}
    foreach ($p in $catalogueList) {
        $id = & $cid $p; $dep = Test-PackageDeprecated -Package $p
        if ($id) { $deprecatedId[$id] = $dep }
        $n = & $name $p
        if ($n -and -not $dep) { $live[$n.ToLowerInvariant()] = $n }
    }
    $replacement = {
        param([string] $n)
        $base = (($n -replace '(?i)[\[\(]\s*deprecated\s*[\]\)]', ' ') -replace '(?i)\bdeprecated\b', ' ' -replace '\s{2,}', ' ').Trim(' ', '-', ':')
        foreach ($c in @("$base (NEW)", $base)) {
            if ($c -and $c -ne $n -and $live.ContainsKey($c.ToLowerInvariant())) { return $live[$c.ToLowerInvariant()] }
        }
        return $null
    }
    $consider = {
        param($p, [bool] $inst)
        $n = & $name $p; if (-not $n) { return }
        $id = & $cid $p
        $dep = (Test-PackageDeprecated -Package $p) -or ($id -and $deprecatedId.ContainsKey($id) -and $deprecatedId[$id])
        $r = if (-not $dep) { if ($inst) { 0 } else { 1 } } else { if ($inst) { 2 } else { 3 } }
        foreach ($tid in (Get-PackageAnalyticsRuleId -Package $p)) {
            if ($rank.ContainsKey($tid) -and $rank[$tid] -le $r) { continue }
            $rank[$tid] = $r
            $map[$tid] = [pscustomobject]@{
                Solution = $n
                Installed = $inst
                Deprecated = [bool]$dep
                ReplacedBy = $(if ($dep) { & $replacement $n } else { $null })
            }
        }
    }
    foreach ($p in $catalogueList) { & $consider $p $false }
    foreach ($p in @($Installed | Where-Object { $null -ne $_ })) { & $consider $p $true }
    return $map
}
