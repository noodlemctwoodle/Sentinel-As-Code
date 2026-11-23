#Requires -Version 7.6

<#
.SYNOPSIS
    Write the lead of the top-findings sentence.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Format-TopFindingsLead.ps1
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

function Format-TopFindingsLead {
    <#
    .SYNOPSIS
        Write the lead of the top-findings sentence.

    .DESCRIPTION
        The lead of the top-findings sentence: how many of how many are shown. The
        wording is "The one finding," for a total of one, "All N findings, each"
        when every finding is shown, "The most severe of N findings," for one shown,
        and "The S most severe of N findings, each" otherwise.

    .PARAMETER Shown
        How many findings the page lists.

    .PARAMETER Total
        How many findings there are.

    .OUTPUTS
        [string].
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param([int]$Shown, [int]$Total)
    $of = Format-BlueprintPlural $Total 'finding'
    if ($Total -eq 1) { return 'The one finding,' }
    if ($Shown -ge $Total) { return "All $of, each" }
    if ($Shown -eq 1) { return "The most severe of $of," }
    return "The $Shown most severe of $of, each"
}
