#Requires -Version 7.6

<#
.SYNOPSIS
    Show a workspace feature flag as text.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Format-FeatureFlag.ps1
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

# Workspace feature-flag boolean → display string. The Sentinel API omits
# these fields when they're at their default value (= False), so a missing
# property must render as "False" not as an empty cell. Otherwise readers
# can't tell "disabled by default" from "report didn't capture this field".
function Format-FeatureFlag {
    param([psobject]$Container, [string]$Property)
    if ($null -eq $Container) { return 'False' }
    if ($Container.PSObject.Properties.Name -notcontains $Property) { return 'False' }
    $val = $Container.$Property
    if ($null -eq $val) { return 'False' }
    return [string]$val
}
