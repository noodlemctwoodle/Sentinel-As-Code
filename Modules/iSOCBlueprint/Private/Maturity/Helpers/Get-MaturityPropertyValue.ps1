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
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Maturity Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-MaturityPropertyValue {
    <#
    .SYNOPSIS
        Read a dotted property path that may be absent, without tripping
        StrictMode.

    .DESCRIPTION
        The path is split on dots and followed through hashtables and objects
        alike. The default is returned when the object is null, a step of the
        path is missing or null, or the value found is null.

    .PARAMETER Object
        The hashtable or object to read.

    .PARAMETER Path
        The property path, with dots between the steps.

    .PARAMETER Default
        The value returned when the path gives nothing. Null when omitted.

    .OUTPUTS
        The value at the path, or Default.
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
