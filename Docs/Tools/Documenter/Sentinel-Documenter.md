# Sentinel Documenter

A read-only inventory-and-gap-analysis tool that runs daily against a live Microsoft
Sentinel workspace and produces a Markdown report of every artefact, every workspace
setting, every DCR/DCE, an estimated monthly cost and a findings list scored against
the documented Microsoft Learn best practices.

> Operating guide (this page): for users running the tool and consuming its output.
> For renderer internals (chart system, helpers, Mermaid-safety rules, how to add
> charts), see [Documenter-Renderer-Design.md](Documenter-Renderer-Design.md).

> [!IMPORTANT]
> **Repository must be private.**
>
> The Documenter generates a folder of detailed tenant configuration:
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
> Documenter, see [Topology options](#topology-options) below.

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

---

## Topology options

The Documenter is hard-wired to refuse public-repo commits. Pick the
topology that matches your setup:

### A. Single private repo (simplest)
- All code, deployment config, and Documenter pipelines live in one
  private repo (private GitHub *or* an ADO project).
- Either pipeline (`.github/workflows/sentinel-document.yml` or
  `Pipelines/Sentinel-Documenter.yml`) opens its PR directly in that repo.
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
  ever produced from the public copy. Run the documenter from the private
  ADO mirror instead.

### C. Don't want a PR at all
- On a **private** repo, set `open-pull-request: false` (GH) or untick the
  equivalent parameter (ADO) and the pipeline still publishes the artefact,
  just without opening a PR. On a public repo nothing is produced either
  way (see option B).

---

## What it produces

A folder per workspace under `SecurityDocs/<workspace>/`. The collector
(`Export-SentinelInventory.ps1`) writes the `_raw/` JSON snapshot; the renderer
(`Convert-SentinelInventoryToMarkdown.ps1`) turns that snapshot into `index.md`
plus **37 numbered Markdown sections**:

```
SecurityDocs/
└── law-sentinel-prod/
    ├── _raw/                          machine-readable JSON snapshot
    │   ├── workspace.json
    │   ├── workspace-tables.json
    │   ├── tables-with-data.json
    │   ├── alert-rules.json
    │   ├── data-connectors-classic.json
    │   ├── ... (≈69 files)
    │   ├── retail-prices-uksouth-2026-05-06.json
    │   ├── cost-estimate.json
    │   └── gap-analysis.json
    ├── index.md                       full TOC, mapped to the Sentinel Config TOC numbering
    ├── 00-overview.md                 headline counts, top findings, cost summary
    ├── 01-live-snapshot.md            workspace-at-a-glance, regenerated every run
    ├── 10-data-connectors.md          classic + CCF + synthesised effective view
    ├── 11-sentinel-health.md          SentinelHealth events (last 7 days)
    ├── 12-soc-optimization.md         SOC Optimization recommendations
    ├── 13-data-source-hygiene.md      CEF/Syslog hygiene, agent dual-collection, noisy events
    ├── 14-coverage-breakdowns.md      AzureActivity / AzureDiagnostics / XDR coverage by source
    ├── 15-incidents.md                incident MTTA/MTTR + top alerting rules
    ├── 20-analytics-rules.md          all rules by kind (Scheduled, NRT, Fusion, …)
    ├── 21-analytics-by-volume.md      top 50 rules by alert volume (30d)
    ├── 22-analytics-microsoft-rules.md  Microsoft-managed rules
    ├── 23-analytics-modifications.md  recently modified rules
    ├── 24-analytics-by-solution.md    rules grouped by Content Hub solution
    ├── 25-mitre-coverage.md           ATT&CK matrix, uncovered tactics flagged
    ├── 26-ueba.md                     UEBA configuration
    ├── 27-threat-intelligence.md      indicator counts by source
    ├── 30-hunting-queries.md
    ├── 35-parsers-functions.md
    ├── 36-data-export.md              data export configuration
    ├── 37-search-restore.md           search jobs / restore logs
    ├── 38-summary-rules.md            summary rules
    ├── 40-workbooks.md                saved workbooks + templates available
    ├── 50-watchlists.md               watchlist *definitions* (item contents never captured)
    ├── 60-automation-rules-playbooks.md  automation rules + playbooks + MI grants
    ├── 70-content-hub.md              installed solutions + repos
    ├── 80-workspace.md                SKU, retention, networking, CMK, feature flags
    ├── 81-table-plans-retention.md    Analytics / Basic / Auxiliary / DataLake matrix
    ├── 82-dedicated-cluster.md        cluster, CMK, availability zones
    ├── 83-data-collection.md          DCRs, DCEs, transforms
    ├── 84-cost-estimate.md            estimated monthly cost + commitment-tier what-if
    ├── 85-rbac.md                     role assignments
    ├── 86-subscription-context.md     subscription, tenant, RPs, locks, policy
    ├── 87-azure-monitor-agents.md     AMA agents heartbeating into the workspace
    ├── 88-sentinel-data-lake.md       Data Lake enrollment, Lake-tier tables, migration candidates
    ├── 90-gap-analysis.md             every finding with remediation + Learn link
    ├── 96-references-microsoft.md     curated Microsoft Learn entry points (user-facing)
    └── 99-references.md               documenter's own API versions + modules (copied from Documenter-References.md)
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
| Are we losing money on data we don't query? | `81-table-plans-retention.md`, `84-cost-estimate.md` |
| Did a connector break overnight? | `10-data-connectors.md`, plus the **Silent tables** appendix in `81-…` |
| What MITRE coverage gaps do we have? | `25-mitre-coverage.md` |
| Where can we apply Microsoft's best practice? | `90-gap-analysis.md` |
| Who has access to the workspace? | `85-rbac.md` |

Beyond those headline pages the report groups into families:

- **Operational health**: `11-sentinel-health.md` (SentinelHealth events, last 7
  days), `12-soc-optimization.md` (SOC Optimization recommendations),
  `13-data-source-hygiene.md` (CEF/Syslog hygiene, agent dual-collection, noisy
  events) and `15-incidents.md` (MTTA/MTTR and the loudest rules).
- **Analytics deep-dives**: `21-analytics-by-volume.md`,
  `22-analytics-microsoft-rules.md`, `23-analytics-modifications.md` and
  `24-analytics-by-solution.md` slice the rule estate by alert volume, ownership,
  recent change and Content Hub solution; `26-ueba.md` and
  `27-threat-intelligence.md` cover UEBA configuration and indicator counts.
- **Data platform**: `36-data-export.md`, `37-search-restore.md`,
  `38-summary-rules.md`, `87-azure-monitor-agents.md` and
  `88-sentinel-data-lake.md` document the ingestion, retention and Data Lake surface.
- **Coverage**: `14-coverage-breakdowns.md` attributes AzureActivity /
  AzureDiagnostics / XDR ingestion back to its source.

---

## How to run it

### In CI

Two pipelines, same scripts, same output, different host:

#### Azure DevOps: `Pipelines/Sentinel-Documenter.yml`
Manual trigger (`trigger: none`). Use this when pipeline testing lives in a
private ADO project. Reuses the `sentinel-deployment` variable group and the
`sc-sentinel-as-code` service connection that the deploy and drift-detect
pipelines already depend on. Pushes to `origin` on the ADO agent, which is
the **ADO repo only**, never GitHub.

> Pipelines → **Sentinel Documenter** → Run pipeline → optionally tick
> *Include preview API surface*. To skip the PR step and get only the
> artefact, untick *Open / refresh an ADO PR with the rendered docs*.

The run-pipeline panel exposes two further parameters:

- *Pre-render Mermaid charts to PNG* (`prerenderChartsToPng`, **default ON**):
  ADO Repos and wiki render `mermaid` fences as plain code and block inline SVG,
  so the pipeline installs `@mermaid-js/mermaid-cli` and converts each fenced chart
  to a PNG via `Convert-MermaidToImage.ps1`. This step is ADO-only; the GitHub
  workflow ships the raw fences because GitHub renders Mermaid natively. Untick it
  to skip the Node/mmdc install on a fast run.
- *Playbook resource group* (`playbookResourceGroup`, default blank): set this when
  Logic App playbooks live in a dedicated RG separate from the workspace RG (the
  Sentinel-As-Code convention). It maps to the collector's `-PlaybookResourceGroup`
  parameter; leave it blank to enumerate playbooks from the workspace RG.

#### GitHub Actions: `.github/workflows/sentinel-document.yml`
Daily at 06:00 UTC plus `workflow_dispatch`. Uses OIDC to a read-only
service principal. Privacy guard: the **Verify repository is private** step
runs **unconditionally** at the top of the job, before any collection, and
**fails the whole run** on a public repo regardless of the `open-pull-request`
input, because `SecurityDocs/` (and the run artefact that carries it) would
otherwise leak tenant config to the world. Scheduled runs are additionally
skipped on a public repo so the upstream doesn't accrue a permanent daily red
failure; a manual `workflow_dispatch` still starts and then hits the guard,
so an operator who tries it is told exactly why.

> Actions → **Sentinel Documenter** → Run workflow → optionally tick
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
# 1. Connect with an account that has the read-only roles described below.
Connect-AzAccount

# 2. Run the collector. Writes to ./SecurityDocs/<workspace>/_raw/.
#    -SubscriptionId, -ResourceGroup and -WorkspaceName are all mandatory.
#    Add -PlaybookResourceGroup when playbooks live in a separate RG.
./Tools/Documenter/Export-SentinelInventory.ps1 `
    -SubscriptionId        'sub-guid' `
    -ResourceGroup         'rg-sentinel-prod' `
    -WorkspaceName         'law-sentinel-prod' `
    -PlaybookResourceGroup 'rg-sentinel-automation' `
    -IncludePreview

# 3. Render. Writes ./SecurityDocs/<workspace>/*.md.
./Tools/Documenter/Convert-SentinelInventoryToMarkdown.ps1 `
    -WorkspaceName 'law-sentinel-prod'
```

Open `SecurityDocs/<workspace>/index.md` in your editor.

At the end of a collector run the script prints a **Capture summary** table: it
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

## Permissions for the documenter SP

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

See [`Documenter-References.md`](Documenter-References.md)
for the complete list of API versions, modules, REST-only gaps and Microsoft
Learn pages the tool depends on.

---

## How the gap engine works

The findings on `90-gap-analysis.md` are produced by small `Test-*` functions
in [`Tools/Documenter/Private/GapChecks.ps1`](../../../Tools/Documenter/Private/GapChecks.ps1),
dispatched by the engine in [`Tools/Documenter/Private/Get-SentinelGap.ps1`](../../../Tools/Documenter/Private/Get-SentinelGap.ps1).
The rules live in [`Tools/Documenter/Private/Resources/best-practices.json`](../../../Tools/Documenter/Private/Resources/best-practices.json),
a single object with `$schema` / `version` / `rules` keys; `Get-SentinelGap`
reads `(ConvertFrom-Json).rules`. Each entry looks like:

```json
{
  "$schema": "best-practices.schema.json",
  "version": "2.0.0",
  "rules": [
    {
      "id": "SENT-001",
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

### Adding a new rule

1. Write `Test-MyNewRule` in `GapChecks.ps1`.
2. Add a row to `best-practices.json` referencing it by name.
3. Add a fixture-driven Pester test under
   `Tests/Documenter/Get-SentinelGap.Tests.ps1`.

That's the complete change.

### Categories and severities

Categories are informational: `Cost`, `Coverage`, `Operational`, `Identity`,
`Network`, `Resilience`, `Hygiene`, `Foundation`, `Strategic`. Severities are
`Critical` / `Warning` / `Info`.

---

## How the cost estimator works

The `84-cost-estimate.md` page is produced by
[`Tools/Documenter/Private/Get-SentinelCostEstimate.ps1`](../../../Tools/Documenter/Private/Get-SentinelCostEstimate.ps1).
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
   [`Private/Resources/sentinel-benefit-tables.json`](../../../Tools/Documenter/Private/Resources/sentinel-benefit-tables.json))
   have their unit price set to zero **on the assumption the benefit is active** -
   the estimator does not itself check whether the workspace actually qualifies.
   Detecting a Defender plan that would activate the benefit is deferred to gap rule
   SENT-019, not applied to the price here.
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
documenter is a planning tool, not a billing tool.

---

## Tests

```powershell
Invoke-Pester -Path Tests/Documenter -Output Detailed
```

The Pester suite is fully offline:

- `Get-SentinelGap.Tests.ps1` runs the gap engine against the deliberately-broken
  fixture under `Tests/Documenter/Fixtures/sample/_raw` and asserts that each
  rule fires (or doesn't) for the conditions encoded in the fixture.
- `Convert-SentinelInventoryToMarkdown.Tests.ps1` invokes the renderer on the
  same fixture, copies output to a temp folder and asserts that every expected
  section file is produced and contains the headings + signal phrases the report
  promises.
- `Invoke-SentinelRest.Tests.ps1` covers the REST wrapper `Private/Invoke-SentinelRest.ps1`:
  `value`/`nextLink` pagination, 429/5xx retry-with-backoff, and 404-as-empty.

All three suites live under `Tests/Documenter/` and are part of the repo's 22 Pester
files. They are picked up automatically by the existing PR-validation workflow
(`Invoke-PRValidation.ps1` runs every suite and emits an NUnit 2.5 report).

---

## Multi-cloud and long-running collections

The Documenter uses `Invoke-AzRestMethod` for every ARM call, which routes
automatically to the audience of the active `Az` context. To target a
sovereign cloud, connect once before running the collector:

```powershell
Connect-AzAccount -Environment AzureUsGovernment
./Tools/Documenter/Export-SentinelInventory.ps1 -ResourceGroup <rg> -WorkspaceName <ws>
```

No URL substitution or per-cloud branching is needed inside the helper.

Token refresh is handled automatically by `Az.Accounts` 2.x+. Long-running
collections (a workspace with hundreds of analytics rules and thousands of
tables-with-data rows can take ten or more minutes end-to-end) do not need
manual `Get-AzAccessToken` calls in the capture script. The
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

[`Tools/Documenter/Private/Get-EffectiveConnectors.ps1`](../../../Tools/Documenter/Private/Get-EffectiveConnectors.ps1)
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
documenter doesn't yet enumerate (e.g. ingestion through a Logic App
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

- [`Documenter-References.md`](Documenter-References.md): durable
  reference of API versions, modules, and Microsoft Learn pages.
- [`Test-SentinelRuleDrift.ps1`](../../../Tools/Test-SentinelRuleDrift.ps1): sister
  read-only tool that detects portal-edited rules. The documenter answers
  "what is deployed?"; drift detection answers "is what's deployed what's in the
  repo?".
- [Microsoft Sentinel best practices](https://learn.microsoft.com/azure/sentinel/best-practices):
  the upstream source for many of the gap rules.
