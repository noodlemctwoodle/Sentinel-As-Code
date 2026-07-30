# DCR from Schema

A single wizard-driven PowerShell script under
[`Tools/DcrFromSchema/`](../../../Tools/DcrFromSchema/) that turns a JSON table schema into a Log
Analytics custom table and a Direct Data Collection Rule for the Logs Ingestion API, then leaves
the ARM templates behind so the result is reviewable and committable.

| What | Where |
| --- | --- |
| The script | [`Tools/DcrFromSchema/New-DcrFromSchema.ps1`](../../../Tools/DcrFromSchema/New-DcrFromSchema.ps1) |
| Example schemas | [`Tools/DcrFromSchema/Examples/`](../../../Tools/DcrFromSchema/Examples/) |
| On-the-box quick reference | [`Tools/DcrFromSchema/README.md`](../../../Tools/DcrFromSchema/README.md) |
| Tests | [`Tests/Test-NewDcrFromSchema.Tests.ps1`](../../../Tests/Test-NewDcrFromSchema.Tests.ps1) |

## Where the documentation lives

This page is the authoritative reference. The kit also carries its own
[`README.md`](../../../Tools/DcrFromSchema/README.md), and that stays. The script is designed to be
copied out of this repository and run on a jump box, in an automation account, or on a customer
machine, and the `Docs/` tree does not travel with it. The README is therefore the quick reference
guaranteed to be on the box next to the script you are about to run.

| Source | Scope |
| --- | --- |
| [`Tools/DcrFromSchema/README.md`](../../../Tools/DcrFromSchema/README.md) | On-the-box quick reference. Enough to run the script safely without access to this repository. |
| This page | The fuller reference: the documented limits and their sources, design rationale, every guard and why it exists, failure modes, troubleshooting. |

When the two disagree, the code wins, then this page, then the README.

## Contents

