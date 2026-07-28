# Classic-to-DCR migration toolkit

Assess which classic (MMA / Data Collector API) custom log tables you have and
what depends on them, migrate them to Data Collection Rule based tables, deploy
the matching DCR, and rehearse the whole thing end to end with live data before
you do it for real.

> **Fuller reference:** [`Docs/Tools/ClassicToDcr/`](../../Docs/Tools/ClassicToDcr/Classic-to-DCR-Toolkit.md)
> is the authoritative documentation for this kit: api-versions, design rationale, every guard and
> why it exists, failure modes and troubleshooting. This README stays because the kit is designed
> to be copied standalone to a jump box or an automation account, where the `Docs/` tree will not
> travel with it, so it is the quick reference guaranteed to be on the box beside the script.

The workflow runs in three stages, and there is a script for each:

1. **Assess** - `Invoke-TableMigrationReview.ps1` inventories your classic
   tables and scores their blast radius (which rules, workbooks, playbooks and
   parsers break) before you change anything.
2. **Migrate** - `Invoke-ClassicTableMigration.ps1` migrates the table, deploys the
   DCR and optionally grants the ingestion role.
3. **Rehearse** - the three aids under `Rehearsal/` -
   `Rehearsal/New-ClassicTableFixture.ps1`, `Rehearsal/Test-DcrIngestion.ps1` and
   `Rehearsal/New-DependencyFixture.ps1` - let you practise the whole thing
   against throwaway content with live data, and prove the assessment step
   really finds what depends on a table.

The two production tools sit at the top of this folder; the rehearsal aids
live in the `Rehearsal/` subfolder so the "safe against prod" tools and the
"scratch workspace only" tools never get confused for each other.

The scripts are **fully standalone**: copy this folder to a jump box or an
automation account and they run with only the Az modules installed. They do
not import the repo's `Sentinel.Common` module (each defines its own
logging), so nothing else from this repository needs to travel with them.

| Script | Purpose | API it uses | Auth |
|---|---|---|---|
| `Invoke-TableMigrationReview.ps1` | The assessment tool: discover classic tables, score dependency impact including chains that reach a table only through a parser, map each to a Content Hub solution and flag connectors with no CCF replacement. Read-only | ARM control plane + Tables/Sentinel APIs | Your Az identity |
| `Invoke-ClassicTableMigration.ps1` | The migration tool: discover classic tables, migrate them, deploy a DCR, optionally grant the ingestion role | ARM control plane + Tables API | Your Az identity |
| [`Rehearsal/New-ClassicTableFixture.ps1`](Rehearsal/README.md) | Rehearsal aid: create a throwaway classic `_CL` table with synthetic data, or stream it continuously | HTTP Data Collector API (legacy) | Workspace SharedKey |
| [`Rehearsal/Test-DcrIngestion.ps1`](Rehearsal/README.md) | Rehearsal aid: stream synthetic data into a migrated DCR and confirm it arrives | Logs Ingestion API (new) | Service principal bearer |
| [`Rehearsal/New-DependencyFixture.ps1`](Rehearsal/README.md) | Rehearsal aid: build known direct and indirect dependency chains (table, parser, rule) so you can prove the assessment tool detects them. Analytics rules are created **disabled** | Data Collector API + savedSearches + Sentinel alertRules | Workspace SharedKey + your Az identity |

