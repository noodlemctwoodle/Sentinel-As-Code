# Rehearsal aids

Three scripts that manufacture test data so you can practise a classic-to-DCR
migration, and prove the assessment tool detects what it claims to, before you
touch anything you care about.

**Scratch workspace only.** Every script here creates real, billable Azure
resources. They exist to be pointed at a throwaway or dedicated test workspace,
never at production. The production tools live one level up in
[`../README.md`](../README.md).

| Script | Purpose | API it uses | Auth |
|---|---|---|---|
| `New-ClassicTableFixture.ps1` | Create a throwaway classic `_CL` table with synthetic data, or stream it continuously | HTTP Data Collector API (legacy) | Workspace SharedKey |
| `Test-DcrIngestion.ps1` | Stream synthetic data into a migrated DCR and confirm it arrives | Logs Ingestion API (new) | Service principal bearer |
| `New-DependencyFixture.ps1` | Build known direct and indirect dependency chains (table, parser, rule) so the assessment tool's detection can be proved. Analytics rules are created **disabled** | Data Collector API + savedSearches + Sentinel alertRules | Workspace SharedKey + your Az identity |

Two constraints apply to everything here, both properties of Azure rather than
of these scripts:

- **Ingestion is billable** and cannot be recalled. The fixtures keep volumes
  tiny on purpose.
- **A classic table cannot be deleted while its subtype is `Classic`.** It has
  to be migrated one-way first, then deleted. Every `-Remove` path mirrors this
  with `-MigrateBeforeRemove` and reports clearly rather than throwing a raw ARM
  error.
- **A deleted `_CL` name will not come back.** Once a classic table has been
  migrated and deleted, re-posting under the same `Log-Type` is accepted
  (HTTP 200) but the table never reappears. Redeploy under a fresh
  `-NamePrefix` rather than reusing the old one.

Commands below are written to be run from the **`Tools/ClassicToDcr`** folder, one
level up, so they read `./Rehearsal/<script>.ps1`. That matches the migration
commands in the main README and the ones the HTML report generates, so you can
paste any of them into the same shell without changing directory.

## Contents

