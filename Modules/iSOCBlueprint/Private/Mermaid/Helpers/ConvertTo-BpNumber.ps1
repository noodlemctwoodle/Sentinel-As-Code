#Requires -Version 7.6

<#
.SYNOPSIS
    Parse text as a number in the invariant culture, or $null when it is not one.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Helpers/ConvertTo-BpNumber.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.3
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Mermaid chart parsing
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-BpNumber {
    <#
    .SYNOPSIS
        Parse text as a number in the invariant culture, or $null when it is
        not one.

    .PARAMETER Text
        The text to parse. Surrounding whitespace is ignored.

    .OUTPUTS
        [double] The number, or $null when the text does not parse.
    #>
    [CmdletBinding()]
    param([string] $Text)
    $n = 0.0
    if ([double]::TryParse($Text.Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)) {
        return $n
    }
    return $null
}
