#Requires -Version 7.6

<#
.SYNOPSIS
    Turn the incident lifecycle into data for the SharePoint graphic.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Incidents/ConvertTo-LifecycleList.ps1
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

function ConvertTo-LifecycleList {
    <#
    .SYNOPSIS
        Turn the incident lifecycle into data for the SharePoint graphic.

    .DESCRIPTION
        Keys whose count is zero or less are left out. With Order, the keys named
        there come first in that order, then any others alphabetically; without it
        the largest count comes first, then by name. A null or empty bag gives an
        empty array.

    .PARAMETER Bag
        A map of key to count.

    .PARAMETER Order
        The keys to list first, in this order.

    .PARAMETER Labels
        A map of key to display label. A key with no entry uses the key as its
        label.

    .OUTPUTS
        An array (kept as an array when empty) of ordered maps with label and count.
    #>
    [CmdletBinding()]
    param([System.Collections.IDictionary]$Bag, [string[]]$Order, [hashtable]$Labels)
    if (-not $Bag -or -not $Bag.Count) { return ,@() }
    $keys = @($Bag.Keys | ForEach-Object { [string]$_ })
    $sorted = if ($Order) { @($Order | Where-Object { $keys -contains $_ }) + @($keys | Where-Object { $Order -notcontains $_ } | Sort-Object) }
              else { @($keys | Sort-Object @{ Expression = { [long]$Bag[$_] }; Descending = $true }, @{ Expression = { $_ } }) }
    return ,@($sorted | Where-Object { [long]$Bag[$_] -gt 0 } | ForEach-Object {
        [ordered]@{ label = $(if ($Labels -and $Labels.ContainsKey($_)) { $Labels[$_] } else { $_ }); count = [long]$Bag[$_] }
    })
}
