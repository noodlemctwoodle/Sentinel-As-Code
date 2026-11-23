#Requires -Version 7.6

<#
.SYNOPSIS
    A name for evidence text: the first of the given paths that is not blank, else a fallback.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Finding/Get-EvidenceName.ps1
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
function Get-EvidenceName {
    <#
    .SYNOPSIS
        A name for evidence text: the first of -Path that is not blank,
        else -Fallback. Blank counts as missing, so an empty display name
        never leaves an empty entry in a list of names.

    .PARAMETER Object
        The object to read the names from. $null gives the fallback.

    .PARAMETER Path
        One or more property paths, tried in order and read with
        Get-PropOrDefault. The first non-blank value is returned, trimmed.

    .PARAMETER Fallback
        What to return when there is no object or no path gives a non-blank
        value. "Unnamed" when omitted.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [AllowNull()] [object]$Object,
        [Parameter(Mandatory = $true)] [string[]]$Path,
        [Parameter(Mandatory = $false)] [string]$Fallback = 'Unnamed'
    )
    if ($null -eq $Object) { return $Fallback }
    foreach ($p in $Path) {
        $v = [string](Get-PropOrDefault $Object $p '')
        if (-not [string]::IsNullOrWhiteSpace($v)) { return $v.Trim() }
    }
    return $Fallback
}
