#Requires -Version 7.6

<#
.SYNOPSIS
    The SHA-256 hash of some content, for change detection.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Output/Get-ContentHash.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-ContentHash {
    <#
    .SYNOPSIS
        The SHA-256 hash of a string, as lower-case hex.

    .DESCRIPTION
        The string is hashed as UTF-8, so equal content gives an equal hash.

    .PARAMETER Text
        The string to hash. It may be empty.

    .OUTPUTS
        [string] The 64-character lower-case hex hash.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return ([System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
}
