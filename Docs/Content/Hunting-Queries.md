# Hunting Queries

Custom threat hunting queries authored in YAML and deployed to Microsoft Sentinel as saved searches via the Log Analytics REST API. Unlike analytics rules, hunting queries do not generate alerts or incidents; they are executed manually or on-demand by analysts conducting proactive threat hunts.

Source files live under [`Content/HuntingQueries/`](../../Content/HuntingQueries).

The [Sentinel as Code Toolkit](../Toolkit/Templates.md) VS Code extension scaffolds and validates this content type: it ships the canonical hunting-query [template](../Toolkit/Templates.md) and the [schema](../Toolkit/Schemas-and-Validation.md) used for real-time authoring validation. The field contract documented below is taken from that Toolkit schema and template (the source of truth); the Toolkit authors and validates hunting queries, and this repository's pipeline deploys them.

## How Hunting Queries Differ from Analytics Rules

| | Analytics Rules | Hunting Queries |
|---|---|---|
| Deployment API | Sentinel Alert Rules API | Log Analytics Saved Searches API |
| Execution | Automated on a schedule | Manual / on-demand |
| Output | Alerts and incidents | Query results for analyst review |
| Purpose | Reactive detection | Proactive threat hunting |
| Severity | Required | Not applicable |
| Trigger threshold | Required | Not applicable |

Hunting queries appear in **Microsoft Sentinel > Hunting** and can be run directly from the portal, bookmarked, or promoted to analytics rules if they identify high-signal behaviour worth automating. For analytics rule schema, see [Analytical Rules](Analytical-Rules.md).

## Folder Structure

`Deploy-CustomHuntingQueries` walks `Content/HuntingQueries/` recursively (`Get-ChildItem -Recurse`), so the subfolder layout is purely organisational and has no bearing on how a query is deployed. The convention in this repository is to group queries by **log-source table**, with a couple of tactic-named folders retained for identity- and persistence-focused queries.

The tree currently holds twelve subfolders. Ten are named after the primary table the queries read from, and two (`Identity/`, `Persistence/`) follow a MITRE-tactic naming:

```
Content/HuntingQueries/
  AzureActivity/               # table-sourced
  DeviceProcessEvents/         # table-sourced
  Identity/                    # tactic-named
  MicrosoftGraphActivityLogs/  # table-sourced
  Persistence/                 # tactic-named
  SecurityAlert/               # table-sourced
  SecurityEvent/               # table-sourced
  SecurityIncident/            # table-sourced
  SigninLogs/                  # table-sourced
  UnifiedSignInLogs/           # table-sourced
  Usage/                       # table-sourced
  pfSense/                     # table-sourced
```

Place new queries in whichever folder best matches their primary data source (or reuse one of the tactic folders if that reads more naturally). Create a new folder if none fits.

## YAML Schema

The Toolkit schema defines exactly seven fields (it is closed, `additionalProperties: false`). Author them in the canonical order the Toolkit template uses: `id`, `name`, `description`, `query`, `tactics`, `techniques`, `tags`. Three fields are required (`id`, `name`, `query`); the rest are optional. The Toolkit's **Fix Field Order** command reorders a file into this order for you.

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (GUID) | Stable unique identifier used as the saved search resource name. Must match the `8-4-4-4-12` hex GUID pattern. Generate with `New-Guid`. Must not change after initial deployment, the PUT is idempotent on this value. |
| `name` | string | Display name shown in the Sentinel Hunting blade. 1 to 260 characters (schema `minLength` 1, `maxLength` 260). |
| `query` | string | KQL query (at least one character). There is no scheduling or threshold, the query returns results directly when run by an analyst. |

`Deploy-CustomHuntingQueries` hard-requires only `id`, `name`, and `query` (files missing any of these are skipped with a warning). The CI Pester schema gate is stricter, see the note under Optional Fields.

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | Plain-English explanation of what the query hunts for and why it is interesting. Begins with "Identifies" or "Detects". Optional in the schema, but **enforced as required by CI** (see note below), even though the deploy script itself treats it as optional. |
| `tactics` | string[] | MITRE ATT&CK tactic names in camelCase / PascalCase (e.g., `InitialAccess`, `Persistence`); schema pattern `^[A-Z][a-zA-Z]{2,30}$`. Joined with commas and stored as a single `tactics` tag on the saved search. |
| `techniques` | string[] | MITRE ATT&CK technique IDs (e.g., `T1078`, `T1098.001`); schema pattern `^T[0-9]{4}(\.[0-9]{3})?$`, so sub-techniques (`T####.###`) are allowed. Split at deploy time into parent-technique and sub-technique tags (see API Mapping). |
| `tags` | object[] | Additional key-value metadata pairs. Each entry must have exactly a `name` and a `value` string (the schema is closed, no other keys per entry). Appended after the standard tactics/techniques tags at deploy time. |

