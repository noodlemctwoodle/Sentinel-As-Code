#Requires -Version 7.2

<#
.SYNOPSIS
    Map a Documenter section number to the family it is grouped under on
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
    File:         Tools/Documenter/SharePoint/Private/Get-SectionFamily.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-08
    Version:      0.1.0
    Last Updated: 2026-10-08
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
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
    'Workspace & data'
    'Cost & access'
    'Findings & references'
)

$script:SacSectionFamilyMap = @{
    0  = 'Overview'                # 00-overview
    1  = 'Overview'                # 01-live-snapshot
    10 = 'Data sources'            # 10-data-connectors
    11 = 'Operational health'      # 11-sentinel-health
    12 = 'Operational health'      # 12-soc-optimization
    13 = 'Data sources'            # 13-data-source-hygiene
    14 = 'Data sources'            # 14-coverage-breakdowns
    15 = 'Operational health'      # 15-incidents
    20 = 'Detection'               # 20-analytics-rules
    21 = 'Detection'               # 21-analytics-by-volume
    22 = 'Detection'               # 22-analytics-microsoft-rules
    23 = 'Detection'               # 23-analytics-modifications
    24 = 'Detection'               # 24-analytics-by-solution
    25 = 'Detection'               # 25-mitre-coverage
    26 = 'Detection'               # 26-ueba
    27 = 'Detection'               # 27-threat-intelligence
    30 = 'Hunting & content'       # 30-hunting-queries
    35 = 'Hunting & content'       # 35-parsers-functions
    36 = 'Workspace & data'        # 36-data-export
    37 = 'Workspace & data'        # 37-search-restore
    38 = 'Hunting & content'       # 38-summary-rules
    40 = 'Hunting & content'       # 40-workbooks
    50 = 'Hunting & content'       # 50-watchlists
    60 = 'Automation'              # 60-automation-rules-playbooks
    70 = 'Hunting & content'       # 70-content-hub
    80 = 'Workspace & data'        # 80-workspace
    81 = 'Workspace & data'        # 81-table-plans-retention
    82 = 'Workspace & data'        # 82-dedicated-cluster
    83 = 'Workspace & data'        # 83-data-collection
    84 = 'Cost & access'           # 84-cost-estimate
    85 = 'Cost & access'           # 85-rbac
    86 = 'Workspace & data'        # 86-subscription-context
    87 = 'Workspace & data'        # 87-azure-monitor-agents
    88 = 'Workspace & data'        # 88-sentinel-data-lake
    90 = 'Findings & references'   # 90-gap-analysis
    96 = 'Findings & references'   # 96-references-microsoft
    99 = 'Findings & references'   # 99-references
}

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
        8 { return 'Workspace & data' }
        9 { return 'Findings & references' }
        default { return 'Other' }
    }
}

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
