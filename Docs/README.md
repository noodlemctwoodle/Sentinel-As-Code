<p align="center">
  <img src="../.images/Sentinel-As-Code-26.06.png" alt="Sentinel-As-Code" />
</p>

# Documentation

Reference material for Sentinel-As-Code, grouped by concern. Pick the
section that matches what you're trying to do.

## Content authoring

Schemas and conventions for every content type the repo deploys.

| Doc | What it covers |
| --- | --- |
| [Analytical Rules](Content/Analytical-Rules.md) | YAML schema for custom analytics rules: required fields, deploy behaviour, Scheduled vs NRT examples |
| [Automation Rules](Content/Automation-Rules.md) | JSON schema for automation rules: trigger conditions, action types (ModifyProperties, RunPlaybook, AddIncidentTask) |
| [Community Rules](Content/Community-Rules.md) | Opt-in third-party rule contributions: deployment defaults, current sources, adding new contributors |
| [Defender Custom Detections](Content/Defender-Custom-Detections.md) | Defender XDR YAML schema, Graph API, response actions, impacted-asset identifiers |
| [Hunting Queries](Content/Hunting-Queries.md) | YAML schema for hunting queries: required fields, tactics/techniques tags, export guide |
| [Playbooks](Content/Playbooks.md) | ARM template requirements, MSI vs standard connections, auto-injected parameters |
| [Summary Rules](Content/Summary-Rules.md) | Summary-rule JSON schema, allowed bin sizes, KQL restrictions, system columns |
| [Watchlists](Content/Watchlists.md) | Watchlist metadata schema, CSV format, KQL usage examples |
| [Workbooks](Content/Workbooks.md) | Gallery-template JSON format, stable GUIDs, export from the Sentinel portal |

## Infrastructure

Azure resources that host Sentinel content — `Infra/`.

| Doc | What it covers |
| --- | --- |
| [Bicep](Infra/Bicep.md) | Subscription-scoped templates, parameters, dual onboarding mechanism, diagnostic settings, optional playbook RG |

## Deployment

How content reaches Sentinel — pipelines and the scripts they invoke (`Deploy/`).

| Doc | What it covers |
| --- | --- |
| [Pipelines](Deploy/Pipelines.md) | Pipeline stages, variable group, parameters, service connection, usage examples |
| [Scripts](Deploy/Scripts.md) | PowerShell deploy and tooling scripts — parameters, examples, known limitations |
| [PR Validation Setup](Deploy/PR-Validation-Setup.md) | One-off GitHub Actions OIDC federated-credential setup for the `arm-validate` PR job |
| [ADO OIDC Setup](Deploy/ADO-OIDC-Setup.md) | One-off Azure DevOps workload-identity-federation setup for `sc-sentinel-as-code` |

## Tooling

CI, maintenance, and reporting that runs *around* deployment — `Tools/`.

| Doc | What it covers |
| --- | --- |
| [Dependency Manifest](Tools/Dependency-Manifest.md) | Auto-derived `dependencies.json` from KQL discovery; PR-validation drift gate; daily auto-PR refresh |
| [Sentinel Drift Detection](Tools/Sentinel-Drift-Detection.md) | Daily detection of portal-edited rules with auto-PR back into the repo |

### Documenter

The read-only documentation generator — `Tools/Documenter/`.

| Doc | What it covers |
| --- | --- |
| [Sentinel Documenter](Tools/Documenter/Sentinel-Documenter.md) | Read-only daily inventory + gap-analysis that renders a Markdown documentation pack from a live workspace |
| [Renderer Design](Tools/Documenter/Documenter-Renderer-Design.md) | Design spec for the Markdown renderer — what drives each chart and section |
| [References & Conventions](Tools/Documenter/Documenter-References.md) | Durable record of every API version, module, KQL query, and Learn page the Documenter relies on (rendered as `99-references.md`) |
| [Data Lake Coverage](Tools/Documenter/Sentinel-Data-Lake-Coverage.md) | What the Documenter captures and renders for the Microsoft Sentinel data lake tier |

## Operations

Continuous run-time concerns: DCR inventory and scheduled jobs.

| Doc | What it covers |
| --- | --- |
| [DCR Watchlist Sync](Operations/DCR-Watchlist.md) | Auto-populated DCR inventory watchlist, billing reporting, runbook deployment |

## Development

Testing, contributing, and extending the tooling.

| Doc | What it covers |
| --- | --- |
| [Pester Tests](Development/Pester-Tests.md) | Running and extending the Pester suite, the AST-extraction pattern this repo uses |
| [GitHub Copilot](Development/GitHub-Copilot.md) | Copilot customisations shipped with the repo: instructions, agents, prompts (cross-platform: github.com + every IDE) |

## Releases

Versioning scheme and the customer-facing changelog.

| Doc | What it covers |
| --- | --- |
| [Versioning](Releases/Versioning.md) | CalVer (`YY.0M`) scheme, tagging, the wave → CalVer history, and how repo CalVer relates to the `Sentinel.Common` module's SemVer |
| [Changelog](Releases/CHANGELOG.md) | Customer-facing summary of changes per release |
| [26.06 Layout Restructure](Migration/26.06-Layout-Restructure.md) | Old → new path map for the by-concern restructure and the fork-migration steps |

## Auto-generated artefacts

The `Community/` folder (created on first import run) is reserved for files written by
[`Tools/Import-CommunityRules.ps1`](../Tools/Import-CommunityRules.ps1).
One file per contributor is regenerated each import run, with per-category
rule listings and last-sync metadata. Do not hand-edit these.

| Auto-generated file | Contributor source |
| --- | --- |
| `Community/Dalonso.md` | David Alonso — see [Community Rules](Content/Community-Rules.md#david-alonso--threat-hunting-rules) |

## Conventions

- **Filename style**: `Title-Case-With-Hyphens.md`
- **Cross-links inside Docs/**: relative paths (`../Operations/Foo.md`, `Sibling.md`). The repo enforces these via the link checker described in [Pester Tests](Development/Pester-Tests.md).
- **Cross-links to repo content**: from a doc at `Docs/{Bucket}/X.md`, the repo root is `../../`. Example: `../../Deploy/content/Deploy-CustomContent.ps1`.
- **Adding a new doc**: place it in the bucket that matches its concern. If the concern doesn't fit any bucket, propose a new bucket folder rather than dropping the file at the `Docs/` root.
