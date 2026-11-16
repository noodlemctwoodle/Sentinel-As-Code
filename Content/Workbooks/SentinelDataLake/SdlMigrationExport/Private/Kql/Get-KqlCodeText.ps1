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
    $named = foreach ($match in [regex]::Matches($Text, 'table\(\s*[''"]([A-Za-z0-9_]+)[''"]\s*\)')) {
        $match.Groups[1].Value
    }
    $tokens = '//[^\r\n]*|@"[^"]*"|@''[^'']*''|"(?:[^"\\\r\n]|\\.)*"|''(?:[^''\\\r\n]|\\.)*'''
    $clean = [regex]::Replace($Text, $tokens, ' ')
    return ($clean + ' ' + ($named -join ' '))
}
