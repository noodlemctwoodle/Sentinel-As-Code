#Requires -Version 7.2

<#
.SYNOPSIS
    Returns KQL text with comments and string literals blanked.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Kql/Get-KqlCodeText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.2+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function Get-KqlCodeText {
    <#
    .SYNOPSIS
        Returns KQL text with comments and string literals blanked.

    .DESCRIPTION
        Lets table names be matched without counting ones that only
        appear in a comment or a string. Names passed to table('X')
        are kept by appending them as bare words.

    .PARAMETER Text
        The KQL text. Empty or $null returns an empty string.

    .OUTPUTS
        [string] The cleaned text.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    if (-not $Text) {
        return ''
    }
    # One alternation, scanned left to right: a table('X') call is taken whole
    # only where it starts in executable KQL, so one inside a comment or a
    # string is swallowed by the comment or string match first.
    $tokens = '(?<![\w.])table\(\s*(?<quote>[''"])(?<table>[A-Za-z0-9_]+)\k<quote>\s*\)|//[^\r\n]*|@"[^"]*"|@''[^'']*''|"(?:[^"\\\r\n]|\\.)*"|''(?:[^''\\\r\n]|\\.)*'''
    $named = foreach ($match in [regex]::Matches($Text, $tokens)) {
        if ($match.Groups['table'].Success) {
            $match.Groups['table'].Value
        }
    }
    $clean = [regex]::Replace($Text, $tokens, ' ')
    return ($clean + ' ' + ($named -join ' '))
}
