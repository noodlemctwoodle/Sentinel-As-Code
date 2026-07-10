# Sentinel Data Lake Migration Workbook Export

`Export-SdlMigrationWorkbook.ps1` mirrors every query behind the **Sentinel
Data Lake Migration** workbook and writes them to a single multi-sheet Excel
file (`.xlsx`), one named worksheet per dataset. It exists because the Azure
portal cannot bundle a multi-grid workbook into one Excel export, each grid
only exports its own sheet, so migration planning across a dozen-plus grids
means a dozen-plus separate downloads. This script produces the whole book in
one read-only pass against the workspace.

| What | Where |
| --- | --- |
| Export script | [`Content/Workbooks/SentinelDataLake/Export-SdlMigrationWorkbook.ps1`](../../Content/Workbooks/SentinelDataLake/Export-SdlMigrationWorkbook.ps1) |
| Companion workbook | [`Content/Workbooks/SentinelDataLake/workbook.json`](../../Content/Workbooks/SentinelDataLake/workbook.json) |
| Workbook metadata | [`Content/Workbooks/SentinelDataLake/metadata.json`](../../Content/Workbooks/SentinelDataLake/metadata.json) (`sourceId: SentinelDataLake`) |
| Documenter coverage of Lake | [`Documenter/Sentinel-Data-Lake-Coverage.md`](Documenter/Sentinel-Data-Lake-Coverage.md) |

The folder holds both the workbook (`workbook.json`, deployed like any other
custom workbook by the Workbooks stage of
[`Deploy/content/Deploy-CustomContent.ps1`](../../Deploy/content/Deploy-CustomContent.ps1))
and this standalone exporter. The script is **not** part of the deploy or the
Documenter pipeline. It is an on-demand analyst tool that you run by hand when
you want the Lake migration analysis as a spreadsheet.

## What it produces

