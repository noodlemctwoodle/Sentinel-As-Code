# Sentinel-As-Code

## Overview

This repository provides a complete end-to-end CI/CD solution for deploying Microsoft Sentinel environments using Azure DevOps pipelines or GitHub Actions. Starting from an empty subscription, the pipeline provisions all required infrastructure via Bicep, deploys Content Hub solutions (the source of truth for out-of-the-box content), deploys custom content (detections, watchlists, playbooks, workbooks, hunting queries, automation rules, summary rules), and deploys Defender XDR custom detection rules — all from a single repo.

## Repository Structure

```
├── .github/workflows/                  # GitHub Actions workflow
│   └── sentinel-deploy.yml             # 5-stage deployment (OIDC auth)
├── Archive/                            # Deprecated legacy files
│   ├── azure-pipelines.yml             # Legacy pipeline (v1)
│   └── Set-SentinelContent.ps1         # Legacy deployment script (v1)
├── AnalyticalRules/                    # Custom Sentinel analytics rules (YAML)
│   ├── README.md                       # Schema docs and export guide
│   ├── Identity/                       # Rules organised by category
│   │   └── AzurePortalBruteForce.yaml  # Scheduled: brute force detection
│   └── PrivilegeEscalation/
│       └── UserAddedToPrivilegedGroup.yaml
├── AutomationRules/                    # Custom automation rules (JSON)
│   ├── README.md                       # Schema docs and action reference
│   ├── AutoCloseInformational.json     # Example: auto-close informational incidents
│   └── AddTaskOnHighSeverity.json      # Example: add task to high severity incidents
├── Bicep/                              # Bicep templates for infrastructure
│   ├── main.bicep                      # Main deployment template
│   ├── sentinel.bicep                  # Sentinel-specific resources
│   └── spn-role-assignment.bicep       # SPN role assignment (ABAC-conditioned UAA)
├── DefenderCustomDetections/           # Defender XDR custom detection rules (YAML)
│   ├── README.md                       # Schema docs and Graph API reference
│   ├── Email/                          # Email detection rules
│   │   └── PhishingLinkClickedByUser.yaml
│   ├── Endpoint/                       # Endpoint detection rules
│   │   ├── LateralMovementViaPsExec.yaml
│   │   └── SuspiciousEncodedPowerShell.yaml
│   └── Identity/                       # Identity detection rules
│       └── BruteForceEntraIDAccounts.yaml
├── HuntingQueries/                     # Custom hunting queries (YAML)
│   ├── README.md                       # Schema docs and export guide
│   ├── Identity/                       # Queries organised by category
│   │   └── SuspiciousSignInFromNewCountry.yaml
│   └── Persistence/
│       └── NewServicePrincipalCredential.yaml
├── Parsers/                            # KQL parsers/functions (YAML)
│   └── README.md                       # Parser schema docs
├── Pipelines/                          # Azure DevOps pipeline definitions
│   ├── README.md                       # Pipeline documentation
│   └── Sentinel-Deploy.yml             # Deployment pipeline (5 stages)
├── Playbooks/                          # Custom playbooks (ARM templates)
│   ├── README.md                       # ARM template docs and export guide
│   ├── Module/                         # Reusable playbook modules
│   ├── Incident/                       # Incident response playbooks
│   ├── Entity/                         # Entity enrichment playbooks
│   ├── AutoCloseIncidents/             # Auto-close automation
│   ├── SyncDfCAlerts/                  # Alert sync playbooks
│   ├── Watchlist/                      # Watchlist management playbooks
│   └── Template/                       # Playbook templates (not deployed)
├── Scripts/                            # PowerShell automation scripts
│   ├── README.md                       # Script documentation
│   ├── Setup-ServicePrincipal.ps1      # One-time SPN bootstrap script
│   ├── Deploy-SentinelContentHub.ps1   # Content Hub deployment script
│   ├── Deploy-CustomContent.ps1        # Custom content deployment script
│   └── Deploy-DefenderDetections.ps1   # Defender XDR detections deployment script
├── SummaryRules/                       # Custom summary rules (JSON)
│   ├── README.md                       # Schema docs and bin size reference
│   ├── SignInSummaryByCountry.json     # Example: hourly sign-in aggregation
│   └── SecurityAlertSummary.json       # Example: hourly alert aggregation
├── Watchlists/                         # Custom watchlists (JSON + CSV)
│   ├── README.md                       # Schema docs
│   ├── breakGlassAccounts/             # Break-glass admin accounts
│   ├── confirmedLeavers/               # Offboarded users
│   ├── environmentIPs/                 # Corporate IP ranges
│   ├── EntraRiskyUsers/                # Risky user accounts
│   ├── GoogleOneVPNIPRanges/           # Google One VPN IPs
│   ├── HighRiskApps/                   # High-risk applications
│   ├── iCloudPrivateRelayIPRanges/     # Apple iCloud Relay IPs
│   ├── knownDCAccounts/                # Domain controller service accounts
│   ├── regionalMap/                    # Country/region mapping
│   ├── socManagedIdentities/           # SOC-managed identities
│   ├── SuspiciousUsers/                # Suspicious user watch list
│   └── TorExitNodes/                   # Tor exit node IP ranges
├── Workbooks/                          # Custom workbooks (gallery JSON)
│   └── README.md                       # Workbook template docs
├── dependencies.json                   # Dependency graph for content items
├── sentinel-deployment.config          # Smart deployment configuration
└── README.md                           # This file
```

