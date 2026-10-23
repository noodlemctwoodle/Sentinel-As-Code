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

    The catalogue flags a solution Microsoft has retired (isDeprecated), such
    as Threat Intelligence, replaced by Threat Intelligence (NEW). A template
    a live solution also ships is credited to the live one; a template only
    deprecated solutions ship is marked Deprecated, with the replacement
    solution when the catalogue names one, and the detection opportunities
    (renderer, dashboard and the SAC-DET gap check) leave it out of what is
    ready to enable.

    The renderer's detection opportunities page and the SharePoint
    dashboard read this, so the two agree.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/Get-TemplateSolution.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.2.0
    Last Updated: 2026-10-14
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

function Test-PackageDeprecated {
    <#
    .SYNOPSIS
        Whether a Content Hub package is deprecated (properties.isDeprecated,
        a boolean or the string "true").

    .PARAMETER Package
        One package as contentPackages or contentProductPackages returns it.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()] $Package)

    if (-not $Package -or -not $Package.properties -or $Package.properties.PSObject.Properties.Name -notcontains 'isDeprecated') { return $false }
    return ([string]$Package.properties.isDeprecated -eq 'true')
}

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
    $name = { param($p) if ($p -and $p.properties -and $p.properties.PSObject.Properties.Name -contains 'displayName') { [string]$p.properties.displayName } else { '' } }
    $cid = { param($p) if ($p -and $p.properties -and $p.properties.PSObject.Properties.Name -contains 'contentId') { ([string]$p.properties.contentId).ToLowerInvariant() } else { '' } }
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
            $map[$tid] = [pscustomobject]@{ Solution = $n; Installed = $inst; Deprecated = [bool]$dep; ReplacedBy = $(if ($dep) { & $replacement $n } else { $null }) }
        }
    }
    foreach ($p in $catalogueList) { & $consider $p $false }
    foreach ($p in @($Installed | Where-Object { $null -ne $_ })) { & $consider $p $true }
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
    return [pscustomobject]@{ Solution = 'Built-in'; Installed = $null; Deprecated = $false; ReplacedBy = $null }
}

function Test-TemplateRetired {
    <#
    .SYNOPSIS
        Whether only deprecated Content Hub solutions ship a template, so it
        is not one to enable.

    .PARAMETER Map
        From Get-TemplateSolutionMap.

    .PARAMETER TemplateId
        The template's id (its name in alert-rule-templates.json).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()] [hashtable] $Map, [AllowEmptyString()] [string] $TemplateId)

    $s = Get-TemplateSolution -Map $Map -TemplateId $TemplateId
    return [bool]($s.PSObject.Properties.Name -contains 'Deprecated' -and $s.Deprecated)
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
