#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 96-references-microsoft.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/ReferencesMicrosoft/Write-BlueprintReferencesMicrosoftSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintReferencesMicrosoftSection {
    <#
    .SYNOPSIS
        Build the figures for and write 96-references-microsoft.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $found = $Context.found
    $m = $Context.m
    $n = $Context.n

    # Section 96 — User-facing Microsoft references (TOC 6.x)
    Write-BlueprintSection '96-references-microsoft.md' (@"
$(Format-Banner -Title "Microsoft References")

Microsoft Learn pages for the topics this report covers, grouped by topic, the best-practice pages its findings link to among them. The Blueprint's own API versions, services, modules and queries are on [99-references.md](99-references.md).

## Microsoft Sentinel

| Page | Use it for |
| --- | --- |
| [Microsoft Sentinel documentation](https://learn.microsoft.com/azure/sentinel/) | The starting point for every Sentinel topic |
| [Best practices](https://learn.microsoft.com/azure/sentinel/best-practices) | Microsoft's recommendations for running Sentinel, which the findings measure against |
| [Deployment guide](https://learn.microsoft.com/azure/sentinel/deploy-overview) | Planning and rolling out a workspace, step by step |
| [Skill-up resources](https://learn.microsoft.com/azure/sentinel/skill-up-resources) | Training paths for analysts and engineers |
| [Move to the Defender portal](https://learn.microsoft.com/azure/sentinel/move-to-defender) | The move to the unified portal, as Sentinel in the Azure portal retires on 31 Mar 2027 |
| [Manage data overview](https://learn.microsoft.com/azure/sentinel/manage-data-overview) | How Sentinel stores, tiers and keeps data |

## Workspace design and resilience

| Page | Use it for |
| --- | --- |
| [Workspace design](https://learn.microsoft.com/azure/azure-monitor/logs/workspace-design) | Choosing how many workspaces, where, and for whom |
| [Sample workspace designs](https://learn.microsoft.com/azure/sentinel/sample-workspace-designs) | Worked designs for common organisations |
| [Workspace replication](https://learn.microsoft.com/azure/azure-monitor/logs/workspace-replication) | Keeping ingestion and queries running through a regional outage |
| [Dedicated clusters](https://learn.microsoft.com/azure/azure-monitor/logs/logs-dedicated-clusters) | When a dedicated cluster pays off, and what it adds |
| [Customer-managed keys](https://learn.microsoft.com/azure/azure-monitor/logs/customer-managed-keys) | Encrypting workspace data with your own key |
| [Azure Monitor Private Link Scope (AMPLS)](https://learn.microsoft.com/azure/azure-monitor/logs/private-link-security) | Keeping ingestion and queries on private networks |

## Data connectors and coverage

| Page | Use it for |
| --- | --- |
| [Data connectors reference](https://learn.microsoft.com/azure/sentinel/data-connectors-reference) | Every connector, what it collects and what it needs |
| [Prioritise data connectors](https://learn.microsoft.com/azure/sentinel/prioritize-data-connectors) | Which sources to connect first |
| [Tables and connectors map](https://learn.microsoft.com/azure/sentinel/sentinel-tables-connectors-reference) | Which connector fills which table |
| [Monitor connector health](https://learn.microsoft.com/azure/sentinel/monitor-data-connectors-health) | Health monitoring for connectors with SentinelHealth |
| [Codeless Connector Framework](https://learn.microsoft.com/azure/sentinel/create-codeless-connector) | Building a connector without code |
| [MITRE ATT&CK coverage](https://learn.microsoft.com/azure/sentinel/mitre-coverage) | Viewing detection coverage against MITRE ATT&CK |

## Content and automation

| Page | Use it for |
| --- | --- |
| [Content Hub solutions](https://learn.microsoft.com/azure/sentinel/sentinel-solutions) | Installing and keeping solutions current |
| [Repositories (CI/CD)](https://learn.microsoft.com/azure/sentinel/ci-cd) | Deploying content from source control |
| [Custom content in CI/CD](https://learn.microsoft.com/azure/sentinel/ci-cd-custom-content) | Customising repository deployments |
| [Automate responses with playbooks](https://learn.microsoft.com/azure/sentinel/automation/automate-responses-with-playbooks) | Playbooks and how automation rules call them |
| [Logic Apps documentation](https://learn.microsoft.com/azure/logic-apps/) | The platform playbooks run on |

## Log Analytics, tables and retention

| Page | Use it for |
| --- | --- |
| [Log Analytics overview](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview) | Querying workspace data in the portal |
| [KQL quick reference](https://learn.microsoft.com/azure/data-explorer/kql-quick-reference) | The query language at a glance |
| [Get started with log queries](https://learn.microsoft.com/azure/azure-monitor/logs/get-started-queries) | A first KQL tutorial |
| [Table plans](https://learn.microsoft.com/azure/azure-monitor/logs/logs-table-plans) | Analytics, Basic and Auxiliary plans, and what each allows |
| [Configure Basic logs](https://learn.microsoft.com/azure/azure-monitor/logs/basic-logs-configure) | Moving a table to the Basic plan |
| [Retention and archive](https://learn.microsoft.com/azure/azure-monitor/logs/data-retention-archive) | Interactive and total retention per table |
| [Manage table tiers and retention](https://learn.microsoft.com/azure/sentinel/manage-table-tiers-retention) | Sentinel's view of tiers and retention, the data lake included |
| [Microsoft Sentinel data lake](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-overview) | Long-term, low-cost storage that stays queryable |
| [Data collection rules](https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-overview) | How data is collected, transformed and routed |
| [Data export](https://learn.microsoft.com/azure/azure-monitor/logs/logs-data-export) | Continuous export to storage or Event Hubs |

## Cost

| Page | Use it for |
| --- | --- |
| [Plan costs and understand billing](https://learn.microsoft.com/azure/sentinel/billing) | How Sentinel and Log Analytics charge |
| [Reduce costs](https://learn.microsoft.com/azure/sentinel/billing-reduce-costs) | Commitment tiers, table plans and filtering |
| [Monitor costs](https://learn.microsoft.com/azure/sentinel/billing-monitor-costs) | Tracking spend and ingestion over time |
| [Azure Monitor cost best practices](https://learn.microsoft.com/azure/azure-monitor/fundamentals/best-practices-cost) | Cost recommendations across Azure Monitor |
| [Cost of logs](https://learn.microsoft.com/azure/azure-monitor/logs/cost-logs) | Pricing for ingestion, retention and queries |
| [Daily cap](https://learn.microsoft.com/azure/azure-monitor/logs/daily-cap) | Capping daily ingestion, and what it stops |
| [Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices) | The price list the cost estimate reads |

## Health and troubleshooting

| Page | Use it for |
| --- | --- |
| [Health, audit and monitoring](https://learn.microsoft.com/azure/sentinel/health-audit) | SentinelHealth and SentinelAudit, and what they record |
| [Log data ingestion time](https://learn.microsoft.com/azure/azure-monitor/logs/data-ingestion-time) | Why data arrives late, and how to measure it |

## Access and the wider platform

| Page | Use it for |
| --- | --- |
| [Roles and permissions](https://learn.microsoft.com/azure/sentinel/roles) | Sentinel's built-in roles and what each can do |
| [Microsoft Defender XDR documentation](https://learn.microsoft.com/defender-xdr/) | The unified security platform Sentinel joins |
"@)
}
