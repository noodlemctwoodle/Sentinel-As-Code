#Requires -Version 7.6

<#
.SYNOPSIS
    Return the SharePoint page name (no .aspx) for a section id or file name.

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Names/Get-SacPageName.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, SharePoint page conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-SacPageName {
    <#
    .SYNOPSIS
        Return the SharePoint page name (no .aspx) for a section id or file
        name.

    .PARAMETER FileName
        Section id or file name, for example '25-mitre-coverage' or
        '25-mitre-coverage.md'.

    .OUTPUTS
        [string] For example 'sac-25-mitre-coverage'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $FileName)

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($FileName).ToLowerInvariant()
    $stem = ($stem -replace '[^a-z0-9-]', '-') -replace '-{2,}', '-'
    return "sac-$stem"
}
