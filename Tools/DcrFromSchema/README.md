# DCR from schema

Turn a JSON table schema into a Log Analytics custom table and a Direct Data
Collection Rule for the Logs Ingestion API, wizard-driven, with the ARM
templates left behind so the result is reviewable and committable.

```powershell
./New-DcrFromSchema.ps1 -SchemaPath ./Examples/threat-intel-alerts.json
```

That is the whole entry point. Everything else the rule needs (subscription,
workspace, plan, retention, DCR name, transform) the wizard asks for, offering
a sensible default at each step.

> **Fuller reference:** [`Docs/Tools/DcrFromSchema/`](../../Docs/Tools/DcrFromSchema/Dcr-From-Schema.md)
> is the authoritative documentation for this tool: every documented limit and the
> Microsoft page it came from, design rationale, each guard and why it exists,
> failure modes and troubleshooting. This README stays because the script is designed
> to be copied standalone to a jump box or an automation account, where the `Docs/`
> tree will not travel with it, so it is the quick reference guaranteed to be on the
> box beside the script.

The script is **standalone**: a single file that runs with only the Az modules
installed. It does not import this repository's `Sentinel.Common` module, so
nothing else here needs to travel with it. Take `Examples/` along if you want
the samples.

> **Related but different:** [`Tools/ClassicToDcr/`](../ClassicToDcr/README.md)
> migrates tables that already exist as classic (MMA / Data Collector API)
> tables. This tool creates a new table from a schema you wrote. If your table
> already exists and reports `tableSubType: Classic`, you want that kit first,
> and this script says so rather than failing at deployment.

## The schema file

```json
{
  "tableName": "MyApp_CL",
  "columns": [
    { "name": "TimeGenerated", "type": "datetime" },
    { "name": "Message",       "type": "string" }
  ]
}
```

Also accepted: the Tables API shape (`{ "properties": { "schema": ... } }`, so
an exported table can be fed back in) and a bare array of columns. Optional
keys used as defaults where present: `description`, `dcrName`, `location`,
`plan`, `retentionInDays`, `totalRetentionInDays`, `transformKql`, plus
`description`, `displayName` and `dataTypeHint` per column. Anything else in
the file is ignored rather than forwarded.

Five examples ship in `Examples/`, one per table plan plus two shape
demonstrations:

| File | Plan | Shows |
| --- | --- | --- |
| `minimal.json` | (unset) | The smallest schema that works |
| `threat-intel-alerts.json` | Analytics | A realistic security feed, with plan and retention set |
| `annotated.json` | Analytics | Every optional feature: descriptions, `displayName`, all four `dataTypeHint` values, a `guid` column, a custom transform |
| `basic-plan.json` | Basic | Cheap ingestion, reduced query surface |
| `auxiliary-plan.json` | Auxiliary | Cheapest ingestion, plus its `TimeGenerated` precision constraint |

## What it does

1. Reads the schema, repairing paste damage (curly quotes, comments, trailing
   commas, byte order mark) if the file will not parse, and reporting each repair.
2. Signs in if needed and offers a numbered list of subscriptions, then
   workspaces. Picking the workspace settles its resource group and region too.
3. Shows the schema for review with each column's table type, stream type and
   any problem. Errors must be resolved; warnings can be accepted. If the table
   already exists, the live schema is diffed against the file first.
4. Asks for plan, retention, DCR name and the transform.
5. Writes both ARM templates. Always, whether or not you deploy.
6. Offers to deploy: validates each template first, creates the table, deploys
   the rule, optionally grants Monitoring Metrics Publisher, and prints the
   ready ingestion URL.

Every prompt that has a default shows it and takes Enter to accept, so nothing
free-text reads like a yes/no question.

## Output, and the order that matters

| File | Deploy to |
| --- | --- |
| `table-<name>.json` | The **workspace's** resource group |
| `<dcrName>.json` | The **DCR's** resource group |

Two templates because the table and the rule can live in different resource
groups and an ARM resource-group deployment only reaches one.

**Deploy the table first.** Nothing about a DCR or the ingestion path creates a
table for you: "The table in the Log Analytics workspace must exist before you
can send data to it." The check happens even earlier than that implies, when the
**rule** is created, so a DCR naming a missing table cannot be created at all
and fails with `InvalidOutputTable`:

```text
Table for output stream 'Custom-MyApp_CL' is not available for destination '<workspace-id>'.
Please ensure that the table exists in Log Analytics Workspace before creating or updating the rule.
```

