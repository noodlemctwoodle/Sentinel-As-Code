#Requires -Version 7.6

<#
.SYNOPSIS
    Format a date-like value as a UTC date and time.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Dates/Format-DateUtc.ps1
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

function Format-DateUtc {
    <#
    .SYNOPSIS
        Format a date-like value as a UTC date and time, such as 15 Oct 2026 21:03.

    .DESCRIPTION
        The dashboard's date style: invariant month names, seconds dropped to reduce
        column width. The time is always UTC, but the zone is the caller's to name
        (a "UTC" after it, or a column header that says so). Empty or null input
        returns an empty string; text that does not parse comes back as given.

    .PARAMETER Value
        A [datetime] or date text.

    .OUTPUTS
        [string].
    #>
    [CmdletBinding()]
    param($Value)
    if ($null -eq $Value) { return '' }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString('d MMM yyyy HH:mm', $inv)
    }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($s, $inv, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
        return $parsed.ToUniversalTime().ToString('d MMM yyyy HH:mm', $inv)
    }
    return $s
}
