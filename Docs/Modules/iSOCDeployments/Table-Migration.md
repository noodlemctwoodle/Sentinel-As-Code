# Classic table migration

Three commands take a classic (CLv1, MMA or Data Collector API) custom log
table to a DCR-based one. The review finds what each table is, what
depends on it and which Content Hub solution covers it; the migration
converts the table and writes, and can deploy, its data collection rule.

| Command | Replaces |
| --- | --- |
| `Get-iSOCTableMigrationImpact` | The assessment in `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` |
| `Export-iSOCTableMigrationReport` | Its CSV, JSON and HTML reports |
| `Invoke-iSOCClassicTableMigration` | `Tools/ClassicToDcr/Invoke-ClassicTableMigration.ps1` |

They replace the scripts at the 26.11.0 cut-over. The rehearsal aids
under `Tools/ClassicToDcr/Rehearsal/` are ported next.

```powershell
Import-Module ./Modules/iSOCDeployments
Connect-AzAccount
Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel

# Assess, and write the five reports.
Get-iSOCTableMigrationImpact | Export-iSOCTableMigrationReport -Path ./migration-report

# Or keep the review and look at it.
$review = Get-iSOCTableMigrationImpact
$review.Impacts | Where-Object TotalAffected -gt 0 | Select-Object TableName, TotalImpacted, TotalIndirect
```

