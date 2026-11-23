#Requires -Version 7.6

<#
.SYNOPSIS
    Convert a date-like value to a UTC datetime, or $null when it is not one.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Dates/ConvertTo-UtcDateTime.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-UtcDateTime {
    <#
    .SYNOPSIS
        Convert a date-like value to a UTC datetime, or $null when it is not one.

    .DESCRIPTION
        The sort key to keep beside Format-DateUtc text, which does not sort as time
        ("9 Oct" falls after "15 Oct"). A [datetime] is converted to UTC. Any other
        value is parsed as text in the invariant culture, taken as UTC when it names
        no zone.

    .PARAMETER Value
        A [datetime] or date text. $null, or text that does not parse, gives $null.

    .OUTPUTS
        [datetime] in UTC, or $null.
    #>
    [CmdletBinding()]
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal,
            [ref]$parsed)) {
        return $parsed.ToUniversalTime()
    }
    return $null
}
