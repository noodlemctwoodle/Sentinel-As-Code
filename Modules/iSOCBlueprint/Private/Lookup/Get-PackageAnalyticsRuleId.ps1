#Requires -Version 7.6

<#
.SYNOPSIS
    The analytics rule content ids a Content Hub package ships

.DESCRIPTION
    One of the helpers beside Get-TemplateSolution.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Get-PackageAnalyticsRuleId.ps1
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