The review is read-only against Azure, so safe to run against production;
the export writes only local files. The migration is not: see
[The migration](#the-migration). They need Az.Accounts and a sign-in that
can read the workspace and, across the subscription, workbooks, data
collection rules and Logic Apps.

## What the review does

1. **Discover.** The workspace's tables, from one call: the migration
   candidates are those of type CustomLog and sub type Classic, except
   AzureDiagnostics. Every table and column name is kept for the alias
   guard below.
2. **Assess.** Each table's dependents across analytics rules, hunting
   queries, parsers, saved searches, Sentinel workbooks, Logic Apps and
   data collection rules. A **direct** dependent names the table in its own
   KQL, matched as a whole word so `MyApp_CL` does not match `MyApp_CL_v2`.
   An **indirect** one reaches it only through one or more parser
   functions: a rule that reads `OfficeActivityParser` never names
   `OfficeActivity_CL`, and a search for the table name misses it. Each
   indirect dependent carries its chain (`rule -> parser -> table`).
3. **Map.** Each table to its Content Hub solutions, from the
   Azure-Sentinel Solutions Analyzer mapping the module ships, with whether
   each is in the catalogue and installed, and each solution's data
   connector classified as CCF, AzureFunctions, AMA, Platform, Agent or
   Legacy. A Legacy or Azure Functions connector with no CCF version needs
   rebuilding, not repointing.

Workbooks are listed with their content (`canFetchContent`); without it
the list carries no `serializedData` and no workbook has a query to scan.
One the list still returns without content is read on its own.

### Where the parser chains stop

A parser's alias is followed only when it is safe to match by name. It is
not followed when it is empty, not a plain KQL name, under four
characters, a KQL keyword or scoping function or a column every table
has, or the same as a table or column in the workspace (a query naming
`Update` far more likely means the Update table). Each alias not followed
is listed with the reason and the content that names it, which has to be
checked by hand; a parser that reads a classic table through such an alias
is an unresolved bridge on that table. Before names are read, comments,
string literals, references into other workspaces, member access,
assignment targets and `let` bindings are taken out of each query; the
match is case-sensitive, as KQL names are. A playbook is read only for
strings shaped like a query, so an alias used as a JSON key is not a
reference. Data collection rules are never followed through parsers: a
transform cannot call a workspace function. Chains deeper than
`-MaxParserChainDepth` (default 10) are reported as truncated, and an
alias named by a large share of the workspace is reported as suspect.

## The result

`Get-iSOCTableMigrationImpact` returns an
`iSOCDeployments.TableMigrationReview`:

| Property | Meaning |
| --- | --- |
| `Context` | `SubscriptionId`, `ResourceGroupName` and `WorkspaceName` |
| `ClassicTables` | Each table: name, type, sub type, plan, retention, column count, resource id |
| `Impacts` | Each table's dependents: a direct and an `Indirect` list per content type, `TotalImpacted` (direct), `TotalIndirect`, `TotalAffected`, `ChainTruncated` and `UnresolvedBridges` |
| `SolutionMatches` | Each table's Content Hub solutions and their connector classification |
| `AliasResolution` | The aliases followed, those not and why, and the fan-out warnings |
| `DirectCount`, `IndirectCount` | The dependents across every table |

`Export-iSOCTableMigrationReport` writes, into `-Path` (default
`./migration-report`), and returns as files:

| File | What it holds |
| --- | --- |
| `tables.csv` | A row per classic table |
| `impact.csv` | A row per dependent: `TableName`, `ContentType`, `Name`, `ResourceId`, `DependencyKind`, `Via`, `ViaChain`, `Depth`, `ChainTruncated` |
| `solution-matches.csv` | A row per table and solution |
| `report.json` | All of it, with the alias resolution |
| `report.html` | A self-contained page to share: each table's dependents, where the lists stop, its solutions, and the commands to preview and migrate it with the module |

A review with no classic tables writes nothing; `-WhatIf` writes nothing.

## The migration

```powershell
# Start here: every classic table, its columns, rows and volume. Changes nothing.
Invoke-iSOCClassicTableMigration -AllClassicTables -ListOnly

# The rule template for one table, leaving the table alone.
Invoke-iSOCClassicTableMigration -TableName MyApp_CL -SkipTableMigration -Path ./Infra/dcr

# Migrate it (asking first), deploy its rule, and let the sender post to it.
Invoke-iSOCClassicTableMigration -TableName MyApp_CL -Deploy -GrantIngestionRoleTo $senderAppId
```

A classic table cannot be the destination of a data collection rule
(InvalidOutputTable); the supported fix is the Tables API's migrate
operation, which **cannot be undone**: the Log Analytics agent can no
longer write to the table, and Custom Fields defined against it stop
receiving data. Migrate the agents first. For each table:

1. **Discover**: its sub type, columns, rows over 90 days and billable
   volume. Emptiness is judged by rows, which are counted directly; Usage
   lags by hours. A table whose rows cannot be counted is not called empty.
2. **Migrate** a Classic table, behind ShouldProcess and a confirmation
   that `-Force` (or `-Confirm:$false`) skips, then read it again.
   `-SkipTableMigration` leaves the tables alone.
3. **Export** a rule template to `-Path/<rule>.json`: the columns a stream
   can declare (reserved, hidden and underscore-led columns are left out
   and warned of, since they stop receiving data; guid is declared string),
   and a transform that casts each column back to the table's type. The
   same table always writes the same file.
4. **Deploy**, with `-Deploy`: refused while the table is still Classic;
   then the rule's immutable id and logs ingestion endpoint are read, and
   `-GrantIngestionRoleTo` gives each identity (an application id or any
   principal's object id) Monitoring Metrics Publisher on the rule. A grant
   that cannot be made is a warning with the command to run.

`-AllClassicTables` takes only `_CL` tables (a platform table reports
Classic once Custom Fields are made against it) and skips those with no
rows unless `-IncludeEmptyTables`. `-DcrKind TextLog` (with `-Platform`,
`-FilePattern`, `-LogFormat`) makes an Azure Monitor Agent file collection
rule, whose transform is a placeholder to edit before machines are
associated.

It needs Az.Accounts, Az.OperationalInsights for the row counts and volume
(`Test-iSOCDeploymentPrerequisite -Step Migrate`), Az.Resources with
`-Deploy`, Log Analytics Contributor on the workspace, Contributor on the
rule's resource group, and, to grant, Owner or User Access Administrator
on the rule.

It returns an `iSOCDeployments.TableMigrationRun`: `Tables` (the
inventory), `Results` (per table: `TableName`, `SubTypeAfter`, `Migrated`,
`RowCount`, `GB90d`, `DcrName`, `TemplatePath`, `Deployed`, `ImmutableId`,
`Endpoint`, `Granted`, `Error`), `Migrated`, `Deployed`, `Failed` and
`ExitCode` (1 when any table failed).

## From the scripts

| `Invoke-TableMigrationReview.ps1` | The module |
| --- | --- |
| `-SubscriptionId`, `-ResourceGroupName`, `-WorkspaceName`, or a prompt for each | `Connect-iSOCWorkspace -SubscriptionId -ResourceGroup -WorkspaceName` first (or `-Context`) |
| `-MaxParserChainDepth` | `Get-iSOCTableMigrationImpact -MaxParserChainDepth` |
| `-OutputPath` | `Export-iSOCTableMigrationReport -Path` |
| `-NonInteractive` | Not needed: nothing prompts |
| The review it returned, with `OutputPath` | The review from `Get-iSOCTableMigrationImpact`; the files from the export |

| `Invoke-ClassicTableMigration.ps1` | `Invoke-iSOCClassicTableMigration` |
| --- | --- |
| `-SubscriptionId`, `-ResourceGroupName`, `-WorkspaceName` | `Connect-iSOCWorkspace -SubscriptionId -ResourceGroup -WorkspaceName` first (or `-Context`) |
| `-OutputDirectory` | `-Path` |
| Every other parameter | The same |
| The result list, the listing under `-ListOnly`, or nothing | The run |

The solution mapping and the report template ship in the module, under
`Resources/ClassicToDcr/`. The mapping is the script's file, which the
weekly refresh writes; a test holds the two identical until the refresh
writes the module's at cut-over. The template is the script's but for the
commands it offers (`Connect-iSOCWorkspace`, then
`Invoke-iSOCClassicTableMigration -ListOnly` or `-Deploy`), its version
badge and its footer, and a test holds it to that.

`Tests/iSOCDeployments/TableMigration.Tests.ps1` runs each helper beside
the script's own over the same inputs, the analysis beside the script's
over a stand-in workspace at three chain depths, and the script itself
unchanged in a child pwsh, its Az commands and `Invoke-RestMethod` stood in
for, beside the commands over the same workspace: the five files must hold
the same data. `Tests/iSOCDeployments/ClassicTableMigration.Tests.ps1` runs
`Invoke-ClassicTableMigration.ps1` unchanged the same way, its Az cmdlets
stood in for over a workspace whose tables turn DCR-based as they are
migrated, beside the command, across listing, every classic table with
deployment and grants, named tables, templates only, text log rules, a
transform, `-WhatIf` and an unreadable Usage table: the same migrations,
deployments and grants in order, the same template files and the same
result per table. `MIGRATION.md` edits E35 to E37 list how the commands
differ from the scripts.

Release 26.11.0 also fixes both scripts. The review (0.2.2) listed
workbooks without `canFetchContent`, so it never found a workbook that
depended on a classic table. The migration (2.0.2) built each template's
top level as a hashtable, whose key order changes from one PowerShell
process to the next, so a template written again differed from the one
committed.
