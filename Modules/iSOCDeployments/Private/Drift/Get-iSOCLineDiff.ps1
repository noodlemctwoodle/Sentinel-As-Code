#Requires -Version 7.2

<#
.SYNOPSIS
    A line-by-line diff of two texts.

.DESCRIPTION
    Copied from Get-LineDiff (Tools/Test-SentinelRuleDrift.ps1): the longest
    common subsequence of the lines, written as git diff writes a hunk.

.NOTES
    File:         Modules/iSOCDeployments/Private/Drift/Get-iSOCLineDiff.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCLineDiff {
    <#
    .SYNOPSIS
        Return every line of both texts, marked '  ' (in both), '- ' (only
        before) or '+ ' (only after), in file order.

    .DESCRIPTION
        Lines compare case-sensitively. The table is m by n lines, which is
        small for the queries it is used on.

    .PARAMETER Before
        The first text.

    .PARAMETER After
        The second text.

    .OUTPUTS
        [string] The marked lines, joined by newlines.

    .EXAMPLE
        Get-iSOCLineDiff -Before $expected -After $deployed
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Before,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $After
    )

    $a = @($Before -split "`r?`n")
    $b = @($After -split "`r?`n")
    $m = $a.Count
    $n = $b.Count

    # Jagged: $L[i, j] would slice a one-dimensional array.
    $L = New-Object 'int[][]' ($m + 1)
    for ($k = 0; $k -le $m; $k++) { $L[$k] = New-Object 'int[]' ($n + 1) }

    for ($i = 1; $i -le $m; $i++) {
        for ($j = 1; $j -le $n; $j++) {
            if ($a[$i - 1] -ceq $b[$j - 1]) { $L[$i][$j] = $L[$i - 1][$j - 1] + 1 }
            else { $L[$i][$j] = [Math]::Max($L[$i - 1][$j], $L[$i][$j - 1]) }
        }
    }

    $out = [System.Collections.Generic.List[string]]::new()
    $i = $m; $j = $n
    while ($i -gt 0 -and $j -gt 0) {
        if ($a[$i - 1] -ceq $b[$j - 1]) {
            $out.Insert(0, '  ' + $a[$i - 1])
            $i--; $j--
        }
        elseif ($L[$i - 1][$j] -ge $L[$i][$j - 1]) {
            $out.Insert(0, '- ' + $a[$i - 1])
            $i--
        }
        else {
            $out.Insert(0, '+ ' + $b[$j - 1])
            $j--
        }
    }
    while ($i -gt 0) { $out.Insert(0, '- ' + $a[$i - 1]); $i-- }
    while ($j -gt 0) { $out.Insert(0, '+ ' + $b[$j - 1]); $j-- }

    $out -join "`n"
}
