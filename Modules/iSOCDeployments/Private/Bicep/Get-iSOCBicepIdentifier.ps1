#Requires -Version 7.6

<#
.SYNOPSIS
    Make a name into a Bicep identifier no other symbol in the file uses.

.NOTES
    File:         Modules/iSOCDeployments/Private/Bicep/Get-iSOCBicepIdentifier.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-06
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCBicepIdentifier {
    <#
    .SYNOPSIS
        Return a unique Bicep identifier for a name, and record it as taken.

    .DESCRIPTION
        Characters other than letters, digits and underscores become
        underscores, and a leading digit gets an underscore in front. A
        Bicep keyword, or a name already taken (compared without case, as
        ARM compares names), gets 2, 3 and on appended until it is free.

    .PARAMETER Name
        The name to start from.

    .PARAMETER Taken
        The identifiers already used in the file; the result is added.

    .OUTPUTS
        [string] The identifier.

    .EXAMPLE
        $taken = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        Get-iSOCBicepIdentifier -Name 'office365-1' -Taken $taken   # office365_1
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $Taken
    )

    $keywords = @(
        'metadata', 'targetScope', 'import', 'using', 'extension', 'param', 'var', 'resource', 'module', 'output',
        'type', 'func', 'existing', 'if', 'for', 'in', 'true', 'false', 'null', 'as', 'with', 'assert', 'extends'
    )

    $base = [regex]::Replace($Name, '[^A-Za-z0-9_]', '_')
    if (-not $base) { $base = 'symbol' }
    if ($base -match '^[0-9]') { $base = "_$base" }

    $candidate = $base
    $suffix = 2
    while ($Taken.Contains($candidate) -or $candidate -in $keywords) {
        $candidate = "$base$suffix"
        $suffix++
    }
    [void]$Taken.Add($candidate)
    $candidate
}