> **CI note:** `Tests/Test-AnalyticalRuleYaml.Tests.ps1` (the `Hunting query schema` `Describe` block) includes a `has a non-empty description` assertion, so a missing or blank `description` fails PR validation. In practice `description` is required for any query merged to `main`, even though `Deploy-CustomHuntingQueries` would deploy a query without one. This is deliberate two-layer validation: the deploy script is lenient (each optional field is individually `ContainsKey`-checked), while the CI gate is strict.

> **Schema note (`requiredDataConnectors`):** The Toolkit hunting-query schema is closed (`additionalProperties: false`) and defines only the seven fields above, so the Toolkit validator flags any other key, including `requiredDataConnectors`, as unknown. A few queries in this repository (for example `Persistence/ChangesToAzureLighthouseDelegation.yaml`) still carry a `requiredDataConnectors` block. The repository's own CI schema gate only asserts `id`, `name`, `description` and `query`, so it tolerates the extra field, and `Deploy-CustomHuntingQueries` ignores it (it is never read into the saved-search body). If you author with the Toolkit, either drop the field or expect a validation warning. See [Schemas and validation](../Toolkit/Schemas-and-Validation.md).

### API Mapping

The pipeline converts each YAML file to a PUT request against the Log Analytics Saved Searches API. The api-version comes from the `$script:SavedSearchApiVersion` variable in `Deploy/content/Deploy-CustomContent.ps1` (currently `2025-07-01`, the same version used for parsers), so it is defined in one place rather than hard-coded per call:

```
PUT /subscriptions/{sub}/resourceGroups/{rg}/providers/
    Microsoft.OperationalInsights/workspaces/{workspace}/
    savedSearches/{id}?api-version=2025-07-01
```

The request body is built by `Deploy-CustomHuntingQueries`. The tags array is assembled in a fixed order: `description` (if present), then `tactics` (the YAML array joined with commas into one tag), then the technique tags, then any custom `tags` entries.

Techniques are **split into two tags**. Every entry is reduced to its parent ID by stripping any `.###` sub-suffix; the deduped parent IDs form the `techniques` tag. Any entries that carried a sub-suffix are deduped into a separate `subTechniques` tag, which is only emitted when at least one sub-technique is present. So `techniques: [T1078, T1098.001]` produces:

```json
{
  "properties": {
    "category": "Hunting Queries",
    "displayName": "<name>",
    "query": "<query>",
    "tags": [
      { "name": "description",   "value": "<description>" },
      { "name": "tactics",       "value": "InitialAccess,Persistence" },
      { "name": "techniques",    "value": "T1078,T1098" },
      { "name": "subTechniques", "value": "T1098.001" }
    ]
  }
}
```

The `tags` property is only set when at least one tag was produced. Custom `tags` entries from the YAML are appended to the array after the standard fields.

## Example YAML

```yaml
id: "d4e5f6a7-b8c9-4d0e-a1b2-c3d4e5f6a7b8"
name: "Suspicious sign-in from new country"
description: "Identifies users signing in from countries not seen in the last 14 days, which may indicate compromised credentials."
query: |
  let lookback = 14d;
  let knownLocations = SigninLogs
      | where TimeGenerated between (ago(lookback) .. ago(1d))
      | where ResultType == 0
      | summarize Countries = make_set(LocationDetails.countryOrRegion) by UserPrincipalName;
  SigninLogs
  | where TimeGenerated > ago(1d)
  | where ResultType == 0
  | extend Country = tostring(LocationDetails.countryOrRegion)
  | join kind=inner knownLocations on UserPrincipalName
  | where Countries !has Country
  | project TimeGenerated, UserPrincipalName, Country, IPAddress, AppDisplayName, DeviceDetail
tactics:
  - InitialAccess
techniques:
  - T1078
```

### Example with Custom Tags

```yaml
id: "b2c3d4e5-f6a7-8901-bcde-234567890bcd"
name: "Dormant account reactivation"
description: "Identifies accounts with no sign-in activity in 90 days that have suddenly become active."
query: |
  SigninLogs
  | where TimeGenerated > ago(1d)
  | where ResultType == 0
  | join kind=leftanti (
      SigninLogs
      | where TimeGenerated between (ago(91d) .. ago(1d))
      | where ResultType == 0
      | summarize by UserPrincipalName
  ) on UserPrincipalName
  | project TimeGenerated, UserPrincipalName, IPAddress, AppDisplayName
tactics:
  - InitialAccess
techniques:
  - T1078
tags:
  - name: "dataSource"
    value: "SigninLogs"
  - name: "huntingPackage"
    value: "IdentityBaseline"
```

