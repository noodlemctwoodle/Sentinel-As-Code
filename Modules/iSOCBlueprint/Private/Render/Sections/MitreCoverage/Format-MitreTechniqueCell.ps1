#Requires -Version 7.6

<#
.SYNOPSIS
    Format a MITRE technique for a table cell.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/MitreCoverage/Format-MitreTechniqueCell.ps1
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

function Format-MitreTechniqueCell {
    <#
    .SYNOPSIS
        Format a MITRE technique for a table cell.

    .DESCRIPTION
        Returns an empty string when Id is empty. Otherwise a Markdown link to the
        technique page on attack.mitre.org. The link text is the id followed by the
        name when the name is in the calling section's $techNameById, and the id
        alone when it is not.

    .PARAMETER Id
        The technique id.

    .PARAMETER Sub
        True for a sub-technique id, whose dot becomes a slash in the link. Defaults
        to $false.

    .OUTPUTS
        [string] of Markdown.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param([string]$Id, [bool]$Sub = $false)
    if (-not $Id) { return '' }
    $name = $techNameById[$Id]
    $urlId = if ($Sub) { $Id.Replace('.', '/') } else { $Id }
    if ($name) {
        return "[${Id}: $name](https://attack.mitre.org/techniques/$urlId/)"
    }
    return "[$Id](https://attack.mitre.org/techniques/$urlId/)"
}
