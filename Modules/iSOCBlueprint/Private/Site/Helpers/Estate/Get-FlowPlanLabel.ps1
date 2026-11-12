#Requires -Version 7.6

<#
.SYNOPSIS
    The plan label for a node of the estate flow.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Estate/Get-FlowPlanLabel.ps1
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

function Get-FlowPlanLabel {
    param([string]$Table, [string]$Plan)
    if ($Plan -in @('Basic', 'Auxiliary')) { return "$Plan plan" }
    if ($Plan -eq 'DataLake') { return $script:FlowTierLabel.LakeOnly }
    $res = if ($Table -and $wsTableByName.ContainsKey($Table)) { $wsTableByName[$Table] } else { $null }
    if ($null -eq $res) { return $(if ($lakeEnrolled) { $script:FlowTierLabel.MirroredOnly } else { $script:FlowTierLabel.AnalyticsOnly }) }
    return $script:FlowTierLabel[(Get-TableTier -Table $res -LakeEnrolled $lakeEnrolled)]
}
