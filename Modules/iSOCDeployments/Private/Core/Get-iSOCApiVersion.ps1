#Requires -Version 7.2

<#
.SYNOPSIS
    The API versions every iSOCDeployments request uses, in one table.

.DESCRIPTION
    The scripts this module replaces each pinned their own versions at the
    top of the file. They are collected here so a version moves in one
    place, and Docs/Modules/iSOCDeployments/Architecture.md lists them.

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/Get-iSOCApiVersion.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.4.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCApiVersion {
    <#
    .SYNOPSIS
        Look up one API version by name, or return the whole table.

    .DESCRIPTION
        Names and what they cover:

          SecurityInsights         Microsoft.SecurityInsights GA: watchlists,
                                   automation rules, metadata, Content Hub
          SecurityInsightsPreview  Microsoft.SecurityInsights alert rules; the
                                   preview keeps subTechniques, which GA drops
          OperationalInsights      Log Analytics workspaces and tables
          SavedSearches            Log Analytics saved searches (parsers and
                                   hunting queries)
          SummaryRules             Log Analytics summary rules
          Workbooks                Microsoft.Insights workbooks
          Deployments              Microsoft.Resources deployments
          ResourceGroups           Microsoft.Resources resource groups
          LogicApps                Microsoft.Logic workflows (playbooks), for
                                   reading them; they deploy as ARM templates
          DataCollectionRules      Microsoft.Insights data collection rules;
                                   2023-03-11 is the first with endpoints
          GraphSecurity            Microsoft Graph security (Defender XDR
                                   custom detections), a Graph version segment
                                   rather than an api-version

    .PARAMETER Name
        The entry to return. Without it the whole table is returned.

    .OUTPUTS
        [string] for one entry; [System.Collections.Specialized.OrderedDictionary]
        for the table.

    .EXAMPLE
        Get-iSOCApiVersion SecurityInsightsPreview
    #>
    [CmdletBinding()]
    [OutputType([string], [System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Position = 0)]
        [string] $Name
    )

    $table = [ordered]@{
        SecurityInsights        = '2025-09-01'
        SecurityInsightsPreview = '2025-07-01-preview'
        OperationalInsights     = '2022-10-01'
        SavedSearches           = '2025-07-01'
        SummaryRules            = '2025-07-01'
        Workbooks               = '2022-04-01'
        Deployments             = '2024-11-01'
        ResourceGroups          = '2021-04-01'
        LogicApps               = '2019-05-01'
        Authorization           = '2022-04-01'
        Automation              = '2023-11-01'
        DataCollectionRules     = '2023-03-11'
        GraphSecurity           = 'beta'
    }

    if (-not $Name) { return $table }
    if (-not $table.Contains($Name)) {
        throw "Unknown API '$Name'. Known: $($table.Keys -join ', ')."
    }
    $table[$Name]
}
