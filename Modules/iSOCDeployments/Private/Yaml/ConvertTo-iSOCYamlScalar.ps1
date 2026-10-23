#Requires -Version 7.2

<#
.SYNOPSIS
    Write a string as a YAML scalar, quoted only when it has to be.

.DESCRIPTION
    Copied from ConvertTo-YamlScalarString in Tools/Test-SentinelRuleDrift.ps1,
    unchanged in behaviour.

.NOTES
    File:         Modules/iSOCDeployments/Private/Yaml/ConvertTo-iSOCYamlScalar.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCYamlScalar {
    <#
    .SYNOPSIS
        Quote a value that YAML would otherwise read differently.

    .DESCRIPTION
        A value holding YAML indicator characters (colon, hash, brackets,
        braces, ampersand, asterisk, exclamation, pipe, greater-than, quotes,
        percent, at, backtick, comma), leading or trailing space, or starting
        with a dash or question mark is single-quoted, with single quotes
        doubled. An empty value is ''.

    .PARAMETER Value
        The text to write.

    .OUTPUTS
        [string]

    .EXAMPLE
        "name: $(ConvertTo-iSOCYamlScalar $rule.displayName)"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Value
    )

    if ([string]::IsNullOrEmpty($Value)) { return "''" }
    if ($Value -match '[:#\[\]\{\}&*!|>''"%@`,]' -or $Value -match '^\s|\s$' -or $Value -match '^[-?]') {
        return ("'" + ($Value -replace "'", "''") + "'")
    }
    $Value
}