## Features

- **End-to-End Deployment**: Single pipeline provisions infrastructure via Bicep, deploys Content Hub content, custom Sentinel content, and Defender XDR custom detections
- **Smart Infrastructure Checks**: Detects existing resources and skips Bicep deployment if infrastructure is already in place
- **Smart Deployment**: Use git diff to detect changed files and only deploy modified content — state file tracks deployment outcomes across runs to automatically retry previously failed items
- **Dependency Graph System**: Declare prerequisites per content item (tables, watchlists, functions); pre-flight checks validate dependencies, missing detections deploy disabled
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

> **Least-privilege alternative**: If your organisation requires tighter RBAC, you can replace **Contributor** with more granular roles. See the [Pipelines doc](./Docs/Pipelines.md#prerequisites) for the least-privilege role assignment table.

> **Note on Setup**: Run `Scripts/Setup-ServicePrincipal.ps1` once to automatically grant all required permissions. The script provides a permission summary, requests Y/N consent, and supports `-SkipEntraRole` and `-SkipGraphPermission` switches for optional steps. After running once, the pipeline is fully autonomous.

> **Note on UEBA/Entity Analytics**: These Sentinel settings require the **Security Administrator** Entra ID directory role on the service principal. If your organisation cannot assign this role to a service principal, UEBA and Entity Analytics can be enabled manually via the Azure portal by a user who holds Security Administrator. All other Bicep resources deploy without it.

> **Note on Defender XDR Detections**: Stage 5 requires the `CustomDetection.ReadWrite.All` Microsoft Graph **application permission** on the service principal's app registration. Grant this in **Entra ID > App Registrations > API Permissions > Microsoft Graph > Application permissions** and provide admin consent.

> **Note**: Required resource providers (`Microsoft.OperationsManagement`, `Microsoft.SecurityInsights`) are registered automatically by the pipeline during infrastructure deployment.

### Setup

1. **Import** this repository into your Azure DevOps project

2. **Create a service connection** named `sc-sentinel-as-code` — see the [Pipelines doc](./Docs/Pipelines.md) for role requirements

3. **Run the bootstrap script** once: `Scripts/Setup-ServicePrincipal.ps1` grants all required roles (Contributor, User Access Administrator, Security Administrator, CustomDetection.ReadWrite.All) with your Y/N consent. Optional steps can be skipped with `-SkipEntraRole` or `-SkipGraphPermission` switches.

4. **Create a variable group** named `sentinel-deployment` in **Pipelines > Library** with your desired resource names — the pipeline will create them if they don't exist. Optionally add `playbookResourceGroup` to deploy playbooks to a separate resource group. See the [Pipelines doc](./Docs/Pipelines.md) for details

5. **Create a pipeline** in Azure DevOps pointing to `Pipelines/Sentinel-Deploy.yml`

6. **Run the pipeline** — the pipeline will:
   - Check if infrastructure already exists
   - Deploy Bicep templates if needed (resource group, Log Analytics, Sentinel)
   - Configure Sentinel settings (Entity Analytics, UEBA, Anomalies, EyesOn)
   - Wait for workspace indexing (60s on new deployments)
   - Deploy Content Hub solutions and content
   - Deploy custom content (analytical rules, watchlists, playbooks, workbooks, hunting queries, parsers, automation rules, summary rules)
   - Deploy Defender XDR custom detection rules via Graph API

## Documentation

All documentation now lives under [`Docs/`](./Docs/).

| Area | Doc | Covers |
|------|-----|--------|
| **Bicep** | [Docs/Bicep.md](./Docs/Bicep.md) | Subscription-scoped templates, parameters, dual onboarding mechanism, diagnostic settings, optional playbook RG |
| **Pipelines** | [Docs/Pipelines.md](./Docs/Pipelines.md) | Pipeline stages, variable group setup, parameters, service connection, usage examples |
| **Scripts** | [Docs/Scripts.md](./Docs/Scripts.md) | Script parameters, PowerShell usage examples, tested solutions, known limitations |
| **Analytical Rules** | [Docs/Analytical-Rules.md](./Docs/Analytical-Rules.md) | YAML schema for custom analytics rules, required fields, deploy behaviour, examples |
| **Community Rules** | [Docs/Community-Rules.md](./Docs/Community-Rules.md) | Opt-in third-party rule contributions, deployment defaults, adding new sources |
| **Watchlists** | [Docs/Watchlists.md](./Docs/Watchlists.md) | Watchlist metadata schema, CSV format, KQL usage examples |
| **Playbooks** | [Docs/Playbooks.md](./Docs/Playbooks.md) | ARM template requirements, managed identity connections, auto-injected parameters |
| **Workbooks** | [Docs/Workbooks.md](./Docs/Workbooks.md) | Gallery template JSON format, stable GUIDs, export guide |
| **Hunting Queries** | [Docs/Hunting-Queries.md](./Docs/Hunting-Queries.md) | YAML schema for hunting queries, required fields, export guide |
| **Automation Rules** | [Docs/Automation-Rules.md](./Docs/Automation-Rules.md) | JSON schema for automation rules, action types, trigger conditions |
| **Summary Rules** | [Docs/Summary-Rules.md](./Docs/Summary-Rules.md) | Summary rule JSON schema, bin sizes, KQL restrictions |
| **Defender Custom Detections** | [Docs/Defender-Custom-Detections.md](./Docs/Defender-Custom-Detections.md) | Defender XDR YAML schema, Graph API, response actions |
| **DCR Watchlist Sync** | [Docs/DCR-Watchlist.md](./Docs/DCR-Watchlist.md) | Auto-populated DCR inventory watchlist, billing reporting, runbook deployment |
| **Sentinel Drift Detection** | [Docs/Sentinel-Drift-Detection.md](./Docs/Sentinel-Drift-Detection.md) | Daily detection of portal-edited rules with auto-PR back into the repo |
| **Pester Tests** | [Docs/Pester-Tests.md](./Docs/Pester-Tests.md) | Running and extending the test suite |

## Infrastructure (Bicep)

The `Bicep/` directory contains templates for provisioning Sentinel infrastructure, called by the pipeline's infrastructure stage:

- **main.bicep**: Subscription-level deployment that creates the resource group and calls the Sentinel module
- **sentinel.bicep**: Deploys and configures:
  - Log Analytics workspace (configurable retention, daily quota, tags)
  - Microsoft Sentinel onboarding (via `Microsoft.OperationsManagement/solutions` for idempotency)
  - Workspace diagnostic settings (audit logs and metrics)
  - Sentinel Health diagnostics (SentinelHealth and SentinelAudit tables)
- **Post-Bicep pipeline step** configures Sentinel settings via REST API:
  - Entity Analytics (Entra ID provider)
  - UEBA (AuditLogs, AzureActivity, SigninLogs, SecurityEvent)
  - Anomalies (built-in ML detection)
  - EyesOn (SOC incident review)

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
