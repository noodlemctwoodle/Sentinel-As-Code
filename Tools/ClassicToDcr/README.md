# DCR migration toolkit

Migrate classic (MMA / Data Collector API) custom log tables to Data
Collection Rule based tables, deploy the matching DCR, and rehearse the
whole thing end to end with live data before you do it for real.

The scripts are **fully standalone**: copy this folder to a jump box or an
automation account and they run with only the Az modules installed. They do
not import the repo's `Sentinel.Common` module (each defines its own
logging), so nothing else from this repository needs to travel with them.

| Script | Purpose | API it uses | Auth |
|---|---|---|---|
| `New-DcrFromClassicTable.ps1` | The migration tool: discover classic tables, migrate them, deploy a DCR, optionally grant the ingestion role | ARM control plane + Tables API | Your Az identity |
| `New-ClassicTableFixture.ps1` | Rehearsal aid: create a throwaway classic `_CL` table with synthetic data, or stream it continuously | HTTP Data Collector API (legacy) | Workspace SharedKey |
| `Test-DcrIngestion.ps1` | Rehearsal aid: stream synthetic data into a migrated DCR and confirm it arrives | Logs Ingestion API (new) | Service principal bearer |

Only `New-DcrFromClassicTable.ps1` runs against real tables. The other two
generate synthetic data to rehearse against a throwaway table; use them in
a scratch workspace, never production. Fuller reference is in
[`Docs/Deploy/Scripts.md`](../../Docs/Deploy/Scripts.md).

## Contents

