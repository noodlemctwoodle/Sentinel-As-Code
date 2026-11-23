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
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-BlueprintDcrTargetsWorkspace {
    <#
    .SYNOPSIS
        Test whether a data collection rule sends to this workspace.

    .DESCRIPTION
        Splits data collection rules into in-scope (at least one Log Analytics
        destination targets this workspace) and out-of-scope (targeting other
        workspaces in the same subscription). The exporter captures rules at
        subscription scope, so without this filter a workspace report lists every
        rule the executing identity can see, even ones that have nothing to do with
        this workspace. Returns $true when no workspace id is given. Otherwise it is
        $true when one of the rule's Log Analytics destinations has that workspace
        resource id (compared without regard to case), and $false when none does or
        the rule has no destinations.

    .PARAMETER Dcr
        The data collection rule resource.

    .PARAMETER WorkspaceId
        The workspace resource id to look for. When empty every rule counts as
        targeting it.

    .OUTPUTS
        [bool].
    #>
    [CmdletBinding()]
    param($Dcr, [string]$WorkspaceId)
    if (-not $WorkspaceId) { return $true }
    if (-not $Dcr.properties.PSObject.Properties.Name -contains 'destinations' -or -not $Dcr.properties.destinations) { return $false }
    if (-not $Dcr.properties.destinations.PSObject.Properties.Name -contains 'logAnalytics') { return $false }
    foreach ($d in @($Dcr.properties.destinations.logAnalytics)) {
        if ([string]::Equals([string]$d.workspaceResourceId, $WorkspaceId, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}
