#Requires -Version 7.6

<#
.SYNOPSIS
    Return the family names in display order, with 'Other' last

.DESCRIPTION
    One of the helpers beside Get-SectionFamily.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SiteShared/Get-SectionFamilyOrder.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-08
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SectionFamilyOrder {
    <#
    .SYNOPSIS
        Return the family names in display order, with 'Other' last.

    .OUTPUTS
        [string[]]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @($script:SacSectionFamilyOrder) + 'Other'
}
