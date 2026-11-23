#Requires -Version 7.6

<#
.SYNOPSIS
    Read a property, or a default when the object or property is absent.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Inventory/Get-BlueprintRawProperty.ps1
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

# Helpers
# ---------------------------------------------------------------------------
function Get-BlueprintRawProperty {
    <#
    .SYNOPSIS
        Read a property, or a default when the object or property is absent.

    .DESCRIPTION
        A StrictMode-safe property read: the default is returned when the object is
        null, the property is missing or its value is null.

    .PARAMETER Object
        The object to read from.

    .PARAMETER Name
        The property name.

    .PARAMETER Default
        What to return when there is no value. Defaults to $null.
    #>
    [CmdletBinding()]
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}
