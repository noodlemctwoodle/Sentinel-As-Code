#Requires -Version 7.6

<#
.SYNOPSIS
    Family display order. Navigation and the dashboard list families in this

.DESCRIPTION
    One of the helpers beside Get-SectionFamily.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SiteShared/Data/SacSectionFamilyOrder.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-08
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file sets a script-scope value rather than running.
#>

# Family display order. Navigation and the dashboard list families in this
# order, not alphabetically.
$script:SacSectionFamilyOrder = @(
    'Overview'
    'Data sources'
    'Operational health'
    'Detection'
    'Hunting & content'
    'Automation'
    'Workspace'
    'Cost & access'
    'Assessment'
    'References'
)
