# Sentinel As Code

<p align="center">
  <img src="./.images/Sentinel-As-Code.png" alt="Sentinel-As-Code" width="512" />
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

## Repository structure

```
.github/            GitHub Actions workflows, composite actions, and Copilot customisations
AGENTS.md           Cross-tool agent guidance (Copilot, Claude, Gemini, Cursor)
Blog/               Source posts for sentinel.blog
Content/            All Sentinel content, grouped by type (analytical/hunting/summary rules,
                    watchlists, playbooks, workbooks, parsers, automation rules, Defender detections)
Infra/              Three subscription-scoped Bicep stacks (production Sentinel, test workspace,
                    DCR-watchlist automation)
Deploy/             Deployment scripts and sentinel-deployment.config
Tools/              CI and maintenance tooling (dependency manifest, drift, PR validation,
                    workbook export, community import, Documenter)
Pipelines/          Azure DevOps pipeline definitions
Modules/            In-repo PowerShell modules (Sentinel.Common shared deployer + KQL helpers)
Tests/              Pester test suite
Docs/               All documentation, mirroring the repo layout (start at Docs/README.md)
dependencies.json   Auto-derived content dependency graph
```

For what lives inside each folder and how content is authored, see the
[Documentation](#documentation) section below, starting at
[`Docs/README.md`](Docs/README.md).

## Features

- **End-to-end deployment**: a single pipeline provisions infrastructure via Bicep, then deploys Content Hub solutions, custom Sentinel content (analytical rules, hunting queries, watchlists, playbooks, workbooks, parsers, automation rules, summary rules), and Defender XDR custom detections.
- **Smart, incremental deployment**: the deploy pipeline runs incrementally by default, using a git diff and a state file to skip unchanged items and auto-retry previously failed ones. See [Deploy](Docs/Pipelines/Deploy.md) and [Scripts](Docs/Deploy/Scripts.md).
- **Auto-derived dependency graph**: `dependencies.json` is generated from KQL content discovery, gated in CI, and refreshed by a daily auto-PR. See [Dependency Manifest](Docs/Tools/Dependency-Manifest.md).
- **Drift detection and absorption**: a daily detector compares every deployed rule against its source of truth and absorbs portal edits back into the repo as PRs. See [Sentinel Drift Detection](Docs/Tools/Sentinel-Drift-Detection.md).
- **Workbook round-trip export**: pull user-authored workbooks from a workspace into the repo with placeholders and curated metadata, making portal authoring a first-class repo workflow. See [Workbooks](Docs/Content/Workbooks.md).
- **PR validation and nightly E2E**: a five-job merge gate (Pester, Bicep build, ARM validation, KQL syntax, dependency-manifest drift) runs on every PR, and a nightly smoke test exercises every deploy path against a throwaway test workspace. See [PR Validation](Docs/Pipelines/PR-Validation.md) and [Deploy Nightly](Docs/Pipelines/Deploy-Nightly.md).
- **Customisation protection and dry runs**: locally tuned rules are detected and skipped, and `-WhatIf` previews changes before applying.
- **Azure Government support**: target both commercial and government cloud environments.
- **Shared tooling**: the `Sentinel.Common` PowerShell module is the single source of truth for the deployer helpers and KQL discovery, and reusable GitHub Actions composites (`azure-login-oidc`, `setup-pwsh-modules`) pin every dependency. See [Sentinel.Common module](Docs/Modules/Sentinel-Common-Module.md).
- **Repo-aware AI assistance**: thirteen cross-platform GitHub Copilot agents plus path-scoped instructions and reusable prompts. See [GitHub Copilot](Docs/GitHub/GitHub-Copilot.md).

## Quick start

1. **Grant permissions.** Run `Deploy/setup/Setup-ServicePrincipal.ps1` once to grant the service principal every required role (Contributor, ABAC-conditioned User Access Administrator, plus the optional Security Administrator and `CustomDetection.ReadWrite.All` grants) with a Y/N consent prompt. After that the pipeline is autonomous. Full role list: [Deploy](Docs/Pipelines/Deploy.md); bootstrap detail: [Scripts](Docs/Deploy/Scripts.md).
2. **Wire up CI.** On Azure DevOps, create the `sc-sentinel-as-code` service connection and the `sentinel-deployment` variable group, then point a pipeline at `Pipelines/Sentinel-Deploy.yml`. See [ADO OIDC Setup](Docs/Deploy/ADO-OIDC-Setup.md) and [Deploy](Docs/Pipelines/Deploy.md). On GitHub, the workflows under `.github/workflows/` authenticate via OIDC; see [PR Validation Setup](Docs/Deploy/PR-Validation-Setup.md).
3. **Run it.** The deploy checks for existing infrastructure, deploys Bicep if needed, configures Sentinel settings, then deploys Content Hub and custom content in ordered stages followed by Defender XDR detections.

New to the project? The [Build and Test Guide](Docs/Guides/Sentinel-As-Code-Build-and-Test-Guide.md) walks through requirements, permissions, and a no-local-install path end to end. For the standalone pipelines, the GitHub-to-ADO parity map, and each pipeline's schedule, see [Docs/Pipelines/README.md](Docs/Pipelines/README.md).

## GitHub Copilot agents

The repo ships a complete GitHub Copilot customisation set so authors get repo-aware AI help out of the box, with no VS Code settings or feature toggles required. It comprises thirteen custom agents (five persona-broad, eight engineering specialists), nine path-scoped instruction files that load automatically when you edit a matching file, and six reusable slash-command prompts, plus repo-wide guidance in [`.github/copilot-instructions.md`](.github/copilot-instructions.md) and cross-tool guidance in [`AGENTS.md`](AGENTS.md). It works on github.com Chat, the github.com cloud agent, VS Code, Visual Studio, JetBrains, and Copilot CLI without configuration. Full roster and usage: [Docs/GitHub/GitHub-Copilot.md](Docs/GitHub/GitHub-Copilot.md).

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

## Contributing

Contributions are welcome. See the [Contributing guide](Docs/Contributing.md) for how to report bugs, suggest enhancements, author content, run the checks, and open a pull request. In short: fork the repository, branch from `main`, fill in the [pull request template](.github/PULL_REQUEST_TEMPLATE.md), and make sure the `template` check and the five-job validation gate pass before requesting a merge.

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
