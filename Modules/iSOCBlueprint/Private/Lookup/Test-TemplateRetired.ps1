#Requires -Version 7.6

<#
.SYNOPSIS
    Whether only deprecated Content Hub solutions ship a template, so it is not one to enable

.DESCRIPTION
    One of the helpers beside Get-TemplateSolution.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Test-TemplateRetired.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-TemplateRetired {
    <#
    .SYNOPSIS
        Whether only deprecated Content Hub solutions ship a template, so it
        is not one to enable.

    .PARAMETER Map
        From Get-TemplateSolutionMap.

    .PARAMETER TemplateId
        The template's id (its name in alert-rule-templates.json).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()] [hashtable] $Map, [AllowEmptyString()] [string] $TemplateId)

    $s = Get-TemplateSolution -Map $Map -TemplateId $TemplateId
    return [bool]($s.PSObject.Properties.Name -contains 'Deprecated' -and $s.Deprecated)
}