- [Proving the dependency scan](#proving-the-dependency-scan)
- [`.env` for the ingestion tester](#env-for-the-ingestion-tester)
- [Rehearsing end to end](#rehearsing-end-to-end)
- [Rehearsing a cutover (data flowing during migration)](#rehearsing-a-cutover-data-flowing-during-migration)
- [Cleanup](#cleanup)
- [Tests](#tests)

## Proving the dependency scan

A direct reference is easy to find: the rule names the table, and a
word-boundary text match sees it. The dangerous case is **indirect**. An
analytics rule queries a **parser**, and the parser queries the classic table.
The rule never names the table, so migrating it silently breaks a live
detection and a direct-match report says nothing at all.

`Rehearsal/New-DependencyFixture.ps1` manufactures those chains against real
ARM responses, so you can run the assessment tool afterwards and see for
yourself what it does and does not report:

| Scenario | Table | What points at it |
|---|---|---|
| Direct | `SacDepDirect_CL` | one analytics rule naming the table |
| OneHop | `SacDepOneHop_CL` | a parser, plus a rule and a hunting query that name **only the parser** |
| TwoHop | `SacDepTwoHop_CL` | an inner parser, an outer parser over it, and a rule naming **only the outer parser** |
| Cycle | `SacDepCycle_CL` | two parsers that reference each other, one of which reads the table, plus a rule |
| Orphan | `SacDepOrphan_CL` | nothing at all, so over-reporting is visible too |

A "parser" here is a saved search whose `properties.functionAlias` is set.
Other queries invoke it by that alias exactly as if it were a table, which is
precisely what makes the indirect case invisible to a text match.

```powershell
# Always dry-run first. This creates nothing and prints one line per object.
./Rehearsal/New-DependencyFixture.ps1 -ResourceGroupName rg-sentinel -WorkspaceName ws-sentinel -WhatIf
```

```powershell
# Create the fixture. Allow 10 to 20 minutes: the time goes on first-ingestion
# latency, not on the ARM calls.
./Rehearsal/New-DependencyFixture.ps1 -ResourceGroupName rg-sentinel -WorkspaceName ws-sentinel -Confirm:$false
```

```powershell
# Skip the deliberately unresolvable cycle pair if you would rather not leave
# a broken function pair behind.
./Rehearsal/New-DependencyFixture.ps1 -ResourceGroupName rg-sentinel -WorkspaceName ws-sentinel `
    -Scenario Direct, OneHop, TwoHop, Orphan, Hunt -Confirm:$false
```

Then run `Invoke-TableMigrationReview.ps1` against the same workspace and check
what each fixture table reports.

### Safety, and why this one can face a live workspace

Unlike the other two rehearsal aids, this script is designed to survive a
production security workspace. That is deliberate: dependency chains are only
worth proving where the real content lives.

- **Analytics rules are created disabled.** `enabled` is `false`, severity is
  `Informational`, `incidentConfiguration.createIncident` is `false`, and every
  rule query is clamped with `| where 1 == 0` so it returns no rows. Three of
  those four survive somebody flipping `enabled` in the portal by hand.
  Enabling the rules needs `-EnableRules`; removing the zero-row clamp needs a
  second switch, `-EnableRulesWithLiveQuery`. Two independent switches cannot
  be reached by a typo.
- **The alias guard is the important one.** In Log Analytics a function alias
  **shadows a same-named table for every query in the workspace**. Creating an
  alias called `Update` or `SecurityEvent` would silently repoint every live
  detection that reads that table. Preflight refuses any alias that collides
  with a table present in the workspace, with a name in the bundled
  `data/solution-mapping.json`, with a static floor list of core platform
  tables, or with an existing parser the fixture does not own. It refuses
  before it writes anything.
- **Nothing is overwritten.** If a target name already exists and does not
  carry the fixture's ownership marker, the whole run aborts and lists every
  collision. Pick a different `-NamePrefix`.
- **Ingestion is tiny.** `-RecordCount` defaults to 5 per table, roughly 5 KB
  in total. Ingested data is billable, inherits workspace retention and cannot
  be recalled.
- **Everything is behind `ShouldProcess`,** at `ConfirmImpact = 'High'`, so an
  interactive run prompts per object. Pass `-Confirm:$false` for a scripted run.

Two consequences worth knowing before the first run. The **cyclic parser pair**
is permanently unresolvable at query time, which is the point (it proves the
resolver terminates), but it will fail any live query and look broken in the
portal function list. Skip it with `-Scenario` if that is not acceptable. And a
**drift detector that absorbs unmanaged workspace rules into source control**
will pick up the fixture rules if they are still there when it runs, so
complete create, review and teardown inside one working window. The
`[SacFixture:...]` sentinel in each rule description makes anything absorbed
easy to find.

### Removing the dependency fixture

`-Remove` enumerates the workspace and deletes only objects carrying the
ownership marker: a `SacFixture` tag on the saved searches, a derived resource
id or the description sentinel on the analytics rules, and the
`SacFixtureMarker_s` column on the tables. Anything that merely matches the
prefix is reported as `SKIP (not owned)` and left alone. Teardown order is
rules, then saved searches, then tables.

```powershell
# Dry run first. Deleting an analytics rule is instant and has no soft-delete,
# so this is the only undo.
./Rehearsal/New-DependencyFixture.ps1 -ResourceGroupName rg-sentinel -WorkspaceName ws-sentinel -Remove -WhatIf
```

```powershell
# A fixture table is still Classic, and the Tables API cannot delete a Classic
# table, so removal needs the migrate-then-delete dance.
./Rehearsal/New-DependencyFixture.ps1 -ResourceGroupName rg-sentinel -WorkspaceName ws-sentinel `
    -Remove -MigrateBeforeRemove -Confirm:$false
```

Without `-MigrateBeforeRemove` the script reports that the table is still
Classic and stops, rather than surfacing the raw ARM 400. With it, the table is
migrated (**one-way**) and then deleted, and ownership is proved before the
migration, never after.

## `.env` for the ingestion tester

`Rehearsal/Test-DcrIngestion.ps1` reads its service principal from the
environment. The `.env` and its template live in the `Rehearsal/` folder next
to the tester. Copy `Rehearsal/.env.example` to `Rehearsal/.env` (the real
`.env` is gitignored) and fill in:

```
DCR_INGEST_TENANT_ID=<tenant guid>
DCR_INGEST_CLIENT_ID=<app id>
DCR_INGEST_CLIENT_SECRET=<secret>
```

The tester loads the `.env` sitting beside it automatically, so it works
whether you run it from `Rehearsal/` or from this folder as
`./Rehearsal/Test-DcrIngestion.ps1` (resolution order: current directory, then
next to the script). The secret
is held in memory only and never printed. The same `DCR_INGEST_CLIENT_ID`
is what you pass to `Invoke-ClassicTableMigration.ps1 -GrantIngestionRoleTo`.

## Rehearsing end to end

The mechanics on a throwaway table, without concurrent load. Use a **fresh
table name each run**.

```bash
# 1. Seed a classic table (100 rows via the Data Collector API)
./Rehearsal/New-ClassicTableFixture.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01 -RecordCount 100
```

```bash
# 2. Baseline (wait ~10-15 min for a new table to become queryable)
./Invoke-ClassicTableMigration.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01_CL -ListOnly
```

```bash
# 3. Migrate + deploy + grant. Grant value = DCR_INGEST_CLIENT_ID from .env
./Invoke-ClassicTableMigration.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01_CL -Deploy -Force -GrantIngestionRoleTo <DCR_INGEST_CLIENT_ID>
```

```bash
# 4. Verify no data loss: SubType DataCollectionRuleBased, ROWS still >= 100
./Invoke-ClassicTableMigration.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01_CL -ListOnly
```

```bash
# 5. Stream through the DCR. batch N OK = HTTP 204; the post-run poll reports arrived 30/30
./Rehearsal/Test-DcrIngestion.ps1 -DcrName dcr-mytest01 -DcrResourceGroupName rg-scratch -BatchCount 3 -Follow
```

## Rehearsing a cutover (data flowing during migration)

To prove there is no ingestion gap, keep legacy data arriving while you
migrate and bring up the new path. Use a throwaway workspace.

**Terminal A, legacy source, leave running the whole time:**

```bash
./Rehearsal/New-ClassicTableFixture.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01 -Stream -IntervalSeconds 15
```

**Terminal B:** run the migration steps above while A keeps streaming. The
baseline climbs (A is still writing); after migration `ROWS` only goes up,
because the Data Collector API keeps writing to existing columns. Then add
the new path:

```bash
./Rehearsal/Test-DcrIngestion.ps1 -DcrName dcr-mytest01 -DcrResourceGroupName rg-scratch -BatchCount 3 -Follow
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

## Cleanup

Stop any `-Stream` fixtures first, or the next POST recreates the table.

For a table that has been **migrated** (the normal end state), the fixture
removes it cleanly:

```bash
./Rehearsal/New-ClassicTableFixture.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01 -Remove
```

If the table is **still Classic** (an aborted run), the Tables API cannot
delete it. `-Remove` detects this and tells you rather than throwing a raw
error. Add `-MigrateBeforeRemove` to migrate it (one-way) and then delete,
or delete it in the Azure portal:

```bash
./Rehearsal/New-ClassicTableFixture.ps1 -ResourceGroupName rg-scratch -WorkspaceName law-scratch -TableName MyTest01 -Remove -MigrateBeforeRemove
```

Remove the DCR:

```bash
Remove-AzDataCollectionRule -ResourceGroupName rg-scratch -Name dcr-mytest01
```

The dependency fixture has its own teardown, because it creates parsers, a
hunting query and analytics rules as well as tables. The same classic-table
rule applies: without `-MigrateBeforeRemove` a still-Classic table is reported
and left alone rather than throwing a raw ARM error.

```bash
./Rehearsal/New-DependencyFixture.ps1 -ResourceGroupName rg-sentinel -WorkspaceName ws-sentinel -Remove -MigrateBeforeRemove -Confirm:$false
```
## Tests

Unit tests for these scripts live in the repo's `Tests/` folder (run by
`Tools/Invoke-PRValidation.ps1`), not here, so the standalone kit stays
runtime-only:

- `Tests/Test-NewClassicTableFixture.Tests.ps1`
- `Tests/Test-NewDependencyFixture.Tests.ps1`
- `Tests/Test-DcrIngestion.Tests.ps1`
