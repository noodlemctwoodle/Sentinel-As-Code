#Requires -Version 7.6

<#
.SYNOPSIS
    Parse an ARM template expression into a small tree.

.DESCRIPTION
    The Bicep writer and the template comparison both work on the parsed
    form of the bracketed strings in an ARM template ("[concat('a',
    parameters('b'))]"), so they agree on what an expression means.

.NOTES
    File:         Modules/iSOCDeployments/Private/Bicep/ConvertFrom-iSOCArmExpression.ps1
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

function ConvertFrom-iSOCArmExpression {
    <#
    .SYNOPSIS
        Return the tree of one ARM expression.

    .DESCRIPTION
        The grammar is the one ARM templates use: a string in single quotes
        (a doubled quote stands for one), an integer, or a function call
        with arguments, each followed by any number of .member and [index]
        accesses. Whitespace between parts is ignored. Anything else throws,
        naming the position.

        Each node is a [pscustomobject] with a Kind: String (Value), Number
        (Value, Int64), Call (Name, Arguments), Member (Target, Name) or
        Index (Target, Index).

    .PARAMETER Expression
        The expression without its outer brackets: concat('a', parameters('b')).

    .OUTPUTS
        [pscustomobject] The root node.

    .EXAMPLE
        ConvertFrom-iSOCArmExpression -Expression "parameters('PlaybookName')"
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Expression
    )

    $state = @{ Text = $Expression; Pos = 0 }

    $fail = { param($What) throw "Cannot read the ARM expression '$($state.Text)': $What at position $($state.Pos)." }
    $skipSpace = { while ($state.Pos -lt $state.Text.Length -and [char]::IsWhiteSpace($state.Text[$state.Pos])) { $state.Pos++ } }
    $peek = { & $skipSpace; if ($state.Pos -lt $state.Text.Length) { $state.Text[$state.Pos] } else { [char]0 } }
    $expect = {
        param([char] $Character)
        if ((& $peek) -ne $Character) { & $fail "expected '$Character'" }
        $state.Pos++
    }
    $readIdentifier = {
        & $skipSpace
        $start = $state.Pos
        while ($state.Pos -lt $state.Text.Length -and ($state.Text[$state.Pos] -match '[A-Za-z0-9_]')) { $state.Pos++ }
        if ($state.Pos -eq $start -or $state.Text[$start] -match '[0-9]') { & $fail 'expected a name' }
        $state.Text.Substring($start, $state.Pos - $start)
    }

    $parseExpression = $null
    $parsePrimary = {
        $next = & $peek
        if ($next -eq "'") {
            $state.Pos++
            $value = [System.Text.StringBuilder]::new()
            while ($true) {
                if ($state.Pos -ge $state.Text.Length) { & $fail 'unterminated string' }
                $character = $state.Text[$state.Pos]
                if ($character -eq "'") {
                    if ($state.Pos + 1 -lt $state.Text.Length -and $state.Text[$state.Pos + 1] -eq "'") {
                        [void]$value.Append("'")
                        $state.Pos += 2
                        continue
                    }
                    $state.Pos++
                    break
                }
                [void]$value.Append($character)
                $state.Pos++
            }
            return [pscustomobject]@{ Kind = 'String'; Value = $value.ToString() }
        }
        if ($next -match '[-0-9]') {
            $start = $state.Pos
            if ($next -eq '-') { $state.Pos++ }
            while ($state.Pos -lt $state.Text.Length -and $state.Text[$state.Pos] -match '[0-9]') { $state.Pos++ }
            $digits = $state.Text.Substring($start, $state.Pos - $start)
            if ($digits -notmatch '^-?[0-9]+$') { & $fail 'expected a number' }
            return [pscustomobject]@{ Kind = 'Number'; Value = [long]$digits }
        }
        $name = & $readIdentifier
        & $expect '('
        $arguments = [System.Collections.Generic.List[object]]::new()
        if ((& $peek) -ne ')') {
            while ($true) {
                $arguments.Add((& $parseExpression))
                if ((& $peek) -eq ',') { $state.Pos++; continue }
                break
            }
        }
        & $expect ')'
        [pscustomobject]@{ Kind = 'Call'; Name = $name; Arguments = $arguments.ToArray() }
    }
    $parseExpression = {
        $node = & $parsePrimary
        while ($true) {
            $next = & $peek
            if ($next -eq '.') {
                $state.Pos++
                $node = [pscustomobject]@{ Kind = 'Member'; Target = $node; Name = (& $readIdentifier) }
            } elseif ($next -eq '[') {
                $state.Pos++
                $index = & $parseExpression
                & $expect ']'
                $node = [pscustomobject]@{ Kind = 'Index'; Target = $node; Index = $index }
            } else { break }
        }
        $node
    }

    $root = & $parseExpression
    if ((& $peek) -ne [char]0) { & $fail 'unexpected text' }
    $root
}
