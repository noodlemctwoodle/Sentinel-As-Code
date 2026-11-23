#Requires -Version 7.6

<#
.SYNOPSIS
    A date as the dashboard writes it: 15 Oct 2026, or with -Time 15 Oct 2026 21:03 UTC. Always UTC; invariant month names.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Format/Text/Format-BlueprintDate.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Blueprint text formatting
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-BlueprintDate {
    <#
    .SYNOPSIS
        A date as the dashboard writes it: 15 Oct 2026, or with -Time
        15 Oct 2026 21:03 UTC. Always UTC; invariant month names.

    .PARAMETER Value
        A [datetime], a [datetimeoffset] or a date string (ISO 8601 and the
        like). A string with no zone is read as UTC.

    .PARAMETER Time
        Add the time of day (hours and minutes) and 'UTC'.

    .OUTPUTS
        [string]; the input as text when it is not a date, '' for $null.
    #>
    [CmdletBinding()]
    param([AllowNull()] $Value, [switch] $Time)
    if ($null -eq $Value) { return '' }
    $dt = $null
    if ($Value -is [datetime]) { $dt = $Value.ToUniversalTime() }
    elseif ($Value -is [datetimeoffset]) { $dt = $Value.UtcDateTime }
    else {
        $s = ([string]$Value).Trim()
        if (-not $s) { return '' }
        $parsed = [datetime]::MinValue
        $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
        if (-not [datetime]::TryParse($s, $script:BlueprintInvariant, $styles, [ref]$parsed)) { return $s }
        $dt = $parsed
    }
    if ($Time) { return $dt.ToString('d MMM yyyy HH:mm', $script:BlueprintInvariant) + ' UTC' }
    $dt.ToString('d MMM yyyy', $script:BlueprintInvariant)
}
