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
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-FeatureFlag {
    <#
    .SYNOPSIS
        Show a workspace feature flag as text.

    .DESCRIPTION
        The Sentinel API omits these fields when they are at their default value
        (False), so a missing property must show as False and not as an empty cell.
        Otherwise readers cannot tell "disabled by default" from "the report did not
        capture this field". Returns 'False' when the container is null, has no such
        property or the property is null; otherwise the property's value as a
        string.

    .PARAMETER Container
        The object that may hold the flag.

    .PARAMETER Property
        The name of the flag property.

    .OUTPUTS
        [string].
    #>
    [CmdletBinding()]
    param([psobject]$Container, [string]$Property)
    if ($null -eq $Container) { return 'False' }
    if ($Container.PSObject.Properties.Name -notcontains $Property) { return 'False' }
    $val = $Container.$Property
    if ($null -eq $val) { return 'False' }
    return [string]$val
}
