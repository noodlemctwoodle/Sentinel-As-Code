<p align="center">
  <img src="./.images/Sentinel-As-Code.png" alt="Sentinel-As-Code" />
</p>

## Overview

This repository provides a complete end-to-end CI/CD solution for deploying Microsoft Sentinel environments using Azure DevOps pipelines or GitHub Actions. Starting from an empty subscription, the pipeline provisions all required infrastructure via Bicep, deploys Content Hub solutions (the source of truth for out-of-the-box content), deploys custom content (detections, watchlists, playbooks, workbooks, hunting queries, automation rules, summary rules), and deploys Defender XDR custom detection rules - all from a single repo.

It ships with a five-job PR validation gate, a nightly end-to-end smoke test against a dedicated test workspace, daily portal-drift detection that absorbs edits back into the repo as PRs, an auto-derived dependency graph, a workbook round-trip exporter, and thirteen cross-platform GitHub Copilot agents that work on github.com and in every supported IDE so authors can build, edit, tune, and explain content with repo-aware AI assistance.

> ### 💛 For organisations using this repository
>
> Sentinel-As-Code is built and maintained on my own time as an open source project. I spend countless hours developing, testing, documenting, and supporting the work that lands in this repository - at no cost to the people and organisations who benefit from it.
>
> **If you are an organisation deploying this code into production**, or if it has saved your team meaningful engineering time, please consider supporting the project. Your contribution directly funds the next round of features, the test infrastructure, and the time it takes to keep the content current with Microsoft's release cadence.
>
> Recurring **Organisation** tiers (£125 / £250 / £500 per month), one-off tips at any amount, and annual sponsorships by invoice are all live on [sentinel.blog/support](https://sentinel.blog/support/). All channels are Stripe-backed, all blog content stays free for everyone, and contributions do not create a support contract - see the support page for the full disclaimer.
>
> [![Support sentinel.blog](https://img.shields.io/badge/💛%20Support%20—%20sentinel.blog%2Fsupport-orange?style=for-the-badge&logo=heart&logoColor=white)](https://sentinel.blog/support/)

### Sentinel as Code Toolkit

The [Sentinel as Code Toolkit](https://marketplace.visualstudio.com/items?itemName=noodlemctwoodle.sentinelcodeguard) is a companion VS Code extension for authoring content in this repo, covering schema validation, IntelliSense, field-order formatting, ARM-to-YAML conversion, and Defender XDR authoring helpers. It authors and validates; it does not deploy, so it pairs with (rather than replaces) the pipelines documented here. See [Docs/Toolkit/README.md](Docs/Toolkit/README.md).

## Repository Structure

```
.archive/                  # Deprecated legacy files
.github/                   # GitHub Actions workflows + composite actions + Copilot customisations (instructions / agents / prompts)
AGENTS.md                  # Cross-tool agent guidance (Copilot, Claude, Gemini, Cursor)
Blog/                      # Source posts for sentinel.blog
Content/                   # All Sentinel content, grouped by type (see Docs/Content/)
  AnalyticalRules/         #   Custom Sentinel analytics rules (YAML)
  AutomationRules/         #   Custom automation rules (JSON)
  DefenderCustomDetections/ #  Defender XDR custom detection rules (YAML)
  HuntingQueries/          #   Custom hunting queries (YAML)
  Parsers/                 #   KQL parsers/functions (YAML)
  Playbooks/               #   Custom playbooks (ARM templates)
  SummaryRules/            #   Custom summary rules (JSON)
  Watchlists/              #   Custom watchlists (JSON + CSV)
  Workbooks/               #   Custom workbooks (gallery JSON)
Infra/                     # Infrastructure-as-code - three Bicep stacks (see Docs/Infra/Bicep.md)
  sentinel/                #   production Sentinel deployment, subscription-scoped (main.bicep + sentinel.bicep)
  test-workspace/          #   PR-validation / E2E test workspace (main.bicep)
  dcr-watchlist/           #   DCR-watchlist automation account + runbook (main.bicep + modules/automationAccount.bicep)
Deploy/                    # Deployment scripts + sentinel-deployment.config (see Docs/Deploy/Scripts.md)
Tools/                     # CI / maintenance / reporting: dependency manifest, drift, PR validation, workbook export, community import, Documenter
Pipelines/                 # Azure DevOps pipeline definitions (see Docs/Pipelines/README.md)
Docs/                      # All documentation, mirroring this repo's folders (start at Docs/README.md)
Modules/                   # In-repo PowerShell modules (Sentinel.Common - shared deployer + KQL discovery helpers)
Tests/                     # Pester test suite (see Docs/Tests/Pester-Tests.md)
dependencies.json          # Auto-derived content dependency graph (see Docs/Tools/Dependency-Manifest.md)
README.md                  # This file
```

For details on what's inside each folder and how content is authored, see the
[Documentation](#documentation) section below.

## Features

- **End-to-End Deployment**: Single pipeline provisions infrastructure via Bicep, deploys Content Hub content, custom Sentinel content, and Defender XDR custom detections
- **Smart Infrastructure Checks**: Detects existing resources and skips Bicep deployment if infrastructure is already in place
- **Smart Deployment**: The deploy pipeline runs incrementally by default (the `smart_deployment` pipeline input defaults **on**): git diff detects changed files and the state file tracks outcomes across runs to auto-retry previously failed items. Set the input to `false` for a full deploy of every item. The underlying `-SmartDeployment` script switch itself defaults **off**, so a direct script call is a full deploy unless you pass it
- **Auto-derived Dependency Graph**: `dependencies.json` is generated from KQL content discovery, not hand-maintained. PR-validation gate refuses to merge on drift; daily auto-PR keeps the manifest fresh. See [Docs/Tools/Dependency-Manifest.md](Docs/Tools/Dependency-Manifest.md)
- **Content Hub Automation**: Deploy solutions, analytics rules, workbooks, automation rules, and hunting queries via REST API
- **KQL Content/Parsers/Functions**: Deploy workspace saved searches as reusable KQL parser functions from YAML
- **Custom Content Deployment**: Deploy custom analytical rules (YAML), watchlists (JSON+CSV), playbooks (ARM), workbooks (gallery JSON), hunting queries (YAML), automation rules (JSON), parsers (YAML), and summary rules (JSON) from the repo
- **Playbook Enhancements**: Module-first ordering, ARM parameter auto-injection, optional separate resource group, template folder exclusion, 64-character name truncation
- **Custom Hunting Queries**: Deploy YAML-based saved searches for proactive threat hunting
- **Custom Automation Rules**: Deploy JSON-based automation rules for incident auto-response
- **Summary Rules**: Deploy JSON-based summary rules to aggregate verbose log data into cost-effective summary tables
- **Defender XDR Custom Detections**: Deploy Advanced Hunting-based custom detection rules to Defender XDR via the Graph Security API
- **Customisation Protection**: Detect and skip locally modified analytics rules to preserve manual tuning
- **Drift Detection and Absorption**: Daily drift detector compares every deployed rule against its source-of-truth and absorbs all three buckets back into the repo as Custom YAML - Custom edits update matching files, ContentHub edits become new YAMLs under `Content/AnalyticalRules/AbsorbedFromPortal/ContentHub/{Solution}/`, Orphans land at `Content/AnalyticalRules/AbsorbedFromPortal/Orphans/`. The next deploy round-trips every absorbed rule through governance. See [Docs/Tools/Sentinel-Drift-Detection.md](Docs/Tools/Sentinel-Drift-Detection.md)
- **Workbook Round-Trip Export**: `Tools/Export-SentinelWorkbooks.ps1` pulls every user-authored workbook from a workspace into `Content/Workbooks/<DisplayName>/{workbook.json, metadata.json}`. Filters out Content Hub workbooks, replaces workspace ARM IDs with placeholders, restores PascalCase folder naming, and preserves author-curated metadata on re-export. Portal authoring becomes a first-class repo workflow
- **Granular Content Control**: Toggle deployment of individual content types via pipeline parameters
- **Dry Run Support**: Preview changes with `-WhatIf` before applying
- **Azure Government Support**: Target both commercial and government cloud environments
- **PR Validation Gate**: Five-job merge gate (Pester · Bicep build · ARM template validation · KQL syntax · dependency-manifest drift) on every PR or push to `main`. The ARM job calls `Test-AzResourceGroupDeployment` (a validation call, not a `-WhatIf`). See [Docs/Tests/Pester-Tests.md](Docs/Tests/Pester-Tests.md)
- **Nightly E2E Smoke Test**: Validates every deploy code path against a test workspace each night so production-deploy regressions are caught six days before the Monday cron runs
- **Shared PowerShell Module**: `Modules/Sentinel.Common` exports the deployer helpers every script depends on (`Write-PipelineMessage`, `Invoke-SentinelApi`, `Connect-AzureEnvironment`) plus six KQL discovery functions used by the dependency-manifest builder. Single source of truth eliminates the bug-fix-in-one-copy class of regression
- **Reusable GitHub Actions Composites**: `azure-login-oidc` and `setup-pwsh-modules` under `.github/actions/`. Replace inlined `Azure/login@v2` and `Install-Module` patterns at every call site; pin every PSGallery dependency by version
- **GitHub Copilot Integration**: Thirteen cross-platform Copilot agents in two tiers - five persona-broad (Build / Edit / Tune / Explain / Understand) plus eight engineering specialists (Pipelines, PowerShell, Bicep, KQL, Tests, Drift, Dependencies, Security) - nine path-scoped instruction files, and six reusable prompts. Works on github.com Chat, github.com cloud agent, VS Code, Visual Studio, JetBrains, and Copilot CLI without configuration. See [Docs/GitHub/GitHub-Copilot.md](Docs/GitHub/GitHub-Copilot.md)

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

> **Least-privilege alternative**: If your organisation requires tighter RBAC, you can replace **Contributor** with more granular roles. See the [Pipelines doc](Docs/Pipelines/README.md#prerequisites) for the least-privilege role assignment table.

> **Note on Setup**: Run `Deploy/setup/Setup-ServicePrincipal.ps1` once to automatically grant all required permissions. The script provides a permission summary, requests Y/N consent, and supports `-SkipEntraRole` and `-SkipGraphPermission` switches for optional steps. After running once, the pipeline is fully autonomous.

> **Note on UEBA/Entity Analytics**: These Sentinel settings require the **Security Administrator** Entra ID directory role on the service principal. If your organisation cannot assign this role to a service principal, UEBA and Entity Analytics can be enabled manually via the Azure portal by a user who holds Security Administrator. All other Bicep resources deploy without it.

> **Note on Defender XDR Detections**: Stage 5 requires the `CustomDetection.ReadWrite.All` Microsoft Graph **application permission** on the service principal's app registration. Grant this in **Entra ID > App Registrations > API Permissions > Microsoft Graph > Application permissions** and provide admin consent.

> **Note**: Required resource providers (`Microsoft.OperationsManagement`, `Microsoft.SecurityInsights`) are registered automatically by the pipeline during infrastructure deployment.

### Setup

1. **Import** this repository into your Azure DevOps project

2. **Create a service connection** named `sc-sentinel-as-code` - see the [Pipelines doc](Docs/Pipelines/README.md) for role requirements

3. **Run the bootstrap script** once: `Deploy/setup/Setup-ServicePrincipal.ps1` grants all required roles (Contributor, User Access Administrator, Security Administrator, CustomDetection.ReadWrite.All) with your Y/N consent. Optional steps can be skipped with `-SkipEntraRole` or `-SkipGraphPermission` switches.

4. **Create a variable group** named `sentinel-deployment` in **Pipelines > Library** with your desired resource names - the pipeline will create them if they don't exist. Optionally add `playbookResourceGroup` to deploy playbooks to a separate resource group. See the [Pipelines doc](Docs/Pipelines/README.md) for details

5. **Create a pipeline** in Azure DevOps pointing to `Pipelines/Sentinel-Deploy.yml`

6. **Run the pipeline** - the pipeline will:
   - Check if infrastructure already exists
   - Deploy Bicep templates if needed (resource group, Log Analytics, Sentinel)
   - Configure Sentinel settings (Entity Analytics, UEBA, Anomalies, EyesOn)
   - Wait for workspace indexing (60s on new deployments)
   - Deploy Content Hub solutions and content
   - Deploy custom content in eight ordered stages (parsers, watchlists, detections/analytical rules, hunting queries, playbooks, workbooks, automation rules, summary rules)
   - Deploy Defender XDR custom detection rules via Graph API

### Optional: standalone pipelines

The repo ships **seven Azure DevOps pipelines** under `Pipelines/` and **seven GitHub Actions workflows** under `.github/workflows/`. Most map one-to-one across the two CI systems, but the coverage is not fully symmetric (see the asymmetry notes below). Per-pipeline detail lives under [Docs/Pipelines/](Docs/Pipelines). Alongside the main deploy, these run on their own schedule:

- **`Pipelines/Sentinel-Drift-Detect.yml`** (daily 06:00 UTC): detects rules edited directly in the Sentinel portal, absorbs Custom drift back into the repo via PR. A `-ReportOnly` run writes the drift report artefact only and never opens a PR. See [Docs/Tools/Sentinel-Drift-Detection.md](Docs/Tools/Sentinel-Drift-Detection.md).
- **`Pipelines/Sentinel-DCR-Inventory.yml`** (on-change): deploys the Azure Automation runbook that inventories Data Collection Rule associations into a Sentinel watchlist for billing reporting. The runbook syncs one watchlist row per DCR, keyed on `DCRName`. See [Docs/Tools/DCR-Watchlist.md](Docs/Tools/DCR-Watchlist.md).
- **`Pipelines/Sentinel-Dependency-Update.yml`** (daily 02:00 UTC): runs `Build-DependencyManifest -Mode Update` and opens a PR if `dependencies.json` drifts from discovery. See [Docs/Tools/Dependency-Manifest.md](Docs/Tools/Dependency-Manifest.md).
- **`Pipelines/Sentinel-PR-Validation.yml`** (on PR): runs every Pester suite plus the dependency-manifest drift gate. See [Docs/Tests/Pester-Tests.md](Docs/Tests/Pester-Tests.md).
- **`Pipelines/Sentinel-Documenter.yml`** (manual trigger only on ADO): runs the two-stage Documenter (collector then renderer) over a live workspace and publishes the `SecurityDocs/<workspace>/` inventory + gap-analysis tree as a pipeline artefact. The Documenter requires a **private** repository. See [Docs/Tools/Documenter/Sentinel-Documenter.md](Docs/Tools/Documenter/Sentinel-Documenter.md).
- **`Pipelines/Sentinel-Word-Report.yml`** (manual, **ADO-only**, no GitHub equivalent): renders the Documenter Markdown into a single formatted Word document with a real page-numbered table of contents. See [Docs/Tools/Documenter/Sentinel-Word-Report.md](Docs/Tools/Documenter/Sentinel-Word-Report.md).

CI asymmetries to be aware of:

- **`.github/workflows/sentinel-deploy-nightly.yml`** (daily 03:00 UTC) is **GitHub-only**: an E2E smoke test against the test workspace, catching deploy-pipeline regressions before the weekly Monday production cron. There is no ADO equivalent.
- **`Pipelines/Sentinel-Word-Report.yml`** is **ADO-only**: there is no GitHub Word-report workflow.
- The **Documenter runs daily** on GitHub (`.github/workflows/sentinel-document.yml`, cron `0 6 * * *` plus `workflow_dispatch`) but is **manual-trigger-only** on ADO (`Pipelines/Sentinel-Documenter.yml`).
- The deployment-state file differs by CI: GitHub writes `.deployment-state.json` (leading dot), ADO writes `deployment-state.json` (no dot). Neither is canonical.

### Schedule alignment

```
02:00 UTC daily    sentinel-dependency-update    Refresh dependencies.json + auto-PR
03:00 UTC daily    sentinel-deploy-nightly       E2E smoke test (GitHub-only)
04:00 UTC Monday   sentinel-deploy               Production deploy
06:00 UTC daily    sentinel-drift-detect         Portal-drift detection + auto-PR
06:00 UTC daily    sentinel-document             Documenter snapshot (GitHub cron; ADO is manual-only)
on every PR        sentinel-pr-validation        5-job merge gate
on change          sentinel-dcr-inventory        DCR runbook deploy
manual only        sentinel-word-report          Word report render (ADO-only)
```

## GitHub Copilot agents

The repo ships with a complete GitHub Copilot customisation set so authors get repo-aware AI help out of the box. No VS Code settings or feature toggles required - open the workspace in any IDE with Copilot Chat enabled, or pick the agent from the dropdown on github.com.

Thirteen agents in two tiers:

**Persona-broad** - pick by what kind of help you want.

| Agent | Purpose |
|---|---|
| `Sentinel-As-Code: Repo Explorer` | **Understand.** Explains repo architecture, content flow, where things live. Read-only. |
| `Sentinel-As-Code: Rule Author` | **Build.** Authors new analytical rules, hunting queries, Defender detections end-to-end. |
| `Sentinel-As-Code: Content Editor` | **Edit.** General-purpose edits across any content type with the right post-edit Pester suite. |
| `Sentinel-As-Code: Rule Tuner` | **Adjust.** Tunes thresholds, severity, query filters on existing rules without changing detection intent. |
| `Sentinel-As-Code: Code Explainer` | **Explain.** Walks through PowerShell, KQL, ARM, workflows in plain prose. Read-only. |

**Engineering specialists** - pick by area of expertise.

| Agent | Purpose |
|---|---|
| `Sentinel-As-Code: Pipeline Engineer` | GitHub Actions + ADO pipelines, parity, composite actions, schedules, failure diagnosis. |
| `Sentinel-As-Code: PowerShell Engineer` | `Sentinel.Common` module, scripts, AST extraction, the repo's foot-gun list. |
| `Sentinel-As-Code: Bicep Engineer` | Bicep templates, parameter design, Sentinel onboarding, test-workspace template. |
| `Sentinel-As-Code: KQL Engineer` | Query optimisation, parser extraction, watchlist promotion, ASIM compatibility. |
| `Sentinel-As-Code: Test Engineer` | Pester suite engineering, coverage analysis, mocking strategy. |
| `Sentinel-As-Code: Security Reviewer` | Reviews playbooks, scripts, role assignments, federated credentials. Read-only. |
| `Sentinel-As-Code: Drift Engineer` | Rule drift sub-system, daily auto-PR triage, Custom / ContentHub / Orphan absorption. |
| `Sentinel-As-Code: Dependencies Engineer` | Dependency-discovery extractor, `Build-DependencyManifest`, the drift gate, the daily refresh workflow. |

Plus nine path-scoped instruction files under [`.github/instructions/`](.github/instructions) that load automatically when you edit a matching file (analytical rules, Defender detections, hunting queries, KQL queries, Pester tests, playbooks, PowerShell scripts, watchlists, workflows), and six reusable prompts under [`.github/prompts/`](.github/prompts) (`/new-analytical-rule`, `/new-hunting-query`, `/new-defender-detection`, `/new-pester-test`, `/review-rule`, `/regenerate-deps`).

Repo-wide guidance lives in [`.github/copilot-instructions.md`](.github/copilot-instructions.md). Cross-tool agent guidance (Claude, Gemini, Cursor) lives in [`AGENTS.md`](AGENTS.md). Full reference: [Docs/GitHub/GitHub-Copilot.md](Docs/GitHub/GitHub-Copilot.md).

## Documentation

All documentation lives under [`Docs/`](Docs), whose folders mirror this repo's
layout (`Deploy/` to `Docs/Deploy/`, `Pipelines/` to `Docs/Pipelines/`, `.github/`
to `Docs/GitHub/`, and so on). Start at [`Docs/README.md`](Docs/README.md) for the
full index. Only `Guides/`, `Releases/`, and `Toolkit/` are concern-based, with no code
counterpart.

### Content - `Docs/Content/`

Schemas and conventions for every content type. The Toolkit schemas and templates
are the authoring source of truth for these.

| Area | Doc |
|------|-----|
| Analytical Rules | [Content/Analytical-Rules.md](Docs/Content/Analytical-Rules.md) |
| Automation Rules | [Content/Automation-Rules.md](Docs/Content/Automation-Rules.md) |
| Community Rules | [Content/Community-Rules.md](Docs/Content/Community-Rules.md) |
| Defender Custom Detections | [Content/Defender-Custom-Detections.md](Docs/Content/Defender-Custom-Detections.md) |
| Hunting Queries | [Content/Hunting-Queries.md](Docs/Content/Hunting-Queries.md) |
| Parsers | [Content/Parsers.md](Docs/Content/Parsers.md) |
| Playbooks | [Content/Playbooks.md](Docs/Content/Playbooks.md) |
| Summary Rules | [Content/Summary-Rules.md](Docs/Content/Summary-Rules.md) |
| Watchlists | [Content/Watchlists.md](Docs/Content/Watchlists.md) |
| Workbooks | [Content/Workbooks.md](Docs/Content/Workbooks.md) |

Auto-generated per-contributor summaries live under `Docs/Content/Community/` (for
example [Dalonso](Docs/Content/Community/Dalonso.md)); do not hand-edit them.

### Authoring Toolkit - `Docs/Toolkit/`

The [Sentinel as Code Toolkit](Docs/Toolkit/README.md) companion VS Code extension
(a separate repository). It authors and validates; it does not deploy.

| Area | Doc |
|------|-----|
| Overview and install | [Toolkit/README.md](Docs/Toolkit/README.md) |
| Commands | [Toolkit/Commands.md](Docs/Toolkit/Commands.md) |
| Templates | [Toolkit/Templates.md](Docs/Toolkit/Templates.md) |
| Schemas and Validation | [Toolkit/Schemas-and-Validation.md](Docs/Toolkit/Schemas-and-Validation.md) |
| Configuration | [Toolkit/Configuration.md](Docs/Toolkit/Configuration.md) |
| ARM to YAML Conversion | [Toolkit/ARM-to-YAML-Conversion.md](Docs/Toolkit/ARM-to-YAML-Conversion.md) |
| Defender Workflows | [Toolkit/Defender-Workflows.md](Docs/Toolkit/Defender-Workflows.md) |
| Graph API Migrations | [Toolkit/Graph-API-Migrations.md](Docs/Toolkit/Graph-API-Migrations.md) |

### Deploy - `Docs/Deploy/`

| Area | Doc |
|------|-----|
| Scripts | [Deploy/Scripts.md](Docs/Deploy/Scripts.md) |
| PR Validation Setup | [Deploy/PR-Validation-Setup.md](Docs/Deploy/PR-Validation-Setup.md) |
| ADO OIDC Setup | [Deploy/ADO-OIDC-Setup.md](Docs/Deploy/ADO-OIDC-Setup.md) |
| PowerShell Module Requirements | [Deploy/PowerShell-Module-Requirements.md](Docs/Deploy/PowerShell-Module-Requirements.md) |

### Pipelines - `Docs/Pipelines/`

Start at the [index](Docs/Pipelines/README.md) for the GitHub/ADO parity map, then
the deep per-pipeline pages: [PR-Validation](Docs/Pipelines/PR-Validation.md),
[Deploy](Docs/Pipelines/Deploy.md), [Deploy-Nightly](Docs/Pipelines/Deploy-Nightly.md),
[Drift-Detect](Docs/Pipelines/Drift-Detect.md), [Documenter](Docs/Pipelines/Documenter.md),
[Dependency-Update](Docs/Pipelines/Dependency-Update.md),
[DCR-Inventory](Docs/Pipelines/DCR-Inventory.md), and
[Word-Report](Docs/Pipelines/Word-Report.md).

### Infrastructure and modules - `Docs/Infra/`, `Docs/Modules/`

| Area | Doc |
|------|-----|
| Bicep | [Infra/Bicep.md](Docs/Infra/Bicep.md) |
| Sentinel.Common module | [Modules/Sentinel-Common-Module.md](Docs/Modules/Sentinel-Common-Module.md) |

### Tools - `Docs/Tools/`

| Area | Doc |
|------|-----|
| Dependency Manifest | [Tools/Dependency-Manifest.md](Docs/Tools/Dependency-Manifest.md) |
| Sentinel Drift Detection | [Tools/Sentinel-Drift-Detection.md](Docs/Tools/Sentinel-Drift-Detection.md) |
| DCR Watchlist Sync | [Tools/DCR-Watchlist.md](Docs/Tools/DCR-Watchlist.md) |
| SDL Migration Workbook Export | [Tools/SDL-Migration-Workbook-Export.md](Docs/Tools/SDL-Migration-Workbook-Export.md) |

Documenter (`Docs/Tools/Documenter/`): [Sentinel Documenter](Docs/Tools/Documenter/Sentinel-Documenter.md),
[Renderer Design](Docs/Tools/Documenter/Documenter-Renderer-Design.md),
[References](Docs/Tools/Documenter/Documenter-References.md),
[Data Lake Coverage](Docs/Tools/Documenter/Sentinel-Data-Lake-Coverage.md), and
[Word Report](Docs/Tools/Documenter/Sentinel-Word-Report.md).

### Tests and Copilot - `Docs/Tests/`, `Docs/GitHub/`

| Area | Doc |
|------|-----|
| Pester Tests | [Tests/Pester-Tests.md](Docs/Tests/Pester-Tests.md) |
| GitHub Copilot | [GitHub/GitHub-Copilot.md](Docs/GitHub/GitHub-Copilot.md) |

### Guides - `Docs/Guides/`

End-to-end walkthroughs.

| Area | Doc |
|------|-----|
| Build and Test Guide | [Guides/Sentinel-As-Code-Build-and-Test-Guide.md](Docs/Guides/Sentinel-As-Code-Build-and-Test-Guide.md) |

### Releases - `Docs/Releases/`

| Area | Doc |
|------|-----|
| Versioning | [Releases/Versioning.md](Docs/Releases/Versioning.md) |
| Changelog | [Releases/CHANGELOG.md](Docs/Releases/CHANGELOG.md) |
| Layout Restructure 26.06 | [Releases/Layout-Restructure-26.06.md](Docs/Releases/Layout-Restructure-26.06.md) |

## Infrastructure (Bicep)

Subscription-scoped Bicep templates in `Infra/` provision the resource group, Log Analytics workspace, Sentinel onboarding (both legacy `OperationsManagement/solutions` and modern `SecurityInsights/onboardingStates`), diagnostic settings, and an optional separate playbook resource group. Sentinel feature settings (Entity Analytics, UEBA, Anomalies, EyesOn) are configured via REST in the same pipeline stage.

For the full parameter reference, resource list, API versions, and limitations, see [Docs/Infra/Bicep.md](Docs/Infra/Bicep.md).

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

The best way to support this project is by subscribing to the blog, submitting issues, suggesting improvements, or contributing code! If you're using this in an organisation, see the [donation callout under Overview](#overview).

## Disclaimer

This project is provided **as-is**, with **no warranty** and **no support** of any kind, express or implied. Use at your own risk.

The maintainers make no guarantee that the code is fit for any particular purpose, that it will work in your environment, or that any issue you encounter will be acknowledged or fixed. Bug reports and pull requests are welcome (see [Contributing](#contributing)), but there is **no SLA, no guaranteed response time, and no obligation to provide assistance**.

You are solely responsible for reviewing, testing, and validating any content from this repository before deploying it to production Microsoft Sentinel or Defender XDR environments.

## License

This project is licensed under the [Apache License 2.0](LICENSE). See [`NOTICE`](NOTICE) for copyright and third-party attribution. Releases from `26.07` onward are Apache-2.0; earlier releases remain available under the MIT License.
