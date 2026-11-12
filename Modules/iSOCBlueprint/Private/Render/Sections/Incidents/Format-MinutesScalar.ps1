#Requires -Version 7.6

<#
.SYNOPSIS
    Format a minutes figure, treating NaN as no data.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Incidents/Format-MinutesScalar.ps1
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

function Format-MinutesScalar {
    param($Value, $CountAcknowledged)
    # KQL returns the literal string "NaN" when an aggregate had no rows to
    # average over (e.g. avg(int(null)) across zero rows), and Save-Json
    # writes that through verbatim. Treat any non-numeric input as
    # unavailable so the report shows "n/a" instead of the noisy "NaN min".
    if ($null -eq $Value) { return 'n/a' }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s) -or $s -eq 'NaN' -or $s -eq 'null') { return 'n/a' }
    $d = 0.0
    if (-not [double]::TryParse($s, [ref]$d)) { return 'n/a' }
    return "$(Format-BlueprintNumber -Value $d -Decimals 1) min"
}
