#Requires -Version 7.6

<#
.SYNOPSIS
    Read a property that may be absent, without tripping StrictMode

.DESCRIPTION
    Split from Get-KqlTableReferences.ps1 so each file holds one function.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Kql/Get-KqlPropertyValue.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-09
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+, SentinelCommon.Kql.ps1 (dot-sourced by the caller)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-KqlPropertyValue {
    <#
    .SYNOPSIS
        Read a property that may be absent, without tripping StrictMode.

    .PARAMETER Object
        A PSObject or hashtable.

    .PARAMETER Name
        Property name.

    .PARAMETER Default
        Returned when the property is missing or null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] $Object,
        [Parameter(Mandatory = $true)] [string] $Name,
        [Parameter(Mandatory = $false)] $Default = $null
    )

    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name) -and $null -ne $Object[$Name]) { return $Object[$Name] }
        return $Default
    }
    if ($Object.PSObject.Properties.Name -contains $Name -and $null -ne $Object.$Name) { return $Object.$Name }
    return $Default
}