## Deployment Behaviour

Hunting queries are stage 4 of the eight-stage `Deploy-CustomContent.ps1` run (Parsers, Watchlists, Detections, **Hunting Queries**, Playbooks, Workbooks, Automation Rules, Summary Rules). Each query file passes through the same shared gates as every other content type before it is PUT:

- **Dependency pre-flight (`Test-ContentDependencies`).** Before deploy, each query is checked against the dependency graph (`dependencies.json`). If a required table, watchlist, or function is missing, the query is **skipped entirely** with a warning listing the missing items. Note the difference from analytics rules: a rule with unmet dependencies deploys in a **disabled** state, whereas a hunting query (like the other non-detection content types) is simply skipped.
- **Smart deployment / deployment state (`Test-ShouldDeployFile`).** When smart deployment is enabled, a query whose content is unchanged since the last successful run (tracked in the deployment-state file) is skipped with an "Unchanged ... (smart deployment)" message. Smart deployment is an opt-in `-SmartDeployment` switch that **defaults to off**; with it off, every query is (re)deployed on each run. On a successful PUT the file's state is recorded via `Set-DeploymentItemState`.
- **`-SkipHuntingQueries` switch.** Passing `-SkipHuntingQueries` to `Deploy-CustomContent.ps1` skips stage 4 wholesale (the run log shows `Hunting: SKIP`), leaving existing saved searches untouched. Use this to deploy other content types without touching hunting queries.

`ConvertTo-Json` serialises the body at a depth of 10, and `-WhatIf` performs a dry run that logs the intended deploy without calling the API.

## Prerequisites

The identity used by the pipeline (service principal or managed identity) requires one of the following roles on the Log Analytics workspace:

- **Contributor** (resource group or workspace scope)
- **Microsoft Sentinel Contributor** (workspace scope)

The `Microsoft.OperationalInsights/workspaces/savedSearches/write` permission is what the deployment needs specifically. Sentinel Contributor grants this alongside all other Sentinel-scoped permissions.

## Adding Hunting Queries

### From Scratch

1. Generate a stable GUID: `New-Guid` (PowerShell) or `uuidgen` (bash/macOS).
2. Author the KQL query in the Sentinel **Logs** blade to validate results before committing.
3. Create a YAML file following the schema above and place it in the folder that matches its primary log source (or one of the tactic folders, see Folder Structure).
4. Open a pull request; the pipeline will deploy the query on merge to `main`.

### Exporting Existing Queries from the Sentinel Portal

1. Navigate to **Microsoft Sentinel > Hunting**.
2. Locate the query you want to export.
3. Click the query name to open the details panel, then click **View query results** to confirm it runs.
4. From the query row, select **...** (ellipsis menu) > **Clone query** or note the KQL from the details panel.
5. Create a new YAML file using the schema above, pasting the KQL into the `query` field.
6. Generate a fresh GUID for `id` with `New-Guid`; do not reuse an existing ID unless you intend to overwrite the saved search in place.
7. Commit the file to this repository so it is source-controlled and deployed idempotently going forward.

### From the Azure-Sentinel GitHub

The [Azure-Sentinel Hunting Queries folder](https://github.com/Azure/Azure-Sentinel/tree/master/Hunting%20Queries) contains community queries organised by log source. These are in `.yaml` format but use a different schema (they target the Content Hub, not the Saved Searches API directly). When adapting them:

1. Copy the `description`, `query`, `tactics`, and `relevantTechniques` fields.
2. Generate a new GUID for `id`.
3. Map `relevantTechniques` to the `techniques` field in this schema.
4. Validate the KQL in the Logs blade before committing.

## Authoring with GitHub Copilot

When editing files under `Content/HuntingQueries/**`, Copilot automatically
loads [`.github/instructions/hunting-queries.instructions.md`](../../.github/instructions/hunting-queries.instructions.md)
plus the cross-cutting
[`.github/instructions/kql-queries.instructions.md`](../../.github/instructions/kql-queries.instructions.md).

Copilot tooling for hunting queries:

- Slash command `/new-hunting-query` (VS Code), bootstrap a fresh query
- Agent `Sentinel-As-Code: Rule Author`, author end-to-end
- Agent `Sentinel-As-Code: KQL Engineer`, optimise the query body

See [GitHub Copilot setup](../GitHub/GitHub-Copilot.md) for the full layout.
