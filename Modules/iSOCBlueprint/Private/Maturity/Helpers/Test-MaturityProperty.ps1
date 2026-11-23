#Requires -Version 7.6

<#
.SYNOPSIS
    True when an object carries the named member, even with a null value.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Maturity/Helpers/Test-MaturityProperty.ps1
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

function Test-MaturityProperty {
    <#
    .SYNOPSIS
        True when the object carries the named member, even with a null value.

    .DESCRIPTION
        Safe under StrictMode on empty objects and primitives. A hashtable is
        tested for the key, and any other object for a member of that name. Null
        is false.

    .PARAMETER Object
        The hashtable or object to test.

    .PARAMETER Name
        The member or key name.

    .OUTPUTS
        [bool] True when the member is there.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] $Object,
        [Parameter(Mandatory = $true)] [string] $Name
    )
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return ($null -ne $Object.PSObject.Properties[$Name])
}
