#Requires -Version 7.6

<#
.SYNOPSIS
    Turn a display name into a file or folder name.

.DESCRIPTION
    Copied from ConvertTo-FileSlug (Tools/Test-SentinelRuleDrift.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/ConvertTo-iSOCFileSlug.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCFileSlug {
    <#
    .SYNOPSIS
        Return the value with every run of other characters made one
        hyphen.

    .DESCRIPTION
        Letters and digits are kept; every run of anything else becomes one
        hyphen, and hyphens at the ends are trimmed. The result is cut to
        -MaxLength and trimmed again. A value with no letters or digits
        becomes 'rule'.

    .PARAMETER Value
        The display name.

    .PARAMETER MaxLength
        The longest slug to return. Default 80.

    .OUTPUTS
        [string]

    .EXAMPLE
        ConvertTo-iSOCFileSlug -Value 'Brute force: Entra ID (sign-ins)'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value,

        [int] $MaxLength = 80
    )

    $slug = ($Value -replace '[^A-Za-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrEmpty($slug)) { $slug = 'rule' }
    if ($slug.Length -gt $MaxLength) { $slug = $slug.Substring(0, $MaxLength).TrimEnd('-') }
    $slug
}
