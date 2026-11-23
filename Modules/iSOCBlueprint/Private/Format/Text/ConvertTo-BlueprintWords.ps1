#Requires -Version 7.6

<#
.SYNOPSIS
    A CamelCase API value in words, first word capitalised: CredentialAccess reads Credential
    access, BenignPositive reads Benign positive, CommandAndControl reads Command and control.
    An acronym keeps its capitals (IPAddress reads IP address); a value with spaces, punctuation
    or in one word is returned as given.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Format/Text/ConvertTo-BlueprintWords.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Blueprint text formatting
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-BlueprintWords {
    <#
    .SYNOPSIS
        A CamelCase API value in words, first word capitalised:
        CredentialAccess reads Credential access, BenignPositive reads
        Benign positive, CommandAndControl reads Command and control. An
        acronym keeps its capitals (IPAddress reads IP address); a value
        with spaces, punctuation or in one word is returned as given.

    .PARAMETER Value
        The value.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    param([AllowNull()] [AllowEmptyString()] [string] $Value)
    if (-not $Value) { return [string]$Value }
    if ($Value -cnotmatch '^[A-Za-z][A-Za-z0-9]*$' -or $Value -cnotmatch '[a-z][A-Z]|[A-Z]{2}[a-z]') { return $Value }
    $words = @([regex]::Split($Value, '(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])'))
    $rest = @($words | Select-Object -Skip 1 | ForEach-Object { if ($_ -cmatch '^[A-Z]{2,}$') { $_ } else { $_.ToLowerInvariant() } })
    $first = $words[0]
    if ($first -cmatch '^[a-z]') { $first = $first.Substring(0, 1).ToUpperInvariant() + $first.Substring(1) }
    (@($first) + $rest) -join ' '
}
