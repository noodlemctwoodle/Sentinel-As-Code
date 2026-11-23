#Requires -Version 7.6

<#
.SYNOPSIS
    The billed GB a table carries in the estate flow.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Estate/Get-FlowBilledGb.ps1
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

# ---- Ingest / billing flow (grounded in cost-estimate) ----
function Get-FlowBilledGb {
    <#
    .SYNOPSIS
        The GB of a table that is billed in the estate flow.

    .DESCRIPTION
        A table's GB is billed in full unless a data grant may cover it. A
        cost-estimate row with a Benefit property marks a grant by a non-empty
        Benefit, and its GB is then not billed. An estimate from before the
        grants were reported has no Benefit property, and marks them by a zero
        monthly cost instead.

    .PARAMETER Row
        The table's row from the cost estimate, read for its Benefit and
        MonthlyCost properties.

    .PARAMETER Gb
        The table's GB, returned as it is when the table is billed.

    .OUTPUTS
        [double] Gb when the table is billed, 0.0 when a grant covers it.
    #>
    [CmdletBinding()]
    param($Row, [double]$Gb)
    if ($Row.PSObject.Properties['Benefit']) { return $(if ([string]$Row.Benefit) { 0.0 } else { $Gb }) }
    return $(if ([double]$Row.MonthlyCost -gt 0) { $Gb } else { 0.0 })
}
