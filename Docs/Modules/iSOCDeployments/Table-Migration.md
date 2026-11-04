# Classic table migration: the review

Two commands assess the classic (CLv1) custom log tables in a workspace
before any is migrated to a DCR-based table: what each table is, what
depends on it, and which Content Hub solution covers it.

| Command | Replaces |
| --- | --- |
| `Get-iSOCTableMigrationImpact` | The assessment in `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` |
| `Export-iSOCTableMigrationReport` | Its CSV, JSON and HTML reports |

They replace the script at the 26.11.0 cut-over. `Invoke-iSOCClassicTableMigration`,
which replaces `Tools/ClassicToDcr/Invoke-ClassicTableMigration.ps1`, is
the next port; until then the migration is the script's.

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

Both are read-only against Azure, so safe to run against production; the
export writes only local files. They need Az.Accounts and a sign-in that
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

## From the script

| `Invoke-TableMigrationReview.ps1` | The module |
| --- | --- |
| `-SubscriptionId`, `-ResourceGroupName`, `-WorkspaceName`, or a prompt for each | `Connect-iSOCWorkspace -SubscriptionId -ResourceGroup -WorkspaceName` first (or `-Context`) |
| `-MaxParserChainDepth` | `Get-iSOCTableMigrationImpact -MaxParserChainDepth` |
| `-OutputPath` | `Export-iSOCTableMigrationReport -Path` |
| `-NonInteractive` | Not needed: nothing prompts |
| The review it returned, with `OutputPath` | The review from `Get-iSOCTableMigrationImpact`; the files from the export |

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
the same data. `MIGRATION.md` edits E35 and E36 list how the commands
differ from the script.

Release 26.11.0 also fixes the script (0.2.2): it listed workbooks without
`canFetchContent`, so it never found a workbook that depended on a classic
table.
