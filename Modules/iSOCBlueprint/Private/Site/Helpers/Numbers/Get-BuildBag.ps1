#Requires -Version 7.6

<#
.SYNOPSIS
    A KQL dynamic bag as a name to number map.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Numbers/Get-BuildBag.ps1
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

function Get-BuildBag {
    <#
    .SYNOPSIS
        A KQL dynamic bag as an ordered name to number map.

    .DESCRIPTION
        The bag, such as ByClassification, may arrive as an object or as JSON
        text. Each of its properties becomes an entry whose value is the
        property parsed as a [long] through ConvertTo-BuildNumber. A null value,
        blank text, text that is not valid JSON and a JSON null all give an
        empty map.

    .PARAMETER Value
        The bag: an object, or JSON text of one.

    .OUTPUTS
        [ordered] A dictionary of name to [long].
    #>
    [CmdletBinding()]
    param($Value)
    $bag = [ordered]@{}
    if ($null -eq $Value) { return $bag }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return $bag }
        try { $Value = $Value | ConvertFrom-Json } catch { return $bag }
        if ($null -eq $Value) { return $bag }
    }
    foreach ($prop in $Value.PSObject.Properties) { $bag[$prop.Name] = [long](ConvertTo-BuildNumber $prop.Value) }
    return $bag
}
