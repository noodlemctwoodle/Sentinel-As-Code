<p align="center">
  <img src="./.images/sentinel-as-code-banner.png" alt="Sentinel-As-Code" />
</p>

## Overview

This repository provides a complete end-to-end CI/CD solution for deploying Microsoft Sentinel environments using Azure DevOps pipelines or GitHub Actions. Starting from an empty subscription, the pipeline provisions all required infrastructure via Bicep, deploys Content Hub solutions (the source of truth for out-of-the-box content), deploys custom content (detections, watchlists, playbooks, workbooks, hunting queries, automation rules, summary rules), and deploys Defender XDR custom detection rules — all from a single repo.

## Repository Structure

```
.archive/                  # Deprecated legacy files
.github/                   # GitHub Actions workflows (deploy / drift / DCR / nightly E2E / dependency update / PR-validation) + composite actions
AnalyticalRules/           # Custom Sentinel analytics rules (YAML, see Docs/Content/Analytical-Rules.md)
Automation/                # Standalone Azure Automation runbooks (DCR-Watchlist sync)
AutomationRules/           # Custom automation rules (JSON, see Docs/Content/Automation-Rules.md)
Bicep/                     # Infrastructure templates (see Docs/Deployment/Bicep.md)
DefenderCustomDetections/  # Defender XDR custom detection rules (YAML, see Docs/Content/Defender-Custom-Detections.md)
Docs/                      # All documentation, grouped by concern (start at Docs/README.md)
HuntingQueries/            # Custom hunting queries (YAML, see Docs/Content/Hunting-Queries.md)
Modules/                   # In-repo PowerShell modules (Sentinel.Common — shared deployer + KQL discovery helpers)
Parsers/                   # KQL parsers/functions (YAML)
Pipelines/                 # Azure DevOps pipeline definitions (see Docs/Deployment/Pipelines.md)
Playbooks/                 # Custom playbooks (ARM templates, see Docs/Content/Playbooks.md)
Scripts/                   # PowerShell automation scripts (see Docs/Deployment/Scripts.md)
SummaryRules/              # Custom summary rules (JSON, see Docs/Content/Summary-Rules.md)
Tests/                     # Pester test suite (see Docs/Development/Pester-Tests.md)
Watchlists/                # Custom watchlists (JSON + CSV, see Docs/Content/Watchlists.md)
Workbooks/                 # Custom workbooks (gallery JSON, see Docs/Content/Workbooks.md)
dependencies.json          # Auto-derived content dependency graph (see Docs/Operations/Dependency-Manifest.md)
sentinel-deployment.config # Smart-deployment configuration
README.md                  # This file
```

