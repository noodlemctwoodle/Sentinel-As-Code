#Requires -Version 7.6

<#
.SYNOPSIS
    Wrap a plain-text secret in a SecureString.

.DESCRIPTION
    The one place a secret from the environment or a .env file becomes a
    SecureString.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/ConvertTo-iSOCSecureString.ps1
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

function ConvertTo-iSOCSecureString {
    <#
    .SYNOPSIS
        Wrap a plain-text secret in a SecureString.

    .DESCRIPTION
        A secret from the environment or a .env file arrives as plain text;
        wrapping it is the mitigation, and this is the one place it happens.

    .PARAMETER Plain
        The secret.

    .OUTPUTS
        [securestring]

    .EXAMPLE
        ConvertTo-iSOCSecureString -Plain $value
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The secret arrives as plain text from the environment or a .env file; wrapping it is the mitigation.')]
    [CmdletBinding()]
    [OutputType([securestring])]
    param(
        [Parameter(Mandatory)]
        [string] $Plain
    )

    ConvertTo-SecureString -String $Plain -AsPlainText -Force
}
