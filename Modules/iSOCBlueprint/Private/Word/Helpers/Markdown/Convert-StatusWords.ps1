#Requires -Version 7.6

<#
.SYNOPSIS
    Colour the status, severity and rating words in table columns.

.DESCRIPTION
    Helper for the Word report conversion (Invoke-iSOCBlueprintWordConversion).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Word/Helpers/Markdown/Convert-StatusWords.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Word report
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Convert-StatusWords {
    <#
    .SYNOPSIS
        Colour status words through a character style: a table cell under
        a status column (Severity, Status, Coverage, Rating) whose whole
        text is a known status, and the value after '**Severity:**' on the
        finding cards. Cells in any other column are left alone, so a
        'None' elsewhere stays plain.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory)] [ref] $Count
    )

    $columns = @{
        'severity' = @{ 'Critical' = 'SevCritical'; 'Warning' = 'SevWarning'; 'Info' = 'SevInfo' }
        'status'   = @{ 'Met' = 'SevLow'; 'Gap' = 'SevCritical' }
        'coverage' = @{ 'Covered' = 'SevLow'; 'Rule and custom detection' = 'SevLow'; 'Sentinel rule' = 'SevLow'; 'Custom detection' = 'SevLow'; 'Thin' = 'SevWarning'; 'None' = 'SevCritical' }
        'rating'   = @{ 'Strong' = 'SevLow'; 'Fair' = 'SevInfo'; 'Weak' = 'SevWarning' }
    }

    $lines = $Text -split "`n"
    $active = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].TrimEnd("`r")
        if ($line -notmatch '^\s*\|') { $active = $null; continue }
        $cells = [regex]::Split($line.Trim().Substring(1).TrimEnd('|'), '(?<!\\)\|')
        if ($null -eq $active) {
            # A header row is the table line followed by its |---| separator.
            if ($i + 1 -lt $lines.Count -and $lines[$i + 1] -match '^\s*\|[\s:|-]+\|?\s*$') {
                $active = [System.Collections.Generic.List[object]]::new()
                foreach ($c in $cells) { $active.Add($columns[$c.Trim().ToLowerInvariant()]) }
                $i++
            }
            continue
        }
        $changed = $false
        for ($c = 0; $c -lt [math]::Min($cells.Count, $active.Count); $c++) {
            $map = $active[$c]
            if ($null -eq $map) { continue }
            $word = $cells[$c].Trim()
            if ($word -and $map.ContainsKey($word)) {
                $cells[$c] = " [$word]{custom-style=`"$($map[$word])`"} "
                $Count.Value++
                $changed = $true
            }
        }
        if ($changed) { $lines[$i] = '|' + ($cells -join '|') + '|' }
    }
    $out = $lines -join "`n"

    $sevStyles = $columns['severity']
    $pattern = '\*\*Severity:\*\*[ \t]+(?<w>Critical|Warning|Info)\b'
    $Count.Value += [regex]::Matches($out, $pattern).Count
    $evaluator = {
        param($m)
        $w = $m.Groups['w'].Value
        "**Severity:** [$w]{custom-style=`"$($sevStyles[$w])`"}"
    }.GetNewClosure()
    return [regex]::Replace($out, $pattern, $evaluator)
}
