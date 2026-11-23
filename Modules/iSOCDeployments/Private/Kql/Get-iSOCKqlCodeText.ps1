#Requires -Version 7.6

<#
.SYNOPSIS
    Replace every comment and string literal in KQL text with a space.

.DESCRIPTION
    The forms handled are the ones KQL defines: // line comments (KQL has no
    block comment), quoted, verbatim (@), multi-line (three backticks) and
    obfuscated (h) string literals.

.NOTES
    File:         Modules/iSOCDeployments/Private/Kql/Get-iSOCKqlCodeText.ps1
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

function Get-iSOCKqlCodeText {
    <#
    .SYNOPSIS
        Replace every comment and string literal in KQL text with a space.

    .DESCRIPTION
        So that names are read only from code. The forms are the ones KQL
        defines:

          //             a line comment, to the end of the line; KQL has no
                         block comment
          '...' "..."    a backslash escapes
          @'...' @"..."  verbatim: a backslash is literal and a doubled
                         quote is the quote
          three backticks a multi-line literal, with no escapes
          h'...'         obfuscated: the h prefix wraps one of the forms
                         above, and the prefix is left in place (one
                         character cannot be a parser alias)

        A single-line literal also ends at an unescaped line break: KQL
        needs a line break in one to be escaped, so an unclosed quote is
        malformed, and stopping at the line end limits the damage to that
        line. Comments and quotes are found in the same pass, so // inside
        a string opens no comment and an apostrophe in a comment opens no
        string.

    .PARAMETER Text
        The KQL text.

    .OUTPUTS
        [string] The code, or '' for no text.

    .EXAMPLE
        Get-iSOCKqlCodeText -Text "T | where Name == 'x' // note"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Text
    )

    if ([string]::IsNullOrEmpty($Text)) { return '' }

    $sb = [System.Text.StringBuilder]::new($Text.Length)
    $len = $Text.Length
    $i = 0

    while ($i -lt $len) {
        $ch = $Text[$i]

        if ($ch -eq '/' -and ($i + 1) -lt $len -and $Text[$i + 1] -eq '/') {
            while ($i -lt $len -and $Text[$i] -ne "`n" -and $Text[$i] -ne "`r") { $i++ }
            [void]$sb.Append(' ')
            continue
        }

        if ($ch -eq '`' -and ($i + 2) -lt $len -and $Text[$i + 1] -eq '`' -and $Text[$i + 2] -eq '`') {
            $close = $Text.IndexOf('``' + '`', $i + 3)
            $i = if ($close -lt 0) { $len } else { $close + 3 }
            [void]$sb.Append(' ')
            continue
        }

        if ($ch -eq "'" -or $ch -eq '"') {
            $verbatim = ($i -gt 0 -and $Text[$i - 1] -eq '@')
            $quote = $ch
            $i++
            while ($i -lt $len) {
                $c = $Text[$i]
                if ($c -eq "`n" -or $c -eq "`r") { break }
                if ($verbatim) {
                    if ($c -eq $quote) {
                        if (($i + 1) -lt $len -and $Text[$i + 1] -eq $quote) { $i += 2; continue }
                        $i++
                        break
                    }
                    $i++
                } else {
                    if ($c -eq '\') { $i += 2; continue }
                    if ($c -eq $quote) { $i++; break }
                    $i++
                }
            }
            [void]$sb.Append(' ')
            continue
        }

        [void]$sb.Append($ch)
        $i++
    }

    $sb.ToString()
}
