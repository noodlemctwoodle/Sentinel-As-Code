# Pipelines

CI/CD that drives infrastructure provisioning, content deployment, and
operational tooling. The repository ships **seven Azure DevOps pipelines**
under [`Pipelines/`](../../Pipelines) and **eight GitHub Actions workflows**
under [`.github/workflows/`](../../.github/workflows).

This page is an index: it covers the shared concepts and the GitHub <-> ADO
mapping, then links out to a per-pipeline deep-dive for each one. Read the
linked page for the triggers, inputs, stages, parameters, and usage of a
specific pipeline.

## Per-Pipeline Docs

| Pipeline | Purpose | Deep-dive |
| --- | --- | --- |
| PR Validation | Merge gate for `main` - runs every Pester suite, `bicep-build`, `arm-validate`, `kql-validate`, and the dependency-manifest drift gate | [PR-Validation.md](PR-Validation.md) |
| PR Template Validation | **GitHub-only** check that fails a PR whose description leaves the required template sections empty | [PR-Template-Validation.md](PR-Template-Validation.md) |
| Deploy | Main end-to-end deploy: Bicep infra, Content Hub solutions, custom content, and Defender XDR custom detections | [Deploy.md](Deploy.md) |
| Deploy Nightly | **GitHub-only** nightly E2E smoke test that provisions and tears down the throwaway `Infra/test-workspace/` workspace | [Deploy-Nightly.md](Deploy-Nightly.md) |
| Drift-Detect | Detect rules edited in the portal and auto-PR the drift back into the repo (report-only runs never open a PR) | [Drift-Detect.md](Drift-Detect.md) |
| Documenter | Snapshot the live Sentinel workspace to Markdown (requires a private repository) | [Documenter.md](Documenter.md) |
| Dependency Update | Keep [`dependencies.json`](../../dependencies.json) in sync with the content tree and auto-PR any drift | [Dependency-Update.md](Dependency-Update.md) |
| DCR Inventory | Deploy the DCR-watchlist sync automation account, runbook, and schedule | [DCR-Inventory.md](DCR-Inventory.md) |
| Word Report | **ADO-only** render of the Documenter Markdown into a styled `.docx` via pandoc and LibreOffice | [Word-Report.md](Word-Report.md) |

## GitHub <-> ADO Parity

Six of the seven ADO pipelines have a GitHub workflow mirror. Three workflows
break the symmetry (one ADO-only, two GitHub-only), so the two sets are **not**
a clean one-to-one mapping.

| ADO pipeline (`Pipelines/`) | GitHub workflow (`.github/workflows/`) |
| --- | --- |
| `Sentinel-PR-Validation.yml` | `pr-validation.yml` |
| `Sentinel-Deploy.yml` | `sentinel-deploy.yml` |
| `Sentinel-Drift-Detect.yml` | `sentinel-drift-detect.yml` |
| `Sentinel-DCR-Inventory.yml` | `sentinel-dcr-inventory.yml` |
| `Sentinel-Dependency-Update.yml` | `sentinel-dependency-update.yml` |
| `Sentinel-Documenter.yml` | `sentinel-document.yml` |
| `Sentinel-Word-Report.yml` | *(ADO-only, no GitHub equivalent)* |
| *(GitHub-only, no ADO equivalent)* | `sentinel-deploy-nightly.yml` |
| *(GitHub-only, no ADO equivalent)* | `pr-template-validation.yml` |

Asymmetries worth knowing:

- [`sentinel-deploy-nightly.yml`](../../.github/workflows/sentinel-deploy-nightly.yml)
  is **GitHub-only** - a nightly E2E smoke test against the throwaway
  workspace from `Infra/test-workspace/main.bicep`. There is no ADO
  equivalent. See [Deploy-Nightly.md](Deploy-Nightly.md).
- [`pr-template-validation.yml`](../../.github/workflows/pr-template-validation.yml)
  is **GitHub-only** - it fails a PR whose description does not fill in
  [`.github/PULL_REQUEST_TEMPLATE.md`](../../.github/PULL_REQUEST_TEMPLATE.md)
  (the `template` status check). The PR body arrives in the Actions event
  payload, which has no ADO build-validation equivalent. See
  [PR-Template-Validation.md](PR-Template-Validation.md).
- [`Sentinel-Word-Report.yml`](../../Pipelines/Sentinel-Word-Report.yml)
  is **ADO-only** - the pandoc plus LibreOffice `.docx` render of the
  Documenter Markdown. There is no `*word*` workflow under
  `.github/workflows/`. See [Word-Report.md](Word-Report.md).
- The **Documenter** pair diverges on schedule: the GitHub workflow
  (`sentinel-document.yml`) runs on a daily cron plus `workflow_dispatch`,
  whereas the ADO pipeline (`Sentinel-Documenter.yml`) is manual-trigger-only
  for now. See [Documenter.md](Documenter.md).

## Shared Concepts

### OIDC Authentication

Both CI systems authenticate to Azure with **workload identity federation
(OIDC)**, not a stored secret. A single service principal in Entra ID carries
federated credentials that trust each CI system's token issuer, so every job
gets a short-lived per-run token and no client secret is stored anywhere.

- **GitHub Actions** logs in through the
  [`azure-login-oidc`](../../.github/actions/azure-login-oidc/action.yml)
  composite action, which wraps `Azure/login@v3` with the standard
  client/tenant/subscription parameter set.
- **Azure DevOps** uses a workload-identity-federation service connection
  (named `sc-sentinel-as-code` by default). Full step-by-step:
  [ADO OIDC Setup](../Deploy/ADO-OIDC-Setup.md). GitHub-side prerequisites:
  [PR Validation Setup](../Deploy/PR-Validation-Setup.md).

### Variables and Secrets

- **Azure DevOps** reads deployment inputs from the `sentinel-deployment`
  variable group under **Pipelines > Library** (subscription ID, resource
  group, workspace name, region, and optional playbook resource group). The
  per-pipeline docs list the variables each one consumes.
- **GitHub Actions** reads the equivalent values from repository or
  environment secrets and variables.

### Composite Actions (GitHub)

To avoid duplicated step blocks across workflows, the GitHub side factors two
shared patterns into composite actions under
[`.github/actions/`](../../.github/actions):

- [`azure-login-oidc`](../../.github/actions/azure-login-oidc/action.yml) -
  the one-line OIDC login described above.
- [`setup-pwsh-modules`](../../.github/actions/setup-pwsh-modules/action.yml) -
  installs the PowerShell modules the jobs need (Pester and
  `powershell-yaml`).

---

## Authoring with GitHub Copilot

When editing files under `.github/workflows/`, `.github/actions/`,
or `Pipelines/`, Copilot automatically loads
[`.github/instructions/workflows.instructions.md`](../../.github/instructions/workflows.instructions.md).
The path-scoped instructions cover ADO-as-source-of-truth, the
composite-action adoption rule, schedule alignment, and the
ADO -> GitHub Actions translation table.

Copilot tooling for pipelines:

- Agent `Sentinel-As-Code: Pipeline Engineer` - owns CI/CD
  end-to-end. Authors and edits workflows, maintains parity between
  ADO and GitHub, manages composite actions, diagnoses pipeline
  failures, manages cron schedules.
- Agent `Sentinel-As-Code: Bicep Engineer` - for the
  `deploy-infrastructure` stage and the underlying Bicep
  templates.
- Agent `Sentinel-As-Code: Security Reviewer` - for permissions
  blocks, OIDC federated-credential scoping, secret references.

See [GitHub Copilot setup](../GitHub/GitHub-Copilot.md) for the full layout.
