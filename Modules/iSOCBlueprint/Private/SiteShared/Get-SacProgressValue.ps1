#Requires -Version 7.6

<#
.SYNOPSIS
    Get-SacProgressValue, a helper of Get-SacProgress.

.DESCRIPTION
    Split from Get-SacProgress.ps1 so each file holds one function.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SiteShared/Get-SacProgressValue.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SacProgressValue {
    <#
    .SYNOPSIS
        A property of a dictionary or an object, or $null; a dotted path
        walks down ('maturity.overall.score').
    #>
    [CmdletBinding()]
    param([AllowNull()] $Object, [Parameter(Mandatory)] [string] $Path)
    $cur = $Object
    foreach ($part in $Path.Split('.')) {
        if ($null -eq $cur) { return $null }
        if ($cur -is [System.Collections.IDictionary]) { $cur = if ($cur.Contains($part)) { $cur[$part] } else { $null } }
        elseif ($cur.PSObject.Properties[$part]) { $cur = $cur.PSObject.Properties[$part].Value }
        else { return $null }
    }
    $cur
}
