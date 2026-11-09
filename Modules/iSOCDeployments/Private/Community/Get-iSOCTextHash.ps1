#Requires -Version 7.6

<#
.SYNOPSIS
    The SHA-256 of a text, as the community import manifest records it.

.DESCRIPTION
    Copied from Get-ContentHash256 (Tools/Import-CommunityRules.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Community/Get-iSOCTextHash.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCTextHash {
    <#
    .SYNOPSIS
        Return the SHA-256 of a text's UTF-8 bytes, as upper-case hex.

    .PARAMETER Content
        The text.

    .OUTPUTS
        [string] 64 hex digits.

    .EXAMPLE
        Get-iSOCTextHash -Content $yaml
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Content
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Content)) }
    finally { $sha.Dispose() }
    [System.BitConverter]::ToString($hash).Replace('-', '')
}
