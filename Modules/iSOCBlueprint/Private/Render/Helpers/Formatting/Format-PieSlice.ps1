#Requires -Version 7.6

<#
.SYNOPSIS
    Build pie slice lines from a label-to-count map, largest first.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Format-PieSlice.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-PieSlice {
    <#
    .SYNOPSIS
        Build pie slice lines from a label-to-count map, largest first.

    .DESCRIPTION
        Slices are ordered by count, largest first, then by label. A double quote in
        a label is replaced by a single quote. Past Limit the rest fold into one
        final slice named Other (with the number of labels it holds) so the pie
        still sums to the total; a page that folds a tail always carries a table
        listing every item.

    .PARAMETER Counts
        A map of label to count.

    .PARAMETER Limit
        The most slices to show before the rest are summed into Other. 0, the
        default, shows every slice.

    .OUTPUTS
        [string[]] of indented slice lines, returned as one array.
    #>
    [OutputType([object[]])]
    [CmdletBinding()]
    param([System.Collections.IDictionary]$Counts, [int]$Limit = 0)
    $sorted = @($Counts.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key)
    $shown = if ($Limit -gt 0 -and $sorted.Count -gt $Limit) { @($sorted | Select-Object -First $Limit) } else { $sorted }
    $lines = @($shown | ForEach-Object { "    `"$($_.Key -replace '"', "'")`" : $($_.Value)" })
    if ($shown.Count -lt $sorted.Count) {
        $rest = (@($sorted | Select-Object -Skip $shown.Count) | Measure-Object -Property Value -Sum).Sum
        $lines += "    `"Other ($($sorted.Count - $shown.Count))`" : $rest"
    }
    return , $lines
}