The legacy HTTP Data Collector API did auto-create a classic `_CL` table on
first POST, which is where the expectation comes from. It retires 2026-09-14 and
the DCR path does not inherit the behaviour.

The table is authored at api-version `2025-07-01` (at `2023-09-01` the Tables API
has no Auxiliary plan) and the DCR at `2023-03-11` (the earliest version that
gives a `kind: Direct` rule its own `logsIngestion` endpoint).

```powershell
New-AzResourceGroupDeployment -ResourceGroupName rg-sentinel -TemplateFile ./table-myapp.json
```

```powershell
New-AzResourceGroupDeployment -ResourceGroupName rg-sentinel -TemplateFile ./dcr-myapp.json
```

Pass `-OutputDirectory ../../Infra/dcr` to land them somewhere tracked.

## Prerequisites and RBAC

- PowerShell 7.2+
- `Az.Accounts`, `Az.OperationalInsights`, `Az.Resources`
- `Connect-AzAccount`

| Identity | Needs | Scope | For |
| --- | --- | --- | --- |
| You | Log Analytics Contributor | Workspace | Create the table |
| You | Contributor | DCR resource group | Deploy the rule |
| You | Owner or User Access Administrator | DCR | Only for `-GrantIngestionRoleTo` |
| The sending identity | **Monitoring Metrics Publisher** | **the DCR** | Send via the Logs Ingestion API |

The sending identity needs nothing on the workspace. Data-plane RBAC can take a
few minutes to take effect, so early POSTs may return 403.

## Unattended use

`-NonInteractive` never prompts, so anything the wizard would have asked for has
to be a parameter. Without `-Deploy` it writes the templates and stops:

```powershell
./New-DcrFromSchema.ps1 -SchemaPath ./Examples/minimal.json -NonInteractive `
    -SubscriptionId '00000000-0000-0000-0000-000000000000' `
    -ResourceGroupName 'rg-sentinel' -WorkspaceName 'law-sentinel' `
    -OutputDirectory ../../Infra/dcr
```

`-WhatIf` works throughout. `-Force` bypasses the deploy confirmation.
`-SkipTable` targets an existing table and only produces the rule.
`-IncludeDataTypeHint` re-enables column `dataTypeHint` output, which is off by
default because the live service rejects the documented enum values.

Run `Get-Help ./New-DcrFromSchema.ps1 -Full` for the complete parameter list.

## Gotchas

| Symptom | Cause and fix |
| --- | --- |
| `InvalidOutputTable`, "not available for destination" | The table does not exist. Validated at rule-create time, so it blocks DCR creation too. Deploy the table template first |
| `InvalidOutputTable`, "Classic (MMA-based) ... not supported" | The table exists but is `Classic`. Migrate it with [`Tools/ClassicToDcr/`](../ClassicToDcr/README.md) |
| `InvalidTransformOutput` | A stream type differs from the table type. Handled automatically; regenerate the templates with the current script |
| Refuses: live column types differ | A column's type cannot be changed after creation. Align the schema with the live table, or use a new table name |
| Refuses the Auxiliary plan | Two column names differ only by case, and Auxiliary ingestion drops rows because of it. Rename them, or choose Analytics or Basic |
| "This tool takes a schema, not a sample of the data" | The file is the JSON you want to ingest, not a description of its columns |
| `MSG 1011: Invalid value provided for data type hint` | The live service rejects the `dataTypeHint` values its own docs prescribe. Hints are dropped by default for this reason; if you passed `-IncludeDataTypeHint`, drop it |
| `InvalidProperty: 'Description' length should be 256 characters or less` | Descriptions are capped at 256 characters for both the table and the rule, which is an undocumented Azure limit |
| Retention was ignored | `retentionInDays` is read-only on Basic and Auxiliary tables |
| New table not queryable yet | First-ingestion query availability lags 10 to 15 minutes |
| 403 on the first POST | Data-plane RBAC propagation. Retry after a few minutes |

The [full reference](../../Docs/Tools/DcrFromSchema/Dcr-From-Schema.md#troubleshooting)
has the longer list.

## Tests

Unit tests live in the repository's `Tests/` folder, run by
`Tools/Invoke-PRValidation.ps1`, so the standalone kit stays runtime-only:

- `Tests/Test-NewDcrFromSchema.Tests.ps1`