The output is a single `.xlsx` written by the
[`ImportExcel`](https://github.com/dfinke/ImportExcel) module. The worksheet
set is defined by the `$sheets` ordered dictionary near the bottom of the
script (the `#region Write xlsx` block). There are **15 worksheets**, always
written in this order:

| Sheet | Backing variable | Contents |
| --- | --- | --- |
| Migration Report | `$migrationReport` | Per-table classification: billable GB/month, Analytics vs Lake monthly cost, monthly saving, saving %, category, plan, ingestion mode, recommendation, status |
| Per-Table Rule Refs | `$perTableRuleSummary` | For each table, the count of enabled analytic rules that reference it, the rule kinds, and up to five example rule names |
| Exclusions | `$exclusionsRows` | Tables that cannot move to Lake (not supported, UEBA, Sentinel feature dependency, system table, Classic V1, Basic plan) with a plain-English reason |
| Deprecation Warnings | `$deprecationRows` | Microsoft-announced table retirements (for example the legacy `ThreatIntelligenceIndicator` table) with replacement and urgency |
| Classic V1 Tables | `$classicV1Rows` | `_CL` tables still on the legacy MMA / HTTP Data Collector ingestion path, enriched with billable GB/month |
| Top 10 Savings | `$top10Rows` | The ten highest-impact migration candidates ranked by projected monthly saving |
| Rules Inventory | `$rulesInventory` | Every analytic rule in the workspace (an `Enabled` column distinguishes enabled from disabled), with kind, severity, tactics, techniques, cadence, and query text |
| Indirection Rules | `$indirection` | Rules whose query uses ASIM parsers, `_GetWatchlist()`, `externaldata()`, or a custom workspace function (the indirect table references a naive scan would miss) |
| Workspace Functions | `$workspaceFunctions` | Saved KQL functions in the workspace (`savedSearches` entries that carry a `functionAlias`) |
| Fns Wrapping Tables | `$functionsWrappingTables` | Which workspace functions reference which tables |
| Function -> Rules | `$functionRuleMap` | Which enabled rules call which workspace functions |
| Query-Weighted | `$queryWeightedRows` | `LAQueryLogs`-based per-table cost model that weights Lake query cost by observed query activity |
| XDR Cost Model | `$xdrRows` | Defender XDR advanced-hunting per-table cost model (optional, skipped when `-XdrLookbackDays 0`) |
| Alert Activity | `$alertActivityRows` | `SecurityAlert` per-alert-name statistics: alert count, high-severity count, last seen |
| Pricing Assumptions | `$pricingAssumptions` | Every pricing and window input used by the export, so the numbers are reproducible |

Any dataset that returns no rows (for example Query-Weighted when `LAQueryLogs`
is not enabled, or XDR when it is skipped) still gets its worksheet: the script
writes a one-row placeholder (`"No rows produced for this dataset."`) so the
book always has all 15 tabs and downstream references never break.

The pricing logic mirrors the workbook exactly, so the spreadsheet and the
in-portal workbook produce the same figures for the same inputs.

## How it works

The console log labels six logical steps (`Step 1/6` through `Step 6/6`); those
six steps between them populate the 15 worksheets:

1. **Tables ARM API.** Lists every workspace table
   (`Get-BaseUri` + `$script:TablesApiVersion`) and buckets them into Classic
   V1 `_CL`, DCR-based `_CL`, Basic-plan, and Auxiliary-plan sets. These sets
   are injected into the classification KQL as `dynamic([...])` literals.
2. **Alert Rules ARM API.** Lists every analytic rule
   (`Microsoft.SecurityInsights/alertRules`, `$script:AlertRulesApiVersion`)
   into `$rulesInventory`, and derives the enabled subset used for reference
   analysis.
3. **Saved searches.** Lists `savedSearches` (`$script:SavedSearchesApiVersion`)
   and keeps only those with a `functionAlias`, giving the workspace-function
   inventory.
4. **Per-table classification.** Runs the mirrored classification KQL against
   the workspace `Usage` table to build the Migration Report, applying the
   category, plan, ingestion-mode, recommendation, and status logic.
5. **Derived datasets.** Word-boundary token matching over each enabled rule's
   query text produces the per-table rule references, the ASIM /
   `_GetWatchlist` / `externaldata` / custom-function indirection grid, the
   functions-wrapping-tables grid, and the function-to-rule map. Legacy TI
   references (`ThreatIntelligenceIndicator`) are expanded to also cover the
   new `ThreatIntelIndicators` / `ThreatIntelObjects` tables.
6. **Secondary datasets.** Exclusions, deprecation warnings, Classic V1
   volumes, Top 10 savings, Query-Weighted, XDR, alert activity, and the
   pricing-assumptions summary.

### KQL correctness details worth knowing

- **Culture-safe numerics.** Every numeric interpolated into a KQL here-string
  goes through `Format-KqlNumber`, which formats with the invariant culture.
  This stops a value like `1.5` rendering as `1,5` on machines with a comma
  decimal separator, which would otherwise produce invalid or wrong KQL.
- **Currency label is constrained.** `$Currency` is interpolated into projected
  column names (for example `AnalyticsCost_USD`). Because KQL identifiers allow
  only letters, digits, and underscores, the parameter is validated against
  `^[A-Z]{3}$` (an ISO 4217 three-letter code) to keep the generated KQL valid.
- **Pagination.** `Get-ArmList` follows `nextLink` on every ARM list call, so
  workspaces with more than one page of tables, rules, or saved searches are
  read in full rather than silently truncated.
- **Throttling and retries.** `Invoke-Arm` sleeps `-ThrottleMs` between calls
  and retries transient failures (HTTP 429 / 503 / 504 and exceptions) with
  exponential back-off.
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
| `-QueryLookbackDays` | 30 | `LAQueryLogs` lookback for the Query-Weighted sheet |
| `-AlertActivityDays` | 30 | `SecurityAlert` lookback for alert-activity stats |
| `-XdrLookbackDays` | 30 | Defender XDR lookback; set to `0` to skip the XDR sheet |
| `-ThrottleMs` | 200 | Milliseconds between ARM calls (`0` disables the sleep) |

### Pricing

| Parameter | Default | Purpose |
| --- | --- | --- |
| `-PricingModel` | `PAYG` | Analytics commitment tier: `PAYG`, `CT50`, `CT100`, `CT200`, `CT300`, `CT400`, `CT500`, `CT1000`, `CT2000`, `CT5000` |
| `-EffectiveAnalyticsRate` | 0 | Override the Analytics rate in currency/GB; `0` uses the `-PricingModel` rate |
| `-Currency` | `USD` | ISO 4217 three-letter code used in column headers (display only) |
| `-LakeIngestPricePerGB` | 0.05 | Lake ingestion price per GB |
| `-LakeProcessingPricePerGB` | 0.10 | Lake data-processing price per GB |
| `-LakeStoragePricePerGBMonth` | 0.023 | Lake storage price per GB-month |
| `-LakeQueryPricePerGB` | 0.005 | Lake KQL query-scan price per GB |
| `-TargetLakeRetentionDays` | 365 | Lake retention used in the storage-cost calculation |
| `-CompressionRatio` | 10 | Storage compression ratio applied to Lake storage cost |

`-CompressionRatio` is a tunable modelling input here (default `10`); it is not
the same figure as the fixed 6:1 compression Microsoft documents for the Lake
storage meter, which is described in the
[Data Lake coverage doc](Documenter/Sentinel-Data-Lake-Coverage.md). Adjust it
if you want the export to model a different assumption.

### Analytics commitment-tier rates

`Get-PricingRate` maps `-PricingModel` to a currency/GB rate when
`-EffectiveAnalyticsRate` is left at `0`:

| Model | Rate/GB | Model | Rate/GB |
| --- | --- | --- | --- |
| PAYG | 4.30 | CT400 | 2.73 |
| CT50 | 3.23 | CT500 | 2.61 |
| CT100 | 2.96 | CT1000 | 2.41 |
| CT200 | 2.85 | CT2000 | 2.22 |
| CT300 | 2.77 | CT5000 | 2.11 |

These are illustrative list prices baked into the workbook; supply
`-EffectiveAnalyticsRate` with your negotiated rate for accurate figures, and
`-Currency` only relabels the column headers (it does not convert any values).

## Prerequisites

- **PowerShell 7+.** The script throws on Windows PowerShell 5.1 or earlier.
- **Az modules:** `Az.Accounts` and `Az.OperationalInsights`.
- **ImportExcel:** required to write the `.xlsx`. Install with
  `Install-Module ImportExcel -Scope CurrentUser`. The script fails fast at
  start-up if any of the three modules is missing.
- **An authenticated Az context.** Run `Connect-AzAccount` first. The script
  reads the current context and, if its subscription differs from
  `-SubscriptionId`, switches to the requested subscription with
  `Set-AzContext`.
- **Workspace read access** for the signed-in identity, plus (for a full book)
  `LAQueryLogs` enabled in the workspace so the Query-Weighted sheet has data.

The API versions the script uses are pinned as `$script:` variables at the top
of the Helpers region: `$script:TablesApiVersion` (`2023-09-01`),
`$script:AlertRulesApiVersion` (`2025-09-01`),
`$script:SavedSearchesApiVersion` (`2020-08-01`), and
`$script:WorkspaceApiVersion` (`2023-09-01`). These are the versions this
standalone reporting tool queries against and are independent of the api-version
variables used by the content deploy scripts.

## Running it

Minimal run, all defaults (30-day window, PAYG pricing, USD):

```powershell
Connect-AzAccount

./Content/Workbooks/SentinelDataLake/Export-SdlMigrationWorkbook.ps1 `
    -SubscriptionId    "<sub>" `
    -ResourceGroupName "<rg>" `
    -WorkspaceName     "<ws>"
```

A commitment-tier model with GBP labels, a negotiated Analytics rate, and an
explicit output path:

```powershell
./Content/Workbooks/SentinelDataLake/Export-SdlMigrationWorkbook.ps1 `
    -SubscriptionId          "<sub>" `
    -ResourceGroupName       "<rg>" `
    -WorkspaceName           "<ws>" `
    -PricingModel            CT200 `
    -Currency                GBP `
    -EffectiveAnalyticsRate  2.18 `
    -OutputPath              "./sentinel-lake-prod.xlsx"
```

### Where the file lands

When `-OutputPath` is omitted, the file is written next to the script itself
(`$PSScriptRoot`) as `SdlMigrationExport_<workspace>_<yyyyMMdd-HHmm>.xlsx`. The
default anchors on the script folder rather than the caller's current working
directory, so "where did the export go?" always has the same answer regardless
of where you launched it from.

If you pass an explicit `-OutputPath`, the script creates the parent directory
if needed and overwrites an existing file of the same name. On macOS and Linux
it rejects a Windows drive-letter path (for example `C:\Reports\foo.xlsx`) up
front with a clear message rather than failing deep in path handling, so a
copied Windows example fails helpfully instead of cryptically.

## Relationship to the Documenter Data Lake coverage

The [Sentinel Documenter](Documenter/Sentinel-Documenter.md) renders a Data
Lake section (Section 88) as part of its automatic inventory report; what that
section captures and renders is documented in
[Sentinel Data Lake, Documenter coverage](Documenter/Sentinel-Data-Lake-Coverage.md).

The two tools are complementary, not overlapping:

- The **Documenter** runs in the inventory pipeline and reports Lake state at
  the plan level (Analytics vs DataLake), driven from captured inventory JSON.
  Its coverage doc lists per-Lake-meter cost attribution as a known gap.
- **This exporter** runs on demand and computes distinct per-table
  `LakeIngestCost`, `LakeProcCost`, and `LakeStorageCost` fields (three of the
  five Lake meters) by mirroring the workbook's KQL against the workspace. It
  is deliberately outside the Documenter capture/render pipeline, so its output
  does not appear in Section 88. The coverage doc's "Known gaps and forward
  work" section names this script as the tool that already closes most of that
  gap, and notes that wiring its cost KQL into the Documenter would remove most
  of the remaining gap without a new Cost Management capture.

If you only need the plan-level picture, read the Documenter report. If you need
the per-table, per-meter Lake cost model as a spreadsheet you can hand to a cost
owner, run this exporter.

## Related

- [`Content/Workbooks/SentinelDataLake/Export-SdlMigrationWorkbook.ps1`](../../Content/Workbooks/SentinelDataLake/Export-SdlMigrationWorkbook.ps1) - the export script
- [`Content/Workbooks/SentinelDataLake/workbook.json`](../../Content/Workbooks/SentinelDataLake/workbook.json) - the companion in-portal workbook
- [Sentinel Data Lake, Documenter coverage](Documenter/Sentinel-Data-Lake-Coverage.md) - what the Documenter reports about Lake
- [Sentinel Documenter](Documenter/Sentinel-Documenter.md) - the inventory-and-report tool
- [Microsoft Sentinel Data Lake overview](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-lake-overview)
- [Data lake tier billing](https://learn.microsoft.com/azure/sentinel/billing#data-lake-tier)
- [ImportExcel module](https://github.com/dfinke/ImportExcel)
