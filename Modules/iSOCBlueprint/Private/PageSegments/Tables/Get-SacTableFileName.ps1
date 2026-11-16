#Requires -Version 7.6

<#
.SYNOPSIS
    The CSV file name for a cut table: the section id and the heading above the table, lower
    case, letters, digits and hyphens only, with -2, -3 and so on when the section has more than
    one under a heading.

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Tables/Get-SacTableFileName.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, SharePoint page conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-SacTableFileName {
    <#
    .SYNOPSIS
        The CSV file name for a cut table: the section id and the heading
        above the table, lower case, letters, digits and hyphens only, with
        -2, -3 and so on when the section has more than one under a heading.

    .PARAMETER Taken
        File names already given out in this section.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Id,
        [AllowEmptyString()] [string] $Heading,
        [AllowEmptyCollection()] [string[]] $Taken = @()
    )
    $slug = ($Heading.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($slug.Length -gt 60) { $slug = $slug.Substring(0, 60).TrimEnd('-') }
    $stem = if ($slug) { "$Id-$slug" } else { "$Id-table" }
    $name = "$stem.csv"
    $n = 2
    while ($Taken -contains $name) { $name = "$stem-$n.csv"; $n++ }
    return $name
}
