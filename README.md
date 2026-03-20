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
├── AutomationRules/                    # Custom automation rules (JSON)
│   ├── README.md                       # Schema docs and action reference
│   ├── AutoCloseInformational.json     # Example: auto-close informational incidents
│   └── AddTaskOnHighSeverity.json      # Example: add task to high severity incidents
├── Bicep/                              # Bicep templates for infrastructure
│   ├── main.bicep                      # Main deployment template
│   └── sentinel.bicep                  # Sentinel-specific resources
├── DefenderDetections/                 # Defender XDR custom detection rules (YAML)
│   ├── README.md                       # Schema docs and Graph API reference
│   ├── Email/                          # Email detection rules
│   │   └── PhishingLinkClickedByUser.yaml
│   ├── Endpoint/                       # Endpoint detection rules
│   │   ├── LateralMovementViaPsExec.yaml
│   │   └── SuspiciousEncodedPowerShell.yaml
│   └── Identity/                       # Identity detection rules
│       └── BruteForceEntraIDAccounts.yaml
├── Detections/                         # Custom Sentinel analytics rules (YAML)
│   ├── README.md                       # Schema docs and export guide
│   ├── Identity/                       # Rules organised by category
│   │   └── AzurePortalBruteForce.yaml  # Scheduled: brute force detection
│   └── PrivilegeEscalation/
│       └── UserAddedToPrivilegedGroup.yaml
├── HuntingQueries/                     # Custom hunting queries (YAML)
│   ├── README.md                       # Schema docs and export guide
│   ├── Identity/                       # Queries organised by category
│   │   └── SuspiciousSignInFromNewCountry.yaml
│   └── Persistence/
│       └── NewServicePrincipalCredential.yaml
├── Pipelines/                          # Azure DevOps pipeline definitions
│   ├── README.md                       # Pipeline documentation
│   └── Sentinel-Deploy.yml             # Deployment pipeline (5 stages)
├── Playbooks/                          # Custom playbooks (ARM templates)
│   └── README.md                       # ARM template docs and export guide
├── Scripts/                            # PowerShell automation scripts
│   ├── README.md                       # Script documentation
│   ├── Deploy-SentinelContentHub.ps1   # Content Hub deployment script
│   ├── Deploy-CustomContent.ps1        # Custom content deployment script
│   └── Deploy-DefenderDetections.ps1   # Defender XDR detections deployment script
├── SummaryRules/                       # Custom summary rules (JSON)
│   ├── README.md                       # Schema docs and bin size reference
│   ├── SignInSummaryByCountry.json     # Example: hourly sign-in aggregation
│   └── SecurityAlertSummary.json       # Example: hourly alert aggregation
├── Watchlists/                         # Custom watchlists (JSON + CSV)
│   ├── README.md                       # Schema docs
│   └── HighValueAssets/                # Example watchlist
│       ├── watchlist.json              # Metadata definition
│       └── data.csv                    # Watchlist data
├── Workbooks/                          # Custom workbooks (gallery JSON)
│   └── README.md                       # Workbook template docs
└── README.md                           # This file
```

## Features

- **End-to-End Deployment**: Single pipeline provisions infrastructure via Bicep, deploys Content Hub content, custom Sentinel content, and Defender XDR custom detections
- **Smart Infrastructure Checks**: Detects existing resources and skips Bicep deployment if infrastructure is already in place
- **Content Hub Automation**: Deploy solutions, analytics rules, workbooks, automation rules, and hunting queries via REST API
- **Custom Content Deployment**: Deploy custom detections (YAML), watchlists (JSON+CSV), playbooks (ARM), workbooks (gallery JSON), hunting queries (YAML), automation rules (JSON), and summary rules (JSON) from the repo
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
| **Security Administrator** (Entra ID) | Tenant | UEBA and Entity Analytics settings *(optional — see note)* |
| **CustomDetection.ReadWrite.All** (Graph) | Tenant | Defender XDR custom detection rules *(Stage 5)* |

> **Least-privilege alternative**: If your organisation requires tighter RBAC, you can replace **Contributor** with more granular roles. See the [Pipelines README](./Pipelines/README.md#prerequisites) for the least-privilege role assignment table.

> **Note on UEBA/Entity Analytics**: These Sentinel settings require the **Security Administrator** Entra ID directory role on the service principal. If your organisation cannot assign this role to a service principal, UEBA and Entity Analytics can be enabled manually via the Azure portal by a user who holds Security Administrator. All other Bicep resources deploy without it.

> **Note on Defender XDR Detections**: Stage 5 requires the `CustomDetection.ReadWrite.All` Microsoft Graph **application permission** on the service principal's app registration. Grant this in **Entra ID > App Registrations > API Permissions > Microsoft Graph > Application permissions** and provide admin consent.

> **Note**: Required resource providers (`Microsoft.OperationsManagement`, `Microsoft.SecurityInsights`) are registered automatically by the pipeline during infrastructure deployment.

### Setup

1. **Import** this repository into your Azure DevOps project

2. **Create a variable group** named `sentinel-deployment` in **Pipelines > Library** with your desired resource names — the pipeline will create them if they don't exist. See the [Pipelines README](./Pipelines/README.md) for details

3. **Create a service connection** named `sc-sentinel-as-code` — see the [Pipelines README](./Pipelines/README.md) for role requirements

4. **Create a pipeline** in Azure DevOps pointing to `Pipelines/Sentinel-Deploy.yml`

5. **Run the pipeline** — the pipeline will:
   - Check if infrastructure already exists
   - Deploy Bicep templates if needed (resource group, Log Analytics, Sentinel, UEBA)
   - Deploy Content Hub solutions and content
   - Deploy custom content (detections, watchlists, playbooks, workbooks, hunting queries, automation rules, summary rules)
   - Deploy Defender XDR custom detection rules via Graph API

## Documentation

| Area | README | Covers |
|------|--------|--------|
| **Pipelines** | [Pipelines/README.md](./Pipelines/README.md) | Pipeline stages, variable group setup, all parameters, service connection, usage examples |
| **Scripts** | [Scripts/README.md](./Scripts/README.md) | Script parameters, PowerShell usage examples, tested solutions, known limitations |
| **Detections** | [Detections/README.md](./Detections/README.md) | YAML schema for custom analytics rules, required fields, export guide |
| **Watchlists** | [Watchlists/README.md](./Watchlists/README.md) | Watchlist metadata schema, CSV format, KQL usage examples |
| **Playbooks** | [Playbooks/README.md](./Playbooks/README.md) | ARM template requirements, managed identity, parameters file |
| **Workbooks** | [Workbooks/README.md](./Workbooks/README.md) | Gallery template JSON format, stable GUIDs, export guide |
| **Hunting Queries** | [HuntingQueries/README.md](./HuntingQueries/README.md) | YAML schema for hunting queries, required fields, export guide |
| **Automation Rules** | [AutomationRules/README.md](./AutomationRules/README.md) | JSON schema for automation rules, action types, trigger conditions |
| **Summary Rules** | [SummaryRules/README.md](./SummaryRules/README.md) | Summary rule JSON schema, bin sizes, KQL restrictions |
| **Defender Detections** | [DefenderDetections/README.md](./DefenderDetections/README.md) | Defender XDR YAML schema, Graph API, response actions |

## Infrastructure (Bicep)

The `Bicep/` directory contains templates for provisioning Sentinel infrastructure, called by the pipeline's infrastructure stage:

- **main.bicep**: Subscription-level deployment that creates the resource group and calls the Sentinel module
- **sentinel.bicep**: Deploys and configures:
  - Log Analytics workspace (configurable retention, daily quota, tags)
  - Microsoft Sentinel onboarding
  - Entity Analytics (Entra ID) — *requires Security Administrator Entra ID role*
  - UEBA (AuditLogs, AzureActivity, SigninLogs, SecurityEvent) — *requires Security Administrator Entra ID role*
  - Anomalies (built-in ML detection)
  - EyesOn (SOC incident review)
  - Workspace diagnostic settings (audit logs and metrics)
  - Sentinel Health diagnostics (SentinelHealth and SentinelAudit tables)

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Support the Project

If you've found Sentinel-As-Code useful, consider buying me a coffee! Your support helps maintain this project and develop new features.

<a href="https://www.buymeacoffee.com/noodlemctwoodle" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

While donations are appreciated, they're entirely optional. The best way to contribute is by submitting issues, suggesting improvements, or contributing code!
Note: All donations will be reinvested into development time and improving this project.

## License

This project is licensed under the MIT License.
