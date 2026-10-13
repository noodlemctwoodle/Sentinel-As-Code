#Requires -Version 7.2

<#
.SYNOPSIS
    Find the Content Hub solution an analytics rule template comes from, and
    whether that solution is installed.

.DESCRIPTION
    The alert-rule templates the collector saves (alert-rule-templates.json)
    do not name their solution. The Content Hub packages do the reverse: each
    package lists the content it ships under properties.dependencies, nested
    criteria with a contentId and a kind, and an analytics rule's contentId
    is the template's id. Reading the installed packages
    (content-packages.json) and the Content Hub catalogue
    (content-product-packages.json) gives every template's solution; a
    template neither lists is a built-in gallery template that no solution
    ships.

    The renderer's detection opportunities page and the SharePoint
    dashboard read this, so the two agree.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/Get-TemplateSolution.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-PackageAnalyticsRuleId {
    <#
    .SYNOPSIS
        The analytics rule content ids a Content Hub package ships.

    .PARAMETER Package
        One package as contentPackages or contentProductPackages returns it.

    .OUTPUTS
        [string[]] The ids, lower-case.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([AllowNull()] $Package)

    $has = { param($o, [string]$n) $null -ne $o -and $o.PSObject.Properties.Name -contains $n -and $null -ne $o.$n }
    if (-not (& $has $Package 'properties') -or -not (& $has $Package.properties 'dependencies')) { return @() }
    $ids = [System.Collections.Generic.List[string]]::new()
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push($Package.properties.dependencies)
    while ($stack.Count) {
        $n = $stack.Pop()
        if ($null -eq $n) { continue }
        if ((& $has $n 'contentId') -and (& $has $n 'kind') -and [string]$n.kind -eq 'AnalyticsRule') { $ids.Add(([string]$n.contentId).ToLowerInvariant()) }
        if (& $has $n 'criteria') { foreach ($c in @($n.criteria)) { $stack.Push($c) } }
    }
    return $ids.ToArray()
}

function Get-TemplateSolutionMap {
    <#
    .SYNOPSIS
        Template id to its solution: Solution (the package's display name)
        and Installed (true when the package is installed in the workspace).

    .PARAMETER Installed
        The installed packages (content-packages.json).

    .PARAMETER Catalogue
        The Content Hub catalogue (content-product-packages.json).

    .OUTPUTS
        [hashtable] Lower-case template id to [pscustomobject] Solution,
        Installed. An installed package wins over the catalogue entry.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowNull()] [AllowEmptyCollection()] [object[]] $Installed,
        [AllowNull()] [AllowEmptyCollection()] [object[]] $Catalogue
    )

    $map = @{}
    $name = { param($p) if ($p -and $p.properties -and $p.properties.PSObject.Properties.Name -contains 'displayName') { [string]$p.properties.displayName } else { '' } }
    foreach ($p in @($Catalogue)) {
        $n = & $name $p; if (-not $n) { continue }
        foreach ($id in (Get-PackageAnalyticsRuleId -Package $p)) { if (-not $map.ContainsKey($id)) { $map[$id] = [pscustomobject]@{ Solution = $n; Installed = $false } } }
    }
    foreach ($p in @($Installed)) {
        $n = & $name $p; if (-not $n) { continue }
        foreach ($id in (Get-PackageAnalyticsRuleId -Package $p)) { $map[$id] = [pscustomobject]@{ Solution = $n; Installed = $true } }
    }
    return $map
}

function Get-TemplateSolution {
    <#
    .SYNOPSIS
        One template's solution from the map, or Built-in when no package
        ships it (Installed is then $null).

    .PARAMETER Map
        From Get-TemplateSolutionMap.

    .PARAMETER TemplateId
        The template's id (its name in alert-rule-templates.json).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([AllowNull()] [hashtable] $Map, [AllowEmptyString()] [string] $TemplateId)

    $key = ([string]$TemplateId).ToLowerInvariant()
    if ($Map -and $key -and $Map.ContainsKey($key)) { return $Map[$key] }
    return [pscustomobject]@{ Solution = 'Built-in'; Installed = $null }
}

function Format-TemplateSolutionSummary {
    <#
    .SYNOPSIS
        A short line of the solutions a set of templates come from, with how
        many each and whether installed: "Microsoft Entra ID (12, installed);
        Azure Activity (3); Built-in (2)". Installed first, then by count.

    .PARAMETER Templates
        Template references (TemplateId).

    .PARAMETER Map
        From Get-TemplateSolutionMap.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [AllowEmptyCollection()] [object[]] $Templates, [AllowNull()] [hashtable] $Map)

    $groups = @{}
    foreach ($t in @($Templates)) {
        if (-not $t) { continue }
        $s = Get-TemplateSolution -Map $Map -TemplateId ([string]$t.TemplateId)
        if (-not $groups.ContainsKey($s.Solution)) { $groups[$s.Solution] = [pscustomobject]@{ Solution = $s.Solution; Installed = $s.Installed; Count = 0 } }
        $groups[$s.Solution].Count++
    }
    $ordered = @($groups.Values | Sort-Object @{ Expression = { if ($_.Installed -eq $true) { 0 } elseif ($_.Installed -eq $false) { 1 } else { 2 } } }, @{ Expression = 'Count'; Descending = $true }, Solution)
    return (($ordered | ForEach-Object { "$($_.Solution) ($($_.Count)$(if ($_.Installed -eq $true) { ', installed' }))" }) -join '; ')
}