`Invoke-TableMigrationReview.ps1` is read-only and safe to run against
production. `Invoke-ClassicTableMigration.ps1` also runs against real tables but
makes irreversible changes. `New-ClassicTableFixture.ps1` and
`Test-DcrIngestion.ps1` generate synthetic data to rehearse against a throwaway
table; use them in a scratch workspace, never production.
`New-DependencyFixture.ps1` is the exception among the rehearsal aids: it is
built to be survivable against a live security workspace, because that is where
the dependency chains are worth proving. It still creates real objects, so read
[Proving the dependency scan](Rehearsal/README.md#proving-the-dependency-scan) before you run it.
Fuller reference is in
[`Docs/Tools/ClassicToDcr/`](../../Docs/Tools/ClassicToDcr/Classic-to-DCR-Toolkit.md), with the
migrate tool's parameter table in
[`Docs/Deploy/Scripts.md`](../../Docs/Deploy/Scripts.md#invoke-classictablemigrationps1).

`Invoke-TableMigrationReview.ps1` originated as the standalone
[Sentinel-CLv1-Analyzer](https://github.com/noodlemctwoodle/Sentinel-CLv1-Analyzer)
project (MIT); it is folded in here under this repository's Apache-2.0 licence.
Its `data/solution-mapping.json` is refreshed weekly from the upstream
Azure-Sentinel Solutions Analyzer by
[`.github/workflows/update-solution-mapping.yml`](../../.github/workflows/update-solution-mapping.yml).

## Contents

- [Assess before you migrate](#assess-before-you-migrate)
- [The three APIs, and which one touches a DCR](#the-three-apis-and-which-one-touches-a-dcr)
- [What a real migration actually requires](#what-a-real-migration-actually-requires)
- [Prerequisites and RBAC](#prerequisites-and-rbac)
- [Do you need a Data Collection Endpoint?](#do-you-need-a-data-collection-endpoint)
- [Migrating a table](#migrating-a-table)
- [How the tool handles the tricky parts](#how-the-tool-handles-the-tricky-parts)
- [Gotchas and troubleshooting](#gotchas-and-troubleshooting)
- [Retirement timeline](#retirement-timeline)
- [Tests](#tests)

## Assess before you migrate

Before touching a table, find out what you have and what leans on it.
`Invoke-TableMigrationReview.ps1` is read-only: it inventories classic V1
custom log tables in a workspace and, for each one, scores the blast radius so
a migration is a decision rather than a surprise.

```powershell
# Interactive - prompts for subscription, resource group, workspace
./Invoke-TableMigrationReview.ps1

# Scripted - write the report bundle to a dated folder
./Invoke-TableMigrationReview.ps1 `
    -SubscriptionId '00000000-0000-0000-0000-000000000000' `
    -ResourceGroupName 'rg-sentinel' `
    -WorkspaceName 'ws-sentinel' `
    -OutputPath './migration-report/2026-07'
```

It runs three steps:

1. **Discover** the classic `_CL` tables (AzureDiagnostics and other
   Microsoft-managed tables are filtered out - they are never candidates).
2. **Assess** each table's dependencies across Analytics Rules, Workbooks,
   Hunting Queries, Parsers, Saved Searches, SOAR Playbooks and Data
   Collection Rules, using a word-boundary KQL match so `MyApp_CL` does not
   falsely match `MyApp_CL_v2`.
3. **Map** each table to its Content Hub solution and classify the connector
   as CCF (Codeless Connector Framework), Azure Functions, AMA, Platform,
   Agent or Legacy. Legacy Azure Functions connectors with no CCF equivalent
   are flagged: those are the ones that need rebuilding, not just repointing.

### Dependencies that never name the table

A parser is a saved search with a `functionAlias`, and everything else invokes
it by that alias exactly as if it were a table. A rule that reads
`OfficeActivityParser | where ...` never mentions `OfficeActivity_CL` anywhere
in its query, so searching the workspace for the table name will not find it.
Migrate the table and the rule breaks just as hard as one that named it
directly.

Step 2 therefore walks the alias graph outward from each classic table and
reports those items too. They are marked **via parser** in the HTML report,
carry the chain that explains them (`rule -> parser -> table`), and appear in
`impact.csv` with `DependencyKind`, `Via`, `ViaChain` and `Depth` columns.
Chains of any length are followed, cycles terminate, and a chain deeper than
`-MaxParserChainDepth` (default 10 hops) is flagged rather than silently
truncated.

#### What counts as a reference

The alias is matched by name, so the question is which occurrences of that name
are real. Before matching, each query is reduced to the text KQL would actually
resolve names in:

| Removed | Why |
| --- | --- |
| `// line comments` | KQL has no block-comment form, so `//` to end of line is the whole story. A parser named in a `// TODO` is not a dependency. |
| String literals: `'...'`, `"..."`, verbatim `@'...'` / `@"..."`, multi-line ``` ``` ```, obfuscated `h'...'` | A name inside a string is data. Escaping is handled per form, so a `//` inside a string does not open a comment and an apostrophe inside a comment does not open a string. |
| `cluster(...)`, `database(...)`, `workspace(...)`, `app(...)` qualified references | `cluster("x").database("y").MyParser` is a function in another cluster, not this workspace's parser. |
| Assignment targets (`Name = ...`) | That is a new column or variable being named, not a function being called. `==` and `=~` are comparisons and are kept. |
| Member access (`Something.Name`) | A workspace function is referenced bare, never dotted. |
| `let`-bound names | A `let` shadows a stored function of the same name for the rest of the query, so those occurrences are locals. |

Matching is **case-sensitive**, because KQL entity names are: `officeparser`
does not resolve to a parser aliased `OfficeParser`, so it is not reported as
one. Two parsers whose aliases differ only in case are two different functions
and both are followed. The direct table matcher stays case-insensitive - that
behaviour is inherited, and a case variant of a table name is nearly always a
typo aimed at the real table, so reporting it errs safe. Indirect resolution
chains off its own matches, where one wrong hit multiplies at every later hop,
so it errs precise instead.

**Playbooks** are matched indirectly only on string values inside the workflow
definition that look like KQL (a pipe followed by a KQL tabular operator, or a
query opening with one). Scanning the whole definition JSON - which is what the
direct pass does - made an object key or a word in an action name into a
dependency. The trade is that a playbook building its query by string
concatenation, or passing it in a shape this test does not recognise, is not
matched indirectly. Direct table matching over playbooks is unchanged and still
reads the whole definition.

**Data Collection Rules** are never followed indirectly at all: an
ingestion-time `transformKql` runs before data reaches the workspace and cannot
invoke a workspace function, so a match there would always be a coincidence.
DCRs are still scanned for direct table references.

#### Aliases that are not followed, and what that costs

An alias is left out of the chain walk when it is not a plain identifier, is
shorter than four characters, is a KQL keyword or scoping function, is a column
Log Analytics puts on every table, or **collides with the name of a real table
in this workspace**. That last one matters most: a parser aliased `Update` or
`SecurityEvent` would otherwise make every query against the genuine built-in
table an indirect dependent of whatever classic table that parser reads. The
workspace's full table list is fetched during discovery anyway, so the guard
costs nothing.

Leaving an alias out is not free either. A parser that reads a classic table but
whose alias cannot be resolved is a chain that stops dead, and everything
calling that parser breaks on migration without appearing anywhere in the
results. So every skip is reported, with its reason **and the content that named
that alias and was therefore not resolved**, in three places: the console, the
`parserAliasResolution` block in `report.json`, and a **Resolver Coverage**
section in the HTML report. Per-table, the parsers that sever a chain for that
specific table appear as `UnresolvedBridges` in the JSON and as a callout above
the dependency list in the HTML.

An alias referenced by an implausible share of the whole workspace gets a
fan-out warning. It never suppresses the chain - hiding a finding to reduce
noise is the wrong trade here - it just tells you to treat those chains as
suspect. It fires only above both an absolute floor (20 referencing items) and a
share of the workspace measured against a minimum scale, so a legitimately
shared parser in a small workspace does not trip it and a large workspace can
still trip it.

**Residual over-reporting.** A bare column reference cannot be told apart from a
function reference without a full KQL parser, which this standalone script does
not carry. So a parser aliased identically to a column name that appears in
unrelated queries - `SigninLogs | project MyParser` - will still be counted. The
table-name guard, the case-sensitivity rule and the fan-out warning cover the
cases that actually occur; this one is stated rather than silently absorbed.

In the JSON report this is purely additive. `TotalImpacted` and the seven
per-type arrays still hold direct hits only, so anything written against the old
shape reads the same numbers. Chained dependents live in parallel
`Indirect<Type>` arrays, `TotalAffected` is the honest sum of both, and
`UnresolvedBridges` lists the chains the resolver could not follow for that
table.

Output is a set of pipeline objects plus a report bundle (CSV per step, a
combined JSON, and a self-contained HTML report) written to
`./migration-report/` by default. That folder is git-ignored - the report can
contain workspace-specific table and connector detail, so treat it as private.

Each table in the HTML report carries its own **Migration Command** section:
the exact `Invoke-ClassicTableMigration.ps1` invocation for that table, with the
resource group, workspace, table name and subscription already filled in, and a
copy button. Two commands are offered per table, a read-only `-ListOnly`
preview and the one-way `-Deploy` migration, so you can check before you commit.
Run them from `Tools/ClassicToDcr` in a signed-in PowerShell 7 session.

The report itself executes nothing. It is a static file with no network access,
and deliberately has no button that performs a migration: the migration is
irreversible and the report is something you might email to a colleague. It
hands you the command; you decide when to run it. Tables whose names the
migrate tool cannot accept get an explanatory note instead of a command.

The connector classification is only as current as the bundled
`data/solution-mapping.json`. The weekly workflow keeps it fresh; to refresh it
by hand, run `node Tools/ClassicToDcr/data/update-solution-mapping.mjs` (Node
18+, standard library only).

## The three APIs, and which one touches a DCR

This distinction is what the whole migration turns on:

- **HTTP Data Collector API (legacy)** is SharedKey auth to
  `<workspaceId>.ods.opinsights.azure.com/api/logs`. It creates classic
  tables and **does not use a DCR**. The fixture uses it, and it is what
  real classic tables were originally fed by.
- **Logs Ingestion API (new)** is an AAD bearer token to a DCR's own
  `logsIngestion` endpoint,
  `<endpoint>/dataCollectionRules/<immutableId>/streams/Custom-<Table>?api-version=2023-01-01`.
  It **requires a DCR**. The tester uses it.
- **Migration** converts a table from the first world to the second. It
  changes what is allowed to write to the table; it does not move any
  sender across for you.

## What a real migration actually requires

Migrating the **table** and deploying the **DCR** is only half the job. To
keep a real source ingesting, you must also **repoint the sender**, because
migration changes what can write to the table. What changes depends on the
legacy source. Identify it from the existing rows: a
`SourceSystem == "RestAPI"` value means the Data Collector API (Case A);
data collected by an agent points at Case B.

### Case A: an app using the HTTP Data Collector API

Three things change in the sending code:

| | Legacy | After cutover |
|---|---|---|
| Endpoint | `<workspaceId>.ods.opinsights.azure.com/api/logs` | the DCR's `logsIngestion` endpoint |
| Auth | workspace **SharedKey** (HMAC) | **AAD bearer token**, an SP or managed identity with *Monitoring Metrics Publisher* on the DCR |
| URL | `/api/logs?api-version=2016-04-01` | `<endpoint>/dataCollectionRules/<immutableId>/streams/Custom-<Table>?api-version=2023-01-01` |

The payload JSON stays essentially the same (it matches the stream
schema), and the DCR's transform reconciles any type differences.
`Rehearsal/Test-DcrIngestion.ps1` is a working reference implementation of
this new sender.

**No gap in this case:** the Data Collector API keeps writing to
**existing columns** after migration, so you migrate, update the app at
your own pace, then retire the old path. It cannot add new columns, and it
retires on 2026-09-14, so do not linger.

### Case B: the MMA / Log Analytics agent reading text log files

On migration, the **MMA agent loses the ability to write to the table**.
Switch to the **Azure Monitor Agent (AMA)** with a text-log DCR (the
`-DcrKind TextLog` mode, a `logFiles` data source). Because MMA cannot
co-write with AMA to the same table, Microsoft's guidance is to give each
agent its own table and join them at query time during the transition, so
no data is lost across the cutover. MMA is already retired, so this move is
mandatory regardless.

### The sequence for a real table

1. Identify the source (Case A or Case B).
2. Migrate and deploy the DCR (`Invoke-ClassicTableMigration.ps1 -Deploy`).
3. Grant the sender's identity Monitoring Metrics Publisher on the DCR
   (`-GrantIngestionRoleTo <identity>`).
4. Repoint the sender: update the app to the Logs Ingestion API (Case A),
   or deploy AMA plus a text-log DCR (Case B).
5. Verify the new path lands data. New rows arrive with a blank
   `SourceSystem`; legacy rows show `RestAPI`.
6. Decommission the legacy sender.

## Prerequisites and RBAC

- PowerShell 7.2+
- `Az.Accounts`, `Az.OperationalInsights`, `Az.Resources`
- An authenticated context: `Connect-AzAccount`

| Identity | Needs | Scope | For |
|---|---|---|---|
| You (running the scripts) | Log Analytics Contributor | Workspace | Read shared keys, migrate tables, query rows |
| You | Contributor | DCR resource group | Deploy the DCR |
| You | Owner or User Access Administrator | DCR | Only if you use `-GrantIngestionRoleTo` (creates a role assignment) |
| The sending identity | **Monitoring Metrics Publisher** | **the DCR** | Send via the Logs Ingestion API (a real app's SP or managed identity, or the tester's SP) |

The sending identity needs nothing on the workspace. A freshly granted role
can take a few minutes to take effect for data-plane calls, so early POSTs
may return 403.

## Do you need a Data Collection Endpoint?

Usually **no**. Two things give a DCR its own ingestion endpoint: it must
be `kind: Direct`, and it must be created on or after 2024-03-31, when the
service began populating the `endpoints` property. This toolkit deploys
fresh Direct DCRs, so they qualify. It authors them at api-version
`2023-03-11` (or later) because that is the minimum schema version that can
carry the `endpoints` property, not because that date grants the endpoint.
The live proof is that a successful deploy prints a real endpoint URL.

You only need a DCE when:

- the DCR was created before 2024-03-31 (older DCRs have no built-in
  endpoint, and one cannot be added, so the DCR must be replaced), or
- the workspace is behind **Private Link (AMPLS)**, or a sender shares DNS
  with AMPLS resources, or
- (AMA text-log path only) you collect Windows Firewall Logs or Prometheus
  metrics.

If you do need one, pass `-DataCollectionEndpointResourceId <dce>` to the
migration script and it wires `dataCollectionEndpointId` into the DCR.

## Migrating a table

Point the migration script at a classic `_CL` table (a real one, or a
throwaway you seeded to rehearse). Use a **fresh table name each run**
(reusing a just-deleted name can hit retained-schema conflicts).

```bash
# 1. Baseline, read-only. SubType = Classic, ROWS = the row count
#    (a brand-new table takes ~10-15 min to become queryable)
./Invoke-ClassicTableMigration.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTable_CL -ListOnly
```

```bash
# 2. Migrate + deploy + grant (irreversible). Grant value = the sender's app/client ID
./Invoke-ClassicTableMigration.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTable_CL -Deploy -Force -GrantIngestionRoleTo <sender-client-id>
```

```bash
# 3. Verify no data loss: SubType now DataCollectionRuleBased, ROWS not lower
./Invoke-ClassicTableMigration.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTable_CL -ListOnly
```

Discover everything first with `-AllClassicTables -ListOnly`. Step 2 prints
the DCR name, immutable ID, endpoint, and the ready ingestion URL, and
writes `dcr-mytable.json` to the current directory (the standalone
default). Add `-OutputDirectory ../../Infra/dcr` to land it somewhere
tracked.

## How the tool handles the tricky parts

- **Type reconciliation.** A DCR stream declaration cannot express `guid`,
  so guid columns are declared `string` while the table keeps `guid`. A
  plain `source` transform then fails with `InvalidTransformOutput`. The
  migration script compares every column's stream type against the table
  type and casts mismatches back (for example
  `source | extend EventId_g = toguid(EventId_g)`), for guid and any other
  divergence.
- **Emptiness by rows, not billable GB.** The `Usage` table lags for
  hours, so a freshly populated table shows `0 GB` while already holding
  rows. Discovery counts actual rows (`ROWS (90d)`) to decide emptiness. A
  table whose count cannot be read shows `unknown` and is treated as **not
  empty**, never skipped.
- **Deploy requires migration first.** A DCR cannot target a `Classic`
  table (`InvalidOutputTable`). The script migrates first, then deploys,
  and refuses `-SkipTableMigration -Deploy` against a still-classic table.
- **Arrival confirmation.** During streaming the per-batch `arrived`
  counts are near zero because Logs Ingestion is asynchronous. The
  authoritative signal is the HTTP 204 per batch, plus the tester's
  post-run poll that waits out latency and reports `arrived N/N`.
- **Deployment errors are surfaced.** A failed deploy reports the real
  operation `StatusMessage`, not the generic "failed with 1 error".

## Gotchas and troubleshooting

| Symptom | Cause and fix |
|---|---|
| `ROWS: unknown` on a new table | First-ingestion query availability lags 10-15 min. Not empty, not skipped. Wait and re-check. |
| `arrived: 0` while streaming | Ingestion latency. The `204` is the real success; the post-run poll confirms arrival. |
| `InvalidOutputTable` on deploy | The table is still `Classic`. Migrate first (drop `-SkipTableMigration`). |
| `InvalidTransformOutput` | A type mismatch (usually guid). Handled automatically; regenerate the template with the current script. |
| Legacy rows keep appearing after migration | Expected: the Data Collector API keeps writing to existing columns. Stop the sender to finish the cutover. |
| A `-Stream` fixture recreates a deleted table | Stop the stream first, then delete. |
| Cannot delete a classic table | The Tables API forbids deleting a `Classic` table. See [Cleanup](Rehearsal/README.md#cleanup). |
| A deleted `_CL` name will not come back | Once a classic table has been migrated and deleted, re-posting to the Data Collector API under the same `Log-Type` is accepted (HTTP 200) but the table never reappears, so anything depending on it fails to validate. Redeploy a fixture under a fresh `-NamePrefix` rather than reusing the old one. |
| Fixture rules fail with the tables missing | The rules are created last on purpose, because Sentinel validates rule KQL against the workspace schema on write. If the tables never materialised, every rule 400s. Check the tables exist before blaming the rules. |
| Dependency fixture refuses to run: alias collision | An alias would shadow a real table for every query in the workspace. Choose a different `-NamePrefix`. Nothing was written. |
| Dependency fixture refuses to run: name collision | A target name exists and does not carry the fixture marker. Nothing is ever overwritten. Choose a different `-NamePrefix`. |
| Fixture rule PUT fails with `Failed to resolve table or column expression named` | Sentinel validates rule KQL server side and the table or parser has not propagated yet. The script retries this case for a bounded window; if it gives up, re-run once the table is queryable. |
| The fixture's cycle parsers fail every query | Expected. The pair is deliberately unresolvable, to prove dependency resolution terminates. Skip it with `-Scenario`. |
| First deploy left the table migrated but no DCR | An earlier failure (for example the guid bug, now fixed). The table is DCR-based; re-run with `-SkipTableMigration -Deploy`. |

## Retirement timeline

- **HTTP Data Collector API**: retires **2026-09-14**. After that it cannot
  create classic tables or ingest, so the fixture (and any real Case A
  source that has not moved) stops working.
- **MMA / Log Analytics agent**: already retired (2024-08-31). Case B
  migration to AMA is mandatory.

## Tests

Unit tests live in the repo's `Tests/` folder (run by
`Tools/Invoke-PRValidation.ps1`), not here, so the standalone kit stays
runtime-only:

- `Tests/Test-InvokeTableMigrationReview.Tests.ps1`
- `Tests/Test-InvokeClassicTableMigration.Tests.ps1`

The rehearsal aids have their own, listed in
[`Rehearsal/README.md`](Rehearsal/README.md).
