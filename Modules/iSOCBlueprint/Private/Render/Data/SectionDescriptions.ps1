#Requires -Version 7.6

<#
.SYNOPSIS
    One-line description of each report section, by file name.

.DESCRIPTION
    Defines $script:SectionDescriptions for the Blueprint renderer when the module loads.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Data/SectionDescriptions.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines a lookup table rather than running.
#>


# What each page covers, for the pages whose opening does not already say:
# Write-Section puts it under the title and the workspace line, so the
# Markdown, the SharePoint pages and the dashboard (above its inner tabs)
# all open with it.
$script:SectionDescriptions = @{
    '00-overview.md'                   = 'The whole assessment on one page: findings by severity, the headline counts, the estate flow, the maturity score, the estimated monthly cost and the most severe findings, each linking to the page that covers it in full.'
    '01-live-snapshot.md'              = 'A summary of the workspace as collected in this run: findings by severity, the workspace at a glance, the estate flow and the top recommendations, with pointers to the pages that go deeper.'
    '10-data-connectors.md'            = 'Which data sources feed the workspace: the classic and Codeless Connector Framework connectors, an effective view that combines them, how the connected ones compare with the Content Hub catalogue, their recent activity and the Defender XDR unification state.'
    '15-incidents.md'                  = 'How incidents move from creation to closure over the last {lookback}: response times, the incident lifecycle and analyst journey, the rules and providers that raise incidents, and how they are closed.'
    '16-alerts.md'                     = 'Alert volume over the last {lookback} by severity, by the product that raised it and by provider, showing where the alert load comes from.'
    '20-analytics-rules.md'            = 'Every analytics rule in the workspace: the mix of rule kinds and states, the full rule list, Microsoft incident-creation and Microsoft-managed rules, recent changes, the Content Hub solutions the rules came from, and Defender XDR custom detections.'
    '30-hunting-queries.md'            = 'The saved hunting queries by ATT&CK tactic, the hunts run in the workspace and the bookmarks analysts have kept.'
    '35-parsers-functions.md'          = 'The KQL parsers and functions saved in the workspace, by category, and its other saved searches.'
    '36-data-export.md'                = 'Where workspace data leaves or is linked: continuous data export rules, linked storage accounts, Azure Data Explorer clusters and other linked services.'
    '40-workbooks.md'                  = 'The workbooks saved in the workspace, how widely they are adopted, and the workbook templates the Content Hub offers.'
    '50-watchlists.md'                 = 'The watchlists in the workspace, which analytics rules use them, and any rule that refers to a watchlist that does not exist.'
    '60-automation-rules-playbooks.md' = 'How incidents are handled automatically: the automation rules, the Logic Apps playbooks they run, how those runs went in the last {lookback}, and recurring incident titles automation could take on.'
    '70-content-hub.md'                = 'Where the workspace content comes from: the Content Hub solutions installed, any that are deprecated or unlisted, connected repositories and legacy management solutions.'
    '80-workspace.md'                  = 'The Log Analytics workspace itself: its history and provenance, pricing tier, usage, networking and replication, resilience, feature flags, Sentinel onboarding and resource locks.'
    '81-table-plans-retention.md'      = 'Every table in the workspace by plan, retention and recent activity: which tables receive data, which have gone silent, orphan and legacy custom tables, and how well each is covered by detections.'
    '82-dedicated-cluster.md'          = 'Whether the workspace is linked to a Log Analytics dedicated cluster, and that cluster''s capacity reservation, billing and encryption settings.'
    '83-data-collection.md'            = 'How data reaches the workspace through Azure Monitor: the data collection rules and endpoints that target it, and other rules in the subscription that send elsewhere.'
    '84-cost-estimate.md'              = 'An estimate of the monthly cost from {lookback} of billable ingestion: cost by plan and by table, where it concentrates, how it flows to the billing tiers, what a commitment tier would save, and how the estimate is worked out.'
    '85-rbac.md'                       = 'Who can do what in the workspace: role assignments by role, the Microsoft Sentinel and Log Analytics roles, high-privilege assignments, and assignments at workspace and resource-group scope.'
    '91-maturity-assessment.md'        = 'How mature the workspace is, scored 0 to 5 across eleven capability areas from the gap findings and the captured configuration, with the roadmap of criteria to close to reach the target level.'
    '86-subscription-context.md'       = 'The Azure subscription and tenant around the workspace: the subscription, the identity that ran the collection, resource-provider registration, locks and the policy assignments that affect Sentinel.'
}
