#Requires -Version 7.6

<#
.SYNOPSIS
    Write a string as a Bicep string literal.

.NOTES
    File:         Modules/iSOCDeployments/Private/Bicep/ConvertTo-iSOCBicepString.ps1
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

function ConvertTo-iSOCBicepString {
    <#
    .SYNOPSIS
        Return the Bicep literal for a string.

    .DESCRIPTION
        A single-quoted literal escapes a backslash, a quote, ${ (which Bicep
        would read as interpolation), carriage return, line feed and tab,
        and writes any other control character as \u{hex}. With
        -AllowMultiLine, text that spans lines is written as a ''' block
        instead, verbatim, when it can be: it holds no carriage return, no
        ''', does not end with a quote (which would run into the closing
        quotes) and has no other control character than a line feed or a
        tab. A
        ''' block has no escapes and no interpolation, and Bicep drops the
        line feed straight after the opening quotes, which the block always
        has.

    .PARAMETER Value
        The string.

    .PARAMETER AllowMultiLine
        Write multi-line text as a ''' block where it can be.

    .PARAMETER Fragment
        Return the escaped text without the quotes, for a piece of an
        interpolated string.

    .OUTPUTS
        [string] The literal.

    .EXAMPLE
        ConvertTo-iSOCBicepString -Value "it's" # 'it\'s'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value,

        [switch] $AllowMultiLine,

        [switch] $Fragment
    )

    if ($AllowMultiLine -and -not $Fragment -and $Value.Contains("`n") -and -not $Value.Contains("`r") -and
        -not $Value.Contains("'''") -and -not $Value.EndsWith("'") -and $Value -notmatch '[\x00-\x08\x0B-\x1F\x7F]') {
        return "'''`n$Value'''"
    }

    $text = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $Value.Length; $i++) {
        $character = $Value[$i]
        switch -CaseSensitive ($character) {
            '\' { [void]$text.Append('\\'); continue }
            "'" { [void]$text.Append("\'"); continue }
            "`n" { [void]$text.Append('\n'); continue }
            "`r" { [void]$text.Append('\r'); continue }
            "`t" { [void]$text.Append('\t'); continue }
            '$' {
                if ($i + 1 -lt $Value.Length -and $Value[$i + 1] -eq '{') { [void]$text.Append('\$') }
                else { [void]$text.Append('$') }
                continue
            }
            default {
                if ([int]$character -lt 0x20 -or [int]$character -eq 0x7F) { [void]$text.Append(('\u{{{0:X}}}' -f [int]$character)) }
                else { [void]$text.Append($character) }
            }
        }
    }
    if ($Fragment) { return $text.ToString() }
    "'" + $text.ToString() + "'"
}