- [The three APIs, and which one touches a DCR](#the-three-apis-and-which-one-touches-a-dcr)
- [What a real migration actually requires](#what-a-real-migration-actually-requires)
- [Prerequisites and RBAC](#prerequisites-and-rbac)
- [`.env` for the ingestion tester](#env-for-the-ingestion-tester)
- [Do you need a Data Collection Endpoint?](#do-you-need-a-data-collection-endpoint)
- [Migrating a table](#migrating-a-table)
- [Rehearsing end to end](#rehearsing-end-to-end)
- [Rehearsing a cutover (data flowing during migration)](#rehearsing-a-cutover-data-flowing-during-migration)
- [How the tool handles the tricky parts](#how-the-tool-handles-the-tricky-parts)
- [Gotchas and troubleshooting](#gotchas-and-troubleshooting)
- [Cleanup](#cleanup)
- [Retirement timeline](#retirement-timeline)
- [Tests](#tests)

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
`Test-DcrIngestion.ps1` is a working reference implementation of this new
sender.

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
2. Migrate and deploy the DCR (`New-DcrFromClassicTable.ps1 -Deploy`).
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

## `.env` for the ingestion tester

`Test-DcrIngestion.ps1` reads its service principal from the environment.
Copy `.env.example` to `.env` (the real `.env` is gitignored) and fill in:

```
DCR_INGEST_TENANT_ID=<tenant guid>
DCR_INGEST_CLIENT_ID=<app id>
DCR_INGEST_CLIENT_SECRET=<secret>
```

Run the tester from this folder and the `.env` is picked up automatically
(resolution order: current directory, then next to the script). The secret
is held in memory only and never printed. The same `DCR_INGEST_CLIENT_ID`
is what you pass to `New-DcrFromClassicTable.ps1 -GrantIngestionRoleTo`.

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
./New-DcrFromClassicTable.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTable_CL -ListOnly
```

```bash
# 2. Migrate + deploy + grant (irreversible). Grant value = the sender's app/client ID
./New-DcrFromClassicTable.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTable_CL -Deploy -Force -GrantIngestionRoleTo <sender-client-id>
```

```bash
# 3. Verify no data loss: SubType now DataCollectionRuleBased, ROWS not lower
./New-DcrFromClassicTable.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTable_CL -ListOnly
```

Discover everything first with `-AllClassicTables -ListOnly`. Step 2 prints
the DCR name, immutable ID, endpoint, and the ready ingestion URL, and
writes `dcr-mytable.json` to the current directory (the standalone
default). Add `-OutputDirectory ../../Infra/dcr` to land it somewhere
tracked.

## Rehearsing end to end

The mechanics on a throwaway table, without concurrent load. Use a **fresh
table name each run**.

```bash
# 1. Seed a classic table (100 rows via the Data Collector API)
./New-ClassicTableFixture.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01 -RecordCount 100
```

```bash
# 2. Baseline (wait ~10-15 min for a new table to become queryable)
./New-DcrFromClassicTable.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01_CL -ListOnly
```

```bash
# 3. Migrate + deploy + grant. Grant value = DCR_INGEST_CLIENT_ID from .env
./New-DcrFromClassicTable.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01_CL -Deploy -Force -GrantIngestionRoleTo <DCR_INGEST_CLIENT_ID>
```

```bash
# 4. Verify no data loss: SubType DataCollectionRuleBased, ROWS still >= 100
./New-DcrFromClassicTable.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01_CL -ListOnly
```

```bash
# 5. Stream through the DCR. batch N OK = HTTP 204; the post-run poll reports arrived 30/30
./Test-DcrIngestion.ps1 -DcrName dcr-mytest01 -DcrResourceGroupName rg-scratch -BatchCount 3 -Follow
```

## Rehearsing a cutover (data flowing during migration)

To prove there is no ingestion gap, keep legacy data arriving while you
migrate and bring up the new path. Use a throwaway workspace.

**Terminal A, legacy source, leave running the whole time:**

```bash
./New-ClassicTableFixture.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01 -Stream -IntervalSeconds 15
```

**Terminal B:** run the migration steps above while A keeps streaming. The
baseline climbs (A is still writing); after migration `ROWS` only goes up,
because the Data Collector API keeps writing to existing columns. Then add
the new path:

```bash
./Test-DcrIngestion.ps1 -DcrName dcr-mytest01 -DcrResourceGroupName rg-scratch -BatchCount 3 -Follow
```

**Confirm both sources landed** (in Logs):

```kql
MyTest01_CL
| extend Path = iff(SourceSystem == "RestAPI", "Legacy (Data Collector API)", "New (DCR / Logs Ingestion)")
| summarize count() by Path, bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

Legacy rows show `SourceSystem == "RestAPI"`; new-path rows arrive with a
**blank** `SourceSystem`. Logs Ingestion is asynchronous, so give new rows
a few minutes to surface. Seeing both across the migration timestamp, with
no gap, is the clean-cutover proof. **Complete the cutover:** Ctrl-C
Terminal A. Legacy goes quiet; the DCR path carries on.

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
| Cannot delete a classic table | The Tables API forbids deleting a `Classic` table. See Cleanup. |
| First deploy left the table migrated but no DCR | An earlier failure (for example the guid bug, now fixed). The table is DCR-based; re-run with `-SkipTableMigration -Deploy`. |

## Cleanup

Stop any `-Stream` fixtures first, or the next POST recreates the table.

For a table that has been **migrated** (the normal end state), the fixture
removes it cleanly:

```bash
./New-ClassicTableFixture.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01 -Remove
```

If the table is **still Classic** (an aborted run), the Tables API cannot
delete it. `-Remove` detects this and tells you rather than throwing a raw
error. Add `-MigrateBeforeRemove` to migrate it (one-way) and then delete,
or delete it in the Azure portal:

```bash
./New-ClassicTableFixture.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01 -Remove -MigrateBeforeRemove
```

Remove the DCR:

```bash
Remove-AzDataCollectionRule -ResourceGroupName rg-scratch -Name dcr-mytest01
```

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

- `Tests/Test-NewDcrFromClassicTable.Tests.ps1`
- `Tests/Test-NewClassicTableFixture.Tests.ps1`
- `Tests/Test-DcrIngestion.Tests.ps1`
