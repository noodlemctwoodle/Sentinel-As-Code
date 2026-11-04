# Custom tables from a schema

`New-iSOCDcrFromSchema` turns a JSON table schema into a Log Analytics
custom table and a Direct data collection rule for the Logs Ingestion
API. It writes two ARM templates and, with `-Deploy`, deploys them in
order and grants the senders their role.

| Command | Replaces |
| --- | --- |
| `New-iSOCDcrFromSchema` | `Tools/DcrFromSchema/New-DcrFromSchema.ps1` |

It replaces the script at the 26.11.0 cut-over. For a table that already
exists as a classic table, use the
[classic table migration](Table-Migration.md) instead.

```powershell
Import-Module ./Modules/iSOCDeployments
Connect-AzAccount
Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel

# Read the workspace and say what a real run would write.
New-iSOCDcrFromSchema -SchemaPath ./threat-intel-alerts.json -WhatIf

# Write the two templates, deploying nothing.
New-iSOCDcrFromSchema -SchemaPath ./threat-intel-alerts.json -OutputDirectory ./Infra/dcr

# Create the table and the rule, and grant the sender its role.
New-iSOCDcrFromSchema -SchemaPath ./threat-intel-alerts.json -Deploy -GrantIngestionRoleTo $appId
```

Nothing prompts. Every value the script's wizard asked for comes from a
parameter, from the schema file, or from the default the script's
unattended run took. It needs Az.Accounts, and Az.Resources with
`-Deploy`. The table needs Log Analytics Contributor on the workspace, the
rule Contributor on its resource group, and `-GrantIngestionRoleTo` Owner
or User Access Administrator on the rule.

## The schema file

Three shapes are read:

- `{ "tableName": "MyApp_CL", "columns": [ { "name": "...", "type": "..." } ] }`
- a table as the Tables API returns it, `{ "properties": { "schema": { "name", "columns" } } }`,
  so a table read from Azure can be fed back in
- a bare array of columns, with `-TableName` naming the table

The file can carry defaults for `description`, `dcrName`, `location`,
`plan`, `retentionInDays`, `totalRetentionInDays` and `transformKql`. A
parameter wins over the file; without either, the description is
`Custom log table <table>.`, the plan Analytics, the rule
`dcr-<table without _CL, lower case>` in the workspace's resource group,
and retention is left to the workspace. The examples under
[`Tools/DcrFromSchema/Examples/`](../../../Tools/DcrFromSchema/Examples)
show each.

A file that will not parse is repaired of what a paste picks up (a byte
order mark, curly quotes, no-break spaces, comments, trailing commas),
with a warning naming each repair; a file that parses is never changed.
Descriptions and display names are cleaned before they are written into
Azure, and keys the Tables API does not define are dropped.

## What is checked

Before anything is written:

- the table name ends `_CL` (added when missing), starts with a letter and
  is 4 to 63 letters, digits and underscores, so KQL can name it unquoted
- each column name starts with an ASCII letter, is 2 to 45 letters,
  digits and underscores, and is not a system or reserved name; each type
  is one of the Tables API's eight (`bool`, `integer`, `double` and other
  aliases are accepted)
- no name repeated exactly; names that differ only by case are a warning,
  and refused on an Auxiliary table, which drops rows over them
- `TimeGenerated` exists and is a datetime; at most 500 columns; a
  transform of at most 15,360 characters; descriptions of at most 256
- a table that already exists is not classic, and no column's type
  differs from it. This read is advice: when it fails, the run goes on
  with a warning naming the two checks it skipped, and Azure still refuses
  both
- the rule's resource group exists

What has one sensible fix is fixed, with a warning: a column whose name
Azure will never accept is dropped, as is an exact repeat; an invalid
`dataTypeHint` is removed; `TimeGenerated` is added or made a datetime.
Anything else stops the run. A bad type is never guessed at.

## The templates

`table-<table without _CL, lower case>.json` and `<rule>.json`, in
`-OutputDirectory` (the current folder unless given). Two templates,
because the table and the rule can be in different resource groups and a
resource group deployment reaches one. Their keys are in a fixed order,
so the same schema writes the same file, with LF line endings and one
final newline.

- The table is written at Tables API 2025-07-01, the first version with
  the Auxiliary plan. `retentionInDays` is sent only for an Analytics
  table: it is read-only on Basic and Auxiliary. `dataTypeHint` is not
  sent unless `-IncludeDataTypeHint`, because the live service refuses the
  values its documentation prescribes.
- The rule is a Direct rule at 2023-03-11, the first version with
  `endpoints`, so it has its own logs ingestion endpoint and needs a data
  collection endpoint only behind Private Link. A stream cannot declare
  `guid`, so a guid column is declared `string` and the default transform
  casts it back (`EventId = toguid(EventId)`).

## Deploying

With `-Deploy`, the table deploys to the workspace's resource group, then
the rule to its own: a rule whose output stream names a missing table
fails with InvalidOutputTable. Each template is validated against its
resource group first, so a preflight rejection says why rather than "See
inner errors for details". The rule's immutable id and logs ingestion
endpoint are read back, and each identity in `-GrantIngestionRoleTo` (an
application id or any principal's object id) is given Monitoring Metrics
Publisher on the rule; one already holding it is left alone, and one that
cannot be granted is a warning with the command to run by hand.
Data-plane role assignments can take a few minutes to apply.

Each write and deployment asks ShouldProcess: `-WhatIf` reads the
workspace and writes nothing, and `-Confirm` asks before each one.

## The result

An `iSOCDeployments.DcrFromSchemaRun`, with the script's properties:

| Property | What it holds |
| --- | --- |
| `TableName`, `ColumnCount` | The table and how many columns it has |
| `WorkspaceName`, `ResourceGroupName` | The workspace |
| `DcrName`, `DcrResourceGroup`, `Location` | The rule |
| `StreamName`, `TransformKql` | Its stream and transform |
| `TableTemplatePath`, `DcrTemplatePath` | The templates (no table template with `-SkipTable`) |
| `Deployed`, `ImmutableId`, `Endpoint` | Whether the rule deployed, and what a sender posts to |
| `Granted` | The identities that hold the ingestion role |

After a deployment, `Test-iSOCDcrIngestion -DcrName <rule> -DcrResourceGroupName <group> -Follow`
proves ingestion end to end with synthetic data.

## From the script

| `New-DcrFromSchema.ps1` | `New-iSOCDcrFromSchema` |
| --- | --- |
| `-SubscriptionId`, `-ResourceGroupName`, `-WorkspaceName` | `Connect-iSOCWorkspace` first (or `-Context`) |
| `-NonInteractive` | Not needed: nothing prompts |
| `-Force` | Not needed: deploying asks only under `-Confirm` |
| Every other parameter | The same; `-SchemaPath` is required |

The schema review's editor is not ported: fix the schema file and run
again. `Tests/iSOCDeployments/DcrFromSchema.Tests.ps1` runs the script
unchanged with `-NonInteractive` beside the command, over a stand-in
workspace whose tables and rules appear as they are deployed, and both
must validate, deploy and grant the same, write the same templates and
return the same result or refuse with the same message. `MIGRATION.md`
edit E41 lists how the command differs from the script.
