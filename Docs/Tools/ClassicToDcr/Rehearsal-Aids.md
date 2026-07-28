# Rehearsal Aids

Three scripts under [`Tools/ClassicToDcr/Rehearsal/`](../../../Tools/ClassicToDcr/Rehearsal/) that
manufacture test data, so you can practise a classic-to-DCR migration and prove the assess step
detects what it claims to, before touching anything you care about.

Migration is one-way. That is the whole reason these exist.

| Script | Purpose | API it uses | Auth |
| --- | --- | --- | --- |
| [`New-ClassicTableFixture.ps1`](../../../Tools/ClassicToDcr/Rehearsal/New-ClassicTableFixture.ps1) | Create a throwaway classic `_CL` table with synthetic data, or stream into it continuously | HTTP Data Collector API (legacy) | Workspace SharedKey |
| [`Test-DcrIngestion.ps1`](../../../Tools/ClassicToDcr/Rehearsal/Test-DcrIngestion.ps1) | Stream synthetic data into a migrated DCR and confirm it arrives | Logs Ingestion API (current) | Service principal bearer token |
| [`New-DependencyFixture.ps1`](../../../Tools/ClassicToDcr/Rehearsal/New-DependencyFixture.ps1) | Build known direct and indirect dependency chains (table, parser, rule) so the assess step's detection can be proved | Data Collector API, `savedSearches`, Sentinel `alertRules` | Workspace SharedKey plus your Az identity |

