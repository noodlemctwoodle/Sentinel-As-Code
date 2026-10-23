#Requires -Version 7.2

<#
.SYNOPSIS
    Helpers the iSOCDeployments suites use to compare the module with the
    scripts it replaces.

.DESCRIPTION
    The module is built beside the scripts and has to send what they send.
    These helpers put both sides into one comparable form:

    - ConvertTo-ParityJson writes a value as compressed JSON with every key
      sorted, after a JSON round trip, so a hashtable built in the module
      and a body a script serialised compare as text.
    - Get-ParityTokenText lists a function's tokens without comments or line
      breaks, so a copied function can be held to its original.

    The helpers are written independently of the module's own canonical
    JSON (Private/Drift/ConvertTo-iSOCCanonicalJson.ps1), so a fault there
    cannot hide a difference here.

.NOTES
    File:         Tests/iSOCDeployments/_helpers/Parity.psm1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-ParityJson {
    <#
    .SYNOPSIS
        Sorted, compressed JSON for a value or a JSON string.

    .PARAMETER InputObject
        A value, or a JSON string (parsed first).

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [object] $InputObject
    )

    $json = if ($InputObject -is [string]) { $InputObject } else { ConvertTo-Json -InputObject $InputObject -Depth 100 -Compress }
    $parsed = ConvertFrom-Json -InputObject $json -AsHashtable -Depth 100

    $sort = {
        param($Value)
        if ($Value -is [System.Collections.IDictionary]) {
            $sorted = [ordered]@{}
            foreach ($key in ([string[]]@($Value.Keys) | Sort-Object -CaseSensitive)) { $sorted[$key] = & $sort $Value[$key] }
            return $sorted
        }
        if ($Value -is [System.Collections.IList]) {
            return , @(foreach ($item in $Value) { , (& $sort $item) })
        }
        $Value
    }
    ConvertTo-Json -InputObject (& $sort $parsed) -Depth 100 -Compress
}

function Get-ParityTokenText {
    <#
    .SYNOPSIS
        The token texts of a function, without comments or line breaks.

    .PARAMETER Path
        The file that defines the function.

    .PARAMETER Name
        The function's name.

    .OUTPUTS
        [string[]] One entry per token, in order.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name
    )

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    $function = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name }, $true) |
        Select-Object -First 1
    if (-not $function) { throw "$Name is not defined in $Path" }

    $tokens = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($function.Extent.Text, [ref]$tokens, [ref]$null)
    @($tokens | Where-Object { $_.Kind -notin 'Comment', 'NewLine', 'LineContinuation', 'EndOfInput' } | ForEach-Object Text)
}

Export-ModuleMember -Function ConvertTo-ParityJson, Get-ParityTokenText
