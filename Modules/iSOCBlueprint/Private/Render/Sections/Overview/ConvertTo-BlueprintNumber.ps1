#Requires -Version 7.6

<#
.SYNOPSIS
    Parse a KQL result cell as a number.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Overview/ConvertTo-BlueprintNumber.ps1
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

function ConvertTo-BlueprintNumber {
    <#
    .SYNOPSIS
        Parse a KQL result cell as a number.

    .DESCRIPTION
        KQL result cells arrive as strings; fixtures carry typed values. Parse
        rather than cast so neither shape throws. Parsed in the invariant culture; a
        null or unparseable value gives 0.

    .PARAMETER Value
        The cell value.

    .OUTPUTS
        [double].
    #>
    [OutputType([double])]
    [CmdletBinding()]
    param($Value)
    if ($null -eq $Value) { return 0.0 }
    $d = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
        return $d
    }
    return 0.0
}
