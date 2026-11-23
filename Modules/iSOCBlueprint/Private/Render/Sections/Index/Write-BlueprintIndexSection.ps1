#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write index.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Index/Write-BlueprintIndexSection.ps1
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
function Write-BlueprintIndexSection {
    <#
    .SYNOPSIS
        Build the figures for and write index.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $OutputRoot = $Context.OutputRoot
    $ResourcesRoot = $Context.ResourcesRoot
    $run = $Context.run
    $WorkspaceName = $Context.WorkspaceName

    # ---------------------------------------------------------------------------
    # Section: 99 — references
    # ---------------------------------------------------------------------------
    $refSrc = Join-Path $ResourcesRoot 'Blueprint-References.md'
    if (Test-Path $refSrc) {
        if ($script:WriteMarkdown) {
            Copy-Item -Path $refSrc -Destination (Join-Path $OutputRoot '99-references.md') -Force
            $script:PagesWritten++
            Write-Verbose 'copied 99-references.md'
        }
        if ($script:WriteJson) { Write-BlueprintSectionModel -FileName '99-references.md' -Markdown (Get-Content -LiteralPath $refSrc -Raw) }
    }

    # ---------------------------------------------------------------------------
    # Index
    # ---------------------------------------------------------------------------
    $indexBody = @"
# ${WorkspaceName}: Sentinel Documentation Index

Generated $(Format-DateUtc $run.StartedAtUtc) UTC by iSOC Blueprint v$($run.BlueprintVersion).

Sections are numbered to match the formal Sentinel Configuration TOC where applicable. Customer-narrative sections (architectural diagrams, SOC operational processes, the licensing inventory) are intentionally not generated, so supply those separately.

| Section | TOC | Description |
|---|---|---|
| [00-overview.md](00-overview.md) | - | Headline counts, top findings, cost summary |
| [01-live-snapshot.md](01-live-snapshot.md) | 1 | Workspace at a glance, regenerated every pipeline run |
| [02-deprecated-legacy-features.md](02-deprecated-legacy-features.md) | - | Retirement deadlines and the legacy features still in use |
| [10-data-connectors.md](10-data-connectors.md) | 4.7 | Classic + CCF connectors |
| [11-sentinel-health.md](11-sentinel-health.md) | 4.8 | SentinelHealth events, last {lookback} |
| [12-soc-optimization.md](12-soc-optimization.md) | 4.9 | SOC Optimization recommendations |
| [13-data-source-hygiene.md](13-data-source-hygiene.md) | - | CEF/Syslog hygiene, agent dual-collection, top noisy events |
| [14-coverage-breakdowns.md](14-coverage-breakdowns.md) | - | AzureActivity / AzureDiagnostics / XDR coverage by source |
| [15-incidents.md](15-incidents.md) | 4.10 | Incident MTTA/MTTR, outcomes, incidents by rule and by provider |
| [16-alerts.md](16-alerts.md) | 4.10 | Alert volume by severity, detection source and provider |
| [20-analytics-rules.md](20-analytics-rules.md) | 4.11 | All detection rules by kind, Microsoft-managed rules, recent modifications, Content Hub solution, Defender XDR custom detections |
| [21-rule-performance.md](21-rule-performance.md) | 4.11.2 | Alert volume per rule, rule effectiveness, noisy rules |
| [22-rule-health-quality.md](22-rule-health-quality.md) | - | Rule run failures, entity-mapping and incident-creation anti-patterns, stale rules, template drift, complexity |
| [25-mitre-coverage.md](25-mitre-coverage.md) | 3.2 | Tactic + technique + sub-technique coverage |
| [26-ueba.md](26-ueba.md) | 4.16 | UEBA configuration |
| [27-threat-intelligence.md](27-threat-intelligence.md) | 4.17 | Indicator counts by source, STIX objects, feeds |
| [28-detection-opportunities.md](28-detection-opportunities.md) | - | Tables with data but no detection, templates ready to enable |
| [30-hunting-queries.md](30-hunting-queries.md) | 4.15 | Hunting queries |
| [35-parsers-functions.md](35-parsers-functions.md) | - | Parsers and functions |
| [36-data-export.md](36-data-export.md) | 4.3.3 | Data export configuration |
| [37-search-restore.md](37-search-restore.md) | 4.3.4 | Search jobs / restore logs |
| [38-summary-rules.md](38-summary-rules.md) | 4.3.5 | Summary rules |
| [40-workbooks.md](40-workbooks.md) | 4.14 | Saved workbooks + templates |
| [50-watchlists.md](50-watchlists.md) | 4.12 | Watchlists |
| [60-automation-rules-playbooks.md](60-automation-rules-playbooks.md) | 4.13 | Automation rules + playbooks + MI grants |
| [70-content-hub.md](70-content-hub.md) | 4.6 | Solutions installed + repositories |
| [80-workspace.md](80-workspace.md) | 4.2 | SKU, retention, networking, feature flags |
| [81-table-plans-retention.md](81-table-plans-retention.md) | 4.3.1 | Per-table plan, activity, detection coverage |
| [82-dedicated-cluster.md](82-dedicated-cluster.md) | 4.2.2 | Dedicated cluster, CMK, AZ |
| [83-data-collection.md](83-data-collection.md) | - | DCRs and DCEs |
| [84-cost-estimate.md](84-cost-estimate.md) | - | Estimated monthly cost |
| [85-rbac.md](85-rbac.md) | 4.4 | Role assignments |
| [86-subscription-context.md](86-subscription-context.md) | 4.1 | Subscription, tenant, RPs, locks, policy |
| [87-azure-monitor-agents.md](87-azure-monitor-agents.md) | 4.5 | AMA agents heartbeating into the workspace |
| [88-sentinel-data-lake.md](88-sentinel-data-lake.md) | - | Sentinel Data Lake enrollment, Lake-tier tables, migration candidates |
| [89-retention.md](89-retention.md) | 4.3.2 | Retention checks, per-table overrides, retention that rolls into the lake, ingestion validation |
| [90-gap-analysis.md](90-gap-analysis.md) | - | Findings against MS Learn best practices |
| [91-maturity-assessment.md](91-maturity-assessment.md) | - | Maturity by area, roadmap, quick wins, NIST CSF rollup |
| [96-references-microsoft.md](96-references-microsoft.md) | 6 | Microsoft Learn pages by topic, best practices included |
| [99-references.md](99-references.md) | - | Blueprint's own API versions and modules |
"@
    Write-BlueprintSection 'index.md' $indexBody
}
