# Sentinel Documenter

A read-only inventory-and-gap-analysis tool that runs daily against a live Microsoft
Sentinel workspace and produces a Markdown report of every artefact, every workspace
setting, every DCR/DCE, an estimated monthly cost and a findings list scored against
the documented Microsoft Learn best practices.

> [!IMPORTANT]
> **Repository must be private to run the PR-creation flow.**
>
> The Documenter generates a folder of detailed tenant configuration —
> workspace IDs, table names, rule details, RBAC principals, cost figures,
> network ACLs. This information **MUST NOT** land in a public repository.
>
> Both pipelines (ADO and GitHub Actions) include a privacy guard that
> refuses to commit `SecurityDocs/` unless the host repository is private.
> If you run the GitHub Actions workflow on a public repo with the PR step
> enabled, the run **fails fast** with an explicit error message. The
> ADO pipeline relies on the fact that ADO repos are private by default
> within a project.
>
> If your source-of-truth lives in a public GitHub repo and you need the
> Documenter, see [Topology options](#topology-options) below.

---

## Delivery channels

Each pipeline run delivers the report through **two** channels, both gated
by the privacy guard:

| Channel | Always on | Where to find it |
|---|---|---|
| Pipeline / workflow artefact (`sentinel-docs.zip`) | ✓ | ADO: Build summary → Related → Published artefacts. GitHub: Actions run page → Artifacts. |
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
- The **GitHub Actions workflow's PR step refuses to run on the public
  repo** — it falls back to artefact-only delivery there, or fails fast
  if the operator explicitly ticks `open-pull-request`.

### C. Don't want a PR at all
- Set `open-pull-request: false` (GH) or untick the equivalent
  parameter (ADO) — the pipeline still publishes the artefact.

---

## What it produces

A folder per workspace under `SecurityDocs/<workspace>/`:

```
SecurityDocs/
└── law-sentinel-prod/
    ├── _raw/                          machine-readable JSON snapshot
    │   ├── workspace.json
    │   ├── workspace-tables.json
    │   ├── tables-with-data.json
    │   ├── alert-rules.json
    │   ├── data-connectors-classic.json
    │   ├── ... (≈30 files)
    │   ├── retail-prices-uksouth-2026-05-06.json
    │   ├── cost-estimate.json
    │   └── gap-analysis.json
    ├── index.md
    ├── 00-overview.md                 headline counts, top findings, cost summary
    ├── 10-data-connectors.md          classic + CCF, table mappings
    ├── 20-analytics-rules.md          all rules by kind (Scheduled, NRT, Fusion, …)
    ├── 25-mitre-coverage.md           ATT&CK matrix, uncovered tactics flagged
    ├── 30-hunting-queries.md
    ├── 35-parsers-functions.md
    ├── 40-workbooks.md                saved workbooks + templates available
    ├── 50-watchlists.md               (item *contents* live in _raw/, never the report)
    ├── 60-automation-rules-playbooks.md
    ├── 70-content-hub.md              installed solutions + repos
    ├── 80-workspace.md                SKU, retention, networking, CMK, feature flags
    ├── 81-table-plans-retention.md    Analytics / Basic / Auxiliary / DataLake matrix
    ├── 82-dedicated-cluster.md        only emitted when a cluster is linked
    ├── 83-data-collection.md          DCRs, DCEs, transforms
    ├── 84-cost-estimate.md            estimated monthly cost + commitment-tier what-if
    ├── 85-rbac.md
    ├── 86-subscription-context.md     RPs, locks, policy assignments
    ├── 90-gap-analysis.md             every finding with remediation + Learn link
    └── 99-references.md               API versions, modules, Learn references
```

The split between `_raw/` (JSON) and the rendered Markdown means the renderer can be
re-run locally on a downloaded artefact without touching Azure — handy for iterating
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

---

## How to run it

### In CI

Two pipelines, same scripts, same output, different host:

#### Azure DevOps — `Pipelines/Sentinel-Documenter.yml`
Manual trigger (`trigger: none`). Use this when pipeline testing lives in a
private ADO project. Reuses the `sentinel-deployment` variable group and the
`sc-sentinel-as-code` service connection that the deploy and drift-detect
pipelines already depend on. Pushes to `origin` on the ADO agent — that is
the **ADO repo only**, never GitHub.

> Pipelines → **Sentinel Documenter** → Run pipeline → optionally tick
> *Include preview API surface*. To skip the PR step and get only the
> artefact, untick *Open / refresh an ADO PR with the rendered docs*.

#### GitHub Actions — `.github/workflows/sentinel-document.yml`
Daily at 06:00 UTC plus `workflow_dispatch`. Uses OIDC to a read-only
service principal. Privacy guard: the workflow **fails fast** if the host
repo is public and `open-pull-request` is set, on the basis that
`SecurityDocs/` would otherwise leak tenant config to the world.

> Actions → **Sentinel Documenter** → Run workflow → optionally tick
> `include-preview`. On a public repo, leave `open-pull-request` **off**
> (artefact-only) or move the workflow to a private repo.

#### Where to find the rendered docs

| Channel | ADO | GitHub Actions |
|---|---|---|
| Artefact (zip) | Build summary → Related → Published artefacts → `sentinel-docs` | Workflow run page → Artifacts → `sentinel-docs-<ws>-<runId>` |
| Pull request | Repos → Pull requests → "docs(sentinel): snapshot …" | Pull requests tab → "docs(sentinel): snapshot …" |

### Locally

```powershell
# 1. Connect with an account that has the read-only roles described below.
Connect-AzAccount

# 2. Run the collector — writes to ./SecurityDocs/<workspace>/_raw/.
./Scripts/Documenter/Export-SentinelInventory.ps1 `
    -SubscriptionId 'sub-guid' `
    -ResourceGroup  'rg-sentinel-prod' `
    -WorkspaceName  'law-sentinel-prod' `
    -IncludePreview

# 3. Render — writes ./SecurityDocs/<workspace>/*.md.
./Scripts/Documenter/Convert-SentinelInventoryToMarkdown.ps1 `
    -WorkspaceName 'law-sentinel-prod'
```

Open `SecurityDocs/<workspace>/index.md` in your editor.

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

The Azure Retail Prices API used by the cost estimator is anonymous — no auth
needed.

OIDC federated-credential subject for the `main` branch:
```
repo:<owner>/<repo>:ref:refs/heads/main
audience: api://AzureADTokenExchange
```

See [`Scripts/Documenter/REFERENCES.md`](../../Scripts/Documenter/REFERENCES.md)
for the complete list of API versions, modules, REST-only gaps and Microsoft
Learn pages the tool depends on.

---

## How the gap engine works

The findings on `90-gap-analysis.md` are produced by 28 small `Test-*` functions
in [`Scripts/Documenter/Private/GapChecks.ps1`](../../Scripts/Documenter/Private/GapChecks.ps1),
dispatched by the engine in [`Scripts/Documenter/Private/Get-SentinelGap.ps1`](../../Scripts/Documenter/Private/Get-SentinelGap.ps1).
Each rule is a row in [`Scripts/Documenter/Private/Resources/best-practices.json`](../../Scripts/Documenter/Private/Resources/best-practices.json):

```json
{
  "id": "SENT-001",
  "title": "Daily cap not configured on the Log Analytics workspace",
  "category": "Cost",
  "severity": "Warning",
  "check": "Test-DailyCapConfigured",
  "remediation": "Set workspaceCapping.dailyQuotaGb to a sensible ceiling…",
  "learn": "https://learn.microsoft.com/azure/azure-monitor/logs/daily-cap"
}
```

Every check function takes a single `$Inventory` parameter (built from the JSON
files in `_raw/`) and returns `$null` on pass or a finding object on fail. The
engine wires the rule metadata around the result.

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
[`Scripts/Documenter/Private/Get-SentinelCostEstimate.ps1`](../../Scripts/Documenter/Private/Get-SentinelCostEstimate.ps1).
It is opinionated and the methodology is reproduced verbatim in the report so
the reader can trust or push back on the number.

In short:
1. Per-table 30-day billable GB comes from the workspace `Usage` table (cheap KQL).
2. Plan attribution (`Analytics` / `Basic` / `Auxiliary` / `DataLake`) decides which
   ingestion meter applies.
3. Unit prices are fetched from the public
   [Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices)
   for the workspace's region — anonymous, no auth.
4. Sentinel free-benefit-eligible tables (in
   [`Private/Resources/sentinel-benefit-tables.json`](../../Scripts/Documenter/Private/Resources/sentinel-benefit-tables.json))
   have their unit price reduced/zeroed when the benefit applies.
5. A commitment-tier "what-if" projects the monthly delta if the workspace moved up
   one CR rung (only meaningful for `PerGB2018` workspaces).
6. The dedicated-cluster candidate flag is set when daily ingest > 500 GB and no
   cluster is currently linked.

### Caveats — explicitly NOT priced

- Query-time billing for Basic / Auxiliary plans.
- Search-job and restored-log storage.
- Data-export egress and cross-region transfer.
- Defender XDR-side meters.

Sanity-check the figure once a quarter against your Cost Management bill — the
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

Both suites are picked up automatically by the existing PR-validation workflow.

---

## What this tool is not

- **Not a real-time monitor.** Use SentinelHealth / LAQueryLogs and Azure Monitor
  alerts for that.
- **Not a billing tool.** It estimates; the source of truth is Cost Management.
- **Not a deployer.** It only reads. Deployment is handled by the existing
  `Scripts/Deploy-*.ps1` family and the `sentinel-deploy.yml` workflow.
- **Not multi-workspace yet.** The script is parameterised, but the workflow runs
  against a single workspace. Adding a matrix strategy is a follow-up.

---

## Related

- [`Scripts/Documenter/REFERENCES.md`](../../Scripts/Documenter/REFERENCES.md) — durable
  reference of API versions, modules, and Microsoft Learn pages.
- [`Test-SentinelRuleDrift.ps1`](../../Scripts/Test-SentinelRuleDrift.ps1) — sister
  read-only tool that detects portal-edited rules. The documenter answers
  "what is deployed?"; drift detection answers "is what's deployed what's in the
  repo?".
- [Microsoft Sentinel best practices](https://learn.microsoft.com/azure/sentinel/best-practices)
  — the upstream source for many of the gap rules.
