# Classic to DCR Migration Toolkit

Three PowerShell scripts under [`Tools/ClassicToDcr/`](../../../Tools/ClassicToDcr/) that take a
classic (MMA / HTTP Data Collector API) custom log table from "we do not know what depends on
this" to "it is migrated, a Data Collection Rule is deployed, and the new sender ingests". The
toolkit assesses, migrates and rehearses; it does not repoint your sending application for you,
and it is honest about the fact that migration is one-way.

| What | Where |
| --- | --- |
| Assess (read-only) | [`Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1`](../../../Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1) |
| Migrate (irreversible) | [`Tools/ClassicToDcr/Invoke-ClassicTableMigration.ps1`](../../../Tools/ClassicToDcr/Invoke-ClassicTableMigration.ps1) |
| Rehearse | [`Tools/ClassicToDcr/Rehearsal/`](../../../Tools/ClassicToDcr/Rehearsal/) |
| Assess reference | [Table Migration Review](Table-Migration-Review.md) |
| Rehearsal reference | [Rehearsal Aids](Rehearsal-Aids.md) |
| Migrate parameter reference | [Deploy Scripts, `Invoke-ClassicTableMigration.ps1`](../../Deploy/Scripts.md#invoke-classictablemigrationps1) |

## Where the documentation lives

This folder is the authoritative reference. The kit also carries two READMEs of its own,
[`Tools/ClassicToDcr/README.md`](../../../Tools/ClassicToDcr/README.md) and
[`Tools/ClassicToDcr/Rehearsal/README.md`](../../../Tools/ClassicToDcr/Rehearsal/README.md), and
those stay. The scripts are designed to be copied out of this repository as a folder and run on a
jump box, in an automation account, or on a customer machine, and the `Docs/` tree does not travel
with them. The READMEs are therefore the quick reference that is guaranteed to be on the box next
to the script you are about to run.

The division of labour:

| Source | Scope |
| --- | --- |
| The two READMEs | On-the-box quick reference. Enough to run the scripts safely without network access to this repository. |
| These `Docs/Tools/ClassicToDcr/` pages | The fuller reference: api-versions, design rationale, every guard and why it exists, failure modes, troubleshooting. |

When the two disagree, the code wins, then these pages, then the READMEs.

## The three stages

| Stage | Script | Safe against production? | What it does |
| --- | --- | --- | --- |
| 1. Assess | `Invoke-TableMigrationReview.ps1` | Yes, read-only | Inventories classic `_CL` tables, scores dependency impact across seven content types including chains that reach a table only through a parser function, maps each table to a Content Hub solution, classifies the connector. Emits CSV, JSON and a self-contained HTML report. |
| 2. Migrate | `Invoke-ClassicTableMigration.ps1` | It runs against real tables and the migration is **one-way** | Migrates the table with the Tables API migrate operation, derives a DCR stream declaration from the post-migration schema, writes an ARM template per table, optionally deploys it and grants the ingestion role. |
| 3. Rehearse | `New-ClassicTableFixture.ps1`, `Test-DcrIngestion.ps1`, `New-DependencyFixture.ps1` | Scratch workspace, with one documented exception | Manufactures throwaway classic tables, streams data through a migrated DCR, and builds known direct and indirect dependency chains so the assess step's detection can be proved rather than assumed. |

The two production tools sit at the top of `Tools/ClassicToDcr/`; the rehearsal aids live in
`Rehearsal/`, so the "safe against production" and "scratch workspace only" tools are never
confused for one another.

`New-DependencyFixture.ps1` is the exception among the rehearsal aids: it is built to survive a
live security workspace, because that is where dependency chains are worth proving. It still
creates real, billable objects. Read
[Rehearsal Aids, safety design](Rehearsal-Aids.md#safety-design-and-why-this-one-can-face-a-live-workspace)
before you run it.

## Why this is urgent

| Thing | Status | Consequence |
| --- | --- | --- |
| HTTP Data Collector API | Retires **2026-09-14** | After that date it can neither create classic tables nor ingest into them. Anything still sending over it stops. The rehearsal fixtures also stop working, because nothing can create a classic table any more. |
| MMA / Log Analytics agent | Already retired (**2024-08-31**) | Any table fed by MMA text-log collection must move to the Azure Monitor Agent with a text-log DCR. This is not optional. |

A migrated table also unlocks things a classic table cannot do: it can be mirrored to the
Microsoft Sentinel data lake tier, and it drops the auto-inferred column-name suffixes
(`_s`, `_d`, `_b`, `_g`, `_t`) that the Data Collector API stamps onto every column.

## When you would reach for it

- You have `_CL` tables and no reliable answer to "what breaks if I migrate this one".
- You know some analytics rules read parser functions rather than tables directly, and a text
  search for the table name therefore under-reports the blast radius.
- You need to hand a migration plan to somebody else. The HTML report is a single self-contained
  file, and each table in it carries the exact command to migrate that table.
- You want to rehearse a cutover with data flowing, to prove there is no ingestion gap, before
  doing it on a table that matters.

You would not reach for it to migrate a table that is not `_CL`. `tableSubType` reads `Classic`
for any table with Custom Fields defined against it, which includes platform tables such as
`AzureDiagnostics`. Those must never be migrated, and both production tools exclude them.

## The three APIs, and which one touches a DCR

This distinction is what the whole migration turns on.

| API | Auth | Endpoint shape | Uses a DCR? |
| --- | --- | --- | --- |
| HTTP Data Collector API (legacy) | Workspace SharedKey (HMAC-SHA256) | `https://<workspaceId>.ods.opinsights.azure.com/api/logs?api-version=2016-04-01` | No. It creates classic tables. |
| Logs Ingestion API (current) | Entra bearer token | `<endpoint>/dataCollectionRules/<immutableId>/streams/Custom-<Table>?api-version=2023-01-01` | Yes, and the identity needs Monitoring Metrics Publisher on the DCR. |
| Tables API migrate operation | Your Az identity | `.../workspaces/<ws>/tables/<table>/migrate` | Neither. It changes what is allowed to write to the table. |

Migration converts a table from the first world to the second. It does not move any sender
across for you.

## What a real migration actually requires

Migrating the table and deploying the DCR is only half the job. To keep a real source ingesting
you must also repoint the sender. Identify which case you are in from the existing rows: a
`SourceSystem == "RestAPI"` value means the Data Collector API (case A); data collected by an
agent points at case B.

### Case A, an application using the HTTP Data Collector API

Three things change in the sending code.

| | Legacy | After cutover |
| --- | --- | --- |
| Endpoint | `<workspaceId>.ods.opinsights.azure.com/api/logs` | the DCR's own `logsIngestion` endpoint |
| Auth | workspace SharedKey (HMAC) | Entra bearer token for a service principal or managed identity holding *Monitoring Metrics Publisher* on the DCR |
| URL | `/api/logs?api-version=2016-04-01` | `<endpoint>/dataCollectionRules/<immutableId>/streams/Custom-<Table>?api-version=2023-01-01` |

The payload JSON stays essentially the same, because it matches the stream schema, and the DCR's
ingestion-time transform reconciles any type differences.
[`Rehearsal/Test-DcrIngestion.ps1`](../../../Tools/ClassicToDcr/Rehearsal/Test-DcrIngestion.ps1)
is a working reference implementation of the new sender.

There is no ingestion gap in this case. The Data Collector API keeps writing to **existing
columns** after migration, so you can migrate, update the application at your own pace, then
retire the old path. It cannot add new columns, and it retires on 2026-09-14, so do not linger.

### Case B, the MMA agent reading text log files

On migration the MMA agent loses the ability to write to the table. Move to the Azure Monitor
Agent with a text-log DCR (`-DcrKind TextLog`, a `logFiles` data source). MMA and AMA cannot
co-write to the same table, so Microsoft's guidance is to give each agent its own table and join
them at query time during the transition, and no data is lost across the cutover. MMA is already
retired, so this move is mandatory regardless.

### The sequence for a real table

1. Identify the source (case A or case B).
2. Run the assess step and work through the reported dependencies, including the indirect ones.
3. Migrate and deploy the DCR (`Invoke-ClassicTableMigration.ps1 -Deploy`).
4. Grant the sender's identity Monitoring Metrics Publisher on the DCR
   (`-GrantIngestionRoleTo <identity>`).
5. Repoint the sender: update the application to the Logs Ingestion API (case A), or deploy AMA
   plus a text-log DCR (case B).
6. Verify the new path lands data. New rows arrive with a blank `SourceSystem`; legacy rows show
   `RestAPI`.
7. Decommission the legacy sender.

## Prerequisites and RBAC

- PowerShell 7.2 or later. `Invoke-TableMigrationReview.ps1` declares `#Requires -Version 7.0`;
  everything else declares 7.2, so 7.2 is the floor for the kit as a whole.
- Modules: `Az.Accounts` (all scripts), plus `Az.OperationalInsights` and `Az.Resources`
  depending on the script. `Invoke-TableMigrationReview.ps1` needs only `Az.Accounts`, because it
  is REST-only over `Invoke-RestMethod` with a token from `Get-AzAccessToken`.
- An authenticated context: `Connect-AzAccount`.

| Identity | Needs | Scope | For |
| --- | --- | --- | --- |
| You | Microsoft Sentinel Reader and Log Analytics Reader | Workspace | Running the assess step |
| You | Log Analytics Contributor | Workspace | Reading shared keys, migrating tables, querying rows |
| You | Microsoft Sentinel Contributor | Workspace | Creating and deleting the dependency fixture's analytics rules |
| You | Contributor | DCR resource group | Deploying the DCR |
| You | Owner or User Access Administrator | DCR | Only when using `-GrantIngestionRoleTo`, which creates a role assignment |
| The sending identity | **Monitoring Metrics Publisher** | **The DCR** | Sending over the Logs Ingestion API |

The sending identity needs nothing on the workspace. A freshly granted role can take a few
minutes to take effect for data-plane calls, so early POSTs may return 401 or 403.

## Do you need a Data Collection Endpoint?

Usually no. Two things give a DCR its own ingestion endpoint: it must be `kind: Direct`, and it
must have been created on or after 2024-03-31, when the service began populating the `endpoints`
property. This toolkit deploys fresh Direct DCRs, so they qualify. It authors them at api-version
`2023-03-11` because that is the minimum schema version that can carry `endpoints`, not because
that api-version grants the endpoint. The live proof is that a successful deploy prints a real
endpoint URL.

You need a Data Collection Endpoint only when:

- the DCR was created before 2024-03-31 (older DCRs have no built-in endpoint, one cannot be
  added, and the DCR therefore has to be replaced), or
- the workspace is behind Private Link (AMPLS), or a sender shares DNS with AMPLS resources, or
- on the AMA text-log path only, you collect Windows Firewall Logs or Prometheus metrics.

If you do need one, pass `-DataCollectionEndpointResourceId <dce>` to the migration script and it
wires `dataCollectionEndpointId` into the DCR.

## Standalone by design

Every script in the kit is fully standalone. Copy `Tools/ClassicToDcr/` to a jump box or an
automation account and it runs with only the Az modules installed. None of them imports the
repository's [`Sentinel.Common`](../../Modules/Sentinel-Common-Module.md) module; each defines its
own `Write-PipelineMessage` (or `Write-Console`) locally, mirroring that module's behaviour, so
nothing else from this repository needs to travel with them.

Two consequences worth knowing:

- Unit tests live in the repository's `Tests/` folder, not in the kit, so the copied folder stays
  runtime-only.
- The standalone constraint is why the assess tool does not carry a full KQL parser. See
  [Table Migration Review, known limits](Table-Migration-Review.md#known-limits).

The folders that do need to travel alongside the scripts are `data/` (the bundled
`solution-mapping.json`) and `Templates/` (the HTML report template). Both are read from
`$PSScriptRoot`, and both degrade with a warning rather than throwing when absent.

## Provenance and licensing

`Invoke-TableMigrationReview.ps1` originated as the standalone
[Sentinel-CLv1-Analyzer](https://github.com/noodlemctwoodle/Sentinel-CLv1-Analyzer) project (MIT).
It is folded in here under this repository's Apache-2.0 licence. Its
`data/solution-mapping.json` is refreshed weekly from the upstream Azure-Sentinel Solutions
Analyzer by
[`.github/workflows/update-solution-mapping.yml`](../../../.github/workflows/update-solution-mapping.yml).
To refresh it by hand, run `node Tools/ClassicToDcr/data/update-solution-mapping.mjs` (Node 18 or
later, standard library only).

## Tests

Unit tests for the whole kit live in the repository's `Tests/` folder and run under
[`Tools/Invoke-PRValidation.ps1`](../../../Tools/Invoke-PRValidation.ps1):

- `Tests/Test-InvokeTableMigrationReview.Tests.ps1`
- `Tests/Test-InvokeClassicTableMigration.Tests.ps1`
- `Tests/Test-NewClassicTableFixture.Tests.ps1`
- `Tests/Test-NewDependencyFixture.Tests.ps1`
- `Tests/Test-DcrIngestion.Tests.ps1`

See [Pester Tests](../../Tests/Pester-Tests.md) for how the suite is run and extended.

## Related

- [Table Migration Review](Table-Migration-Review.md) - full reference for the assess tool
- [Rehearsal Aids](Rehearsal-Aids.md) - full reference for the three rehearsal scripts
- [Deploy Scripts](../../Deploy/Scripts.md#invoke-classictablemigrationps1) - parameter and
  behaviour reference for the migrate tool
- [SDL Migration Workbook Export](../SDL-Migration-Workbook-Export.md) - the Classic V1 sheet in
  that export is the cost-side view of the same tables
- [Custom logs migration](https://learn.microsoft.com/azure/azure-monitor/logs/custom-logs-migrate)
- [Data Collection Rule overview](https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-overview)
- [Logs Ingestion API overview](https://learn.microsoft.com/azure/azure-monitor/logs/logs-ingestion-api-overview)
- [`Invoke-AzOperationalInsightsMigrateTable`](https://learn.microsoft.com/powershell/module/az.operationalinsights/invoke-azoperationalinsightsmigratetable)
