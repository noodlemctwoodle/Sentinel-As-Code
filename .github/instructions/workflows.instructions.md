---
name: CI/CD workflows and pipelines
description: Conventions for GitHub Actions workflows and Azure DevOps pipelines.
applyTo: ".github/workflows/**/*.yml,.github/actions/**/*.yml,Pipelines/**/*.yml"
---

# CI/CD workflows and pipelines

GitHub Actions workflows live under `.github/workflows/`; Azure DevOps
pipelines live under `Pipelines/`. The ADO version is the source of
truth — GitHub workflows mirror ADO behaviour. Reference doc:
[`Docs/Deployment/Pipelines.md`](../../Docs/Deployment/Pipelines.md).

## File inventory

| GitHub Actions | Azure DevOps | What |
| --- | --- | --- |
| `.github/workflows/sentinel-deploy.yml` | `Pipelines/Sentinel-Deploy.yml` | Weekly Mon 04:00 UTC: full deploy (Bicep + Content Hub + custom + Defender) |
| `.github/workflows/sentinel-drift-detect.yml` | `Pipelines/Sentinel-Drift-Detect.yml` | Daily 06:00 UTC: detect portal-edited rules + auto-PR |
| `.github/workflows/sentinel-dcr-inventory.yml` | `Pipelines/Sentinel-DCR-Inventory.yml` | On change: deploy DCR inventory runbook |
| `.github/workflows/sentinel-dependency-update.yml` | `Pipelines/Sentinel-Dependency-Update.yml` | Daily 02:00 UTC: refresh `dependencies.json` + auto-PR |
| `.github/workflows/pr-validation.yml` | `Pipelines/Sentinel-PR-Validation.yml` | On every PR: 5-job merge gate |
| `.github/workflows/sentinel-deploy-nightly.yml` | *(GitHub-only)* | Daily 03:00 UTC: E2E smoke test against test workspace |

## Composite actions

Two composite actions live under `.github/actions/`. **Use these**
instead of inlining `Azure/login@v2` or `Install-Module` patterns:

- **`./.github/actions/azure-login-oidc`** — OIDC federated login.
  Inputs: `client-id`, `tenant-id`, `subscription-id`,
  `enable-azps-session` (default `'true'`).
- **`./.github/actions/setup-pwsh-modules`** — cached + pinned
  install of Pester + powershell-yaml. Inputs: `pester-version`,
  `yaml-version`, `install-pester` (set `'false'` for yaml-only jobs
  like the dep-manifest gate).

## Hard rules

1. **ADO is the source of truth.** When the two diverge, change ADO
   first, then port to GitHub. The reverse direction creates merge
   conflicts that are hard to spot in review.
2. **Pin versions for every PSGallery / NuGet / GitHub Action you
   add.** Workflow-level env vars (`PESTER_VERSION`, `YAML_VERSION`,
   `KUSTO_LANGUAGE_VERSION`) are the convention. A breaking change
   shipped from a registry must NOT be able to silently fail a
   scheduled run on an unrelated repo change.
3. **Use `actions/checkout@v4`** (the latest pinned major). Don't
   pin to `@main` or `@master`.
4. **Auth via OIDC, not service principal secrets.** All federated
   creds use the SP set up by
   `Scripts/Setup-ServicePrincipal.ps1`; the workflow needs
   `permissions: id-token: write`.
5. **Schedule alignment** — daily / weekly schedules must avoid
   stepping on each other. Current alignment:
   - 02:00 UTC daily: `sentinel-dependency-update`
   - 03:00 UTC daily: `sentinel-deploy-nightly` (GH-only)
   - 04:00 UTC Monday: `sentinel-deploy`
   - 06:00 UTC daily: `sentinel-drift-detect`
6. **`concurrency: cancel-in-progress: true`** for PR-style workflows
   (re-runs invalidate the previous run's status check).
   `cancel-in-progress: false` for scheduled workflows that should
   accumulate (nightly E2E, drift sync — each run keeps its own
   context for diagnosis).
7. **`workflow_dispatch` inputs match parameters** — when a workflow
   has both a schedule trigger and a manual `workflow_dispatch`
   trigger, every dispatch input must default to the same value the
   schedule run gets implicitly.
8. **Permissions block** — declare `permissions:` explicitly on
   every job (or workflow-level). Default-permissive is the wrong
   default for any job that touches a write API.

## Path filters (ADO build-validation)

The ADO PR-validation policy currently filters on these paths:

```
AnalyticalRules/*;HuntingQueries/*;Modules/*;Scripts/*;Tests/*;dependencies.json
```

If you add a new top-level folder that should trigger PR validation
(e.g. a future `Connectors/` folder), update this filter in two
places:

- `Pipelines/Sentinel-PR-Validation.yml` — `pr.paths.include` and
  `trigger.paths.include`
- The build-validation policy in ADO (Project Settings → Repos →
  Repositories → `<repo>` → Policies → Branch policies for `main`
  → Build validation). The path filter on the policy is the
  enforcement boundary; the YAML's `pr.paths.include` is the
  *trigger* boundary.

## Cross-references

- Pipeline reference: [`Docs/Deployment/Pipelines.md`](../../Docs/Deployment/Pipelines.md)
- Composite actions: [`Docs/Deployment/PR-Validation-Setup.md`](../../Docs/Deployment/PR-Validation-Setup.md)
- PR-validation gate reference: [`Docs/Development/Pester-Tests.md`](../../Docs/Development/Pester-Tests.md)
