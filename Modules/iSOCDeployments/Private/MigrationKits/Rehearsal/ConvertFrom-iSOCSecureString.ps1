#Requires -Version 7.2

<#
.SYNOPSIS
    Read a SecureString back to plain text, in memory.

.DESCRIPTION
    The one place the client secret is read back, so it is easy to audit.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/ConvertFrom-iSOCSecureString.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertFrom-iSOCSecureString {
    <#
    .SYNOPSIS
        Read a SecureString back to plain text, in memory.

    .DESCRIPTION
        The one place the client secret is read back, for the token request,
        so it is easy to find and audit.

    .PARAMETER Secure
        The SecureString.

    .OUTPUTS
        [string]

    .EXAMPLE
        ConvertFrom-iSOCSecureString -Secure $ClientSecret
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [securestring] $Secure
    )

    [System.Net.NetworkCredential]::new('', $Secure).Password
}