For details on what's inside each folder and how content is authored, see the
[Documentation](#documentation) section below.

## Features

- **End-to-End Deployment**: Single pipeline provisions infrastructure via Bicep, deploys Content Hub content, custom Sentinel content, and Defender XDR custom detections
- **Smart Infrastructure Checks**: Detects existing resources and skips Bicep deployment if infrastructure is already in place
- **Smart Deployment**: Use git diff to detect changed files and only deploy modified content — state file tracks deployment outcomes across runs to automatically retry previously failed items
- **Auto-derived Dependency Graph**: `dependencies.json` is generated from KQL content discovery, not hand-maintained. PR-validation gate refuses to merge on drift; daily auto-PR keeps the manifest fresh. See [Docs/Operations/Dependency-Manifest.md](./Docs/Operations/Dependency-Manifest.md)
- **Content Hub Automation**: Deploy solutions, analytics rules, workbooks, automation rules, and hunting queries via REST API
- **KQL Parsers/Functions**: Deploy workspace saved searches as reusable KQL parser functions from YAML
- **Custom Content Deployment**: Deploy custom analytical rules (YAML), watchlists (JSON+CSV), playbooks (ARM), workbooks (gallery JSON), hunting queries (YAML), automation rules (JSON), parsers (YAML), and summary rules (JSON) from the repo
- **Playbook Enhancements**: Module-first ordering, ARM parameter auto-injection, optional separate resource group, template folder exclusion, 64-character name truncation
- **Custom Hunting Queries**: Deploy YAML-based saved searches for proactive threat hunting
- **Custom Automation Rules**: Deploy JSON-based automation rules for incident auto-response
- **Summary Rules**: Deploy JSON-based summary rules to aggregate verbose log data into cost-effective summary tables
- **Defender XDR Custom Detections**: Deploy Advanced Hunting-based custom detection rules to Defender XDR via the Graph Security API
- **Customisation Protection**: Detect and skip locally modified analytics rules to preserve manual tuning
- **Granular Content Control**: Toggle deployment of individual content types via pipeline parameters
- **Dry Run Support**: Preview changes with `-WhatIf` before applying
- **Azure Government Support**: Target both commercial and government cloud environments
- **PR Validation Gate**: Five-job merge gate (Pester · Bicep build · ARM What-If · KQL syntax · dependency-manifest drift) on every PR to `main`. See [Docs/Development/Pester-Tests.md](./Docs/Development/Pester-Tests.md)
- **Nightly E2E Smoke Test**: Validates every deploy code path against a test workspace each night so production-deploy regressions are caught six days before the Monday cron runs

## Quick Start

### Prerequisites

- Azure subscription
- Azure DevOps organisation and project
- Service Principal with the following roles:

| Role | Scope | Purpose |
|------|-------|---------|
| **Contributor** | Subscription | Resource group, workspace, Bicep deployments, Sentinel content, and summary rules |
| **User Access Administrator** (ABAC-conditioned) | Subscription | Playbook managed identity role assignments *(restricted to 5 roles)* |
| **Security Administrator** (Entra ID) | Tenant | UEBA and Entity Analytics settings *(optional)* |
| **CustomDetection.ReadWrite.All** (Graph) | Tenant | Defender XDR custom detection rules *(Stage 5)* |

> **Least-privilege alternative**: If your organisation requires tighter RBAC, you can replace **Contributor** with more granular roles. See the [Pipelines doc](./Docs/Deployment/Pipelines.md#prerequisites) for the least-privilege role assignment table.

> **Note on Setup**: Run `Scripts/Setup-ServicePrincipal.ps1` once to automatically grant all required permissions. The script provides a permission summary, requests Y/N consent, and supports `-SkipEntraRole` and `-SkipGraphPermission` switches for optional steps. After running once, the pipeline is fully autonomous.

> **Note on UEBA/Entity Analytics**: These Sentinel settings require the **Security Administrator** Entra ID directory role on the service principal. If your organisation cannot assign this role to a service principal, UEBA and Entity Analytics can be enabled manually via the Azure portal by a user who holds Security Administrator. All other Bicep resources deploy without it.

> **Note on Defender XDR Detections**: Stage 5 requires the `CustomDetection.ReadWrite.All` Microsoft Graph **application permission** on the service principal's app registration. Grant this in **Entra ID > App Registrations > API Permissions > Microsoft Graph > Application permissions** and provide admin consent.

> **Note**: Required resource providers (`Microsoft.OperationsManagement`, `Microsoft.SecurityInsights`) are registered automatically by the pipeline during infrastructure deployment.

### Setup

1. **Import** this repository into your Azure DevOps project

2. **Create a service connection** named `sc-sentinel-as-code` — see the [Pipelines doc](./Docs/Deployment/Pipelines.md) for role requirements

3. **Run the bootstrap script** once: `Scripts/Setup-ServicePrincipal.ps1` grants all required roles (Contributor, User Access Administrator, Security Administrator, CustomDetection.ReadWrite.All) with your Y/N consent. Optional steps can be skipped with `-SkipEntraRole` or `-SkipGraphPermission` switches.

4. **Create a variable group** named `sentinel-deployment` in **Pipelines > Library** with your desired resource names — the pipeline will create them if they don't exist. Optionally add `playbookResourceGroup` to deploy playbooks to a separate resource group. See the [Pipelines doc](./Docs/Deployment/Pipelines.md) for details

5. **Create a pipeline** in Azure DevOps pointing to `Pipelines/Sentinel-Deploy.yml`

6. **Run the pipeline** — the pipeline will:
   - Check if infrastructure already exists
   - Deploy Bicep templates if needed (resource group, Log Analytics, Sentinel)
   - Configure Sentinel settings (Entity Analytics, UEBA, Anomalies, EyesOn)
   - Wait for workspace indexing (60s on new deployments)
   - Deploy Content Hub solutions and content
   - Deploy custom content (analytical rules, watchlists, playbooks, workbooks, hunting queries, parsers, automation rules, summary rules)
   - Deploy Defender XDR custom detection rules via Graph API

### Optional: standalone pipelines

Pipelines that run on their own schedule alongside the main deploy:

- **`Pipelines/Sentinel-Drift-Detect.yml`** (daily 06:00 UTC) — detects rules edited directly in the Sentinel portal, absorbs Custom drift back into the repo via PR. See [Docs/Operations/Sentinel-Drift-Detection.md](./Docs/Operations/Sentinel-Drift-Detection.md).
- **`Pipelines/Sentinel-DCR-Inventory.yml`** (on-change) — deploys the Azure Automation runbook that inventories Data Collection Rule associations into a Sentinel watchlist for billing reporting. See [Docs/Operations/DCR-Watchlist.md](./Docs/Operations/DCR-Watchlist.md).
- **`Pipelines/Sentinel-Dependency-Update.yml`** (daily 02:00 UTC) — runs `Build-DependencyManifest -Mode Update` and opens a PR if `dependencies.json` drifts from discovery. See [Docs/Operations/Dependency-Manifest.md](./Docs/Operations/Dependency-Manifest.md).
- **`Pipelines/Sentinel-PR-Validation.yml`** (on PR) — runs every Pester suite plus the dependency-manifest drift gate. See [Docs/Development/Pester-Tests.md](./Docs/Development/Pester-Tests.md).

GitHub-only:

- **`.github/workflows/sentinel-deploy-nightly.yml`** (daily 03:00 UTC) — nightly E2E smoke test against the Phase C test workspace. Catches deploy-pipeline regressions before the weekly Monday production cron.

## Documentation

All documentation lives under [`Docs/`](./Docs/), grouped by concern. Start at [`Docs/README.md`](./Docs/README.md) for the index.

### Content authoring — schemas and conventions

| Area | Doc |
|------|-----|
| Analytical Rules | [Docs/Content/Analytical-Rules.md](./Docs/Content/Analytical-Rules.md) |
| Automation Rules | [Docs/Content/Automation-Rules.md](./Docs/Content/Automation-Rules.md) |
| Community Rules | [Docs/Content/Community-Rules.md](./Docs/Content/Community-Rules.md) |
| Defender Custom Detections | [Docs/Content/Defender-Custom-Detections.md](./Docs/Content/Defender-Custom-Detections.md) |
| Hunting Queries | [Docs/Content/Hunting-Queries.md](./Docs/Content/Hunting-Queries.md) |
| Playbooks | [Docs/Content/Playbooks.md](./Docs/Content/Playbooks.md) |
| Summary Rules | [Docs/Content/Summary-Rules.md](./Docs/Content/Summary-Rules.md) |
| Watchlists | [Docs/Content/Watchlists.md](./Docs/Content/Watchlists.md) |
| Workbooks | [Docs/Content/Workbooks.md](./Docs/Content/Workbooks.md) |

### Deployment — how content reaches Sentinel

| Area | Doc |
|------|-----|
| Bicep | [Docs/Deployment/Bicep.md](./Docs/Deployment/Bicep.md) |
| Pipelines | [Docs/Deployment/Pipelines.md](./Docs/Deployment/Pipelines.md) |
| Scripts | [Docs/Deployment/Scripts.md](./Docs/Deployment/Scripts.md) |

### Operations — continuous run-time concerns

| Area | Doc |
|------|-----|
| DCR Watchlist Sync | [Docs/Operations/DCR-Watchlist.md](./Docs/Operations/DCR-Watchlist.md) |
| Sentinel Drift Detection | [Docs/Operations/Sentinel-Drift-Detection.md](./Docs/Operations/Sentinel-Drift-Detection.md) |
| Dependency Manifest | [Docs/Operations/Dependency-Manifest.md](./Docs/Operations/Dependency-Manifest.md) |

### Development — testing and contributing

| Area | Doc |
|------|-----|
| Pester Tests | [Docs/Development/Pester-Tests.md](./Docs/Development/Pester-Tests.md) |

## Infrastructure (Bicep)

Subscription-scoped Bicep templates in `Bicep/` provision the resource group, Log Analytics workspace, Sentinel onboarding (both legacy `OperationsManagement/solutions` and modern `SecurityInsights/onboardingStates`), diagnostic settings, and an optional separate playbook resource group. Sentinel feature settings (Entity Analytics, UEBA, Anomalies, EyesOn) are configured via REST in the same pipeline stage.

For the full parameter reference, resource list, API versions, and limitations, see [Docs/Deployment/Bicep.md](./Docs/Deployment/Bicep.md).

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Support the Project

If you've found Sentinel-As-Code useful, subscribe to [sentinel.blog](https://sentinel.blog) for more Sentinel and security content!

[![Subscribe to Sentinel Blog](https://img.shields.io/badge/Subscribe-sentinel.blog-blue?style=for-the-badge&logo=ghost&logoColor=white)](https://sentinel.blog/#/portal/signup)

The best way to support this project is by subscribing to the blog, submitting issues, suggesting improvements, or contributing code!

## License

This project is licensed under the MIT License.
