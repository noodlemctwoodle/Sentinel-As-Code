#Requires -Version 7.6

<#
.SYNOPSIS
    A volume in GB as the dashboard writes it: two decimal places with thousands separators
    (56,941.81), <0.01 for a volume too small to show, 0.00 for none. The caller adds ' GB'.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Format/Numbers/Format-BlueprintGb.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Blueprint text formatting
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-BlueprintGb {
    <#
    .SYNOPSIS
        A volume in GB as the dashboard writes it: two decimal places with
        thousands separators (56,941.81), <0.01 for a volume too small to
        show, 0.00 for none. The caller adds ' GB'.

    .PARAMETER Value
        GB, as a number or numeric string.

    .OUTPUTS
        [string]; the input as text when it is not a number, '' for $null.
    #>
    [CmdletBinding()]
    param([AllowNull()] $Value)
    $d = ConvertTo-BlueprintDouble $Value
    if ($null -eq $d) { return $(if ($null -eq $Value) { '' } else { [string]$Value }) }
    if ($d -gt 0 -and $d -lt 0.005) { return '<0.01' }
    Format-BlueprintNumber -Value $d -Decimals 2
}
