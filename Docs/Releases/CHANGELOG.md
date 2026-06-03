# Changelog

Customer-facing changes to Sentinel-As-Code, newest first. Releases use CalVer
(`YY.0M`) — see [Versioning](Versioning.md). "Wave N" was the previous release
label (now retired); the wave → CalVer mapping is in [Versioning](Versioning.md).

## 26.06.1

- **Repository restructure** into a by-concern layout — `Content/`, `Infra/`,
  `Deploy/`, `Tools/`. No Sentinel content logic changed.
- **Adopted monthly CalVer versioning** (`YY.0M`); the "Wave N" naming is retired.
- Added a layout migration guide and a one-shot fork-rebase helper.
- Forks and anyone referencing repo paths should review the
  [26.06 Layout Restructure guide](../Migration/26.06-Layout-Restructure.md).

## 26.06.0 — Wave 4 · June 2026

- **Sentinel Documenter v1** — generates a full Markdown documentation pack
  (inventory, coverage, and gap analysis) from a live Sentinel workspace, and
  runs daily.
- **Dependency manifest** — `dependencies.json` is auto-derived from KQL
  discovery and enforced as a PR-validation gate, so content and the tables and
  functions it depends on can't silently drift apart.
- Continuous-integration hardening across the validation and deploy workflows.

## 26.05 — Wave 3 · May 2026

- **`Sentinel.Common` PowerShell module** — shared deployment logic extracted
  into a tested, reusable module.
- **GitHub Actions ↔ Azure DevOps parity** — both pipelines deploy the same
  content with aligned defaults and inputs.
- **Deploy only what's missing** — deployments now detect existing
  infrastructure and skip whatever is already in place.
- **Data-lake migration savings audit workbook** — replaces the earlier
  data-lake workbook with a cost-savings audit view.
- Auto-create the playbook resource group via Bicep; security hardening
  (subscription IDs scrubbed from in-tree references).

## 26.04 — Wave 2 · April 2026

- **Smart, dependency-aware deployment** — content converges in dependency
  order, resolving the tables and functions each item needs.
- **Analytics rule drift detection + auto-sync** — portal-edited rules are
  detected daily and synced back into the repository.
- **Community threat-hunting rules** — opt-in third-party rule sets imported on
  a standardised schema.
- **28 Defender XDR custom detection rules** added, with the NRT caveat
  documented.
- Expanded playbook catalogue and `Set-PlaybookPermissions`; optional playbook
  resource-group onboarding.
- **PR validation** workflow with YAML schema checks for analytics and hunting
  content.

## 26.03 — Wave 1 · March 2026

- **Content Hub deployment pipeline** — deploy Microsoft-published Content Hub
  solutions through a parameterised pipeline.
- **Custom content deployment** — a five-stage pipeline and script that deploy
  analytics rules, hunting queries, playbooks, watchlists, parsers, and
  workbooks.
- **DCR watchlist inventory** — an Automation runbook that inventories Data
  Collection Rule associations into a Sentinel watchlist for billing and audit.
- **Bulk playbook export** for extracting Logic App definitions.
- Least-privilege RBAC guidance (Contributor, with a documented narrower
  alternative).
