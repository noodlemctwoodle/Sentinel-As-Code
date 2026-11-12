#Requires -Version 7.6

<#
.SYNOPSIS
    Read a property by dotted path from an object or hashtable, or return a default when any step is missing.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Inventory/Get-PropOrDefault.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Helper, returns a property if it exists, else default. Sentinel/LA REST occasionally
# returns objects with subtly different property shapes between API versions; this lets
# checks stay tolerant.
function Get-PropOrDefault {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object]$Object,
        [Parameter(Mandatory = $true)] [string]$Path,
        [Parameter(Mandatory = $false)] $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    $current = $Object
    foreach ($segment in $Path -split '\.') {
        if ($null -eq $current) { return $Default }
        if ($current -is [hashtable] -and $current.ContainsKey($segment)) {
            $current = $current[$segment]
        } elseif ($null -ne $current.PSObject.Properties[$segment]) {
            # The indexer, not .Properties.Name: an empty JSON object has no
            # properties, and member enumeration over none throws in strict mode.
            $current = $current.PSObject.Properties[$segment].Value
        } else {
            return $Default
        }
    }
    if ($null -eq $current) { return $Default }
    return $current
}
