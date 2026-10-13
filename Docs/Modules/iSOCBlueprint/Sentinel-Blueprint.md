# iSOC Blueprint

A read-only documentation and assessment tool for a live Microsoft Sentinel
workspace. It records every artefact, every workspace setting and every DCR/DCE,
estimates the monthly cost, scores a findings list against the documented
Microsoft Learn best practices and rates the workspace on a maturity model. The
results come out as JSON (the section model), Markdown, a Word report or a
SharePoint site. It runs from the pipelines (daily on GitHub, on demand on Azure
DevOps) or locally from the `iSOCBlueprint` module.

> Operating guide (this page): for users running the tool and consuming its output.
> The tool is the [`iSOCBlueprint`](../../../Modules/iSOCBlueprint/README.md)
> PowerShell module; its README lists the commands and what each needs.
> For renderer internals (chart system, helpers, Mermaid-safety rules, how to add
> charts), see [Blueprint-Renderer-Design.md](Blueprint-Renderer-Design.md).

> [!IMPORTANT]
> **Repository must be private.**
>
> The Blueprint generates a folder of detailed tenant configuration:
> workspace IDs, table names, rule details, RBAC principals, cost figures,
> network ACLs. This information **MUST NOT** land in a public repository,
> and that includes run artefacts, which are world-downloadable on public
> GitHub repos.
>
> The GitHub Actions workflow therefore never collects or publishes
> `SecurityDocs/` on a public repo, regardless of the `open-pull-request`
> toggle: scheduled runs are skipped on a public repo, and a manual run on
> a public repo **fails fast** with an explicit error before any collection.
> The ADO pipeline relies on ADO repos being private by default within a
> project.
>
> If your source-of-truth lives in a public GitHub repo and you need the
> Blueprint, see [Topology options](#topology-options) below.

---

## Delivery channels

Each pipeline run delivers the report through **two** channels, both gated
by the privacy guard:

| Channel | Always on | Where to find it |
|---|---|---|
| Pipeline / workflow artefact | ✓ | ADO: Build summary → Related → Published artefacts → `sentinel-docs`. GitHub: Actions run page → Artifacts → `sentinel-docs-<workspace>-<runId>`. |
| Pull request from a rolling per-workspace branch | Default ON, can be disabled per-run | ADO: Repos → Pull requests. GitHub: Pull requests. |

The PR is intentionally **review-only**. Merging it would commit tenant
configuration to the target branch permanently. The PR description carries
a "Do not merge" banner and the PR is created without auto-complete.

Two downstream outputs build on the artefact:

- **SharePoint site.** The SharePoint Publish pipeline runs after every
  successful Blueprint run and keeps a generated iSOC Blueprint site in
  step: a page per section, navigation, a findings list with history and
  the interactive dashboard. See [iSOC Blueprint SharePoint Site](Sentinel-SharePoint-Site.md).
- **Word report.** An ADO-only pipeline renders the Markdown into a
  page-numbered `.docx`. See [iSOC Blueprint Word Report](Sentinel-Word-Report.md).

---

## Topology options

The Blueprint is hard-wired to refuse public-repo commits. Pick the
topology that matches your setup:

### A. Single private repo (simplest)
- All code, deployment config, and Blueprint pipelines live in one
  private repo (private GitHub *or* an ADO project).
- Either pipeline (`.github/workflows/sentinel-blueprint.yml` or
  `Pipelines/Sentinel-Blueprint.yml`) opens its PR directly in that repo.
- Recommended for most users.

### B. Public GitHub source + private ADO mirror (this repository)
- Source-of-truth is a public GitHub repo (community contributions,
  issues, discussion).
- Pipeline testing is mirrored to a private Azure DevOps project.
- The **ADO pipeline** opens PRs in the private ADO mirror; its push
  reaches `origin` (= ADO repo on the agent) only and never touches the
  public GitHub copy.
- The **GitHub Actions workflow does not run productively on the public
  repo at all**: scheduled runs are skipped there, and a manual run fails
  fast before collecting anything, so no `SecurityDocs/` artefact or PR is
  ever produced from the public copy. Run the Blueprint from the private
  ADO mirror instead.

### C. Don't want a PR at all
- On a **private** repo, set `open-pull-request: false` (GH) or untick the
  equivalent parameter (ADO) and the pipeline still publishes the artefact,
  just without opening a PR. On a public repo nothing is produced either
  way (see option B).

---

## What it produces

A folder per workspace under `SecurityDocs/<workspace>/`. The collector
(`Export-iSOCBlueprintInventory`) writes the `_raw/` JSON snapshot; the renderer
(`ConvertTo-iSOCBlueprint`) turns that snapshot into **35 numbered
sections**, written twice: as the [section model](Section-Model.md) in `sections/`
(typed JSON, what the SharePoint site is built from and what to build on) and as
Markdown files with an `index.md` contents page (`-Format Json` skips the
Markdown):

```
SecurityDocs/
└── law-sentinel-prod/
    ├── _raw/                          machine-readable JSON snapshot
    │   ├── workspace.json
    │   ├── workspace-tables.json
    │   ├── tables-with-data.json
    │   ├── alert-rules.json
    │   ├── data-connectors-classic.json
    │   ├── rule-table-references.json  which tables each rule reads (and template-table-references.json)
    │   ├── rule-effectiveness.json     incidents, closures and classifications per rule (30d)
    │   ├── playbook-runs.json          runs and failures per playbook (7d)
    │   ├── ... (≈87 files)
    │   ├── retail-prices-uksouth-2026-05-06.json
    │   ├── cost-estimate.json
    │   ├── gap-analysis.json          findings that fired
    │   ├── gap-checks.json            one outcome per rule: Fired, Passed, Errored or Undefined
    │   └── maturity.json              maturity assessment: area scores, roadmap, quick wins, CSF rollup
    ├── sections/                      the section model (see Section-Model.md)
    │   ├── index.json                 the sections in reading order, with the run's facts
    │   ├── 00-overview.json           one file per section below: blocks, text runs, charts as data
    │   └── ...
    ├── index.md                       full TOC, mapped to the Sentinel Config TOC numbering
    ├── 00-overview.md                 headline counts, top findings, cost summary
    ├── 01-live-snapshot.md            workspace-at-a-glance, regenerated every run
    ├── 02-deprecated-legacy-features.md  retirement deadlines, legacy features still in use
    ├── 10-data-connectors.md          classic + CCF + synthesised effective view with the connector behind each table, connected connectors against the connector catalogue, Defender XDR unification
    ├── 11-sentinel-health.md          SentinelHealth events and failures, connector and DCR health issues (last 7 days)
    ├── 12-soc-optimization.md         SOC Optimization recommendations
    ├── 13-data-source-hygiene.md      CEF/Syslog hygiene with vendors, SecurityEvent duplicates, noisy event IDs, Syslog and SecurityEvent contributors
    ├── 14-coverage-breakdowns.md      AzureActivity / AzureDiagnostics per category / Azure Firewall categories / XDR coverage by source, Entra ID table presence
    ├── 15-incidents.md                incident MTTA/MTTR, outcomes, 7-day incident metrics, incidents by rule and by provider
    ├── 16-alerts.md                   alert volume by severity, detection source and provider
    ├── 20-analytics-rules.md          all rules by kind, Microsoft-managed, recent modifications, by Content Hub solution, Defender XDR custom detections
    ├── 21-rule-performance.md         alert volume per rule, rule effectiveness, noisy rules
    ├── 22-rule-health-quality.md      rule run failures, rules without entity mappings, alert-only rules, stale rules, template drift, complexity
    ├── 25-mitre-coverage.md           ATT&CK tactics, techniques and sub-techniques covered, every rule's mapping
    ├── 26-ueba.md                     UEBA configuration, data sources over 7/12/14 days, entity analytics
    ├── 27-threat-intelligence.md      TI table migration, indicator health, indicators by source and type, connectors, TAXII clients
    ├── 28-detection-opportunities.md  tables with data but no detection with every candidate template, tables no template covers and the solutions that ship them, templates ready to enable
    ├── 30-hunting-queries.md          hunting queries, hunts and bookmarks
    ├── 35-parsers-functions.md        parsers and functions, other saved searches
    ├── 36-data-export.md              continuous data exports, linked storage accounts, linked ADX clusters
    ├── 37-search-restore.md           search jobs / restore logs
    ├── 38-summary-rules.md            summary rules
    ├── 40-workbooks.md                saved workbooks + templates available
    ├── 50-watchlists.md               watchlist *definitions* (item contents never captured)
    ├── 60-automation-rules-playbooks.md  automation rules + playbooks + MI grants, automation opportunities
    ├── 70-content-hub.md              installed solutions + repos
    ├── 80-workspace.md                SKU, retention, networking, resilience summary, CMK, feature flags
    ├── 81-table-plans-retention.md    Analytics / Basic / Auxiliary / DataLake matrix, silent tables by detection impact, classic (Data Collector API) tables
    ├── 82-dedicated-cluster.md        cluster, CMK, availability zones
    ├── 83-data-collection.md          DCRs, DCEs, transforms
    ├── 84-cost-estimate.md            estimated monthly cost + commitment-tier what-if, Sentinel pricing settings
    ├── 85-rbac.md                     role assignments, by role, Sentinel and monitoring roles, high-privilege assignments
    ├── 86-subscription-context.md     signed-in identity, subscription, tenant, RPs, locks, policy
    ├── 87-azure-monitor-agents.md     AMA agents heartbeating into the workspace, agent heartbeat mix by OS and version
    ├── 88-sentinel-data-lake.md       Data Lake enrollment, Lake-tier tables, usage evidence, migration candidates
    ├── 89-retention.md                retention checks, per-table overrides, retention that rolls into the lake, ingestion validation
    ├── 90-gap-analysis.md             every finding with remediation + Learn link
    ├── 91-maturity-assessment.md     maturity scale, maturity by area, open gaps and their impact, roadmap, quick wins, NIST CSF rollup
    ├── 96-references-microsoft.md     curated Microsoft Learn entry points (user-facing)
    └── 99-references.md               blueprint's own API versions + modules (copied from Blueprint-References.md)
```

Sections are numbered to line up with the formal Sentinel Configuration TOC where
one applies (`index.md` prints the mapping in its own column). `82-dedicated-cluster.md`
and `88-sentinel-data-lake.md` render placeholder content when the feature is absent
rather than being skipped, so the section set is stable run to run. Customer-narrative
sections (architecture diagrams, SOC processes, the licensing inventory) are
intentionally not auto-generated.

The split between `_raw/` (JSON) and the rendered Markdown means the renderer can be
re-run locally on a downloaded artefact without touching Azure, handy for iterating
on report layout or evaluating a new gap rule against historical state.

---

## How to read the report

Start at [`index.md`](#) for the table of contents, then [`00-overview.md`](#) for the
headline. The five most important pages day-to-day are:

| When you want to know… | Read |
|---|---|
| Are we losing money on data we don't query? | `81-table-plans-retention.md`, `84-cost-estimate.md`, `89-retention.md` |
| Did a connector break overnight? | `10-data-connectors.md`, plus the **Silent tables** appendix in `81-…` |
| What MITRE coverage gaps do we have? | `25-mitre-coverage.md` |
| Where can we apply Microsoft's best practice? | `90-gap-analysis.md` |
| Who has access to the workspace? | `85-rbac.md` |

Beyond those headline pages the report groups into families:

- **Operational health**: `11-sentinel-health.md` (SentinelHealth events and
  failed ingestion or schema operations, last 7 days), `12-soc-optimization.md` (SOC Optimization recommendations),
  `13-data-source-hygiene.md` (CEF/Syslog hygiene, agent dual-collection, noisy
  events), `15-incidents.md` (MTTA/MTTR, outcomes, incidents by rule and
  provider) and `16-alerts.md` (alert volume by severity, product and
  provider).
- **Analytics**: `20-analytics-rules.md` is the rule inventory (every rule by
  kind, the Microsoft incident-creation and Microsoft-managed rules, recent
  modifications, the Content Hub solution breakdown, the Defender XDR custom
  detections); `21-rule-performance.md` holds alert volume per rule with the
  incident outcomes and the noisy rules; `22-rule-health-quality.md` holds
  run failures, the entity-mapping and incident-creation anti-patterns,
  stale rules, template drift and query complexity; `26-ueba.md` and
  `27-threat-intelligence.md` cover UEBA configuration and indicator counts.
- **Data platform**: `36-data-export.md`, `37-search-restore.md`,
  `38-summary-rules.md`, `87-azure-monitor-agents.md`,
  `88-sentinel-data-lake.md` and `89-retention.md` document the ingestion,
  retention and Data Lake surface.
- **Retirements**: `02-deprecated-legacy-features.md` sets the platform
  deadlines against the legacy features this workspace still uses.
- **Assessment**: `90-gap-analysis.md` (the findings) and
  `91-maturity-assessment.md` are one assessment. Each finding says which
  maturity criterion it decides and what closing it lifts the overall score
  by, or that it is a hygiene or cost check the score does not count; the
  SharePoint site groups both pages and the findings list under one
  Assessment heading, and the dashboard shows them behind one Assessment
  tab.
- **Coverage**: `14-coverage-breakdowns.md` attributes AzureActivity /
  AzureDiagnostics / XDR ingestion back to its source.

---

## How to run it

### In CI

Two pipelines, same scripts, same output, different host:

#### Azure DevOps: `Pipelines/Sentinel-Blueprint.yml`
Manual trigger (`trigger: none`). Use this when pipeline testing lives in a
private ADO project. Reuses the `sentinel-deployment` variable group and the
`sc-sentinel-as-code` service connection that the deploy and drift-detect
pipelines already depend on. Pushes to `origin` on the ADO agent, which is
the **ADO repo only**, never GitHub.

> Pipelines → the pipeline built from `Pipelines/Sentinel-Blueprint.yml` → Run pipeline. *Export: SharePoint
> site* and *Collector: include preview APIs* are ticked by default; untick
> the SharePoint export for a workspace with no site. To skip the PR step and get only the
> artefact, untick *Export: Markdown (docs pull request in this repo)*. The
> section model (`sections/*.json`) is rendered on every run, and the
> SharePoint site is built from it; the Markdown pack is rendered when the
> pull request or the Word report needs it, or when no export is ticked.

The run-pipeline panel exposes three further parameters:

- *Charts: Mermaid to PNG* (`prerenderChartsToPng`, **default ON**):
  ADO Repos and wiki render `mermaid` fences as plain code and block inline SVG,
  so the pipeline installs `@mermaid-js/mermaid-cli` and converts each fenced chart
  to a PNG via `ConvertTo-iSOCBlueprintChartImage`. This step is ADO-only; the GitHub
  workflow ships the raw fences because GitHub renders Mermaid natively. It is
  skipped on a run that writes no Markdown (SharePoint only). Untick it to skip
  the Node/mmdc install on a fast run.
- *Collector: playbook resource group* (`playbookResourceGroup`, default blank): set this when
  Logic App playbooks live in a dedicated RG separate from the Sentinel RG (the
  Sentinel-As-Code convention). It maps to the collector's `-PlaybookResourceGroup`
  parameter; leave it blank and the pipeline uses the Sentinel RG
  (`sentinelResourceGroup` from the variable group).
- *Target maturity level* (`targetMaturityLevel`, default `3`): the level the
  maturity assessment measures the workspace against. Maps to the collector's
  `-TargetMaturityLevel`; see
  [Sentinel-Maturity-Model.md](Sentinel-Maturity-Model.md).

#### GitHub Actions: `.github/workflows/sentinel-blueprint.yml`
Daily at 06:00 UTC plus `workflow_dispatch`. Uses OIDC to a read-only
service principal. Privacy guard: the **Verify repository is private** step
runs **unconditionally** at the top of the job, before any collection, and
**fails the whole run** on a public repo regardless of the `open-pull-request`
input, because `SecurityDocs/` (and the run artefact that carries it) would
otherwise leak tenant config to the world. Scheduled runs are additionally
skipped on a public repo so the upstream doesn't accrue a permanent daily red
failure; a manual `workflow_dispatch` still starts and then hits the guard,
so an operator who tries it is told exactly why.

> Actions → **iSOC Blueprint** → Run workflow → optionally tick
> `include-preview`. There is no artefact-only path on a public repo: the guard
> fails the run before collection whether `open-pull-request` is on or off, so
> move the workflow to a private repo (or use the ADO pipeline against a private
> mirror). On a private repo, untick `open-pull-request` to publish the artefact
> without opening a PR.

#### Where to find the rendered docs

| Channel | ADO | GitHub Actions |
|---|---|---|
| Artefact (zip) | Build summary → Related → Published artefacts → `sentinel-docs` | Workflow run page → Artifacts → `sentinel-docs-<ws>-<runId>` |
| Pull request | Repos → Pull requests → "docs(sentinel): snapshot …" | Pull requests tab → "docs(sentinel): snapshot …" |

### Locally

```powershell
# 1. Connect with an account that has the read-only roles described below,
#    and load the module.
Connect-AzAccount
Import-Module ./Modules/iSOCBlueprint

# 2. Collect and render in one line. Writes ./SecurityDocs/<workspace>/:
#    the _raw/ snapshot, sections/*.json and the Markdown pages.
#    -ResourceGroup and -WorkspaceName are required; -SubscriptionId
#    defaults to the current Az context. Add -PlaybookResourceGroup when
#    playbooks live in a separate RG, and Word or SharePoint to -Format for
#    those outputs too.
New-iSOCBlueprint `
    -SubscriptionId        'sub-guid' `
    -ResourceGroup         'rg-sentinel-prod' `
    -WorkspaceName         'law-sentinel-prod' `
    -PlaybookResourceGroup 'rg-sentinel-automation' `
    -IncludePreview `
    -Format Json, Markdown

# Or step by step: collect, then render (-Format Json for the section
# model only). Re-render an existing snapshot without collecting again with
# New-iSOCBlueprint -WorkspaceName <ws> -SkipCollection.
Export-iSOCBlueprintInventory -ResourceGroup 'rg-sentinel-prod' -WorkspaceName 'law-sentinel-prod' |
    ConvertTo-iSOCBlueprint
```

Open `SecurityDocs/<workspace>/index.md` in your editor. To check what the
machine can produce first, run `Test-iSOCBlueprintPrerequisite`.

At the end of a collection the collector prints a **Capture summary** table: it
re-reads a set of files that are almost always populated on an active workspace
(`alert-rules`, `data-connectors-classic`, `workspace`, `workspace-tables`) plus a
set that should be populated *if the feature is in use* (`automation-rules`,
`watchlists`, `playbooks`, `hunting-queries`, `workbooks-saved`, `cost-estimate`),
flags any that came back empty or errored, and lists every capture step that raised
an error (each GET is wrapped so one failure does not abort the run). An unexpected
`EMPTY` almost always means an RBAC gap - the hint reminds you that **Microsoft
Sentinel Reader at workspace scope** is required for automation rules, watchlists,
hunting queries and incidents. Read this summary before filing a "the report says
zero of X" bug.

---

## Permissions for the Blueprint SP

Read-only at workspace + RG + subscription scope:

| Role | Scope | Why |
|---|---|---|
| Microsoft Sentinel Reader | workspace | Sentinel artefacts |
| Log Analytics Reader      | workspace | Workspace, tables, KQL `Usage`/`Operation` |
| Reader                    | resource group | Playbooks (Logic Apps), DCRs |
| Monitoring Reader         | subscription | Full DCR JSON, DCEs |
| Reader                    | subscription | Dedicated clusters, policy assignments, locks, RP registration |

The Azure Retail Prices API used by the cost estimator is anonymous, no auth
needed.

OIDC federated-credential subject for the `main` branch:
```
repo:<owner>/<repo>:ref:refs/heads/main
audience: api://AzureADTokenExchange
```

See [`Blueprint-References.md`](Blueprint-References.md)
for the complete list of API versions, modules, REST-only gaps and Microsoft
Learn pages the tool depends on.

---

## How the gap engine works

The findings on `90-gap-analysis.md` are produced by small `Test-*` functions
in [`Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1`](../../../Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1),
dispatched by the engine in [`Modules/iSOCBlueprint/Engine/Private/Get-SentinelGap.ps1`](../../../Modules/iSOCBlueprint/Engine/Private/Get-SentinelGap.ps1).
The rules live in [`Modules/iSOCBlueprint/Engine/Private/Resources/best-practices.json`](../../../Modules/iSOCBlueprint/Engine/Private/Resources/best-practices.json),
a single object with `$schema` / `version` / `rules` keys; `Get-SentinelGap`
reads `(ConvertFrom-Json).rules`. Each entry looks like:

```json
{
  "$schema": "best-practices.schema.json",
  "version": "2.3.0",
  "rules": [
    {
      "id": "SAC-LOG-03",
      "title": "Daily cap not configured on the Log Analytics workspace",
      "category": "Cost",
      "severity": "Warning",
      "check": "Test-DailyCapConfigured",
      "remediation": "Set workspaceCapping.dailyQuotaGb to a sensible ceiling…",
      "learn": "https://learn.microsoft.com/azure/azure-monitor/logs/daily-cap"
    }
  ]
}
```

`Get-SentinelGap` builds one `$Inventory` object from the JSON files in `_raw/`,
then for each rule dot-sources `GapChecks.ps1` and dispatches the named `check`
function. Every check function takes that single `$Inventory` parameter and
returns `$null` on pass or an Evidence/Detail object on fail; the engine wires the
rule metadata (id, title, category, severity, remediation, Learn link) around the
result.

Detection coverage (the estate flow, the table-coverage view on page 81,
page 28 and rule SAC-MON-05) counts enabled Sentinel analytics rules and
enabled Defender XDR custom detections that read a table. Custom detections
come from Microsoft Graph (`beta/security/rules/detectionRules`). The
pipeline identity needs the `CustomDetection.Read.All` application
permission; for an interactive run, sign in to the Graph PowerShell SDK
first (`Connect-MgGraph -Scopes 'CustomDetection.Read.All'`) and the capture
uses that session, because Azure PowerShell's own app cannot request that
delegated scope. Without either, the capture is recorded as not taken, the
pages say so and coverage counts Sentinel rules only. Product alerts raised
inside Defender XDR, Entra ID Protection, Defender for Identity or Defender
for Cloud never read workspace tables, so they are shown per source family
on the dashboard rather than counted as coverage.

Finding ids follow the maturity scheme, `SAC-<AREA>-NN`, where the area is
one of the eleven assessment areas (DET, PLT, COV, AUT, MON, INC, INV, TI,
HNT, LOG, GOV). A rule that decides a maturity criterion on its own carries
that criterion's id, so finding `SAC-DET-03` is the reason criterion
`SAC-DET-03` is a Gap; rules with no criterion of their own take the next
numbers in their area. Every rule written before catalogue 3.1.0 keeps
its retired `SENT-NNN` id as `legacyId` (catalogue 3.0.0); the SharePoint
findings list recognises an item filed under the legacy id and moves it
to the new id instead of resolving one finding and adding another. Rules
added from 3.1.0 never had a `SENT-NNN` id, so they carry no `legacyId`.
The dashboard and the report show only the current id; the old ids are
listed below.

### Ids before the SAC scheme

Every rule that had a `SENT-NNN` id, with the id it carries now
(59 rules).

| Old id | Id | Rule |
| --- | --- | --- |
| SENT-001 | SAC-LOG-03 | Daily cap not configured on the Log Analytics workspace |
| SENT-002 | SAC-LOG-07 | Workspace default retention below the 90-day Sentinel free benefit |
| SENT-003 | SAC-LOG-08 | High-volume table on Analytics plan with no DCR transform |
| SENT-004 | SAC-COV-07 | Recommended data connectors not deployed |
| SENT-005 | SAC-COV-05 | User & Entity Behaviour Analytics (UEBA) disabled |
| SENT-006 | SAC-MON-04 | MITRE ATT&CK tactic with zero enabled detection rules |
| SENT-007 | SAC-DET-05 | Analytics rules disabled or in error state |
| SENT-008 | SAC-DET-09 | High-severity rule templates not deployed |
| SENT-009 | SAC-GOV-06 | Owner or Contributor RBAC at workspace scope |
| SENT-010 | SAC-PLT-08 | Diagnostic settings on the Log Analytics workspace not configured |
| SENT-011 | SAC-AUT-05 | Playbook managed identity lacks the Microsoft Sentinel Responder role |
| SENT-012 | SAC-LOG-09 | DCR transform missing on noisy custom tables |
| SENT-013 | SAC-DET-07 | Content Hub solution updates available |
| SENT-014 | SAC-PLT-11 | Sentinel still on Azure portal: Defender XDR migration deadline 2027-03-31 |
| SENT-015 | SAC-LOG-10 | Workspace on PerGB2018 while sustained ingest exceeds the next commitment-tier break-even |
| SENT-016 | SAC-LOG-02 | High-volume Analytics-plan table is a Basic/Auxiliary candidate |
| SENT-017 | SAC-LOG-11 | Long-term data on Analytics interactive retention rather than archive |
| SENT-018 | SAC-LOG-12 | Total ingest > 500 GB/day but no dedicated cluster |
| SENT-019 | SAC-LOG-13 | Sentinel free benefit not detected on a workspace with eligible Defender plans |
| SENT-020 | SAC-PLT-05 | Workspace replication disabled in a paired-region production tenant |
| SENT-021 | SAC-PLT-06 | Public network access enabled for ingestion or query (no AMPLS) |
| SENT-022 | SAC-PLT-09 | Sentinel or Log Analytics resource provider not registered on the subscription |
| SENT-023 | SAC-LOG-14 | Eligible tables not yet evaluated for Sentinel Data Lake mirroring |
| SENT-024 | SAC-GOV-07 | disableLocalAuth is false on the workspace (shared-key ingestion permitted) |
| SENT-025 | SAC-GOV-08 | enableLogAccessUsingOnlyResourcePermissions misconfigured for the chosen access model |
| SENT-026 | SAC-INV-01 | Silent table: had ingestion historically but nothing in the last 7 days |
| SENT-027 | SAC-INV-04 | Orphan table: schema deployed but no data in the last 90 days |
| SENT-028 | SAC-PLT-10 | Connected data connector is not delivering data |
| SENT-029 | SAC-INC-06 | Incident MTTR above the 24-hour SOC efficiency threshold |
| SENT-030 | SAC-INC-05 | Majority of incidents closed without ever being acknowledged |
| SENT-031 | SAC-DET-04 | Enabled detection rule not modified in over 12 months |
| SENT-032 | SAC-DET-10 | Deployed analytics rule lags behind the latest template version |
| SENT-033 | SAC-DET-11 | Single analytics rule accounts for over 30 % of total alert volume |
| SENT-034 | SAC-AUT-01 | No automation rules defined: every incident hits analysts manually |
| SENT-035 | SAC-DET-12 | Enabled rule has produced zero alerts in the last 90 days |
| SENT-036 | SAC-DET-06 | Analytics rule closes mostly as false positive |
| SENT-037 | SAC-DET-03 | Enabled analytics rule has no entity mappings |
| SENT-038 | SAC-MON-01 | Enabled analytics rule does not create incidents |
| SENT-039 | SAC-GOV-05 | Service principal granted Owner or Contributor at workspace scope |
| SENT-040 | SAC-GOV-04 | No identity holds the Microsoft Sentinel Responder role |
| SENT-041 | SAC-DET-08 | Legacy Microsoft incident-creation rules still enabled |
| SENT-042 | SAC-GOV-03 | No deletion-protection lock on the Sentinel workspace |
| SENT-043 | SAC-LOG-15 | CommonSecurityLog volume warrants a custom-table split to a vendor _CL |
| SENT-044 | SAC-LOG-16 | Syslog volume warrants a facility-based DCR filter or _CL split |
| SENT-045 | SAC-LOG-17 | SecurityEvent or WindowsEvent volume warrants an XPath filter on the AMA DCR |
| SENT-046 | SAC-LOG-18 | AzureDiagnostics carrying multiple resource providers: switch to resource-specific tables |
| SENT-047 | SAC-PLT-02 | Custom log table still using the HTTP Data Collector API (CLv1): retirement 2026-09-14 |
| SENT-048 | SAC-PLT-03 | Legacy Log Analytics agent (MMA / OMS) still heartbeating: retired 2024-08-31 |
| SENT-049 | SAC-TI-01 | Threat intelligence ingestion still on the legacy ThreatIntelligenceIndicator table: stopped 2025-07-31 |
| SENT-050 | SAC-TI-02 | Enabled analytics rule queries the retired ThreatIntelligenceIndicator table |
| SENT-051 | SAC-MON-05 | High-volume table with no enabled analytics rule reading it |
| SENT-052 | SAC-MON-06 | Table that enabled analytics rules depend on has gone silent |
| SENT-053 | SAC-AUT-02 | Playbook runs failed in the last 7 days |
| SENT-054 | SAC-DET-13 | Installed Content Hub solution is deprecated or no longer in the catalogue |
| SENT-055 | SAC-TI-05 | Threat intelligence relies on a single feed |
| SENT-056 | SAC-LOG-06 | Azure Firewall logs collected twice (AzureDiagnostics and resource-specific tables) |
| SENT-057 | SAC-INC-02 | Most incidents are closed without a classification |
| SENT-058 | SAC-HNT-01 | No hunting activity recorded |
| SENT-059 | SAC-DET-14 | Analytics rule runs are failing |

The catalogue holds 66 rules. Version 3.1.0 added seven that close the
remaining gaps against health-check build 38 (see
[Health-Check-Coverage.md](Health-Check-Coverage.md)):

| Rule | What it reads | Fires when |
|---|---|---|
| SAC-COV-08 Entity analytics not enabled | `settings.json`, `ueba-data-presence.json` | the EntityAnalytics settings carry no identity provider and `IdentityInfo` received no rows in 14 days |
| SAC-LOG-19 Summary rules not in use | `summary-rules.json`, `tables-with-data.json` | no summary rule exists while one or more tables ingest 50 GB or more in 30 days |
| SAC-LOG-20 Retention out of order | `workspace-tables.json` | a table's analytics retention is longer than its total retention |
| SAC-LOG-21 Long retention nobody uses | `workspace-tables.json`, `rule-table-references.json`, `summary-rules.json`, `table-query-usage.json` | a table keeps data beyond its analytics retention (or is on the DataLake plan) and no enabled rule, summary rule, search or restore table, or audited query reads it |
| SAC-LOG-22 SecurityEvent duplicates | `security-event-duplicates.json` | a host sent the same SecurityEvent record more than once in the last hour (two agents, or overlapping DCRs) |
| SAC-LOG-23 CEF in Syslog | `cef-in-syslog.json` | CEF-formatted messages landed in `Syslog` instead of `CommonSecurityLog` in 7 days; the evidence lists every forwarder |
| SAC-PLT-12 Query auditing off | `la-query-logs.json` | `LAQueryLogs` recorded no queries in 7 days |

Each one stays quiet when the capture it reads is missing, so a failed
call is never reported as a gap. Version 3.1.1 widened SAC-PLT-10 (a
connected connector not delivering): it measures all volume over 7 days,
so free tables such as OfficeActivity no longer look silent, and besides
the core tables of five named connectors it checks every connected
connector the connector catalogue knows, flagging one when none of the
tables the catalogue lists for it received data. Version 2.3.0 added SAC-DET-14 (analytics rule
runs failing, from `SentinelHealth`). Version 2.2.0 added thirteen that port the
checks from the Sentinel health-check script contributed to the project:

| Rule | What it reads | Fires when |
|---|---|---|
| SAC-DET-06 Noisy rule | `rule-effectiveness.json` | a Sentinel analytics rule (rows with a rule id; other products' alerts are tuned in their own portal) with 20+ closed incidents and more than 70% false positive |
| SAC-DET-03 No entity mappings | `alert-rules.json` | an enabled Scheduled/NRT rule has no `entityMappings` |
| SAC-MON-01 Alert-only rule | `alert-rules.json` | `incidentConfiguration.createIncident` is explicitly false |
| SAC-DET-08 Legacy incident creation | `alert-rules.json`, `data-connectors-classic.json` | a `MicrosoftSecurityIncidentCreation` rule is enabled; the evidence says whether XDR already syncs incidents |
| SAC-TI-02 Rule on the retired TI table | `rule-table-references.json` | an enabled rule reads `ThreatIntelligenceIndicator` |
| SAC-MON-05 Table nobody detects on | `rule-table-references.json`, `template-table-references.json`, `tables-with-data.json` | a table at 5 GB or more in 30 days is read by no enabled rule; suggests every undeployed, non-deprecated template per table |
| SAC-MON-06 Silent dependency | `rule-table-references.json`, `workspace-tables.json`, `tables-with-data.json` | a table an enabled rule reads ingested nothing in 7 days |
| SAC-AUT-02 Playbook failures | `playbook-runs.json` | any playbook failed a run in 7 days |
| SAC-DET-13 Deprecated solution | `content-packages.json`, `content-product-packages.json` | an installed solution is `isDeprecated` or missing from the catalogue |
| SAC-TI-05 Single TI feed | `data-connectors-classic.json`, `threat-intel-counts.json` | at most one TI connector kind and no non-Microsoft indicator source |
| SAC-LOG-06 Azure Firewall logged twice | `azure-diagnostics-categories.json`, `tables-with-data.json` | `AzureFirewall*` categories and `AZFW*` tables both carry data |
| SAC-INC-02 Closed unclassified | `incidents-summary.json` | 10+ closed and more than half Undetermined or unclassified |
| SAC-HNT-01 No hunting | `hunts.json`, `bookmarks.json` (or `bookmarks-count.json` when the list was too large to fetch) | both captures ran and both are empty |

The collector only writes some of those files when their capture succeeds
(`hunts.json`, `playbook-runs.json`, `rule-effectiveness.json` and the
reference files among them). `Inventory.RawFiles` lists the JSON files
that exist, and the checks that need it use it to stay quiet when a
capture did not run rather than report "none" on a failed call. KQL
result cells arrive as strings, so the checks read numbers through small
`_ToInt` / `_ToDouble` helpers rather than casting.

### Adding a new rule

1. Write `Test-MyNewRule` in `GapChecks.ps1`.
2. Add a row to `best-practices.json` referencing it by name.
3. Add a fixture-driven Pester test under
   `Tests/iSOCBlueprint/Get-SentinelGap.Tests.ps1`.

That's the complete change. If the rule reads a capture that can be
absent, read it through `Read-JsonArray` in `Get-SentinelGap.ps1` and check
`$Inventory.RawFiles` before treating an empty array as a finding.

---

## How the maturity assessment works

After the gap engine, the collector runs
[`Modules/iSOCBlueprint/Engine/Private/Get-SentinelMaturity.ps1`](../../../Modules/iSOCBlueprint/Engine/Private/Get-SentinelMaturity.ps1)
over the same `_raw/` folder and the per-rule outcomes, and writes
`maturity.json`: eleven areas scored 0 to 5 from sixty criteria, each
resolved to Met, Gap or Unknown from a SENT rule outcome or a metric
computed from the captures, plus a roadmap ordered by lift, five quick
wins and a NIST CSF 2.0 rollup. Unknown never counts against the
workspace. The methodology, the scoring and the full criteria list are in
[Sentinel-Maturity-Model.md](Sentinel-Maturity-Model.md).

### Categories and severities

Categories are informational: `Cost`, `Coverage`, `Operational`, `Identity`,
`Network`, `Resilience`, `Hygiene`, `Foundation`, `Strategic`. Severities are
`Critical` / `Warning` / `Info`.

---

## How the cost estimator works

The `84-cost-estimate.md` page is produced by
[`Modules/iSOCBlueprint/Engine/Private/Get-SentinelCostEstimate.ps1`](../../../Modules/iSOCBlueprint/Engine/Private/Get-SentinelCostEstimate.ps1).
It is opinionated and the methodology is reproduced verbatim in the report so
the reader can trust or push back on the number.

In short:
1. Per-table 30-day billable GB comes from the workspace `Usage` table (cheap KQL).
2. Plan attribution (`Analytics` / `Basic` / `Auxiliary` / `DataLake`) decides which
   ingestion meter applies.
3. Unit prices are fetched from the public
   [Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices)
   for the workspace's region (anonymous, no auth).
4. Sentinel free-benefit-eligible tables (in
   [`Private/Resources/sentinel-benefit-tables.json`](../../../Modules/iSOCBlueprint/Engine/Private/Resources/sentinel-benefit-tables.json))
   have their unit price set to zero **on the assumption the benefit is active** -
   the estimator does not itself check whether the workspace actually qualifies.
   Detecting a Defender plan that would activate the benefit is deferred to gap rule
   SAC-LOG-13, not applied to the price here.
5. A commitment-tier "what-if" projects the monthly delta if the workspace moved up
   one CR rung (only meaningful for `PerGB2018` workspaces).
6. The dedicated-cluster candidate flag is set purely on volume, when the 30-day
   average daily ingest exceeds 500 GB/day. It is a `($totalGb30d / 30) > 500` test;
   it does **not** check whether a dedicated cluster is already linked.

### Caveats: explicitly NOT priced

- Query-time billing for Basic / Auxiliary plans.
- Search-job and restored-log storage.
- Data-export egress and cross-region transfer.
- Defender XDR-side meters.

Sanity-check the figure once a quarter against your Cost Management bill; the
Blueprint is a planning tool, not a billing tool.

---

## Tests

```powershell
Invoke-Pester -Path Tests/iSOCBlueprint -Output Detailed
```

The Pester suite is fully offline:

- `Get-SentinelGap.Tests.ps1` runs the gap engine against the deliberately-broken
  fixture under `Tests/iSOCBlueprint/Fixtures/sample/_raw` and asserts that each
  rule fires (or doesn't) for the conditions encoded in the fixture.
- `Convert-SentinelInventoryToMarkdown.Tests.ps1` invokes the renderer on the
  same fixture, copies output to a temp folder and asserts that every expected
  section file is produced and contains the headings + signal phrases the report
  promises.
- `Invoke-SentinelRest.Tests.ps1` covers the REST wrapper `Private/Invoke-SentinelRest.ps1`:
  `value`/`nextLink` pagination, 429/5xx retry-with-backoff, and 404-as-empty.
- `Get-KqlTableReferences.Tests.ps1` runs the table-to-rule builder over the
  fixture rules and templates and asserts equality with the hand-authored
  reference files (it dot-sources the module's copy of the Sentinel.Common
  KQL helpers, so it needs no Azure modules).
- `Get-SentinelMaturity.Tests.ps1` scores the fixture, checks named criteria,
  the roadmap order and the NIST CSF rollup, runs synthetic criteria for the
  scoring arithmetic and guards the criteria file's schema.
- `Section-Model.Tests.ps1` covers the section model: the Markdown converter,
  every chart kind the Mermaid parser reads, and the renderer's
  `sections/*.json` validated against the schemas.
- `SharePoint-Site.Tests.ps1` covers the section families, the
  section-model-to-page conversion, the publish planners, the maturity
  history helper, the publisher's SharePoint steps (chart web part placement
  included) against stand-in PnP functions and an offline bundle build.
- `SharePoint-PnPCalls.Tests.ps1` checks that every PnP.PowerShell call in the
  SharePoint scripts binds against the pinned PnP version (skipped when that
  version is not installed).
- `Module.Tests.ps1`, `Module-Standalone.Tests.ps1` and `Pipelines.Tests.ps1`
  cover the module itself: the manifest and help, each command's parameter
  mapping, a run from a copy outside the repository, and every call the
  pipelines make to it. `Vendored.Tests.ps1` keeps the module's copies of
  the two Sentinel.Common KQL helpers and of page 99 identical to their
  originals, and `Migration-Map.Tests.ps1` keeps the move out of the old
  `Tools/Blueprint` folder complete.

All the suites live under `Tests/iSOCBlueprint/` and are picked up automatically
by the existing PR-validation workflow (`Invoke-PRValidation.ps1` runs every
suite and emits an NUnit 2.5 report).

---

## Multi-cloud and long-running collections

The Blueprint uses `Invoke-AzRestMethod` for every ARM call, which routes
automatically to the audience of the active `Az` context. To target a
sovereign cloud, connect once before running the collector:

```powershell
Connect-AzAccount -Environment AzureUsGovernment
Export-iSOCBlueprintInventory -ResourceGroup <rg> -WorkspaceName <ws>
```

No URL substitution or per-cloud branching is needed inside the helper.

Token refresh is handled automatically by `Az.Accounts` 2.x+. Long-running
collections (a workspace with hundreds of analytics rules and thousands of
tables-with-data rows can take ten or more minutes end-to-end) do not need
manual `Get-AzAccessToken` calls in the collector. The
`Invoke-AzRestMethod` cmdlet refreshes the bearer token when it is within
~5 minutes of expiry.

If you ever see persistent 401s on a long run, the cause is almost always
a Conditional Access policy refusing the token after a tenant-side timeout,
not the helper. Re-`Connect-AzAccount` and the next run completes.

---

## Effective connectors (synthesised view)

The Sentinel `dataConnectors` and `dataConnectorDefinitions` REST endpoints
only enumerate the connectors that register against the Sentinel resource
provider. A modern workspace ingests most of its data through DCRs and
diagnostic-settings pipelines that never appear in those two endpoints, so
rendering section 10 purely from those two captures makes well-instrumented
workspaces look almost empty.

[`Modules/iSOCBlueprint/Engine/Private/Get-EffectiveConnectors.ps1`](../../../Modules/iSOCBlueprint/Engine/Private/Get-EffectiveConnectors.ps1)
synthesises a unified ingestion view by walking the five captures in this
order, with each later step skipping any table already claimed by an earlier
one (precedence avoids double-counting):

| # | Source              | Reads from                              | What it claims                          |
|---|---------------------|-----------------------------------------|-----------------------------------------|
| 1 | Classic             | `_raw/data-connectors-classic.json`     | The Log Analytics table each connector data-type targets, derived via `Get-ConnectorTargetTable`. |
| 2 | CCF                 | `_raw/data-connector-definitions.json`  | Listed by name. Doesn't claim a table because CCF table mapping is connector-specific. |
| 3 | DCR                 | `_raw/dcrs.json`                        | Each data-flow's `outputStream` resolves to a table (`Microsoft-` / `Custom-` prefix stripped). |
| 4 | Diagnostic settings | `_raw/diagnostic-settings.json`         | Each enabled log category resolves to a table by name. |
| 5 | Active-table        | `_raw/tables-with-data.json`            | Any remaining table with `BillableLast24h > 0` that no earlier source claimed. The `Identifier` column carries an inferred product family rather than a blank. |

The Active-table row is deliberately a visibility signal: if a workspace
receives data into a table no captured ingestion mechanism explains, an
operator wants to know. It usually means data arrived via a path the
Blueprint doesn't yet enumerate (e.g. ingestion through a Logic App
running outside the captured playbook resource group, or a legacy MMA
agent still attached to the workspace). Rather than leaving the `Identifier`
blank, `Get-EffectiveConnectors` runs the table name through an
`_ActiveTableFamily` helper that maps it to an inferred product family
(for example `Microsoft Defender XDR`, `Microsoft Entra ID`, or
`CEF / Syslog`), so the row at least hints at which source the unmapped
ingestion belongs to.

The `Last24hGB` and `LastIngested` columns come from the
`tables-with-data` join. Empty values mean the table either receives no
billable data or wasn't seen in the 90-day usage window.

---

## What this tool is not

- **Not a real-time monitor.** Use SentinelHealth / LAQueryLogs and Azure Monitor
  alerts for that.
- **Not a billing tool.** It estimates; the source of truth is Cost Management.
- **Not a deployer.** It only reads. Deployment is handled by the existing
  `Deploy/Deploy-*.ps1` family and the `sentinel-deploy.yml` workflow.
- **Not multi-workspace yet.** The script is parameterised, but the workflow runs
  against a single workspace. Adding a matrix strategy is a follow-up.

---

## Related

- [`Blueprint-References.md`](Blueprint-References.md): durable
  reference of API versions, modules, and Microsoft Learn pages.
- [iSOC Blueprint SharePoint Site](Sentinel-SharePoint-Site.md): the generated
  SharePoint site built from this tool's output.
- [`Test-SentinelRuleDrift.ps1`](../../../Tools/Test-SentinelRuleDrift.ps1): sister
  read-only tool that detects portal-edited rules. The Blueprint answers
  "what is deployed?"; drift detection answers "is what's deployed what's in the
  repo?".
- [Microsoft Sentinel best practices](https://learn.microsoft.com/azure/sentinel/best-practices):
  the upstream source for many of the gap rules.
