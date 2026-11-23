#Requires -Version 7.6

<#
.SYNOPSIS
    Read the items of a dynamic KQL column as an array.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Inventory/Get-BlueprintRawList.ps1
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

function Get-BlueprintRawList {
    <#
    .SYNOPSIS
        Read the items of a dynamic KQL column as an array.

    .DESCRIPTION
        The items of a dynamic column (make_set, make_list): an array from a
        fixture, JSON text ('["Success","Failure"]') from Log Analytics. Text that
        starts with [ is read as JSON, and is returned as one item when it does not
        parse. Other non-empty text is one item; empty text and $null give an empty
        array.

    .PARAMETER Value
        An array, or JSON or plain text.

    .OUTPUTS
        [string[]].
    #>
    [OutputType([object[]])]
    [CmdletBinding()]
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        $t = $Value.Trim()
        if ($t.StartsWith('[')) { try { return @($t | ConvertFrom-Json -ErrorAction Stop | ForEach-Object { [string]$_ }) } catch { return @($t) } }
        return $(if ($t) { @($t) } else { @() })
    }
    return @($Value | ForEach-Object { [string]$_ })
}
