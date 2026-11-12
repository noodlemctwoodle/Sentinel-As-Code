#Requires -Version 7.6

<#
.SYNOPSIS
    Build pie slice lines from a label-to-count map, largest first.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Format-PieSlices.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

# Pie slices for a label -> count map, largest first. Past $Limit the rest
# fold into one "Other" slice so the pie still sums to the total; a page that
# folds a tail always carries a table listing every item.
function Format-PieSlices { param([System.Collections.IDictionary]$Counts, [int]$Limit = 0)
    $sorted = @($Counts.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key)
    $shown = if ($Limit -gt 0 -and $sorted.Count -gt $Limit) { @($sorted | Select-Object -First $Limit) } else { $sorted }
    $lines = @($shown | ForEach-Object { "    `"$($_.Key -replace '"', "'")`" : $($_.Value)" })
    if ($shown.Count -lt $sorted.Count) {
        $rest = (@($sorted | Select-Object -Skip $shown.Count) | Measure-Object -Property Value -Sum).Sum
        $lines += "    `"Other ($($sorted.Count - $shown.Count))`" : $rest"
    }
    return ,$lines
}
