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
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

# The incident lifecycle as data for the SharePoint graphic (the chart web
# part's incident-lifecycle visual): the window's incidents at their
# current status, how the closed ones got there (acknowledged first, or
# closed straight from New), the response times, how they were classified
# and who closed them. It rides in the Mermaid block on a %% line, which
# Mermaid ignores and ConvertFrom-BlueprintMermaid reads; a figure the
# capture lacks is null and the graphic leaves it out.
function ConvertTo-LifecycleList {
    param([System.Collections.IDictionary]$Bag, [string[]]$Order, [hashtable]$Labels)
    if (-not $Bag -or -not $Bag.Count) { return ,@() }
    $keys = @($Bag.Keys | ForEach-Object { [string]$_ })
    $sorted = if ($Order) { @($Order | Where-Object { $keys -contains $_ }) + @($keys | Where-Object { $Order -notcontains $_ } | Sort-Object) }
              else { @($keys | Sort-Object @{ Expression = { [long]$Bag[$_] }; Descending = $true }, @{ Expression = { $_ } }) }
    return ,@($sorted | Where-Object { [long]$Bag[$_] -gt 0 } | ForEach-Object {
        [ordered]@{ label = $(if ($Labels -and $Labels.ContainsKey($_)) { $Labels[$_] } else { $_ }); count = [long]$Bag[$_] }
    })
}
