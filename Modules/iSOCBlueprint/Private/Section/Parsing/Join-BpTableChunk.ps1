#Requires -Version 7.6

<#
.SYNOPSIS
    Join the table chunks Split-BpLongTable made back into one table.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Parsing/Join-BpTableChunk.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, Section model conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Join-BpTableChunk {
    <#
    .SYNOPSIS
        Join the table chunks Split-BpLongTable made back into one table.

    .PARAMETER Blocks
        The section's top-level blocks.

    .OUTPUTS
        The blocks, with each table followed by a seam and another table
        merged into one, and the seams removed.
    #>
    param([object[]] $Blocks)

    $out = [System.Collections.Generic.List[object]]::new()
    $joinNext = $false
    foreach ($b in $Blocks) {
        if ($b -is [System.Collections.IDictionary] -and $b.type -eq 'tableContinues') { $joinNext = $true; continue }
        $last = if ($out.Count) { $out[$out.Count - 1] } else { $null }
        if ($joinNext -and $b.type -eq 'table' -and $last -and $last.type -eq 'table') {
            $last.rows = @($last.rows) + @($b.rows)
        }
        else { $out.Add($b) }
        $joinNext = $false
    }
    return $out.ToArray()
}