- [Related but different: ClassicToDcr](#related-but-different-classictodcr)
- [The schema file](#the-schema-file)
- [Table plans](#table-plans)
- [What the wizard does](#what-the-wizard-does)
- [Validation, and where every rule comes from](#validation-and-where-every-rule-comes-from)
- [dataTypeHint is documented but rejected](#datatypehint-is-documented-but-rejected)
- [Sanitising pasted input](#sanitising-pasted-input)
- [The guid problem](#the-guid-problem)
- [Output, and the deployment order that matters](#output-and-the-deployment-order-that-matters)
- [Prerequisites and RBAC](#prerequisites-and-rbac)
- [Unattended use](#unattended-use)
- [Sending data](#sending-data)
- [Design decisions](#design-decisions)
- [Troubleshooting](#troubleshooting)
- [References](#references)

## Related but different: ClassicToDcr

[`Tools/ClassicToDcr/`](../ClassicToDcr/Classic-to-DCR-Toolkit.md) migrates tables that **already
exist** as classic (MMA / HTTP Data Collector API) tables. This script creates a **new** table from
a schema you wrote.

The two do not overlap and the boundary is enforced: if the target table already exists and reports
`tableSubType: Classic`, this script refuses and points you at the migration toolkit, rather than
letting the DCR deployment fail later with `InvalidOutputTable`.

| You have | Use |
| --- | --- |
| A schema for data nobody is sending yet | This script |
| A vendor feed you want to push over the Logs Ingestion API | This script |
| An existing `_CL` table whose `tableSubType` is `Classic` | [ClassicToDcr](../ClassicToDcr/Classic-to-DCR-Toolkit.md), then this script is unnecessary |
| An existing DCR-based table and you want another rule against it | This script with `-SkipTable` |

## The schema file

The minimum is a table name and a column list:

```json
{
  "tableName": "MyApp_CL",
  "columns": [
    { "name": "TimeGenerated", "type": "datetime" },
    { "name": "Message",       "type": "string" }
  ]
}
```

Three shapes are accepted, so a schema rarely needs reformatting before use:

| Shape | When you would have it |
| --- | --- |
| `{ "tableName": ..., "columns": [...] }` | Hand-written, and what the examples use |
| `{ "properties": { "schema": { "name": ..., "columns": [...] } } }` | Straight out of `az monitor log-analytics workspace table show`, so a table exported from Azure can be fed back in |
| A bare array of `{ "name", "type" }` | Copied out of a larger document. Supply `-TableName`, or the wizard asks |

A bare array holding exactly **one** column is handled specially, because `ConvertFrom-Json`
unrolls a single-element array: the lone object arrives looking like a schema object, and its
`name` would otherwise be read as the table's name. The single-column case is detected before the
table-name lookup for that reason.

### Optional keys

Used as defaults where present, prompted for otherwise:

| Key | Effect |
| --- | --- |
| `description` | Recorded on the table schema and the DCR |
| `dcrName` | Overrides the generated `dcr-<table>` name |
| `location` | DCR region. Must match the workspace region |
| `plan` | `Analytics`, `Basic` or `Auxiliary` |
| `retentionInDays` | Interactive retention. Analytics only |
| `totalRetentionInDays` | Interactive plus long-term retention |
| `transformKql` | Overrides the derived transform |

Per column, `description`, `displayName` and `dataTypeHint` are carried through. `description` is
also read from `desc`, `comment`, `note` or `notes`, because a pasted schema rarely uses the key
the API expects.

Anything else in the file is **ignored rather than forwarded**. A `"note"` a colleague left on a
column, a `"required"` flag from whatever tool produced it: the templates emit only the properties
the Tables API `Column` object and the DCR `ColumnDefinition` object actually define.

### The examples

Five schemas ship in [`Tools/DcrFromSchema/Examples/`](../../../Tools/DcrFromSchema/Examples/), one
per table plan plus two shape demonstrations:

| File | Plan | Shows |
| --- | --- | --- |
| `minimal.json` | (unset) | The smallest schema that works |
| `threat-intel-alerts.json` | Analytics | A realistic security feed, with plan and both retention values set |
| `annotated.json` | Analytics | Every optional feature: column descriptions, `displayName`, all four `dataTypeHint` values, a `guid` column, and a custom `transformKql` |
| `basic-plan.json` | Basic | Cheap ingestion with a reduced query surface, and why filterable fields stay real columns |
| `auxiliary-plan.json` | Auxiliary | Cheapest ingestion, plus the `TimeGenerated` precision constraint the plan imposes |

Every example is exercised by the test suite, which asserts the column count, the derived
transform, the declared plan, and that no example needs a single repair to be accepted.

## Table plans

The plan is chosen in the wizard, or set in the schema file. It changes cost, query capability and
what the tool is allowed to send.

| Plan | Interactive retention | Query | Alerting | Notes |
| --- | --- | --- | --- | --- |
| `Analytics` (default) | 4 to 730 days, configurable | Full KQL | Yes | The only plan where `retentionInDays` is writable |
| `Basic` | 30 days, service-fixed | Reduced KQL surface | No | Keep the fields you filter on as real columns |
| `Auxiliary` | 30 days, service-fixed | Low-fidelity query only | No | Called "Auxiliary / Lake" in the portal |

Two consequences the tool enforces:

- **`retentionInDays` is read-only on Basic and Auxiliary.** It is never sent for those plans, and
  a value supplied anyway is reported as ignored rather than silently dropped.
- **An Auxiliary table drops rows when column names differ only by case.** That makes a case-only
  collision a warning on Analytics and Basic (where the names are genuinely two distinct columns)
  but a hard failure the moment Auxiliary is chosen.

Auxiliary tables also only accept `TimeGenerated` as ISO 8601 with six decimal places
(`2026-07-30T09:15:22.123456Z`). That is a constraint on the **sender**, not on the schema, so the
tool cannot enforce it; `auxiliary-plan.json` documents it on the column instead.

## What the wizard does

1. **Read the schema.** Repairs paste damage if the file will not parse, and reports every repair.
2. **Azure context.** Signs in if needed, then offers a numbered list of subscriptions.
3. **Pick the workspace.** One `Get-AzOperationalInsightsWorkspace` call lists every workspace in
   the subscription with its resource group and region, so choosing the workspace answers all three
   questions at once. The operator never has to know its resource group.
4. **Review the schema.** Prints each column with its table type, the stream type it maps to, and
   any problem. Errors must be resolved; warnings can be accepted. Rename, retype, add or remove
   columns, or let it fix what has one obvious answer. If the table already exists, the live schema
   is diffed against the file first.
5. **Table settings.** Plan, interactive retention, total retention.
6. **DCR settings.** Name, resource group, the transform (shown and editable), and a Data
   Collection Endpoint if one is needed.
7. **Write the templates.** Always. Nothing has to be deployed to get an artefact.
8. **Deploy.** Offered, not assumed. Creates the table, deploys the rule, optionally grants the
   ingestion role, and prints the ready ingestion URL.

## Validation, and where every rule comes from

Every limit and enum is taken from the Azure Monitor documentation rather than from experience, so
the wizard rejects what Azure rejects and nothing more. The script's constants block carries the
same citations.

| Check | Rule | Source |
| --- | --- | --- |
| Column type | One of `boolean`, `dateTime`, `dynamic`, `guid`, `int`, `long`, `real`, `string` | Tables API `Column.type` enum |
| `dataTypeHint` | One of `armPath`, `guid`, `ip`, `uri`. Validated, but **not emitted** by default, see [dataTypeHint is documented but rejected](#datatypehint-is-documented-but-rejected) | Tables API `Column.dataTypeHint` enum |
| Stream column type | One of `boolean`, `datetime`, `dynamic`, `int`, `long`, `real`, `string`. No `guid` | DCR `ColumnDefinition.type` enum |
| Plan | `Analytics`, `Basic` or `Auxiliary` | Tables API `TableProperties.plan` enum |
| `retentionInDays` | 4 to 730, or `-1` for the workspace default. Read-only on Basic and Auxiliary | Tables API `TableProperties` |
| `totalRetentionInDays` | 4 to 4383, or `-1` to match interactive retention | Tables API `TableProperties` |
| Column name | Starts with an ASCII letter, then letters, digits and underscores only, 2 to 45 characters | Add or delete tables and columns |
| Reserved column names | `id`, `BilledSize`, `IsBillable`, `InvalidTimeGenerated`, `TenantId`, `Title`, `Type`, `UniqueId`, `_ItemId`, `_ResourceGroup`, `_ResourceId`, `_SubscriptionId`, `_TimeReceived`, plus `MG`, `ManagementGroupName`, `SourceSystem` | Add or delete tables and columns, plus platform-populated names carried over from ClassicToDcr where they were hit in practice |
| `TimeGenerated` | Required on every table | Add or delete tables and columns |
| Table name | Ends `_CL`, 4 to 63 characters | Tables API resource name constraint |
| Column count | 500 maximum | Azure Monitor service limits |
| Transform length | 15,360 characters maximum | Azure Monitor service limits, data collection rules |
| Description length | 256 characters maximum, on both the table schema and the rule. **Undocumented**, observed only as a preflight rejection | `InvalidProperty` on `Properties.Description` |

Two places where the tool is deliberately **stricter** than the API, both documented in the code:

- **Table name characters.** ARM's own pattern is `^[A-Za-z0-9-_]+$`, which accepts
  `9-my-table_CL`. That deploys and is then unusable without bracket-quoting the table in every
  KQL query that touches it, so the tool requires a leading letter and no hyphens.
- **Column length cap on free text.** The description and display-name caps are the tool's, not
  Azure's. They exist so a pasted essay does not become a table description.

And one place it is deliberately **more lenient**: type aliases. `bool`, `integer`, `int32`,
`int64`, `double`, `float`, `decimal`, `uuid`, `object`, `array`, `date` and `timestamp` are
normalised to the canonical type rather than rejected, because those are typos of spelling, not of
intent.

A wrong **type** is never guessed. Choosing between `long` and `real` for a column called `Count`
changes what gets stored, so that stays a decision for whoever knows the data. Errors block the
run; warnings are reported and can be accepted. Under `-NonInteractive` the wizard repairs what has
one sensible answer and fails on anything else, because a pipeline that silently ships a broken
schema is worse than one that stops.

### What "repair" is allowed to do

| Problem | Repair | Why |
| --- | --- | --- |
| No `TimeGenerated` | Add it as `dateTime` | Required, and there is only one correct answer |
| `TimeGenerated` declared as another type | Correct it to `dateTime` | Same |
| Column name Azure will reject | Drop the column | The column cannot exist under that name |
| Exact duplicate column name | Drop the repeat | Keeping both is impossible |
| Invalid `dataTypeHint` | Drop the hint, keep the column | A hint is a display annotation; losing it beats losing the column |
| Invalid column type | **Nothing** | Guessing changes what is stored |
| Case-only name collision | **Nothing** (warning only) | On Analytics and Basic these are two real columns |

## dataTypeHint is documented but rejected

`dataTypeHint` is validated against its documented enum but **not emitted** unless
`-IncludeDataTypeHint` is passed. That is a deliberate refusal to trust the documentation.

Both the [ARM template reference](https://learn.microsoft.com/azure/templates/microsoft.operationalinsights/workspaces/tables)
and the [REST reference](https://learn.microsoft.com/rest/api/loganalytics/tables/create-or-update)
document `ColumnDataTypeHintEnum` as exactly four values, at every api-version from 2023-09-01 to
2025-07-01:

| Value | Documented meaning |
| --- | --- |
| `uri` | A string matching the pattern of a URI |
| `guid` | A standard 128-bit GUID |
| `armPath` | An Azure Resource Manager resource path |
| `ip` | A standard V4/V6 IP address |

Sending exactly those values, on `string` columns, in a table-create deployment, was rejected by the
live service:

```text
Deployment failed: User provided schema is invalid, due to - HttpClient: Response status code does
not indicate success - 400 (Bad Request), due to reason - [Table validation failed with following
3 errors: MSG 1011: Invalid value provided for data type hint ;MSG 1011: Invalid value provided for
data type hint ;MSG 1011: Invalid value provided for data type hint]. (Code: InvalidParameter)
```

Three hints in the schema, three errors: every one of `ip`, `armPath` and `uri` was refused. So the
service's validator does not accept the enum its own published schema prescribes, and the real
accepted vocabulary is undocumented.

The trade is straightforward. A hint is a logical annotation that affects how the portal and entity
mapping present a column; it changes nothing about what is stored, what is queryable, or what the
DCR does. It is not worth failing a table creation over, so it is dropped by default and the drop
is reported:

```text
Dropping the dataTypeHint on 3 column(s): SourceIp, GatewayResourceId, CallbackUrl. The live
service rejects the documented enum values, and a hint only affects display. Pass
-IncludeDataTypeHint to send them anyway.
```

The hints stay in `annotated.json` and are still validated, so the schema keeps documenting intent
and a genuinely invalid hint (`ipaddress`) is still caught. `-IncludeDataTypeHint` exists so the
behaviour can be retested when Azure changes, without editing the script.

**To find the real values**, read them off a table that already has them. Every workspace table has
an `_ResourceId` standard column, which carries a hint:

```powershell
$path = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights" +
        "/workspaces/<ws>/tables/AzureActivity?api-version=2025-07-01"
$table = (Invoke-AzRestMethod -Path $path -Method GET).Content | ConvertFrom-Json
@($table.properties.schema.standardColumns) + @($table.properties.schema.columns) |
    Where-Object dataTypeHint | Select-Object name, type, dataTypeHint
```

Whatever casing or spelling that returns is the vocabulary the validator actually accepts.

## Sanitising pasted input

A schema is usually pasted from somewhere: a vendor's API page, an internal wiki, a colleague's
message. That journey adds things JSON does not allow, and the resulting parse error points at a
character that looks perfectly normal on screen.

Rather than hand that back to the operator, the wizard repairs the known-safe cases and reports
each one:

| Artefact | Where it comes from |
| --- | --- |
| Byte order mark | Windows editors saving as "UTF-8 with signature" |
| Curly quotes (`U+201C`, `U+201D`, `U+2018`, `U+2019`) | Word and most wikis substituting as you type |
| No-break space (`U+00A0`) | Web pastes, between tokens |
| `//` and `/* */` comments | Hand-written JSONC, and every documentation sample |
| Trailing commas before `}` or `]` | Hand-edited lists |

Comment and trailing-comma removal is a single pass that **tracks string state**, so a `//` or a
`, ]` inside a string value is left alone. That matters: a description reading
`see http://wiki/schema` would otherwise lose the rest of the line, including the closing quote and
brace.

Worth knowing which repairs actually fire: PowerShell's own `ConvertFrom-Json` is already lenient
about comments and trailing commas and accepts them without complaint, so those two branches
usually run only alongside a failure caused by something else, curly quotes being the common one.
They are kept because the reporting has to be honest about everything the file contained, and
because that leniency is a property of the current parser rather than a guarantee.

A file that parses is **never rewritten**. The repair path is only reachable after a failed parse.

### Free text, and why it is treated differently from code

Descriptions and display names are what carry paste damage, and ARM accepts all of it, so an
embedded newline or a zero-width joiner would be deployed and then sit in the portal indefinitely.
Those values have control characters (`\p{Cc}`) and format characters (`\p{Cf}`, which covers
zero-width joiners and bidi marks) replaced with spaces, runs of whitespace collapsed, and length
capped.

The **transform is code, not prose**. Collapsing its whitespace would turn a multi-line query into
one line and could change behaviour inside a string literal, so only its curly quotes and no-break
spaces are substituted (KQL accepts neither) and its length is checked against the documented
15,360-character limit.

The substituted characters are written in the source as explicit code points
(`[char]0x201C`) rather than literally. Pasting them in would make the script non-ASCII, so it
would need a byte order mark to stay readable everywhere, and an invisible no-break space in a
replacement expression cannot be reviewed and is trivially lost to a later edit. A test asserts the
script stays pure ASCII for exactly that reason.

## The guid problem

A DCR stream declaration cannot express `guid`. The documented `ColumnDefinition` type enum is
`boolean`, `datetime`, `dynamic`, `int`, `long`, `real`, `string`, and Azure Monitor stores and
queries GUIDs as strings even when the table column is declared `guid`. Microsoft's own samples
omit `guid` from the stream for this reason.

So a `guid` column is declared `string` in the stream. A plain `source` passthrough then fails,
because Azure Monitor validates that every transform output column type matches the destination
table column type:

```text
Types of transform output columns do not match the ones defined by the output stream:
TransactionId [produced:'String', output:'Guid'] (Code: InvalidTransformOutput)
```

The default transform therefore casts back:

```kusto
source | extend TransactionId = toguid(TransactionId)
```

Rather than special-case `guid`, the script compares every column's stream type against its table
type and casts on any mismatch, using the KQL function for the table type (`toguid`, `toint`,
`todatetime`, and so on). That catches every type divergence, not just the one seen first, which
matters if the type maps diverge further in future. A schema whose columns all match gets a plain
`source`.

This is the same reconciliation
[`Invoke-ClassicTableMigration.ps1`](../ClassicToDcr/Classic-to-DCR-Toolkit.md) performs, for the
same reason.

## Output, and the deployment order that matters

Two templates, written to the current directory by default:

| File | Deploy to |
| --- | --- |
| `table-<name>.json` | The **workspace's** resource group |
| `<dcrName>.json` | The **DCR's** resource group |

Two rather than one, because the table and the rule can live in different resource groups and an
ARM resource-group deployment only reaches one.

Before each deployment the template is validated with `Test-AzResourceGroupDeployment`. That is not
belt-and-braces: a **preflight** rejection means the deployment was never created, so there are no
deployment operations to read the cause from afterwards, and ARM reports only *"reported preflight
validation errors ... See inner errors for details"*. The validator returns those inner errors as
objects instead, and `Format-DeploymentError` flattens the nested `Details[]` tree into one line. A
256-character description limit hid behind three levels of that wrapping.

**The table must be deployed first.** This is not a preference. The Logs Ingestion API
documentation states it twice, "The table in the Log Analytics workspace must exist before you can
send data to it", and the constraint is enforced earlier than that wording suggests: the DCR
service validates the destination table when the **rule** is created, so a DCR naming a table that
does not exist cannot be created at all.

The failure is `InvalidOutputTable`, reported as:

```text
Table for output stream 'Custom-MyApp_CL' is not available for destination '<workspace-id>'.
Please ensure that the table exists in Log Analytics Workspace before creating or updating the rule.
```

The same code covers a table that exists but is still `Classic`, with different wording, which is
why the tool checks the subtype before it writes anything.

Nothing about the DCR or the ingestion path creates a table. That is worth stating plainly because
the API this replaces did: the legacy HTTP Data Collector API auto-created a classic `_CL` table
from the `Log-Type` header on first POST, needing no table and no DCR. It retires **2026-09-14**,
and the DCR path deliberately does not inherit the behaviour. The Azure portal's "Create custom
table" wizard is the only place it still feels automatic, and that is the portal creating the table
and the rule together in the right order, not ingestion creating anything.

The wizard's own deploy step gets the ordering right; deploying the artefacts by hand requires
keeping it:

```powershell
New-AzResourceGroupDeployment -ResourceGroupName rg-sentinel -TemplateFile ./table-myapp.json
```

```powershell
New-AzResourceGroupDeployment -ResourceGroupName rg-sentinel -TemplateFile ./dcr-myapp.json
```

Pass `-OutputDirectory ../../Infra/dcr` to land them somewhere tracked.

The table is created through an ARM template rather than a direct Tables API `PUT` so the
long-running create is handled by ARM, and so the artefact can be committed and redeployed like
everything else in the repository.

### Do you need a Data Collection Endpoint?

Usually **no**. The DCR is authored as `kind: Direct` at API version `2023-03-11`, the earliest
version carrying the `endpoints` property, so the rule receives its own `logsIngestion` endpoint.
The live proof is that a successful deploy prints a real endpoint URL.

Two api-versions are pinned, for unrelated reasons, and neither is arbitrary:

| Resource | Version | Why |
| --- | --- | --- |
| `Microsoft.OperationalInsights/workspaces/tables` | `2025-07-01` | At `2023-09-01` the Tables API documents `plan` as only `Analytics` or `Basic`. The Auxiliary plan does not exist at that version, so an Auxiliary table cannot be authored against it |
| `Microsoft.Insights/dataCollectionRules` | `2023-03-11` | The earliest version carrying the `endpoints` property. Endpoints cannot be added to an existing DCR, so authoring below this leaves a rule that permanently needs a DCE |

A DCE is required when:

- the workspace is behind **Private Link (AMPLS)**, or a sender shares DNS with AMPLS resources, or
- the DCR was created before 2024-03-31, when the service began populating `endpoints`. Endpoints
  cannot be added to an existing DCR, so such a rule has to be replaced.

Pass `-DataCollectionEndpointResourceId <dce>` and it is wired into `dataCollectionEndpointId`.

Note that the ARM template reference for `Microsoft.Insights/dataCollectionRules` documents `kind`
as only `Linux` or `Windows`. `Direct` is nonetheless correct and is what Microsoft's own
Logs Ingestion samples and the ClassicToDcr toolkit both use; the published enum lags the service.

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

The sending identity needs nothing on the workspace. Data-plane RBAC can take a few minutes to take
effect, so early POSTs may return 403.

## Unattended use

`-NonInteractive` never prompts, so anything the wizard would have asked for has to be a parameter.
Without `-Deploy` it writes the templates and stops, which is the shape to use from a pipeline that
commits the artefacts and deploys them in a later stage:

```powershell
./New-DcrFromSchema.ps1 -SchemaPath ./Examples/minimal.json -NonInteractive `
    -SubscriptionId '00000000-0000-0000-0000-000000000000' `
    -ResourceGroupName 'rg-sentinel' -WorkspaceName 'law-sentinel' `
    -OutputDirectory ../../Infra/dcr
```

`-WhatIf` works throughout. `-Force` bypasses the deploy confirmation. `-SkipTable` targets an
existing table and only produces the rule.

The script emits a single `PSCustomObject` describing the table, the DCR, both template paths and,
when deployed, the immutable ID and ingestion endpoint, so a pipeline can consume the result rather
than scrape the console.

## Sending data

A successful deploy prints the URL to POST to:

```text
<endpoint>/dataCollectionRules/<immutableId>/streams/Custom-<Table>?api-version=2023-01-01
```

Authentication is an Entra bearer token for an identity holding Monitoring Metrics Publisher on the
DCR, **not** a workspace shared key. Relevant limits: a call is capped at 1 MB (compressed or
uncompressed), a field value is truncated at 64 KB, and a single DCR accepts 2 GB and 12,000
requests per minute.

To prove ingestion end to end with synthetic data,
[`Tools/ClassicToDcr/Rehearsal/Test-DcrIngestion.ps1`](../ClassicToDcr/Rehearsal-Aids.md) builds and
sends that POST against any DCR, including one this script created.

## Design decisions

| Decision | Reasoning |
| --- | --- |
| Two templates, not one | The table and the rule can be in different resource groups, and an ARM resource-group deployment reaches only one |
| Table created via ARM, not a Tables API `PUT` | ARM handles the long-running create, and the artefact is committable |
| Templates always written, deploy always optional | The artefact is the durable output; deploying should never be a precondition for getting it |
| Standalone single file, no `Sentinel.Common` import | It has to run unchanged on a jump box or in an automation account where that module is absent |
| Workspace picker drives resource group and region | One call already returns all three, so asking for them separately is wasted friction and a source of mismatched regions |
| Case-only duplicates warn rather than fail | Analytics and Basic tables are case sensitive, so they are genuinely two columns. Failing would reject a legal schema |
| Bad types are never auto-fixed | The choice changes what is stored |
| Free text sanitised, transform only punctuation-repaired | Prose can be normalised safely; code cannot |
| Unknown schema keys dropped, not forwarded | The templates emit only what the APIs define, so pasted noise cannot reach a deployed resource |
| `-NonInteractive` fails rather than guessing | A pipeline shipping a silently-broken schema is worse than one that stops |
| Templates validated before deploying | A preflight rejection leaves no deployment operations to diagnose from, so the cause has to be captured from the validator instead |
| `dataTypeHint` validated but not sent | The service rejects the values its own reference documents. A display annotation is not worth failing a table creation over |
| Reading the existing table is advisory, not fatal | It powers two guards Azure enforces anyway. Blocking a valid deployment because one diagnostic GET returned an odd shape is the wrong trade |
| Every prompt with a default says "Enter to accept" | A free-text prompt showing only `[rg-sentinel]`, between two `[y/N]` questions, got answered `y` and produced a resource group named `y` |
| The DCR resource group is checked to exist up front | Otherwise a typo is caught only by ARM, several steps and one created table later, as `ResourceGroupNotFound` |
| Error formatters never return empty | An unrecognised error shape is exactly when the caller most needs output; reporting a failure with no reason wastes a whole debugging cycle |

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `InvalidOutputTable`, "Table for output stream ... is not available for destination" | The table does not exist. The rule is validated against the destination table at create time, so this blocks DCR creation, not just ingestion. Deploy the table template first |
| `InvalidOutputTable`, "Classic (MMA-based) custom log tables ... are not supported" | The table exists but is still `Classic`. Migrate it with [ClassicToDcr](../ClassicToDcr/Classic-to-DCR-Toolkit.md) |
| `InvalidTransformOutput` | A stream type differs from the table type. Handled automatically for `guid` and anything else; regenerate the templates with the current script |
| The wizard refuses: live column types differ | A column's type cannot be changed after creation. Align the schema with the live table, or use a new table name |
| The wizard refuses the Auxiliary plan | Two column names differ only by case, and Auxiliary ingestion drops rows because of it. Rename them, or choose Analytics or Basic |
| "This tool takes a schema, not a sample of the data" | The file is the JSON you want to ingest, not a description of its columns. Write a `columns` list |
| `Schema file needed cleaning up before it would parse` | Paste damage was repaired. The run continues; fix the source file so it is not needed next time |
| New table not queryable yet | First-ingestion query availability lags 10 to 15 minutes. Wait and re-check |
| 403 on the first POST | Data-plane RBAC propagation. Retry after a few minutes |
| No `logsIngestion` endpoint on the deployed rule | Endpoints cannot be added to an existing DCR. It needs a DCE, or a replacement rule |
| A column stops receiving data after a rename | The stream declaration and the sender's payload keys have to agree. Rename in the schema, regenerate, redeploy, and update the sender |
| `MSG 1011: Invalid value provided for data type hint` | The service rejects the documented `dataTypeHint` enum. Hints are suppressed by default; if you passed `-IncludeDataTypeHint`, drop it |
| `InvalidProperty: 'Description' length should be 256 characters or less` | A description longer than 256 characters. Both the table schema and the rule description are capped at that, so this should not reach Azure; if it does, the cap was bypassed |
| Retention was ignored | `retentionInDays` is read-only on Basic and Auxiliary tables. Use `totalRetentionInDays`, or the Analytics plan |

## References

| Topic | Page |
| --- | --- |
| Tables resource: column type, `dataTypeHint`, plan, retention ranges | [Microsoft.OperationalInsights/workspaces/tables](https://learn.microsoft.com/azure/templates/microsoft.operationalinsights/workspaces/tables) |
| Column naming rules, reserved names, `TimeGenerated` requirement, `_CL` suffix | [Add or delete tables and columns in Azure Monitor Logs](https://learn.microsoft.com/azure/azure-monitor/logs/create-custom-table) |
| Column count, column name length, transform length, Logs Ingestion API limits | [Azure Monitor service limits](https://learn.microsoft.com/azure/azure-monitor/fundamentals/service-limits) |
| DCR resource: `streamDeclarations`, `dataFlows`, `kind` | [Microsoft.Insights/dataCollectionRules](https://learn.microsoft.com/azure/templates/microsoft.insights/datacollectionrules) |
| The ingestion path this DCR serves | [Logs Ingestion API overview](https://learn.microsoft.com/azure/azure-monitor/logs/logs-ingestion-api-overview) |
| Table plans and what each costs | [Azure Monitor Logs data platform](https://learn.microsoft.com/azure/azure-monitor/logs/data-platform-logs) |
