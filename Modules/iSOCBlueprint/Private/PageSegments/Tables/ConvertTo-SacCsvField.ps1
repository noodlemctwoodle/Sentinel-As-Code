#Requires -Version 7.6

<#
.SYNOPSIS
    One CSV field: quoted when it holds a comma, quote or line break, and kept from being read as a formula.

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Tables/ConvertTo-SacCsvField.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, SharePoint page conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function ConvertTo-SacCsvField {
    <#
    .SYNOPSIS
        One CSV field: quoted when it holds a comma, quote or line break,
        and kept from being read as a formula.

    .DESCRIPTION
        A cell can carry text from the workspace (a rule name, an incident
        title) that someone outside the SOC influenced. Excel runs a cell
        that starts with =, +, -, @, a tab or a carriage return as a
        formula, so such a field is prefixed with an apostrophe, which Excel
        shows as text. A plain negative number is left alone.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Value)
    $v = $Value
    if ($v -match '^[=+\-@\t\r]' -and $v -notmatch '^-\d+(\.\d+)?$') { $v = "'" + $v }
    if ($v -match '[",\r\n]') { $v = '"' + $v.Replace('"', '""') + '"' }
    return $v
}