**Scratch workspace only**, with one documented exception. Every script here creates real,
billable Azure resources. `New-ClassicTableFixture.ps1` and `Test-DcrIngestion.ps1` should be
pointed at a throwaway or dedicated test workspace, never production.
`New-DependencyFixture.ps1` is built to survive a live security workspace, because that is where
dependency chains are worth proving, but it still writes real objects. Read
[Safety design](#safety-design-and-why-this-one-can-face-a-live-workspace) before running it.

Commands below are written to be run from `Tools/ClassicToDcr`, one level up, so they read
`./Rehearsal/<script>.ps1`. That matches the commands the HTML report generates, so anything can
be pasted into the same shell without changing directory.

This page is the fuller reference. The on-the-box quick reference is
[`Tools/ClassicToDcr/Rehearsal/README.md`](../../../Tools/ClassicToDcr/Rehearsal/README.md), which
stays because the kit is designed to be copied standalone to a jump box where this `Docs/` tree
will not be present.

## Three Azure behaviours that catch people out

These are properties of Azure, not of these scripts. All three shape how the scripts behave.

| Behaviour | Consequence | How the scripts handle it |
| --- | --- | --- |
| **Ingestion is billable and cannot be recalled.** | Every record posted costs money and inherits workspace retention. | Volumes are kept deliberately tiny. `New-DependencyFixture.ps1` defaults to 5 records per table, roughly 5 KB in total. `New-ClassicTableFixture.ps1` defaults to 50. |
| **A classic table cannot be deleted while its subtype is `Classic`.** | The Tables API refuses the delete outright. | Every `-Remove` path detects the state and reports it plainly rather than surfacing a raw ARM 400. `-MigrateBeforeRemove` migrates the table one-way so it becomes deletable, then deletes it. Ownership is proved *before* the migration, never after. |
| **A deleted `_CL` name will not come back.** | Once a classic table has been migrated and deleted, re-posting under the same `Log-Type` is accepted (HTTP 200) but the table never reappears, so anything depending on it fails to validate. | Redeploy under a fresh `-NamePrefix` (dependency fixture) or a fresh `-TableName` (classic table fixture) rather than reusing the old one. |

One more, which is why the dependency fixture is ordered the way it is: **Sentinel validates
analytics rule KQL against the workspace schema on write.** A rule PUT whose query names a table
or function that does not resolve comes back HTTP 400,
`Failed to resolve table or column expression named`. Saved searches carry no such validation.

## API versions in use

| Script | Surface | Version |
| --- | --- | --- |
| `New-ClassicTableFixture.ps1` | Tables API | `2023-09-01` |
| `New-ClassicTableFixture.ps1` | HTTP Data Collector API | `2016-04-01` |
| `New-DependencyFixture.ps1` | Tables API | `2023-09-01` |
| `New-DependencyFixture.ps1` | `Microsoft.SecurityInsights` (`alertRules`, `onboardingStates`) | `2024-03-01` |
| `New-DependencyFixture.ps1` | `savedSearches` | `2020-08-01` |
| `New-DependencyFixture.ps1` | HTTP Data Collector API | `2016-04-01` |
| `Test-DcrIngestion.ps1` | `Microsoft.Insights/dataCollectionRules` | `2023-03-11` (the version carrying the `endpoints` property) |
| `Test-DcrIngestion.ps1` | Logs Ingestion API | `2023-01-01` |

The Tables, Sentinel and `savedSearches` pins match
[the assess tool](Table-Migration-Review.md#api-versions-in-use). The DCR pin differs on purpose:
the assess tool only lists DCRs to read their transforms, so it uses `2022-06-01`, whereas the
ingestion tester has to read the `endpoints` property and therefore needs `2023-03-11`.

## Proving the dependency scan

A direct reference is easy to find: the rule names the table and a word-boundary text match sees
it. The dangerous case is indirect. An analytics rule queries a **parser**, and the parser queries
the classic table. The rule never names the table, so migrating it silently breaks a live
detection and a direct-match report says nothing at all.

`New-DependencyFixture.ps1` manufactures those chains against real ARM responses, so the detection
can be verified end to end rather than only against synthetic unit-test objects.

### The scenarios

| Scenario | Table | What points at it | Proves |
| --- | --- | --- | --- |
| `Direct` | `{Prefix}Direct_CL` | one analytics rule naming the table | The baseline case still works |
| `OneHop` | `{Prefix}OneHop_CL` | a parser (`{Prefix}OneHopParser`), plus an analytics rule naming **only the parser** | Single-hop indirect resolution |
| `TwoHop` | `{Prefix}TwoHop_CL` | an inner parser (`{Prefix}InnerParser`), an outer parser over it (`{Prefix}OuterParser`), and a rule naming **only the outer** | Multi-hop chains are followed to their end |
| `Cycle` | `{Prefix}Cycle_CL` | two parsers (`{Prefix}CycleA`, `{Prefix}CycleB`) that reference each other, one of which also reads the table, plus a rule | Resolution terminates instead of looping |
| `Orphan` | `{Prefix}Orphan_CL` | nothing at all | Over-reporting is visible too |
| `Hunt` | reuses `{Prefix}OneHop_CL` | a hunting query naming **only the OneHop parser** | A non-rule content type is covered |

A full run creates **five classic tables, five parsers, one hunting query and four disabled
analytics rules**. `-Scenario` selects a subset; selecting `Hunt` implies `OneHop`, because the
hunting query reaches its table through the OneHop parser and would otherwise reference an alias
that does not exist. An empty selection means all of them, and the result is always returned in
the canonical create order.

Two details in the plan are load-bearing:

- **An indirect query must not contain the literal table name anywhere, comments included.** The
  assess tool matches on text, so a table name in a comment would make the fixture quietly prove
  the wrong thing.
- **No analytics rule queries a cycle member.** The cycle pair never resolves, so a rule naming
  one would be rejected outright by the server-side query validator. The Cycle rule therefore
  names the table directly. Resolution is still exercised: walking the table's dependents reaches
  `CycleA`, which reaches `CycleB`, which reaches `CycleA` again.

The cycle needs three parser writes rather than two, because a genuinely cyclic pair cannot be
created in two without one of them momentarily dangling: `CycleA` is written reading only the
table, then `CycleB` over it, then `CycleA` is rewritten to close the loop.

### Ordering, and why it takes ten to twenty minutes

Saved searches are not validated server side. Analytics rules are. So the run goes:

1. Tables, created implicitly by posting to the Data Collector API.
2. A wait for each table to appear through the Tables API, then a further wait for it to become
   **queryable**, which is the gate the rule validator actually cares about. `-TimeoutSeconds`
   budgets this, defaulting to 900.
3. Parsers, in dependency order, so a partial failure never leaves an outer parser pointing at an
   alias that does not exist yet.
4. The hunting query.
5. The analytics rules, last.

Teardown is the reverse: rules, then saved searches, then tables.

Allow ten to twenty minutes for a cold run. The time goes on first-ingestion latency, not on the
ARM calls. If the tables never materialised, every rule returns HTTP 400: check the tables exist
before blaming the rules.

### Safety design, and why this one can face a live workspace

Unlike the other two rehearsal aids, this script is designed to survive a production security
workspace. That is deliberate: dependency chains are only worth proving where the real content
lives.

**Analytics rules are created disabled.** Four independent properties, of which three survive
somebody flipping `enabled` in the portal by hand:

| Property | Value |
| --- | --- |
| `enabled` | `false` |
| `severity` | `Informational` |
| `incidentConfiguration.createIncident` | `false` |
| query clamp | `\| where 1 == 0` appended, guaranteeing zero rows so the `GreaterThan 0` trigger can never be satisfied |

The clamp leaves the table name and parser alias textually present, so the assess tool still sees
exactly what it is meant to see. Enabling the rules needs `-EnableRules`; removing the clamp needs
a second switch, `-EnableRulesWithLiveQuery`. Two independent switches cannot be reached by a typo,
and only that combination can produce an alert. Incident creation stays off either way.

**Alias shadowing is refused before anything is written.** This is the important guard. In Log
Analytics a function alias **shadows a same-named table for every query in the workspace**.
Creating an alias called `Update` or `SecurityEvent` would silently repoint every live detection
that reads that table. Preflight refuses any alias that collides with, in this order of severity:

| Collides with | Why it is refused |
| --- | --- |
| A table present in the live workspace | The worst outcome, and the one that silently rewrites production detections today |
| A table name in the bundled `data/solution-mapping.json`, or in a static floor list of 60 core platform tables | A solution installed later would then be shadowed. The static floor is what keeps the guard useful when the mapping file has not travelled with the script |
| An existing parser the fixture does not own | It would not break a table, but it would silently replace somebody else's query |

Comparison is case insensitive, because the KQL resolver is. The refusal happens before any
write, and nothing is left behind.

**Nothing is overwritten.** If any target name already exists and does not carry the fixture's
ownership marker, the whole run aborts and lists every collision. Pick a different `-NamePrefix`.

**Ownership markers exist before anything can be deleted.** `-Remove` deletes only objects that
carry a marker, never objects that merely match the prefix. The marker is constant across
prefixes on purpose: the prefix says which fixture run an object belongs to, the marker says the
object is a fixture at all.

| Object type | Marker | Where it lives |
| --- | --- | --- |
| Saved searches (parsers, hunting query) | A `SacFixture` tag, plus `SacFixtureRun` and `SacFixtureScenario` | ARM tags on the saved search |
| Analytics rules | A deterministic rule GUID derived from a fixed namespace, plus a `[SacFixture:...]` sentinel in the description | The resource id and the description, so ownership is recomputable rather than merely pattern matched |
| Tables | A `SacFixtureMarker_s` column | The ingested data. Tables carry no ARM tags, and a classic table is created implicitly by the Data Collector API, so the only place a marker can live is the data itself |

Anything matching the prefix without a marker is reported as `SKIP (not owned)` and left alone.
`-RemoveUnmarkedTable` is the escape hatch for a run interrupted before the marker column landed
in the schema. It can delete somebody else's table, so it warns loudly and is never implied by any
other switch.

**Everything is behind `ShouldProcess`**, at `ConfirmImpact = 'High'`, so an interactive run
prompts per object. Pass `-Confirm:$false` for a scripted run. `-WhatIf` prints the full plan, one
line per object, and creates nothing.

### Two consequences to know before the first run

- **The cyclic parser pair is permanently unresolvable at query time.** That is the point, but it
  will fail any live query and look broken in the portal function list. Skip it with `-Scenario`
  if that is not acceptable.
- **A drift detector that absorbs unmanaged workspace rules into source control will pick up the
  fixture rules** if they are still there when it runs. Complete create, review and teardown
  inside one working window, or exclude the prefix on the drift run. The `[SacFixture:...]`
  sentinel in each rule description makes anything absorbed easy to find. See
  [Sentinel Drift Detection](../Sentinel-Drift-Detection.md).

### Running it

```bash
# Always dry-run first. This creates nothing and prints one line per object.
./Rehearsal/New-DependencyFixture.ps1 -ResourceGroupName rg-sentinel -WorkspaceName ws-sentinel -WhatIf
```

```bash
# Create the fixture. Allow 10 to 20 minutes for first-ingestion latency.
./Rehearsal/New-DependencyFixture.ps1 -ResourceGroupName rg-sentinel -WorkspaceName ws-sentinel -Confirm:$false
```

```bash
# Skip the deliberately unresolvable cycle pair.
./Rehearsal/New-DependencyFixture.ps1 -ResourceGroupName rg-sentinel -WorkspaceName ws-sentinel \
    -Scenario Direct,OneHop,TwoHop,Orphan,Hunt -Confirm:$false
```

Then run [`Invoke-TableMigrationReview.ps1`](Table-Migration-Review.md) against the same workspace
and check what each fixture table reports. `Direct` should show a direct rule; `OneHop` and
`TwoHop` should show indirect dependents with a `ViaChain`; `Cycle` should terminate; `Orphan`
should show nothing.

### Removing it

```bash
# Dry run. Deleting an analytics rule is instant and has no soft-delete,
# so this is the only undo.
./Rehearsal/New-DependencyFixture.ps1 -ResourceGroupName rg-sentinel -WorkspaceName ws-sentinel -Remove -WhatIf
```

```bash
# A fixture table is still Classic, and the Tables API cannot delete a Classic
# table, so removal needs the migrate-then-delete dance.
./Rehearsal/New-DependencyFixture.ps1 -ResourceGroupName rg-sentinel -WorkspaceName ws-sentinel \
    -Remove -MigrateBeforeRemove -Confirm:$false
```

Without `-MigrateBeforeRemove` the script reports that the table is still Classic and stops.

### Parameters

| Parameter | Type | Default | Purpose |
| --- | --- | --- | --- |
| `-ResourceGroupName` | string | required | Resource group containing the workspace |
| `-WorkspaceName` | string | required | Log Analytics workspace name |
| `-SubscriptionId` | string | current context | Subscription to operate in |
| `-NamePrefix` | string, `^[A-Za-z][A-Za-z0-9]{2,15}$` | `SacDep` | Stamped on every object. Must start with a letter and be 3 to 16 characters, so it cannot be blanked into a prefix matching everything |
| `-Scenario` | `Direct`, `OneHop`, `TwoHop`, `Cycle`, `Orphan`, `Hunt` | all | Which scenarios to create or remove. `Hunt` implies `OneHop` |
| `-RecordCount` | int, 1 to 100 | `5` | Records posted per fixture table. Ingestion is billable |
| `-OdsEndpointSuffix` | string | `ods.opinsights.azure.com` | Data Collector endpoint suffix. Azure Government: `ods.opinsights.azure.us` |
| `-TimeoutSeconds` | int, 60 to 3600 | `900` | Budget for waiting on each new table to appear and then become queryable |
| `-EnableRules` | switch | off | Create the rules enabled. The zero-row clamp stays on, so they still cannot alert. Warns before writing |
| `-EnableRulesWithLiveQuery` | switch | off | Used with `-EnableRules`. Also removes the clamp. The only combination that can produce an alert |
| `-Remove` | switch | off | Delete the fixture. Marker-gated |
| `-MigrateBeforeRemove` | switch | off | Used with `-Remove`. Migrate a still-Classic table one-way so it becomes deletable |
| `-RemoveUnmarkedTable` | switch | off | Used with `-Remove`. Delete a matching table with no marker column. Can delete somebody else's table |
| `-Reseed` | switch | off | Post records again to a table that already exists and is already marked. Without this the seed is skipped, because re-posting is billable and buys nothing |

RBAC: Log Analytics Contributor on the workspace (shared keys, saved searches, table migrate and
delete) plus Microsoft Sentinel Contributor on the workspace (analytics rules).

## Creating a throwaway classic table

`New-ClassicTableFixture.ps1` exists because the only way to manufacture a genuine classic table
is the HTTP Data Collector API. Posting to it auto-creates a table whose `tableSubType` is
`Classic`, with the `_s` / `_d` / `_b` / `_g` column-name suffixes the API infers from each field's
type. That is exactly the shape the migration script has to cope with.

It fetches the workspace shared key through your authenticated Az session
(`Get-AzOperationalInsightsWorkspaceSharedKey`), so you never paste a key and the key is never
printed. It generates synthetic records with a deliberate mix of types, so the resulting table
exercises the type mapping in the migration script (notably the `guid` case). It signs the request
with HMAC-SHA256 over the documented string-to-hash, posts it, then polls the Tables API until the
table appears and reports its subtype.

The `_CL` suffix is appended by the API, so `-TableName SacMigrationTest` produces the table
`SacMigrationTest_CL`. Passing the suffix is tolerated and stripped before sending.

| Parameter | Type | Default | Purpose |
| --- | --- | --- | --- |
| `-ResourceGroupName` | string | required | Resource group containing the workspace |
| `-WorkspaceName` | string | required | Use a test workspace |
| `-TableName` | string, `^[A-Za-z0-9_]+$` | required | Custom log type to create |
| `-RecordCount` | int, 1 to 10000 | `50` | Records to post, or the batch size when `-Stream` is set |
| `-SubscriptionId` | string | current context | Subscription to operate in |
| `-OdsEndpointSuffix` | string | `ods.opinsights.azure.com` | Azure Government: `ods.opinsights.azure.us` |
| `-TimeoutSeconds` | int, 30 to 1800 | `300` | How long to poll for the table. One-shot seed only |
| `-Stream` | switch | off | Keep posting batches on an interval instead of seeding once. Each batch is signed afresh, because the Data Collector signature is time-dependent. Does not poll for the table |
| `-IntervalSeconds` | int, 1 to 3600 | `10` | Seconds between batches when streaming |
| `-DurationSeconds` | int | none | Stop streaming after this many seconds |
| `-BatchCount` | int | none | Stop streaming after this many batches. With neither limit, streaming runs until Ctrl-C |
| `-Remove` | switch | off | Delete the fixture table. Behind `ShouldProcess` |
| `-MigrateBeforeRemove` | switch | off | Migrate a still-Classic table one-way so it becomes deletable, then delete it |

RBAC: Log Analytics Contributor on the workspace.

One signature detail worth knowing if you are writing your own sender: `ContentLength` in the
string-to-hash must be the UTF-8 **byte** length of the request body, not its character length.
Passing the character length is the classic cause of a 403 signature mismatch on any body
containing multi-byte characters.

## Proving the new ingestion path

`Test-DcrIngestion.ps1` is the last step of a rehearsal and a working reference implementation of
a Logs Ingestion API sender.

It reads everything it needs from the DCR itself under your Az context: the immutable ID, the
`logsIngestion` endpoint, the stream declaration (so generated records match the schema), and the
destination table and workspace for the optional arrival check. It then streams batches on an
interval, authenticated as a **service principal** through the OAuth2 client-credentials flow.
Your own Az session is used only for the read side; only the ingestion POSTs use the service
principal, which needs Monitoring Metrics Publisher on the DCR.

### Configuring the service principal

The tester reads its credentials from the environment. Copy
[`Rehearsal/.env.example`](../../../Tools/ClassicToDcr/Rehearsal/.env.example) to
`Rehearsal/.env` (the real `.env` is git-ignored) and fill in:

```text
DCR_INGEST_TENANT_ID=<tenant guid>
DCR_INGEST_CLIENT_ID=<app id>
DCR_INGEST_CLIENT_SECRET=<secret>
```

Resolution order for a relative `-EnvFile` is the **current directory first, then next to the
script**, so a `.env` kept alongside the toolkit is found whether you run from `Rehearsal/` or
from one level up as `./Rehearsal/Test-DcrIngestion.ps1`. An absolute path is used as given.
Values already present in the environment are never overwritten, so an explicit export always
beats the file. Explicit parameters beat both. The fallback env var names `AZURE_TENANT_ID`,
`AZURE_CLIENT_ID` and `AZURE_CLIENT_SECRET` are also accepted.

The secret is held in memory only and never printed. The same `DCR_INGEST_CLIENT_ID` is what you
pass to `Invoke-ClassicTableMigration.ps1 -GrantIngestionRoleTo`.

### Arrival confirmation

During streaming the per-batch `arrived` counts are near zero. That is not a failure: Logs
Ingestion is asynchronous, so rows have not surfaced yet by the time the next batch is prepared.

| Signal | Meaning |
| --- | --- |
| HTTP 204 per batch | The authoritative success signal. Auth, endpoint and schema are all correct |
| Per-batch `arrived: N` during `-Follow` | Informational only, and expected to lag |
| Post-run poll, `arrived N / N` | The real arrival confirmation. It waits out ingestion latency up to `-ArrivalTimeoutSeconds` and reports the final count |

| Parameter | Type | Default | Purpose |
| --- | --- | --- | --- |
| `-DcrName` | string | required | Deployed DCR to send to |
| `-DcrResourceGroupName` | string | required | Resource group containing the DCR |
| `-TenantId`, `-ClientId` | string | from environment | Sending service principal |
| `-ClientSecret` | SecureString | from environment | Kept out of shell history and the process argument list |
| `-EnvFile` | string | `.env` | Dotenv file of `KEY=VALUE` lines. Ignored if it does not exist |
| `-StreamName` | string | inferred | Input stream, for example `Custom-MyApp_CL`. Optional when the DCR declares exactly one stream, which is the usual case for a migrated table |
| `-BatchSize` | int, 1 to 1000 | `10` | Records per POST. Keep the JSON body under 1 MB |
| `-IntervalSeconds` | int, 1 to 3600 | `5` | Seconds between batches |
| `-DurationSeconds` | int | none | Stop after this many seconds |
| `-BatchCount` | int | none | Stop after this many batches. With neither limit, streaming runs until Ctrl-C |
| `-Follow` | switch | off | After each batch, query the destination table for rows from this run |
| `-ArrivalTimeoutSeconds` | int, 0 to 1800 | `300` | Budget for the post-run arrival poll |
| `-GrantIngestionRole` | switch | off | Grant the service principal Monitoring Metrics Publisher on the DCR if it lacks it. Off by default: the script otherwise checks and prints the command for you to run |
| `-AuthorityHost` | string | `https://login.microsoftonline.com` | Azure Government: `https://login.microsoftonline.us` |
| `-IngestionAudience` | string | `https://monitor.azure.com` | Azure Government: `https://monitor.azure.us` |
| `-SubscriptionId` | string | current context | Subscription to operate in |

RBAC: your Az identity needs Reader on the DCR, plus Log Analytics Reader on the workspace when
using `-Follow`. The service principal needs Monitoring Metrics Publisher on the DCR. A freshly
granted role can take a few minutes to take effect for data-plane calls, so expect 401 or 403
immediately after `-GrantIngestionRole`.

## Rehearsing end to end

The mechanics on a throwaway table, without concurrent load. Use a **fresh table name each run**:
reusing a just-deleted name can hit retained-schema conflicts, and a deleted `_CL` name does not
come back.

```bash
# 1. Seed a classic table (100 rows via the Data Collector API)
./Rehearsal/New-ClassicTableFixture.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01 -RecordCount 100
```

```bash
# 2. Baseline. Wait 10 to 15 minutes for a new table to become queryable.
#    SubType = Classic, ROWS = the row count
./Invoke-ClassicTableMigration.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01_CL -ListOnly
```

```bash
# 3. Migrate, deploy, grant. Grant value = DCR_INGEST_CLIENT_ID from .env
./Invoke-ClassicTableMigration.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01_CL -Deploy -Force -GrantIngestionRoleTo <DCR_INGEST_CLIENT_ID>
```

```bash
# 4. Verify no data loss: SubType now DataCollectionRuleBased, ROWS not lower
./Invoke-ClassicTableMigration.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01_CL -ListOnly
```

```bash
# 5. Stream through the DCR. "batch N OK" is HTTP 204; the post-run poll reports arrived 30/30
./Rehearsal/Test-DcrIngestion.ps1 -DcrName dcr-mytest01 -DcrResourceGroupName rg-scratch -BatchCount 3 -Follow
```

## Rehearsing a cutover with data flowing

To prove there is no ingestion gap, keep legacy data arriving while you migrate and bring up the
new path. Throwaway workspace only.

Terminal A, the legacy source, left running the whole time:

```bash
./Rehearsal/New-ClassicTableFixture.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01 -Stream -IntervalSeconds 15
```

Terminal B: run the migration steps above while A keeps streaming. The baseline climbs, because A
is still writing; after migration `ROWS` only goes up, because the Data Collector API keeps
writing to existing columns. Then start the new path with `Test-DcrIngestion.ps1`.

Confirm both sources landed:

```kusto
MyTest01_CL
| extend Path = iff(SourceSystem == "RestAPI", "Legacy (Data Collector API)", "New (DCR / Logs Ingestion)")
| summarize count() by Path, bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

Legacy rows show `SourceSystem == "RestAPI"`; new-path rows arrive with a **blank**
`SourceSystem`. Logs Ingestion is asynchronous, so give new rows a few minutes to surface. Seeing
both across the migration timestamp with no gap is the clean-cutover proof. To complete the
cutover, stop terminal A with Ctrl-C: legacy goes quiet and the DCR path carries on.

## Cleanup

Stop any `-Stream` fixture first, or the next POST recreates the table.

```bash
# Migrated table (the normal end state)
./Rehearsal/New-ClassicTableFixture.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01 -Remove
```

```bash
# Still-Classic table (an aborted run). Migrates one-way, then deletes.
./Rehearsal/New-ClassicTableFixture.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01 -Remove -MigrateBeforeRemove
```

```bash
# The DCR
Remove-AzDataCollectionRule -ResourceGroupName rg-scratch -Name dcr-mytest01
```

The dependency fixture has its own teardown, because it creates parsers, a hunting query and
analytics rules as well as tables. See [Removing it](#removing-it).

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `ROWS: unknown` on a new table | First-ingestion query availability lags 10 to 15 minutes. The table is treated as not empty and is not skipped. Wait and re-check |
| `arrived: 0` while streaming | Ingestion latency. The HTTP 204 is the real success; the post-run poll confirms arrival |
| `InvalidOutputTable` on deploy | The table is still `Classic`. Migrate first, that is, drop `-SkipTableMigration` |
| A `-Stream` fixture recreates a deleted table | Stop the stream first, then delete |
| Cannot delete a classic table | The Tables API forbids deleting a `Classic` table. Add `-MigrateBeforeRemove` |
| A deleted `_CL` name will not come back | Redeploy under a fresh `-NamePrefix` or `-TableName` rather than reusing the old one |
| Fixture rules fail with the tables missing | The rules are created last on purpose, because Sentinel validates rule KQL against the workspace schema on write. If the tables never materialised, every rule returns 400. Check the tables exist before blaming the rules |
| Dependency fixture refuses to run: alias collision | An alias would shadow a real table for every query in the workspace. Choose a different `-NamePrefix`. Nothing was written |
| Dependency fixture refuses to run: name collision | A target name exists and does not carry the fixture marker. Nothing is ever overwritten. Choose a different `-NamePrefix` |
| Rule PUT fails with `Failed to resolve table or column expression named` | Sentinel validates rule KQL server side and the table or parser has not propagated yet. The script retries this case for a bounded window; if it gives up, re-run once the table is queryable |
| The cycle parsers fail every query | Expected. The pair is deliberately unresolvable, to prove dependency resolution terminates. Skip it with `-Scenario` |
| HTTP 403 from the Data Collector API | Usually a signature mismatch. `ContentLength` must be the UTF-8 byte length of the body, not the character length |

## Tests

Unit tests live in the repository's `Tests/` folder, not in the kit, so the standalone folder
stays runtime-only:

- `Tests/Test-NewClassicTableFixture.Tests.ps1`
- `Tests/Test-NewDependencyFixture.Tests.ps1`
- `Tests/Test-DcrIngestion.Tests.ps1`

## Related

- [Classic to DCR Migration Toolkit](Classic-to-DCR-Toolkit.md) - overview, prerequisites, RBAC,
  the retirement timeline
- [Table Migration Review](Table-Migration-Review.md) - the tool these fixtures exist to prove
- [Deploy Scripts, `Invoke-ClassicTableMigration.ps1`](../../Deploy/Scripts.md#invoke-classictablemigrationps1) -
  the migrate tool used in the rehearsal steps above
- [Sentinel Drift Detection](../Sentinel-Drift-Detection.md) - the drift detector that will absorb
  fixture rules left in place
- [HTTP Data Collector API](https://learn.microsoft.com/azure/azure-monitor/logs/data-collector-api)
- [Logs Ingestion API overview](https://learn.microsoft.com/azure/azure-monitor/logs/logs-ingestion-api-overview)
- [Log Analytics functions](https://learn.microsoft.com/azure/azure-monitor/logs/functions)
