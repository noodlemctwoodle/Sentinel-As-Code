#Requires -Version 7.6

<#
.SYNOPSIS
    Find the Content Hub solution an analytics rule template comes from, and
    whether that solution is installed.

.DESCRIPTION
    The alert-rule templates the collector saves (alert-rule-templates.json)
    do not name their solution. The Content Hub packages do the reverse: each
    package lists the content it ships under properties.dependencies, nested
    criteria with a contentId and a kind, and an analytics rule's contentId
    is the template's id. Reading the installed packages
    (content-packages.json) and the Content Hub catalogue
    (content-product-packages.json) gives every template's solution; a
    template neither lists is a built-in gallery template that no solution
    ships.

    The catalogue flags a solution Microsoft has retired (isDeprecated), such
    as Threat Intelligence, replaced by Threat Intelligence (NEW). A template
    a live solution also ships is credited to the live one; a template only
    deprecated solutions ship is marked Deprecated, with the replacement
    solution when the catalogue names one, and the detection opportunities
    (renderer, dashboard and the SAC-DET gap check) leave it out of what is
    ready to enable.

    The renderer's detection opportunities page and the SharePoint
    dashboard read this, so the two agree.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Get-TemplateSolution.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.2.3
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-TemplateSolution {
    <#
    .SYNOPSIS
        One template's solution from the map, or Built-in when no package
        ships it (Installed is then $null).

    .PARAMETER Map
        From Get-TemplateSolutionMap.

    .PARAMETER TemplateId
        The template's id (its name in alert-rule-templates.json).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([AllowNull()] [hashtable] $Map, [AllowEmptyString()] [string] $TemplateId)

    $key = ([string]$TemplateId).ToLowerInvariant()
    if ($Map -and $key -and $Map.ContainsKey($key)) { return $Map[$key] }
    return [pscustomobject]@{ Solution = 'Built-in'; Installed = $null; Deprecated = $false; ReplacedBy = $null }
}
