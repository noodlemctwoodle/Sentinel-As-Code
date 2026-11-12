#Requires -Version 7.6

<#
.SYNOPSIS
    Read a dotted property path that may be absent, without tripping StrictMode.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Maturity/Helpers/Get-MaturityPropertyValue.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Maturity Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-MaturityPropertyValue {
    <#
    .SYNOPSIS
        Read a dotted property path that may be absent, without tripping
        StrictMode. Hashtables and PSObjects both work.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] $Object,
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $false)] $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    $current = $Object
    foreach ($segment in $Path -split '\.') {
        if ($null -eq $current) { return $Default }
        if ($current -is [System.Collections.IDictionary]) {
            if (-not $current.Contains($segment)) { return $Default }
            $current = $current[$segment]
        } else {
            # The indexer returns null for a missing member and never trips
            # StrictMode, which .Properties.Name does on an empty object.
            $prop = $current.PSObject.Properties[$segment]
            if ($null -eq $prop) { return $Default }
            $current = $prop.Value
        }
    }
    if ($null -eq $current) { return $Default }
    return $current
}
