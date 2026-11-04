#Requires -Version 7.2

<#
.SYNOPSIS
    Remove what a pasted schema picks up on the way: a byte order mark, curly quotes, no-break spaces, comments and trailing commas.

.DESCRIPTION
    Called only after a straight parse has failed, so a file that parses is
    never changed.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Repair-iSOCJsonText.ps1
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

function Repair-iSOCJsonText {
    <#
    .SYNOPSIS
        Remove what a pasted schema picks up on the way: a byte order mark,
        curly quotes, no-break spaces, comments and trailing commas.

    .DESCRIPTION
        Repairs the cases that are safe to repair, and says which it made:

          - a UTF-8 byte order mark at the start
          - curly quotes and no-break spaces, which can never be JSON
            punctuation, so they are replaced throughout
          - // line comments and /* block */ comments
          - a comma before } or ]

        Comments and trailing commas are removed in one pass that tracks
        whether it is inside a string, so a '//' or ', ]' in a value (a URL
        in a description) is left alone. ConvertFrom-Json already accepts
        comments and trailing commas, so those two usually run beside a
        failure from something else; they are kept so the report says
        everything the file held.

    .PARAMETER Text
        The file's text.

    .OUTPUTS
        [pscustomobject] Text (the repaired JSON) and Applied (the repairs
        made, for the report).

    .EXAMPLE
        Repair-iSOCJsonText -Text (Get-Content -LiteralPath $path -Raw)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $applied = [System.Collections.Generic.List[string]]::new()

    if ($Text.Length -gt 0 -and $Text[0] -eq [char]0xFEFF) {
        $Text = $Text.Substring(1)
        $applied.Add('byte order mark')
    }

    $straightened = ConvertTo-iSOCStraightPunctuation -Text $Text
    if ($straightened -ne $Text) {
        $Text = $straightened
        $applied.Add('curly quotes or no-break spaces')
    }

    $builder = [System.Text.StringBuilder]::new($Text.Length)
    $inString = $false
    $escaped = $false
    $strippedComment = $false
    $strippedComma = $false
    $index = 0

    while ($index -lt $Text.Length) {
        $char = $Text[$index]

        if ($inString) {
            [void]$builder.Append($char)
            if ($escaped) { $escaped = $false }
            elseif ($char -eq '\') { $escaped = $true }
            elseif ($char -eq '"') { $inString = $false }
            $index++
            continue
        }

        if ($char -eq '"') {
            $inString = $true
            [void]$builder.Append($char)
            $index++
            continue
        }

        if ($char -eq '/' -and ($index + 1) -lt $Text.Length) {
            $next = $Text[$index + 1]
            if ($next -eq '/') {
                while ($index -lt $Text.Length -and $Text[$index] -ne "`n") { $index++ }
                $strippedComment = $true
                continue
            }
            if ($next -eq '*') {
                $index += 2
                while (($index + 1) -lt $Text.Length -and -not ($Text[$index] -eq '*' -and $Text[$index + 1] -eq '/')) {
                    $index++
                }
                $index += 2
                $strippedComment = $true
                continue
            }
        }

        if ($char -eq ',') {
            $lookahead = $index + 1
            while ($lookahead -lt $Text.Length -and [char]::IsWhiteSpace($Text[$lookahead])) { $lookahead++ }
            if ($lookahead -lt $Text.Length -and ($Text[$lookahead] -eq '}' -or $Text[$lookahead] -eq ']')) {
                $strippedComma = $true
                $index++
                continue
            }
        }

        [void]$builder.Append($char)
        $index++
    }

    if ($strippedComment) { $applied.Add('JSON comments') }
    if ($strippedComma) { $applied.Add('trailing commas') }

    [pscustomobject]@{
        Text    = $builder.ToString()
        Applied = $applied.ToArray()
    }
}
