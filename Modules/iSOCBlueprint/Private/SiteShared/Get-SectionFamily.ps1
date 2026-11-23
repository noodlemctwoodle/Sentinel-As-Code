#Requires -Version 7.6

<#
.SYNOPSIS
    Map a Blueprint section number to the family it is grouped under on
    the iSOC Blueprint dashboard and in the SharePoint site navigation.

.DESCRIPTION
    The Markdown renderer numbers its section files (00-overview.md,
    25-mitre-coverage.md, ...). The numbers follow the formal Sentinel
    configuration table of contents, so a "tens digit" grouping puts
    unrelated sections together (hunting queries next to MITRE coverage,
    data export next to cost). This file holds an explicit table instead,
    shared by the dashboard Sections tab and the generated top navigation
    so both always agree.

    Numbers missing from the table fall back to the tens-digit grouping,
    then to 'Other', so a new renderer section still lands somewhere
    sensible until it is added here.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SiteShared/Get-SectionFamily.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-08
    Version:      0.2.4
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SectionFamily {
    <#
    .SYNOPSIS
        Return the family name for a section number.

    .PARAMETER Number
        The two-digit prefix of the section file name, as an integer.

    .OUTPUTS
        [string] One of the names in $script:SacSectionFamilyOrder, or
        'Other' for a number that neither the table nor the fallback
        recognises.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [int] $Number)

    if ($script:SacSectionFamilyMap.ContainsKey($Number)) {
        return $script:SacSectionFamilyMap[$Number]
    }

    switch ([math]::Floor($Number / 10)) {
        0 { return 'Overview' }
        1 { return 'Operational health' }
        2 { return 'Detection' }
        3 { return 'Hunting & content' }
        4 { return 'Hunting & content' }
        5 { return 'Hunting & content' }
        6 { return 'Automation' }
        7 { return 'Hunting & content' }
        8 { return 'Workspace' }
        9 { return $(if ($Number -ge 96) { 'References' } else { 'Assessment' }) }
        default { return 'Other' }
    }
}
