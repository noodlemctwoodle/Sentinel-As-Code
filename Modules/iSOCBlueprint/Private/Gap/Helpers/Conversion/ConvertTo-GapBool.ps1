#Requires -Version 7.6

<#
.SYNOPSIS
    A KQL result cell or flag as a boolean.

.DESCRIPTION
    KQL result cells arrive as strings from Invoke-AzOperationalInsightsQuery
    and as typed values from fixture files, so every numeric read goes through
    ConvertTo-GapInt or ConvertTo-GapDouble and every flag through ConvertTo-GapBool.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Conversion/ConvertTo-GapBool.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function ConvertTo-GapBool {
    <#
    .SYNOPSIS
        A KQL result cell or flag as a boolean.

    .DESCRIPTION
        $null is $false and a [bool] is returned as it is. Anything else is
        $true only when its trimmed text is "true", compared without regard
        to case.

    .PARAMETER Value
        The cell or flag to read.

    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    param([object]$Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return $Value }
    return ([string]$Value).Trim() -eq 'true'
}
