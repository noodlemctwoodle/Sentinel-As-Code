#Requires -Version 7.6

<#
.SYNOPSIS
    True when a page property asks for a full-width section.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Pages/Test-SacFullWidthProperty.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Test-SacFullWidthProperty {
    <#
    .SYNOPSIS
        True when a web part's properties JSON carries isFullWidth = true,
        the flag PnP needs to save a page with the web part in a full-width
        section.

    .PARAMETER PropertiesJson
        The web part's PropertiesJson as Get-PnPPageComponent returns it.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowEmptyString()] [string] $PropertiesJson)

    if ([string]::IsNullOrWhiteSpace($PropertiesJson)) { return $false }
    try { $props = $PropertiesJson | ConvertFrom-Json -ErrorAction Stop } catch { return $false }
    return [bool]($props.PSObject.Properties['isFullWidth'] -and $props.isFullWidth -eq $true)
}
