# Changelog

Customer-facing changes to Sentinel-As-Code, newest first. Releases use CalVer
(`YY.0M`) — see [Versioning](Versioning.md). "Wave N" was the previous release
label (now retired); the wave → CalVer mapping is in [Versioning](Versioning.md).

## 26.09

Connector, workbook and content-hygiene release, plus a repository-wide
standardisation of PowerShell file headers.

- **Sophos Central codeless connector** — a Codeless Connector Framework (CCF)
  package that ingests Sophos Central SIEM API events and alerts with no Logic
  App or Function App in the path. Auth is OAuth2 client credentials, paging is
  cursor-based over `NextPageToken`, and raw snake_case field names are
  translated to PascalCase in the DCR transform so the translation lives in
  exactly one place. Deploy-time placeholders keep the package portable across
  workspaces and regions. This is the first CCF package in the repository and
  establishes `Content/CodelessConnectors/` as the home for the pattern.
- **Detection Engineering dashboard** — a nine-tab workbook covering the health,
  coverage, fidelity and lifecycle of the detection portfolio: rule inventory
  and health, MITRE coverage, alert fidelity, incident outcomes, ingestion, and
  engineering velocity. Built on the `AlertInfo` advanced-hunting table rather
  than `SecurityAlert`, so it spans Defender for Endpoint, Office 365, Identity
  and Cloud Apps alongside custom detections, and still returns data in unified
  SecOps tenants where `SentinelHealth` and `SentinelAudit` are not enabled. It
  also surfaces which classic custom tables are still posting to the Azure
  Monitor HTTP Data Collector API, which loses support on 14 September 2026.
  Ships with a reference page and an Overview screenshot.
- **Connector metadata corrections** — `requiredDataConnectors` fixed on 14
  analytical rules that carried authoring placeholders (`YourConnectorId`),
  empty connector blocks, non-existent connector IDs, or data types the named
  connector does not emit. Nothing failed at deploy time, which is why the
  errors survived, but the metadata feeds Content Hub solution mapping and the
  dependency-impact scoring in `Invoke-TableMigrationReview.ps1`, so wrong
  values there produced wrong answers in migration assessments. No detection
  logic changed.
- **PowerShell file headers standardised** — every `.ps1` and `.psm1` in the
  repository now opens with its `#Requires` statements, then a comment-based
  help block, and nothing else above either. The five-line `#` path/date banner
  is gone and its metadata moved into `.NOTES`, which now carries the same eight
  keys everywhere. Scripts also declare their real dependencies as `#Requires`
  statements rather than only in prose, so a missing module now fails at the
  door instead of part-way through a deployment. Modules a script installs for
  itself stay out of `#Requires`, since the statement aborts the load before the
  install could run. The header rewrite itself is comment-only, verified by
  comparing the executable token stream of all 64 files before and after; the
  one behavioural change that came out of this work is listed separately below.
- **Setup-ServicePrincipal installs the right Graph submodule** — the Entra ID
  role-assignment step installed `Microsoft.Graph.Identity.DirectoryManagement`
  but called `Get-MgRoleManagementDirectoryRoleAssignment` and its `New-`
  counterpart, both of which ship in `Microsoft.Graph.Identity.Governance`. On a
  machine that already had Governance present the step worked by accident; on a
  clean machine the install succeeded, the cmdlet lookup failed, and the catch
  block reported it as a missing Privileged Role Administrator permission,
  sending anyone debugging it after a problem that did not exist. The script now
  installs `Microsoft.Graph.Identity.Governance`, and the docs that repeated the
  wrong module name were corrected with it.
- **Notebook ordering** — the data-lake demo notebooks are zero-padded
  (`demo01` to `demo18`) so GitHub's lexical file listing matches the order the
  catalogue presents them in, rather than burying the connect-and-orient
  notebook two thirds of the way down.

## 26.07.3

Data-lake tooling release: two migration toolkits for moving off classic custom
log tables, and two new content types for the Microsoft Sentinel data lake.

- **Classic-to-DCR migration toolkit** — three PowerShell scripts under
  `Tools/ClassicToDcr/` that take a classic (MMA / HTTP Data Collector API)
  custom log table from "we do not know what depends on this" to migrated, with
  a Data Collection Rule deployed and the new sender ingesting. A read-only
  assessment pass scores impact and resolves indirect parser chains before
  anything changes; the migration itself is one-way and says so; and a rehearsal
  harness lets you prove the ingestion path before you commit. It does not
  repoint your sending application for you.
- **DCR-from-schema wizard** — `Tools/DcrFromSchema/New-DcrFromSchema.ps1` turns
  a JSON table schema into a Log Analytics custom table and a Direct Data
  Collection Rule for the Logs Ingestion API, then leaves the ARM templates
  behind so the result is reviewable and committable rather than clicked into
  existence.
