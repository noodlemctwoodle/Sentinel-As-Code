# Changelog

Customer-facing changes to Sentinel-As-Code, newest first. Releases use CalVer
(`YY.0M`) — see [Versioning](Versioning.md). "Wave N" was the previous release
label (now retired); the wave → CalVer mapping is in [Versioning](Versioning.md).

## Unreleased

- **The dashboard web part lands on a new site's home page** - the first
  real publish to a new site failed with "You cannot host text controls
  inside a one column full width section". `Add-PnPPageWebPart -Component
  <id>` matches the id string exactly, SharePoint returned it in another
  form, and the miss became an empty web part that PnP refuses in a
  full-width section. `Publish-SacDashboardPage` now finds the component
  in `Get-PnPAvailablePageComponents` with the id normalised and passes
  the object, reuses a full-width section an earlier failed run left on
  the page, and when the web part never appears says so instead of
  retrying an unrelated error for five minutes.
- **The dashboard web part is called isoc-blueprint** - the SPFx project
  moves from `Tools/Documenter/SharePoint/webpart/sentinel-navigator/` to
  `webpart/isoc-blueprint/` and builds `isoc-blueprint.sppkg`
  (`isoc-blueprint-client-side-solution`, web part `IsocBlueprintWebPart`),
  version 1.2.0. The solution and web part ids are unchanged. SharePoint
  refuses the same solution id under a second file name (`Add-PnPApp`
  fails with "appMetadata"), so on a site that still has the old package
  the publisher removes it and then adds the new one; the dashboard
  page keeps working because the web part's component id is the same. The Documenter pipeline, the GitHub SharePoint
  workflow, the site scripts' help and the docs use the new path.
- **The SharePoint stage no longer renders Mermaid** - the dashboard draws
  its own charts, so the `SharePoint` stage of
  `Pipelines/Sentinel-Documenter.yml` drops its mermaid-cli install and
  pre-render step (and the `mermaidCliVersion` variable). The section
  pages reuse the PNGs when the Document stage already made them
  (**Charts** ticked); otherwise `ConvertTo-SharePointPageSegments` leaves
  each Mermaid block out with no placeholder and no warning, and
  `Build-SentinelDocsSite.ps1` logs how many it left out. The GitHub
  SharePoint workflow still pre-renders.
- **Tidier Documenter run panel** - the queue-time options of
  `Pipelines/Sentinel-Documenter.yml` now read as groups with one-line
  labels: the three exports first and side by side (`Export: SharePoint
  site`, `Export: Markdown`, `Export: Word report`, any combination), then
  the `SharePoint:` options, `Charts:`, `Collector:` and `Maturity:`. The
  Markdown export is the review pull request; the Markdown itself is
  rendered on every run because the other exports are built from it. The
  playbook resource group field is no longer marked Required, which had
  disabled Next: its default is now a single space, which the collector
  step trims, and left blank it falls back to the Sentinel RG
  (`sentinelResourceGroup`), shown on the run log's `Playbook RG` line.
- **One Documenter pipeline on Azure DevOps, with a tick box per output** -
  `Pipelines/Sentinel-Documenter.yml` now carries the three documentation
  outputs as queue-time options that can be combined freely: the Markdown
  pack as a review-only pull request (`openPullRequest`), the Word report
  (`publishWordReport`, a new `WordReport` stage) and the iSOC Blueprint
  SharePoint site (`publishSharePointSite`, a new `SharePoint` stage with
  `sharePointWhatIf` and `deployAppPackage`). The two publish stages run
  after `Document`, read the artefact of the same run and sign in with
  their own identities, so a failed publish can be rerun without
  collecting again. `Pipelines/Sentinel-SharePoint-Publish.yml` and
  `Pipelines/Sentinel-Word-Report.yml` are removed; the GitHub SharePoint
  workflow is unchanged.
- **One-shot bootstrap for the SharePoint publisher identity** -
  `Deploy/setup/Setup-SharePointPublisher.ps1` finds or creates the
  publisher app registration, declares and consents the SharePoint Online
  `Sites.Selected` application permission, grants Reader on one resource
  group, creates the `sc-sentinel-sharepoint` service connection with
  workload identity federation through the Azure DevOps REST API, adds the
  federated credential, and optionally authorises the Documenter pipeline
  and sets `sharePointSiteUrl` in the variable group. Idempotent, with
  `-WhatIf`.
- **The Markdown pack carries everything the dashboard shows** - the
  estate flow on the overview pages gains a Source families table (tables,
  GB, tables read by a detection, first-party alerts beside their family)
  and a Defender XDR custom-detection count; the incidents page gains
  alert volume by severity and alerts by detection source; the hunting
  page gains the bookmarks (or the service-reported count when the list
  was too large to fetch). Tables are no longer cut to a top N: incidents
  by rule, rule effectiveness, detection opportunities and the maturity
  roadmap list every row, and the collector keeps up to 500 alerting rules
  and 500 incident-producing rule titles instead of 50 and 25. The product
  to family mapping the dashboard uses now lives in the shared
  `Get-ProductFamily` helper, so both outputs agree.
- **Sentinel health check folded into the Documenter and the iSOC Blueprint
  site** - the content of the Sentinel health-check script written by
  Lasitha R, who gave it to the project, now lands on the Documenter's own
  layers and is refreshed by the daily pipelines. Thirteen new gap rules
  (SENT-036, 037, 038, 041 and 050 to 058: noisy rules, missing entity
  mappings, alert-only rules, legacy incident-creation rules, rules on the
  retired threat-intelligence table, high-volume tables no rule reads with
  the templates that would cover them, silent tables that enabled rules
  depend on, playbook failures, deprecated solutions, a single TI feed,
  Azure Firewall logged twice, incidents closed unclassified, no hunting
  activity), 58 in all. A maturity assessment, the Sentinel-As-Code
  maturity assessment, scores eleven capability areas 0 to 5 from sixty
  criteria with a roadmap, quick wins and a NIST CSF 2.0 rollup, written to
  `maturity.json` and measured against a target level that both pipelines
  take as a parameter (default 3). The Markdown pack gains an estate flow
  on the overview, `28-detection-opportunities.md` and
  `91-maturity-assessment.md`, and ten extended sections (incident
  outcomes, rule effectiveness, STIX objects and feeds, hunts, linked
  services, playbook run health, deprecated solutions, daily ingestion,
  tables by detection coverage). The SharePoint dashboard's Overview is an
  executive summary with pipeline rings, the estate flow, a maturity card
  and quick wins; a Maturity tab and five Insights panels are new; every
  publish records the score so the tab draws a trend. The criterion set,
  the estate-flow view and the detection-headroom idea are Lasitha R's;
  the methodology, scoring and taxonomy are the project's own and carry no
  third-party model's name. Also fixed on the way: the live-snapshot MITRE
  headline counted hunting-query tags instead of the 14-tactic catalogue,
  and `incidents-summary` returned presence flags where counts were meant.
- **Every capture reaches a page, and the lake reaches the dashboard** -
  three captures that nothing rendered now do: failed ingestion and schema
  operations on the health page, the legacy management solutions on the
  Content Hub page, and the Sentinel onboarding state (customer-managed key)
  on the workspace page. The dashboard gains a "Data lake" glance tile and
  an Insights panel with the enrolment status, tier distribution, top
  extended-retention tables and lake cost split, counted by the same helper
  as the data lake page, and the billing-flow Sankey's plan column now names
  the lake tier each table lands in instead of one "Analytics plan" box.
- **One id scheme for findings and criteria** - gap findings are now
  `SAC-<AREA>-NN` like the maturity criteria, with the area taken from the
  eleven assessment areas; a rule that decides a criterion on its own
  carries that criterion's id, so the finding and the gap it causes share
  a name. Every rule keeps its retired id as `legacyId` (catalogue 3.0.0),
  page anchors, finding links and the SharePoint findings list follow the
  new ids, and an existing list item under the old id is moved rather than
  resolved and re-added. The mapping:

  | Retired | New |
  | --- | --- |
  | SENT-001 | SAC-LOG-03 |
  | SENT-002 | SAC-LOG-07 |
  | SENT-003 | SAC-LOG-08 |
  | SENT-004 | SAC-COV-07 |
  | SENT-005 | SAC-COV-05 |
  | SENT-006 | SAC-MON-04 |
  | SENT-007 | SAC-DET-05 |
  | SENT-008 | SAC-DET-09 |
  | SENT-009 | SAC-GOV-06 |
  | SENT-010 | SAC-PLT-08 |
  | SENT-011 | SAC-AUT-05 |
  | SENT-012 | SAC-LOG-09 |
  | SENT-013 | SAC-DET-07 |
  | SENT-014 | SAC-PLT-11 |
  | SENT-015 | SAC-LOG-10 |
  | SENT-016 | SAC-LOG-02 |
  | SENT-017 | SAC-LOG-11 |
  | SENT-018 | SAC-LOG-12 |
  | SENT-019 | SAC-LOG-13 |
  | SENT-020 | SAC-PLT-05 |
  | SENT-021 | SAC-PLT-06 |
  | SENT-022 | SAC-PLT-09 |
  | SENT-023 | SAC-LOG-14 |
  | SENT-024 | SAC-GOV-07 |
  | SENT-025 | SAC-GOV-08 |
  | SENT-026 | SAC-INV-01 |
  | SENT-027 | SAC-INV-04 |
  | SENT-028 | SAC-PLT-10 |
  | SENT-029 | SAC-INC-06 |
  | SENT-030 | SAC-INC-05 |
  | SENT-031 | SAC-DET-04 |
  | SENT-032 | SAC-DET-10 |
  | SENT-033 | SAC-DET-11 |
  | SENT-034 | SAC-AUT-01 |
  | SENT-035 | SAC-DET-12 |
  | SENT-036 | SAC-DET-06 |
  | SENT-037 | SAC-DET-03 |
  | SENT-038 | SAC-MON-01 |
  | SENT-039 | SAC-GOV-05 |
  | SENT-040 | SAC-GOV-04 |
  | SENT-041 | SAC-DET-08 |
  | SENT-042 | SAC-GOV-03 |
  | SENT-043 | SAC-LOG-15 |
  | SENT-044 | SAC-LOG-16 |
  | SENT-045 | SAC-LOG-17 |
  | SENT-046 | SAC-LOG-18 |
  | SENT-047 | SAC-PLT-02 |
  | SENT-048 | SAC-PLT-03 |
  | SENT-049 | SAC-TI-01 |
  | SENT-050 | SAC-TI-02 |
  | SENT-051 | SAC-MON-05 |
  | SENT-052 | SAC-MON-06 |
  | SENT-053 | SAC-AUT-02 |
  | SENT-054 | SAC-DET-13 |
  | SENT-055 | SAC-TI-05 |
  | SENT-056 | SAC-LOG-06 |
  | SENT-057 | SAC-INC-02 |
  | SENT-058 | SAC-HNT-01 |
  | SENT-059 | SAC-DET-14 |

- **Defender XDR custom detections count as coverage** - a new
  `defender-custom-detections` capture reads the tenant's custom detection
  rules through Microsoft Graph (`CustomDetection.Read.All`) and resolves
  the tables each one queries; an enabled custom detection now counts as
  detection coverage in the estate flow, on the table-coverage view, on
  the detection-opportunities page and in rule SAC-MON-05, and the
  analytics page lists the rules with their tables, state, severity and
  period. When the permission is missing the pages and the flow say the
  capture did not run rather than showing zero.
- **Coverage means Sentinel rules, and says so** - the estate flow, its
  detail panel and page 28 state that "read by a rule" means an enabled
  Sentinel analytics rule; first-party detections (Defender XDR, Entra ID
  Protection, Defender for Identity, Defender for Cloud) do not read
  workspace tables and are now listed per family in the detail panel from
  the alert volumes by product. The disabled-rules finding names a bulk
  change day when most disabled rules share a last-modified date and lists
  the disabled rules that still produced alerts in the last 30 days.
- **Interactive estate flow** - hover a source family to spotlight its
  strands; click a family or the "Not monitored" pool for the tables behind
  it (GB, rules reading each, monitored or not); click a ring to open its
  page and the Closed or Open box to open the incidents page. Unmonitored
  strands keep their family colour and run dashed into the pool, so the
  legend reads by family at both ends. Report tables right-align the header
  of every numeric column with its figures.
- **Findings and criteria as cards** - the Findings tab, the Overview
  findings and the maturity criteria share one card layout: a card per
  item with the pill, id and title on one line and a chevron at its right,
  chips beneath (category, area, the retired id; area, kind and effort for
  criteria), then Evidence beside Remediation or Guidance, each clamped to
  three lines, with Microsoft Learn under the remediation and "Open
  finding" under a criterion's evidence. Every card is the same height
  when collapsed, and the chevron (or a click on the clamped text) opens
  both blocks. Findings filter by severity, category and
  search; criteria by status, area and search, and a criterion that shares
  its id with a fired finding links to it.
- **Dashboard reading comfort** - long evidence, remediation and guidance
  cells clamp to three lines with an Expand control (semicolon lists open
  as bullets), so table rows stay uniform and nothing is cut; the Overview
  alerting-rules table shows eight with "Show all"; finding ids never wrap;
  the per-section view is the "Report" tab and sits before Maturity; Report
  section titles and subsection headings are more prominent; doc-table
  cells longer than 40 characters wrap instead of overflowing; the estate
  flow and Sankey no longer shorten any label. Documenter version 0.2.0.
  The estate flow keeps its layout but reads cleanly: ring captions wrap
  onto two lines with a panel-coloured halo, the "Not monitored" pool is
  sized to its text and sits below the rings, and the unmonitored strands
  drop early and run in from the left instead of crossing the ingestion
  ring and its captions.
- **Six new captures close the last health-check gaps** - `rule-health`
  (analytics rules whose runs failed, with the recorded reason; new rule
  SENT-059 and a "Rule run failures" table on the analytics page),
  `incident-title-stats` (frequent incident titles with closure speed and
  verdicts, rendered as "Automation opportunities" on the automation page
  with a suggested response per title family), `threat-intel-by-type`
  (indicators by observable type on the threat-intelligence page),
  `syslog-contributors` and `securityevent-top-hosts` (log composition by
  host on the data-source hygiene page) and `table-query-usage` (audited
  queries per lake-retained table, the last column of the lake usage
  evidence). `best-practices.json` is 2.3.0 with 59 rules. A new
  [Health-Check-Coverage.md](../Tools/Documenter/Health-Check-Coverage.md)
  maps every section of the contributed health check to its Documenter
  page.
- **Sections cross-referenced with the health check** - six subsections
  the health check had and the pages did not, all from captures already
  taken: Defender XDR unification and the Defender for Cloud connectors on
  the connectors page; Entra ID table presence on the coverage page; a
  rule-complexity heuristic on the analytics page; a resilience summary
  (replication, Private Link, public access, customer-managed key, managed
  identity, daily cap, locks) on the workspace page; the silent tables in
  detail, split by detection impact, and a classic (Data Collector API)
  custom-table inventory with last ingestion and an action per table on
  the table-plans page; lake usage evidence and the tables without extended
  lake retention on the data lake page.
- **Interactive billing flow and nothing hidden behind "N more"** - the
  Data flow Sankey is rebuilt in the browser from every ingesting table:
  click a source family (or its chip) to see every table in that family,
  click "Other" or "Every table" to see them all. Every dashboard list
  (findings, tables by volume, alerting rules, health operations, rule
  effectiveness, detection opportunities and their templates, extended-
  retention tables, failing playbooks, the roadmap) shows its first entries
  with a "Show all N" control, and the model carries the full lists.
- **Dashboard layout** - Insights cards sit in bands of similar height
  (donuts, bar lists, tables) separated by the full-width panels, so a long
  table never shares a row with a short donut; a short last row widens to
  fill its band. Sankey columns size to their longest label, stacking the
  value under the label when the two cannot share a line, so names neither
  overlap nor truncate. The Sankey lives on the Data flow tab only; the
  Overview no longer carries a second copy. The posture-card percentage
  rings are masked donuts, so the value sits in a real hole instead of
  behind a translucent disc, and the flow box, grid lines and table-node
  labels follow the dark theme.
- **One analytics page** - the four analytics deep-dives (by alert volume,
  Microsoft-managed rules, recent modifications, by Content Hub solution)
  are now subsections of `20-analytics-rules.md` rather than separate
  files, so the Detection family reads as one rules page. A site published
  from an earlier run retires the four old pages on its next publish.

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
