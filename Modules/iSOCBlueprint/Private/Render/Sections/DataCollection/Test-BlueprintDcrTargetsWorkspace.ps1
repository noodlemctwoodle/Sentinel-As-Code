#Requires -Version 7.6

<#
.SYNOPSIS
    Test whether a data collection rule sends to this workspace.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/DataCollection/Test-BlueprintDcrTargetsWorkspace.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

# Split DCRs into in-scope (at least one LA destination targets this
# workspace) and out-of-scope (targeting other workspaces in the same
# subscription). The exporter captures DCRs at subscription scope, so
# without this filter a workspace's report lists every DCR the
# executing identity can see — even ones that have nothing to do with
# this workspace, which is confusing.
function Test-BlueprintDcrTargetsWorkspace {
    param($Dcr, [string]$WorkspaceId)
    if (-not $WorkspaceId) { return $true }
    if (-not $Dcr.properties.PSObject.Properties.Name -contains 'destinations' -or -not $Dcr.properties.destinations) { return $false }
    if (-not $Dcr.properties.destinations.PSObject.Properties.Name -contains 'logAnalytics') { return $false }
    foreach ($d in @($Dcr.properties.destinations.logAnalytics)) {
        if ([string]::Equals([string]$d.workspaceResourceId, $WorkspaceId, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}
