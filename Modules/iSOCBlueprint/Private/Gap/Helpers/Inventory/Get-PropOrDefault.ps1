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
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Get-PropOrDefault {
    <#
    .SYNOPSIS
        Read a property by dotted path from an object or hashtable, or return a default when any step is missing.

    .DESCRIPTION
        Sentinel and Log Analytics REST calls occasionally return objects with
        subtly different property shapes between API versions; this lets checks
        stay tolerant. The default is also returned when the object is $null,
        when a step along the path is $null, and when the value found is $null.

    .PARAMETER Object
        The object or hashtable to read from.

    .PARAMETER Path
        The property names to follow, separated by dots, such as
        properties.displayName. Each step reads a hashtable key or a property.

    .PARAMETER Default
        What to return when the path cannot be followed or ends in $null.
        $null when omitted.

    .OUTPUTS
        The value found at the path, else the default.
    #>
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
