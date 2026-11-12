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
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

# ---- Ingest / billing flow (grounded in cost-estimate) ----
# A table's GB is billed in full unless a data grant may cover it. An
# estimate from before the grants were reported marks them by a zero cost.
function Get-FlowBilledGb {
    param($Row, [double]$Gb)
    if ($Row.PSObject.Properties['Benefit']) { return $(if ([string]$Row.Benefit) { 0.0 } else { $Gb }) }
    return $(if ([double]$Row.MonthlyCost -gt 0) { $Gb } else { 0.0 })
}
