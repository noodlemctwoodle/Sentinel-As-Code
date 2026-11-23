#Requires -Version 7.6

<#
.SYNOPSIS
    One ring of the estate chart: a value out of a maximum, with its percentage.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Estate/New-EstateRing.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function New-EstateRing {
    <#
    .SYNOPSIS
        One ring of the estate chart: a value out of a maximum, with its
        percentage.

    .DESCRIPTION
        The percentage is rounded to a whole number, and is $null when Max is
        not above zero.

    .PARAMETER Label
        The ring's caption.

    .PARAMETER Value
        The count the ring shows.

    .PARAMETER Max
        The count Value is measured against.

    .OUTPUTS
        [ordered] A dictionary with label, value, max and pct.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; nothing outside the call changes.')]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [CmdletBinding()]
    param([string]$Label, [int]$Value, [int]$Max)
    [ordered]@{ label = $Label; value = $Value; max = $Max; pct = $(if ($Max -gt 0) { [int][math]::Round(100.0 * $Value / $Max, 0) } else { $null }) }
}
