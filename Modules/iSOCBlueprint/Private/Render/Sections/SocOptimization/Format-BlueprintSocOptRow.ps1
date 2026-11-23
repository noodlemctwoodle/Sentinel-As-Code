#Requires -Version 7.6

<#
.SYNOPSIS
    Build one row of a SOC optimisation table.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/SocOptimization/Format-BlueprintSocOptRow.ps1
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

function Format-BlueprintSocOptRow {
    <#
    .SYNOPSIS
        Build one row of a SOC optimisation table.

    .DESCRIPTION
        The row has Title, AffectedItem (the named field of the recommendation
        additional properties), State and Description, with runs of whitespace in
        the description collapsed to one space.

    .PARAMETER Item
        The SOC optimisation recommendation.

    .PARAMETER AffectedField
        The name of the field in the recommendation's additional properties that
        holds the affected item.

    .OUTPUTS
        [pscustomobject].
    #>
    [CmdletBinding()]
    param($Item, [string]$AffectedField)
    [pscustomobject]@{
        Title        = $Item.properties.title
        AffectedItem = $Item.properties.additionalProperties.$AffectedField
        State        = $Item.properties.state
        Description  = ($Item.properties.description -replace '\s+', ' ')
    }
}
