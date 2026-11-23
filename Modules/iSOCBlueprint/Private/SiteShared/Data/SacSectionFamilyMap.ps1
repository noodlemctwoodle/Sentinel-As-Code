#Requires -Version 7.6

<#
.SYNOPSIS
    The value SacSectionFamilyMap the Get-SectionFamily functions read.

.DESCRIPTION
    One of the helpers beside Get-SectionFamily.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SiteShared/Data/SacSectionFamilyMap.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-08
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file sets a script-scope value rather than running.
#>

$script:SacSectionFamilyMap = @{
    0  = 'Overview'                # 00-overview
    1  = 'Overview'                # 01-live-snapshot
    2  = 'Overview'                # 02-deprecated-legacy-features
    3  = 'Overview'                # 03-whats-new
    10 = 'Data sources'            # 10-data-connectors
    11 = 'Operational health'      # 11-sentinel-health
    12 = 'Operational health'      # 12-soc-optimization
    13 = 'Data sources'            # 13-data-source-hygiene
    14 = 'Data sources'            # 14-coverage-breakdowns
    15 = 'Operational health'      # 15-incidents
    16 = 'Operational health'      # 16-alerts
    20 = 'Detection'               # 20-analytics-rules (Microsoft rules, modifications, solutions and custom detections are subsections)
    21 = 'Detection'               # 21-rule-performance
    22 = 'Detection'               # 22-rule-health-quality
    25 = 'Detection'               # 25-mitre-coverage
    26 = 'Detection'               # 26-ueba
    27 = 'Detection'               # 27-threat-intelligence
    28 = 'Detection'               # 28-detection-opportunities
    30 = 'Hunting & content'       # 30-hunting-queries
    35 = 'Hunting & content'       # 35-parsers-functions
    36 = 'Workspace'        # 36-data-export
    37 = 'Workspace'        # 37-search-restore
    38 = 'Hunting & content'       # 38-summary-rules
    40 = 'Hunting & content'       # 40-workbooks
    50 = 'Hunting & content'       # 50-watchlists
    60 = 'Automation'              # 60-automation-rules-playbooks
    70 = 'Hunting & content'       # 70-content-hub
    80 = 'Workspace'        # 80-workspace
    81 = 'Workspace'        # 81-table-plans-retention
    82 = 'Workspace'        # 82-dedicated-cluster
    83 = 'Workspace'        # 83-data-collection
    84 = 'Cost & access'           # 84-cost-estimate
    85 = 'Cost & access'           # 85-rbac
    86 = 'Workspace'        # 86-subscription-context
    87 = 'Workspace'        # 87-azure-monitor-agents
    88 = 'Workspace'        # 88-sentinel-data-lake
    89 = 'Workspace'        # 89-retention
    90 = 'Assessment'              # 90-gap-analysis (the findings)
    91 = 'Assessment'              # 91-maturity-assessment
    96 = 'References'              # 96-references-microsoft
    99 = 'References'              # 99-references
}
