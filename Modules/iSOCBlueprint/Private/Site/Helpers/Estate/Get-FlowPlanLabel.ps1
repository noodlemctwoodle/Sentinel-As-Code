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
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-FlowPlanLabel {
    <#
    .SYNOPSIS
        The plan label for a node of the estate flow.

    .DESCRIPTION
        A Basic or Auxiliary plan is labelled "<plan> plan", and a DataLake plan
        takes the LakeOnly entry of $script:FlowTierLabel. Any other plan is
        looked up by table name in $wsTableByName, which the function reads from
        the calling scope together with $lakeEnrolled. A table not found there
        takes the MirroredOnly entry when the workspace is enrolled in the lake
        and the AnalyticsOnly entry when it is not. A table found takes the
        entry for its tier from Get-TableTier.

    .PARAMETER Table
        The table name, looked up in $wsTableByName. It may be empty.

    .PARAMETER Plan
        The table's plan. Basic, Auxiliary and DataLake are labelled directly;
        any other value is labelled from the lookup by Table.

    .OUTPUTS
        [string] The label.
    #>
    [CmdletBinding()]
    param([string]$Table, [string]$Plan)
    if ($Plan -in @('Basic', 'Auxiliary')) { return "$Plan plan" }
    if ($Plan -eq 'DataLake') { return $script:FlowTierLabel.LakeOnly }
    $res = if ($Table -and $wsTableByName.ContainsKey($Table)) { $wsTableByName[$Table] } else { $null }
    if ($null -eq $res) { return $(if ($lakeEnrolled) { $script:FlowTierLabel.MirroredOnly } else { $script:FlowTierLabel.AnalyticsOnly }) }
    return $script:FlowTierLabel[(Get-TableTier -Table $res -LakeEnrolled $lakeEnrolled)]
}