- **Spark notebooks for the data lake** — 18 runnable PySpark notebooks under
  `Content/SparkNotebooks/`, covering foundation and scheduled-job patterns,
  visual analytics (peer-group clustering, impossible travel, volume
  forecasting, lateral-movement graphs, command-line entropy), and
  hypothesis-driven threat hunting (full-history IOC retro-hunt, stack counting,
  first-seen hunts, LOLBin abuse, entity timelines, ATT&CK coverage). Every code
  cell carries a plain-English description, and the statistical techniques are
  explained rather than just named. `apply_config.py` keeps your workspace name
  in a git-ignored `.env` and out of commits.
- **Sentinel MCP prompt books** — 18 prompt books under `Content/PromptBooks/`
  for the Microsoft Sentinel MCP server in VS Code with GitHub Copilot, grouped
  by tool collection (data exploration, triage, agent creation) plus a set that
  ties MCP findings back into this repository: turn a lake finding into a
  committed analytics rule, validate a committed rule against real data, and
  analyse detection gaps across the rule and hunting-query library. Ships with
  drop-in MCP server configuration and documents the non-obvious tool
  constraints (seven-day entity-analyser windows, SHA-1-only Defender file
  endpoints, graph scoping).
- **Data-lake notebook cost model documented.** `Docs/Content/Spark-Notebooks.md`
  now explains the Advanced data insights meter: compute hours are vCores
  multiplied by *session-active* time, so an idle session with a warm kernel
  bills exactly like a running one. Includes worked examples and the related
  lake meters a notebook can trigger.
- **Fixes.** Drift auto-sync no longer aborts when a drift report contains no
  rule sub-headings, on both CI systems, and the related PR-description summary
  table no longer truncates. A redundant no-op filter was removed from the two
  unentitled-user Copilot analytics rules.
- **Housekeeping.** The root README now points at the `Docs/` tree and ships a
  Contributing guide; Toolkit docs were reconciled with YAML-first authoring;
  and the superseded `.archive/` directory (a monolithic deploy script and a
  root-level Azure DevOps pipeline, both long replaced by `Deploy/` and
  `Pipelines/`) has been removed.

## 26.07.2

- **Documentation overhaul.** Every doc audited against the code, pipelines, and
  scripts and corrected for accuracy: the `Setup-ServicePrincipal` parameters,
  the Smart Deployment default, stale API versions and PowerShell line-number
  citations, and the pipeline docs.
- **Toolkit documentation.** New `Docs/Toolkit/` pages for the companion Sentinel
  as Code Toolkit VS Code extension: commands, templates, schemas and validation,
  configuration, ARM-to-YAML conversion, Defender workflows, and the Graph API migration notes preserved from the Toolkit repository. The Toolkit
  schemas and templates are now the authoring source of truth for the
  content-type docs, which were reconciled against them.
- **Per-pipeline documentation.** A dedicated page for every pipeline under
  `Docs/Pipelines/`, with the GitHub and Azure DevOps mechanics side by side.
- **Docs restructure.** `Docs/` now mirrors the repository layout, one docs folder
  per code folder, with a consistent naming convention.
- **Build and Test guide.** A new `Docs/Guides/` walkthrough for building and
  validating the repository without a local PowerShell install.
- **Fixes.** ARM-template-wrapped workbooks now deploy correctly (the inner
  workbook is extracted rather than the ARM envelope); the DCR-watchlist runbook
  is registered with the correct `DCRName` search key; and a `-ReportOnly` drift
  run no longer opens a pull request on either CI system.

- **PR template validation gate** — an enriched pull-request template plus a
  GitHub Actions check that fails any PR whose description is not filled in
  (Summary, why the change is needed, what it does, and testing, with a ticked
  change type), so reviewers get the context up front.

## 26.07

- **Word report generation** — a pandoc-based converter renders the Sentinel
  Documenter's Markdown pack into a formatted Word (.docx) report with a real,
  page-numbered table of contents, colour-coded severities and styled tables.
  Lives under `Tools/Documenter/Report/`, with a manual pipeline
  (`Sentinel-Word-Report.yml`) that publishes the .docx artefact.
- **Relicensed from MIT to the Apache License 2.0** — still open source, now
  with an explicit patent grant and a `NOTICE` file. Applies from this release
  forward; earlier tagged releases remain under MIT.
- Added a GitHub Sponsors button (`.github/FUNDING.yml`) and documented the
  external tool dependencies in
  `Docs/Deploy/PowerShell-Module-Requirements.md`.

## 26.06.1

- **Repository restructure** into a by-concern layout — `Content/`, `Infra/`,
  `Deploy/`, `Tools/`. No Sentinel content logic changed.
- **Adopted monthly CalVer versioning** (`YY.0M`); the "Wave N" naming is retired.
- Added a layout migration guide and a one-shot fork-rebase helper.
- Fixed an include-preview expression-quoting error in the Documenter workflow
  (`.github/workflows/sentinel-document.yml`) that had shipped with Wave 4 and
  caused every scheduled run and manual dispatch to fail to compile (erroring in
  0s before any step ran); the daily Documenter now runs as intended (#26).
- Forks and anyone referencing repo paths should review the
  [26.06 Layout Restructure guide](Layout-Restructure-26.06.md).

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
