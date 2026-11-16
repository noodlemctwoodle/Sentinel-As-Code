# Sentinel Data Lake Migration Workbook Export

The `SdlMigrationExport` PowerShell module and its one command,
`Export-SdlMigrationWorkbook`, mirror every query behind the **Sentinel Data
Lake Migration** workbook and write them to a single multi-sheet Excel file
(`.xlsx`), one named worksheet per dataset. It exists because the Azure portal
cannot bundle a multi-grid workbook into one Excel export (each grid only
exports its own sheet), so migration planning across a dozen-plus grids means
a dozen-plus separate downloads. The command produces the whole book in one
read-only pass against the workspace.

> **Deprecated (version 0.2.0).** This module is frozen and will be replaced
> by the `iSOCDeployments` PowerShell module. Until the module takes over this
> function it receives correctness fixes only, and the command prints a
> deprecation warning at the start and end of every run. Exports taken from
> versions before 0.2.0 are **not comparable** with 0.2.0 output: the default
> lake prices, the XDR, Query-Weighted and Alert Activity sheets and the
> rule-reference counts all changed (see [Changes in 0.2.0](#changes-in-020)).
> Before 0.2.0 it was a standalone script; it is now a module (see
> [Running it](#running-it)).

| What | Where |
| --- | --- |
| Module | [`Content/Workbooks/SentinelDataLake/SdlMigrationExport/`](../../Content/Workbooks/SentinelDataLake/SdlMigrationExport) (manifest `SdlMigrationExport.psd1`, [README](../../Content/Workbooks/SentinelDataLake/SdlMigrationExport/README.md)) |
| Public command | [`Public/Export-SdlMigrationWorkbook.ps1`](../../Content/Workbooks/SentinelDataLake/SdlMigrationExport/Public/Export-SdlMigrationWorkbook.ps1) |
| Internal functions | [`Private/`](../../Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private), one function per file |
| Tests | [`Tests/Test-ExportSdlMigrationWorkbook.Tests.ps1`](../../Tests/Test-ExportSdlMigrationWorkbook.Tests.ps1) |
| Companion workbook | [`Content/Workbooks/SentinelDataLake/workbook.json`](../../Content/Workbooks/SentinelDataLake/workbook.json) |
| Workbook metadata | [`Content/Workbooks/SentinelDataLake/metadata.json`](../../Content/Workbooks/SentinelDataLake/metadata.json) (`sourceId: SentinelDataLake`) |
| iSOC Blueprint coverage of Lake | [`Docs/Modules/iSOCBlueprint/Sentinel-Data-Lake-Coverage.md`](../Modules/iSOCBlueprint/Sentinel-Data-Lake-Coverage.md) |

`Content/Workbooks/SentinelDataLake/` holds the workbook (`workbook.json` and
`metadata.json`, deployed like any other custom workbook by the Workbooks stage
of [`Deploy/content/Deploy-CustomContent.ps1`](../../Deploy/content/Deploy-CustomContent.ps1)).
All of the exporter's code lives in the `SdlMigrationExport/` subfolder. The
deploy only reads the workbook files, so nothing in it is deployed. The module
is **not** part of the deploy or the Blueprint pipeline; it is an on-demand
analyst tool that you run by hand when you want the Lake migration analysis as
a spreadsheet.

## Layout

| Path | Contents |
| --- | --- |
| `SdlMigrationExport.psd1` | Manifest: version, the one exported function by name, dependencies |
| `SdlMigrationExport.psm1` | Sets strict mode, loads `Private/` and `Public/`, exports `Export-SdlMigrationWorkbook` by name (never a wildcard) |
| `Public/Export-SdlMigrationWorkbook.ps1` | The only exported command: parameters and the six steps |
| `Private/Azure/` | `Assert-SdlPrerequisite` (modules, token check, automatic sign-in), `Test-SdlAzureToken`, `Invoke-SdlArmRequest` (GET only, transient-only retry), `Get-SdlArmList` (paging), `Invoke-SdlKqlQuery`, `Get-SdlBaseUri`, `Get-SdlPropertyValue` (strict-mode-safe reads) |
| `Private/Console/` | `Write-SdlStatus` (information stream, not `Write-Host`), `Write-SdlDeprecationNotice` |
| `Private/Kql/` | `Get-SdlPricingRate`, `Get-SdlPricingLet`, `Get-SdlClassificationLet`, `Get-SdlCategoryKql`, `Assert-SdlSetting`, `Expand-KqlTemplate`, `Format-KqlNumber`, `ConvertTo-KqlList`, `Get-KqlCodeText`, `Test-KqlIdentifier`, `Test-KqlCall` |
| `Private/Inventory/` | `Get-SdlTableInventory`, `Get-SdlRuleInventory`, `Get-SdlFunctionInventory` |
| `Private/Rule/` | `Get-SdlRuleBody`, `Get-SdlFunctionReach`, `Get-SdlRuleReference`, `Get-SdlRuleTableSummary`, `Get-SdlIndirectionReport`, `Get-SdlFunctionTableReport`, `Get-SdlFunctionRuleMap` |
| `Private/Report/` | One function per sheet query: Migration, Query-Weighted, XDR, Exclusions, Top 10, Deprecation, Classic V1, Alert Activity |
| `Private/Workbook/` | `Write-SdlWorkbook` (supports `-WhatIf`), `Resize-SdlColumn`, `Limit-SdlExcelCell`, `Resolve-SdlOutputPath`, `Get-SdlPricingAssumption` |
| `README.md` | Usage, requirements and layout of the module |

Every function is an advanced function. Connection details and pricing
settings are passed to each function as parameters (no script or global
state). `-WhatIf` runs every query but writes no file; `-Verbose` traces each
ARM call and KQL query.

### Coding standard

The module follows the repository's PowerShell coding standard. How each part is met:

| Standard | How it is met |
| --- | --- |
| PSScriptAnalyzer on every file in every PR pipeline, errors fail the run | [`Tests/Test-PSScriptAnalyzer.Tests.ps1`](../../Tests/Test-PSScriptAnalyzer.Tests.ps1) lints every PowerShell file in the repository with the profiles in [`Tests/PSScriptAnalyzer/`](../../Tests/PSScriptAnalyzer) (see [PSScriptAnalyzer lint](../Tests/Pester-Tests.md#psscriptanalyzer-lint)). This module's files have no baseline entries, so they must stay clean. Both PR pipelines install PSScriptAnalyzer 1.25.0; in CI the lint fails, not skips, when the analyser is missing, and any analyser error fails it |
| Built-in rules named by the standard | All run, plus the opt-in ones: OTBS braces, consistent whitespace and indentation, aligned hashtables, lowercase keywords and operators, single-quoted constant strings, no semicolon line terminators, comment help on every function |
| Rules with no built-in equivalent | Checked in [`Tests/Test-ExportSdlMigrationWorkbook.Tests.ps1`](../../Tests/Test-ExportSdlMigrationWorkbook.Tests.ps1) through the AST and tokenizer: one function per file named after the file, files ASCII (UTF-8 without a BOM), no backtick line continuation, comments start with a capital, no space just inside parentheses, a uniform function header and `param (` placement, blank lines between parameters, mandatory parameters first, named arguments at any count, no `+=`, a 300-line cap. Command-name casing comes from the repository lint's formatting pass |
| Modular scripting | Module with a manifest, a root module, one exported function named explicitly, `Private/` helpers, a README, Pester tests, `Import-Module` to load it |
| Advanced functions, `PositionalBinding = $false`, comment help | Every function; checked per file |
| Error handling | `$ErrorActionPreference = 'Stop'` in the command; specific exception types where they are known (`IOException` for a locked output file, `InvalidOperationException` wrapping a failed query with the workspace name); `-ErrorVariable` where an error is deliberately not fatal; tests that trigger each error path |
| Output and logging | Progress on the information stream, details on `Write-Verbose` |
| Comments | Explain reasoning and decisions, not what a command does |

One limit of the checks: the positional check cannot see a positional
argument placed straight after a switch (`-Force 'x'`), because without
resolving the command it cannot tell a switch from a parameter that takes a
value. PSScriptAnalyzer's own threading crash (#1708) and how the lint avoids
it are described in [PSScriptAnalyzer lint](../Tests/Pester-Tests.md#psscriptanalyzer-lint).

## What it produces

The output is a single `.xlsx` written by the
[`ImportExcel`](https://github.com/dfinke/ImportExcel) module. The worksheet
set is defined by the `$sheets` ordered dictionary near the bottom of the
script (the `#region Write xlsx` block). There are **15 worksheets**, always
written in this order:

| Sheet | Backing variable | Contents |
| --- | --- | --- |
| Migration Report | `$migrationReport` | Per-table classification: billable GB/month, Analytics vs Lake monthly cost, monthly saving, saving %, category, plan, ingestion mode, recommendation, status |
| Per-Table Rule Refs | `$perTableRuleSummary` | For each table, the count of enabled analytic rules that reference it, counted by ARM rule ID so rules sharing a display name are not merged (`EnabledRuleCount`, split into `DirectRuleCount` and `ViaFunctionRuleCount`), the rule kinds, and up to five example rule names |
| Exclusions | `$exclusionsRows` | Tables that cannot move to Lake (not supported, UEBA, Sentinel feature dependency, system table, Classic V1, Auxiliary plan, Basic plan) with a plain-English reason. Read off the Migration Report, so the two always agree |
| Deprecation Warnings | `$deprecationRows` | Microsoft-announced table retirements (for example the legacy `ThreatIntelligenceIndicator` table) with replacement and urgency |
| Classic V1 Tables | `$classicV1Rows` | `_CL` tables still on the legacy MMA / HTTP Data Collector ingestion path, enriched with billable GB/month |
| Top 10 Savings | `$top10Rows` | The ten highest-impact migration candidates (Migration Report rows with status `Eligible`) ranked by projected monthly saving |
| Rules Inventory | `$rulesInventory` | Every analytic rule in the workspace (an `Enabled` column distinguishes enabled from disabled), with kind, severity, tactics, techniques, cadence, and query text |
| Indirection Rules | `$indirection` | Rules whose query uses ASIM parsers, `_GetWatchlist()`, `externaldata()`, or a custom workspace function (the indirect table references a naive scan would miss) |
| Workspace Functions | `$workspaceFunctions` | Saved KQL functions in the workspace (`savedSearches` entries that carry a `functionAlias`) |
| Fns Wrapping Tables | `$functionsWrappingTables` | Which workspace functions reference which tables |
| Function -> Rules | `$functionRuleMap` | Which enabled rules call which workspace functions |
| Query-Weighted | `$queryWeightedRows` | `LAQueryLogs`-based per-table cost model that weights Lake query cost by observed query activity: queries in the window (human and automated), monthly scan GB, Analytics vs Lake total cost, recommendation. Tables nobody queried are kept with zero query cost |
| XDR Cost Model | `$xdrRows` | Cost model for the 21 core Defender XDR tables present in the workspace (optional, skipped when `-XdrLookbackDays 0`): rows, billed GB/month from `Usage` and from the records' `_BilledSize` side by side, which one was costed (`Basis`), Analytics vs Lake cost and saving |
| Alert Activity | `$alertActivityRows` | `SecurityAlert` per-alert-name statistics: alert count, high (including Critical), medium and low counts, last seen, tactics, criticality |
| Pricing Assumptions | `$pricingAssumptions` | Every pricing and window input used by the export, so the numbers are reproducible |

Any dataset that returns no rows (for example Query-Weighted when `LAQueryLogs`
is not enabled, or XDR when it is skipped) still gets its worksheet: the script
writes a one-row placeholder (`"No rows produced for this dataset."`) so the
book always has all 15 tabs and downstream references never break.

The cost formulas and the default pricing inputs mirror the workbook, so the
spreadsheet and the in-portal workbook produce the same figures for the same
inputs. Three deliberate differences remain: the exporter treats
Auxiliary-plan tables as not modelled (see below), it measures XDR volume from
`Usage` first, and it uses decimal GB (10^9 bytes, as Microsoft bills) for
every volume.

## How it works

The console log labels six logical steps (`Step 1/6` through `Step 6/6`); those
six steps between them populate the 15 worksheets:

1. **Tables ARM API.** Lists every workspace table
   (`Get-SdlTableInventory`, `TablesApiVersion`) and buckets them into Classic
   V1 `_CL`, DCR-based `_CL`, Basic-plan, and Auxiliary-plan sets. These sets
   are injected into the classification KQL as `dynamic([...])` literals.
2. **Alert Rules ARM API.** Lists every analytic rule
   (`Microsoft.SecurityInsights/alertRules`, `AlertRulesApiVersion`)
   into `$rulesInventory`, and derives the enabled subset used for reference
   analysis.
3. **Saved searches.** Lists `savedSearches` (`SavedSearchesApiVersion`)
   and keeps only those with a `functionAlias`, giving the workspace-function
   inventory.
4. **Per-table classification.** Runs the mirrored classification KQL against
   the workspace `Usage` table to build the Migration Report, applying the
   category, plan, ingestion-mode, recommendation, and status logic.
5. **Derived datasets.** Identifier matching over each enabled rule's query
   text (comments and string literals blanked first, `table('X')` kept)
   produces the per-table rule references, the ASIM / `_GetWatchlist` /
   `externaldata` / custom-function indirection grid, the
   functions-wrapping-tables grid, and the function-to-rule map. Workspace
   functions are resolved to the tables they reach, including through other
   functions they call, and a rule that calls such a function is counted
   against those tables (`ViaFunctionRuleCount`). Legacy TI references
   (`ThreatIntelligenceIndicator`) are expanded to also cover the new
   `ThreatIntelIndicators` / `ThreatIntelObjects` tables. This is still a
   text heuristic: a column that shares a table's name (for example
   `Operation`) can be counted as a reference, so treat a count as an upper
   bound for common words and a floor for content reached some other way
   (playbooks, notebooks, other workbooks).
6. **Secondary datasets.** Exclusions and Top 10 savings (read off the Migration
   Report), deprecation warnings, Classic V1 volumes, Query-Weighted, XDR,
   alert activity, and the pricing-assumptions summary.

### KQL correctness details worth knowing

- **Culture-safe numerics.** Every numeric interpolated into a KQL here-string
  goes through `Format-KqlNumber`, which formats with the invariant culture.
  This stops a value like `1.5` rendering as `1,5` on machines with a comma
  decimal separator, which would otherwise produce invalid or wrong KQL.
- **Currency label is constrained.** `$Currency` is interpolated into projected
  column names (for example `AnalyticsCost_USD`). Because KQL identifiers allow
  only letters, digits, and underscores, the parameter is validated against
  `^[A-Z]{3}$` (an ISO 4217 three-letter code) to keep the generated KQL valid.
- **One classification.** Every query classifies tables through the same
  category lists (including `Alert` and `Anomalies`) and the same `case`
  block, so the Migration Report, Query-Weighted and the sheets derived from
  the report cannot disagree.
- **Auxiliary-plan tables.** They are billed at the Auxiliary rate, not the
  Analytics rate, so a saving against the Analytics rate would be
  meaningless. They are categorised `Auxiliary plan (not modelled)` and get no
  Analytics cost, Lake cost or saving.
- **Strict-mode-safe reads.** ARM omits properties such as
  `schema.tableSubType` on Microsoft tables; `Get-SdlPropertyValue` returns `$null`
  instead of throwing.
- **Pagination.** `Get-SdlArmList` follows `nextLink` on every ARM list call, so
  workspaces with more than one page of tables, rules, or saved searches are
  read in full rather than silently truncated.
- **Throttling and retries.** `Invoke-SdlArmRequest` sleeps `-ThrottleMs` between calls
  and retries only transient failures (HTTP 429 / 503 / 504 and transport
  exceptions) with exponential back-off. Other HTTP errors, such as a 403 for
  missing permissions, fail immediately.
- **Excel limits.** Strings longer than 32,000 characters are truncated with a
  marker, because Excel cannot store more than 32,767 characters in a cell.
  No worksheet autofilter is set on top of the table style, which can make
  Excel report the file as damaged.
- **Read-only.** The script only ever issues `GET` ARM calls and KQL queries.
  It never calls `PATCH` or `PUT` and never mutates the workspace.

## Parameters

Three parameters are mandatory; everything else has a default.

### Required

| Parameter | Purpose |
| --- | --- |
| `-SubscriptionId` | Subscription containing the Log Analytics workspace |
| `-ResourceGroupName` | Resource group containing the workspace |
| `-WorkspaceName` | Sentinel-enabled Log Analytics workspace name |

### Output and analysis windows

| Parameter | Default | Purpose |
| --- | --- | --- |
| `-OutputPath` | auto (see below) | Path for the `.xlsx` |
| `-TimeRangeDays` | 30 | Ingestion analysis window (matches the workbook's TimeRange) |
| `-QueryLookbackDays` | 7 | `LAQueryLogs` lookback for the Query-Weighted sheet (workbook default; `LAQueryLogs` keeps 30 days unless retention was extended) |
| `-AlertActivityDays` | 30 | `SecurityAlert` lookback for alert-activity stats |
| `-XdrLookbackDays` | 7 | XDR lookback (workbook default); set to `0` to skip the XDR sheet |
| `-ThrottleMs` | 200 | Milliseconds between ARM calls (`0` disables the sleep) |

### Pricing

| Parameter | Default | Purpose |
| --- | --- | --- |
| `-PricingModel` | `PAYG` | Analytics tier: `PAYG` or a commitment tier `CT50` to `CT50000` |
| `-EffectiveAnalyticsRate` | 0 | Override the Analytics rate in currency/GB; `0` uses the `-PricingModel` rate |
| `-Currency` | `USD` | ISO 4217 three-letter code used in column headers (display only, no conversion; the script warns when it is not `USD` and no `-EffectiveAnalyticsRate` is given) |
| `-LakeIngestPricePerGB` | 0.05 | Lake ingestion price per GB |
| `-LakeProcessingPricePerGB` | 0.10 | Lake data-processing price per GB |
| `-LakeStoragePricePerGBMonth` | 0.026 | Lake storage price per GB-month (workbook default) |
| `-LakeQueryPricePerGB` | 0.005 | Lake KQL query-scan price per GB |
| `-TargetLakeRetentionDays` | 730 | Total retention the table must keep, applied to both sides of the comparison (workbook default) |
| `-AnalyticsRetentionDays` | 90 | Analytics retention if the table stays on the Analytics tier (first 90 days free) |
| `-AnalyticsRetentionPricePerGBMonth` | 0.10 | Analytics retention price beyond 90 days, per uncompressed GB-month |
| `-CompressionRatio` | 6 | Storage compression ratio applied to Lake storage cost |

`-CompressionRatio` defaults to the fixed 6:1 compression Microsoft documents
for the Lake storage meter (described in the
[Data Lake coverage doc](../Modules/iSOCBlueprint/Sentinel-Data-Lake-Coverage.md)).
Versions before 0.2.0 defaulted to 10, which understated storage cost. Adjust
it only if you want the export to model a different assumption.

### Analytics commitment-tier rates

`Get-SdlPricingRate` maps `-PricingModel` to a USD/GB rate when
`-EffectiveAnalyticsRate` is left at `0`. Each commitment rate is the tier's
daily price divided by its size, read from the
[Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices)
(service `Sentinel`, region `eastus`) on 16 November 2026. PAYG is the
`Pay-as-you-go Analysis` meter, which in the simplified pricing tiers already
includes Log Analytics ingestion.

| Model | Daily price | Rate/GB | Model | Daily price | Rate/GB |
| --- | --- | --- | --- | --- | --- |
| PAYG | - | 4.30 | CT1000 | 2,480.00 | 2.48 |
| CT50 | 161.25 | 3.225 | CT2000 | 4,800.00 | 2.40 |
| CT100 | 296.00 | 2.96 | CT5000 | 11,550.00 | 2.31 |
| CT200 | 548.00 | 2.74 | CT10000 | 22,240.00 | 2.224 |
| CT300 | 800.00 | 2.6667 | CT25000 | 53,450.00 | 2.138 |
| CT400 | 1,037.33 | 2.5933 | CT50000 | 102,600.00 | 2.052 |
| CT500 | 1,265.00 | 2.53 | | | |

Versions before 0.2.0 (and the workbook) used 2.85, 2.77, 2.73, 2.61, 2.41,
2.22 and 2.11 for CT200 to CT5000, which do not match the published prices.

These are East US list prices. Other regions differ, so pass your region's
rate (or your negotiated rate) as `-EffectiveAnalyticsRate`, and set the Lake
prices for your region too. `-Currency` only relabels the column headers (it
does not convert any values); if you change it, set every price in that
currency, or the saving mixes currencies.

### How the costs are calculated

Every cost is a steady-state monthly figure per table, from billable volume in
`Usage` (`Quantity` is in MB; billing GB is 10^9 bytes, so GB = MB / 1000).
Microsoft's billing rules that the formulas follow:

- Lake ingestion and data processing are charged only for tables set to the
  data lake tier only. Mirroring an Analytics table to the lake is free.
- Lake storage is charged per GB-month for data held in the lake **after the
  analytics retention ends**, at a fixed 6:1 compression. A lake-only table
  pays it for the whole retention.
- Analytics retention is free for 90 days; beyond that it is charged at the
  Log Analytics retention price per (uncompressed) GB-month.
- Lake queries are charged per uncompressed GB scanned; Analytics queries are
  included.

With `GB` = billable GB/month, `R` = `-TargetLakeRetentionDays`, `A` =
`-AnalyticsRetentionDays` and `c` = `-CompressionRatio`:

| Side | Monthly cost |
| --- | --- |
| Stay on Analytics | `GB x (AnalyticsRate + max(A - 90, 0) / 30 x RetentionPrice + max(R - A, 0) / 30 / c x StoragePrice)` |
| Move to Lake only | `GB x (IngestPrice + ProcessingPrice + R / 30 / c x StoragePrice)` |
| Query-Weighted adds | `MonthlyScanGB x QueryPrice` to the Lake side |

Worked example with the defaults (100 GB/month, PAYG, A = 90, R = 730, c = 6):
Analytics = 100 x (4.30 + 0 + 640 / 30 / 6 x 0.026) = 439.24; Lake = 100 x
(0.05 + 0.10 + 730 / 30 / 6 x 0.026) = 25.54; saving 413.70 a month.

What the model does not capture, so treat the saving as an estimate:

- **Commitment tiers.** The effective per-GB rate is used for every GB. Under
  a commitment you pay for the whole tier, so moving data out only saves money
  once it lets you drop to a lower tier.
- **Free data grants.** The Microsoft 365 E5/A5/F5/G5 benefit (5 MB per user
  per day for eligible Defender XDR and Entra ID tables) and the Defender for
  Servers 500 MB allowance are applied by billing meters, not in `Usage`, so
  the Analytics cost of the covered tables is overstated and so is their
  saving.
- **Classic pricing tiers.** Workspaces still on the classic tiers are billed
  Log Analytics and Sentinel separately; pass the combined rate as
  `-EffectiveAnalyticsRate`.
- **Basic plan.** Tables on the Basic plan are shown at the Analytics rate
  (what they would cost once converted), not their current Basic price.
- **Notebooks and graph.** The advanced data insights and graph meters are not
  modelled.

Sources: [Plan costs and understand Microsoft Sentinel pricing and billing](https://learn.microsoft.com/azure/sentinel/billing),
[Manage data in Microsoft Sentinel and Defender](https://learn.microsoft.com/azure/sentinel/manage-data-overview),
[Azure Monitor Logs cost calculations](https://learn.microsoft.com/azure/azure-monitor/logs/cost-logs#data-size-calculation),
[Analyze usage in a Log Analytics workspace](https://learn.microsoft.com/azure/azure-monitor/logs/analyze-usage),
[Azure Monitor cost and usage: data allocation benefits](https://learn.microsoft.com/azure/azure-monitor/fundamentals/cost-usage#view-data-allocation-benefits).

## Prerequisites

- **PowerShell 7.2 or later** (the manifest declares it).
- **Az modules:** `Az.Accounts` and `Az.OperationalInsights`.
- **ImportExcel:** required to write the `.xlsx`. Install with
  `Install-Module ImportExcel -Scope CurrentUser`. The three modules are listed
  in the manifest's `ExternalModuleDependencies` and checked when the command
  runs (not in `RequiredModules`), so the module imports where they are
  missing and ImportExcel loads without its libgdiplus warning. The command
  fails fast, with the install command, if any is missing.
- **An Azure sign-in.** The command checks that the current context targets
  `-SubscriptionId` and can obtain tokens for Azure Resource Manager and Log
  Analytics. If the context is missing, points at another subscription or its
  token has expired or needs MFA, it switches subscription and, failing that,
  runs `Connect-AzAccount` for you scoped to the subscription's tenant. An
  expired sign-in mid-run stops with a clear message instead of retrying.
- **Workspace read access** for the signed-in identity, plus (for a full book)
  `LAQueryLogs` enabled in the workspace so the Query-Weighted sheet has data.

The API versions are pinned on the `$connection` object the command builds:
`TablesApiVersion` (`2023-09-01`), `AlertRulesApiVersion` (`2025-09-01`),
`SavedSearchesApiVersion` (`2020-08-01`) and `WorkspaceApiVersion`
(`2023-09-01`). They are independent of the api-version variables used by the
content deploy scripts.

## Running it

Import the module, then run the command. All defaults (30-day window, PAYG
pricing, USD):

```powershell
Import-Module ./Content/Workbooks/SentinelDataLake/SdlMigrationExport

Export-SdlMigrationWorkbook -SubscriptionId '<sub>' -ResourceGroupName '<rg>' -WorkspaceName '<ws>'
```

A commitment-tier model with a negotiated Analytics rate and an explicit output
path:

```powershell
Export-SdlMigrationWorkbook -SubscriptionId '<sub>' -ResourceGroupName '<rg>' -WorkspaceName '<ws>' -PricingModel 'CT200' -EffectiveAnalyticsRate 2.18 -OutputPath './sentinel-lake-prod.xlsx'
```

Add `-WhatIf` to run the queries without writing a file, or `-Verbose` to see
each ARM call and KQL query.

### Where the file lands

When `-OutputPath` is omitted, the file is written to the current directory as
`SdlMigrationExport_<workspace>_<yyyyMMdd-HHmm>.xlsx`. A module has no script
folder to write beside, and its own folder sits inside the repository. The
file holds workspace data, so `.gitignore` excludes `SdlMigrationExport_*.xlsx`
anywhere in the repository.

If you pass an explicit `-OutputPath`, the command creates the parent directory
if needed and overwrites an existing file of the same name; if that file is
open (for example in Excel) it stops with a message saying so. On macOS and
Linux it rejects a Windows drive-letter path (for example
`C:\Reports\foo.xlsx`) up front with a clear message.

## Changes in 0.2.0

Version 0.2.0 marks the script deprecated and fixes the places where its
output disagreed with the workbook or with Microsoft's documented billing.
Re-run any export you still rely on; do not compare it with an older one.

| Area | Before | Now |
| --- | --- | --- |
| Lake storage defaults | 0.023 per GB-month, 365 days, compression 10 | 0.026, 730 days, compression 6 (workbook values and Microsoft's 6:1). Storage cost was understated by roughly a factor of four, so savings were overstated |
| Query-Weighted | Assumed every query scans 10 percent of a table, matched any capitalised word as a table, no storage cost, no category handling | Workbook method: scan = table's average hourly ingestion x the query's time-range width, scaled to a month; tables matched with the workbook's pipeline-start pattern; storage included; excluded categories nulled; recommendation; unqueried tables kept |
| XDR Cost Model | Billed GB from `Usage` for a different 21-table list (included TVM tables, omitted `DeviceInfo`, `IdentityQueryEvents`, `IdentityDirectoryEvents`, `IdentityInfo`, `CloudAppEvents`); no Lake cost or saving | The workbook's 21 tables; `Usage` and record `_BilledSize` volumes side by side (the workbook's `estimate_data_size` is not the billed size); Lake cost, saving and notes |
| Commitment-tier rates | CT200 to CT5000 at 2.85 / 2.77 / 2.73 / 2.61 / 2.41 / 2.22 / 2.11 | Derived from the published daily prices: 2.74 / 2.6667 / 2.5933 / 2.53 / 2.48 / 2.40 / 2.31; CT10000, CT25000 and CT50000 added |
| Retention on the Analytics side | Ignored: an Analytics table was costed for ingestion only while the Lake side paid storage for the full retention | Analytics side pays retention beyond 90 days and lake storage for the days after analytics retention ends, as Microsoft bills it (`-AnalyticsRetentionDays`, `-AnalyticsRetentionPricePerGBMonth`) |
| Alert Activity | Only `High` counted as high severity; no medium/low, tactics or criticality | `High` and `Critical` counted as high; medium, low, tactics and the workbook's criticality label |
| Category lists | `Alert` and `Anomalies` missing | Included; Auxiliary-plan tables no longer given a saving against the Analytics rate |
| Top 10 Savings | Could list tables with a negative or zero saving | Only `Eligible` rows, read off the Migration Report |
| Per-Table Rule Refs | Raw word match including comments and strings; rules calling parser functions not counted against the tables underneath | Comments and strings blanked, `table('X')` honoured, function-reached tables counted (`ViaFunctionRuleCount`); no more duplicate "(via ...)" rule names inflating counts |
| ASIM detection | Case-sensitive `_Asim_`, so `_ASim_*` parsers were missed | Case-insensitive `_Im_` / `_ASim_` |
| Deprecation Warnings | Said legacy TI ingestion ends mid-2026 | Microsoft stopped ingesting into `ThreatIntelligenceIndicator` after 31 July 2025 |
| Structure and lint | One 1,168-line script, 22 `Write-Host` calls, a `ShouldProcess` and a byte-order-mark finding, script-scope state | The `SdlMigrationExport` module: manifest, one exported command, one function per file (none over 300 lines), parameters passed explicitly, zero findings under the strict `PSScriptAnalyzer` settings, Pester checks for the standard's other rules, PSScriptAnalyzer installed in both PR pipelines, `-WhatIf` and `-Verbose` |
| Robustness | Strict-mode errors on tables without `tableSubType`, retries of 403/404, empty lists collapsing to `$null`, cells over Excel's limit, autofilter plus table style | All handled (see "KQL correctness details worth knowing") |

## Relationship to the Blueprint Data Lake coverage

The [iSOC Blueprint](../Modules/iSOCBlueprint/Sentinel-Blueprint.md) renders a Data
Lake section (Section 88) as part of its automatic inventory report; what that
section captures and renders is documented in
[Sentinel Data Lake, iSOC Blueprint coverage](../Modules/iSOCBlueprint/Sentinel-Data-Lake-Coverage.md).

The two tools are complementary, not overlapping:

- The **Blueprint** runs in the inventory pipeline and reports Lake state at
  the plan level (Analytics vs DataLake), driven from captured inventory JSON.
  Its coverage doc lists per-Lake-meter cost attribution as a known gap.
- **This exporter** runs on demand and computes distinct per-table
  `LakeIngestCost`, `LakeProcCost`, and `LakeStorageCost` fields (three of the
  five Lake meters) by mirroring the workbook's KQL against the workspace. It
  is deliberately outside the Blueprint capture/render pipeline, so its output
  does not appear in Section 88. The coverage doc's "Known gaps and forward
  work" section names this script as the tool that already closes most of that
  gap, and notes that wiring its cost KQL into the Blueprint would remove most
  of the remaining gap without a new Cost Management capture.

If you only need the plan-level picture, read the Blueprint report. If you need
the per-table, per-meter Lake cost model as a spreadsheet you can hand to a cost
owner, run this exporter.

## Related

- [`Content/Workbooks/SentinelDataLake/SdlMigrationExport/Public/Export-SdlMigrationWorkbook.ps1`](../../Content/Workbooks/SentinelDataLake/SdlMigrationExport/Public/Export-SdlMigrationWorkbook.ps1) - the export script
- [`Content/Workbooks/SentinelDataLake/workbook.json`](../../Content/Workbooks/SentinelDataLake/workbook.json) - the companion in-portal workbook
- [Sentinel Data Lake, iSOC Blueprint coverage](../Modules/iSOCBlueprint/Sentinel-Data-Lake-Coverage.md) - what the Blueprint reports about Lake
- [iSOC Blueprint](../Modules/iSOCBlueprint/Sentinel-Blueprint.md) - the inventory-and-report tool
- [Microsoft Sentinel Data Lake overview](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-overview)
- [Data lake tier billing](https://learn.microsoft.com/azure/sentinel/billing#data-lake-tier)
- [ImportExcel module](https://github.com/dfinke/ImportExcel)
