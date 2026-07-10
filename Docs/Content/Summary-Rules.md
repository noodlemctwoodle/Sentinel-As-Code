# Summary Rules

## Overview

Summary rules are an Azure Monitor (Log Analytics) feature that execute scheduled batch KQL queries and write aggregated results into a custom `_CL` destination table. They run automatically on a fixed time cadence called a **bin**, processing all data that arrived within each bin's time window.

Source files live under [`Content/SummaryRules/`](../../Content/SummaryRules).

### Why Use Summary Rules?

**Cost reduction** - Verbose tables ingested into Basic or Auxiliary tier (e.g. `SigninLogs`, `AuditLogs`, `CommonSecurityLog`) can be pre-aggregated into small Analytics-tier custom tables. Downstream queries, workbooks, and analytics rules then hit the cheap summary table instead of the expensive source.

**Performance** - Pre-aggregated data means dashboards and workbooks return results in milliseconds rather than scanning millions of raw rows on every load.

**Privacy / data minimisation** - The summary query can omit, hash, or truncate PII columns (e.g. `UserPrincipalName`, IP addresses) before writing to the destination, reducing the surface area of sensitive data in the workspace.

---

## Important: API Provider

Summary rules are a **Log Analytics / Azure Monitor** feature. They use the `Microsoft.OperationalInsights` provider, **not** `Microsoft.SecurityInsights`. The deployment script targets:

```
PUT https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.OperationalInsights/workspaces/{workspace}/summarylogs/{ruleName}?api-version=2025-07-01
```

---

## Folder Structure

JSON files can be placed directly in `Content/SummaryRules/` or organised into subfolders by data source, use case, or team. The deployment script discovers all `*.json` files recursively.

```
Content/SummaryRules/
├── SignInSummaryByCountry.json
├── SecurityAlertSummary.json
├── Identity/
│   └── ...
├── Network/
│   └── ...
└── Endpoint/
    └── ...
```

---

## JSON Schema

Each summary rule is defined as a single JSON file. The top-level keys map directly to the `ruleDefinition` block in the REST API body, with `name`, `description`, and `displayName` promoted to the top level for readability.

The authoring contract below (field names, required-vs-optional, types, patterns, and allowed values) is defined by the Sentinel as Code Toolkit schema `sentinel-summary-rule-schema.json`. The Toolkit scaffolds summary rules as a commented YAML template; you author the YAML, then run its Convert Content YAML to JSON command to produce the JSON form stored on disk here, and it validates that JSON against the same schema in the editor. See [Toolkit Templates](../Toolkit/Templates.md) and [Schemas and Validation](../Toolkit/Schemas-and-Validation.md).

### Required Fields

| Field | Type | Description |
|---|---|---|
| `name` | string | Rule name. Used as the resource name in the URL path. Must be unique within the workspace. Alphanumeric and hyphens only. |
| `query` | string | KQL summarization query. Must NOT include time filters (the bin boundary is the implicit time window). See [KQL Query Restrictions](#kql-query-restrictions). |
| `binSize` | integer | Bin size in minutes. See [Allowed binSize Values](#allowed-binsize-values). |
| `destinationTable` | string | Target custom log table name. Must end with the `_CL` suffix. |

### Optional Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `displayName` | string | Same as `name` | Display name shown in the Azure portal. |
| `description` | string | None | Human-readable description of the rule's purpose. |
| `binDelay` | integer | Service default (between 3.5 minutes and 10% of `binSize`) | Wait time in minutes before executing each bin, to account for ingestion latency. Integer between `0` and `1440`. Increase this if your source table has high ingestion lag. |
| `binStartTime` | string (ISO 8601) | None | Timestamp at which the first bin starts. Must fall on a whole hour boundary. Format: `YYYY-MM-DDTHH:MM:SSZ`. |

No other keys are permitted: the schema sets `additionalProperties: false`, so any field not listed above is rejected by validation.

### Field Order

The canonical field order (from the Toolkit template) is `name`, `displayName`, `description`, `query`, `binSize`, `destinationTable`, `binDelay`, `binStartTime`. The Full Example below follows this order. The Toolkit's Fix Field Order command reorders keys to match.

### Full Example

```json
{
  "name": "SignInSummaryByCountry",
  "displayName": "Sign-in summary by country",
  "description": "Hourly aggregation of successful and failed sign-ins by country and application for cost-effective trend analysis.",
  "query": "SigninLogs\n| summarize SuccessCount = countif(ResultType == 0), FailureCount = countif(ResultType != 0), DistinctUsers = dcount(UserPrincipalName) by Location = tostring(LocationDetails.countryOrRegion), AppDisplayName",
  "binSize": 60,
  "destinationTable": "SignInSummaryByCountry_CL",
  "binDelay": 10,
  "binStartTime": "2026-01-01T00:00:00Z"
}
```

Note that this example includes `binStartTime` for completeness, but neither of the two live samples shipped in `Content/SummaryRules/` (`SignInSummaryByCountry.json`, `SecurityAlertSummary.json`) sets it: both let the first bin start immediately, which is the usual choice unless you need bins to align to a specific hour boundary.

---

## Allowed binSize Values

| Value (minutes) | Human-readable |
|---|---|
| `20` | 20 minutes |
| `30` | 30 minutes |
| `60` | 1 hour |
| `120` | 2 hours |
| `180` | 3 hours |
| `360` | 6 hours |
| `720` | 12 hours |
| `1440` | 24 hours (1 day) |

Choose the smallest bin that satisfies your latency requirements. Smaller bins produce fresher data but generate more rule executions. For SOC dashboards that refresh hourly, `60` is a sensible default.

---

## KQL Query Restrictions

Summary rule queries run against a fixed time window determined by the bin boundary. The following restrictions apply:

### Time Filters
- **Must NOT include explicit time filters** (`where TimeGenerated > ago(...)`, `| where _time between ...`, etc.). The bin start and end timestamps are injected automatically. Including a time filter will cause incorrect or empty results.

### Unsupported Cross-Resource Functions
The following functions are not permitted in summary rule queries:
- `workspaces()` - cross-workspace queries
- `app()` - Application Insights queries
- `resource()` - cross-resource queries
- `adx()` - Azure Data Explorer queries
- `arg()` - Azure Resource Graph queries

### Unsupported Plugins
- `bag_unpack` - schema-reshaping plugin
- `narrow` - schema-reshaping plugin
- `pivot` - schema-reshaping plugin

### Other Restrictions
- No user-defined functions (UDFs)
- No `union *` or `union` with `isfuzzy=true`
- Basic or Auxiliary tier source tables may only join up to **5 Analytics-tier tables** using the `lookup` operator

---

## System Columns

The following columns are automatically appended to every row written to the destination table by the runtime. You do not need to include these in your query.

| Column | Type | Description |
|---|---|---|
| `_RuleName` | string | Name of the summary rule that produced the row. |
| `_RuleLastModifiedTime` | datetime | Timestamp of the last rule modification. |
| `_BinSize` | int | Bin size in minutes for this execution. |
| `_BinStartTime` | datetime | Start timestamp of the bin that produced the row. |

---

## Limitations

| Limit | Value |
|---|---|
| Max active rules per workspace | 100 |
| Max `binDelay` | 1440 minutes |
| Max result record size | 1 MB |
| Consecutive bin failure threshold | 8 (rule suspended after 8 consecutive failures) |
| Cloud availability | Public cloud only - not available in sovereign or government clouds |

**No historical backfill** - Summary rules process incoming data from the point of activation onwards. They do not retroactively process data that was ingested before the rule was created or enabled.

---

## Prerequisites

The identity running the deployment (service principal, managed identity, or user) requires the **Log Analytics Contributor** role on the target Log Analytics workspace. This is distinct from any Microsoft Sentinel roles, which operate at the workspace level via `Microsoft.SecurityInsights`. See [Pipelines](../Pipelines/README.md) for end-to-end pipeline RBAC.

---

## Dependency Checks and Smart Deployment

Summary rules go through the same two shared gates that every other content type in `Deploy-CustomContent.ps1` passes through - there is nothing special about summary rules here, but it's easy to miss if you're only reading this page.

**Dependency graph gate** - before a rule is built and PUT to the API, `Deploy-CustomSummaryRules` runs it through `Test-ContentDependencies`, the same dependency-graph pre-flight check used for detections, watchlists, and parsers. If the rule's entry in `dependencies.json` declares required source tables that don't exist in the target workspace, the rule is **silently skipped** (not deployed and not deployed-disabled, unlike a detection with missing dependencies). The skip is logged with the missing dependency names, but authors adding a summary rule that reads from a table another PR hasn't deployed yet should be aware the rule simply won't appear rather than appearing in a disabled state.

**Smart deployment** - when the deployment is run with `-SmartDeployment`, `Test-ShouldDeployFile` skips any summary rule JSON file that is unchanged since the last successful deployment, and retries any file that previously failed. `-SmartDeployment` is an opt-in switch that defaults to off, so a full deploy (the default) processes every file in `Content/SummaryRules/` regardless of change state. Deployment outcomes (success/failed) are recorded per file via `Set-DeploymentItemState`, the same state tracking used by every other content type.

**Skipping the stage entirely** - pass `-SkipSummaryRules` to `Deploy-CustomContent.ps1` to omit the Summary Rules stage from the run altogether (stage 8 of 8; see [Content Deployment Order](../Pipelines/README.md) for the full stage list).

**`-WhatIf`** - with `-WhatIf`, each rule that passes validation and the dependency gate is logged as `[WhatIf] Would deploy summary rule: <name> (bin: <n>min -> <table>)` and counted as deployed, but no API call is made and no deployment state is written.

---

## Exporting or Creating Rules from the Azure Portal

1. Navigate to your Log Analytics workspace in the Azure portal.
2. Select **Settings > Summary rules** from the left-hand menu.
3. To create a new rule interactively, select **+ Create** and complete the form. Once saved, use the rule name and the JSON structure above to create the equivalent file in this repository.
4. To view an existing rule's definition, select the rule name and copy the query and properties into a new JSON file following the schema above.

Rules created in the portal are not automatically synchronised back to this repository. Always commit rule definitions here and treat this repository as the source of truth.

## Authoring with GitHub Copilot

Summary rules don't have a dedicated path-scoped instruction file;
the repo-wide
[`.github/copilot-instructions.md`](../../.github/copilot-instructions.md)
plus the cross-cutting
[`.github/instructions/kql-queries.instructions.md`](../../.github/instructions/kql-queries.instructions.md)
(loaded automatically when editing `Content/SummaryRules/**/*.json`) cover
the conventions.

Copilot tooling for summary rules:

- Agent `Sentinel-As-Code: Content Editor` - general edits with
  the right post-edit Pester suite (`Test-SummaryRuleJson.Tests.ps1`)
- Agent `Sentinel-As-Code: KQL Engineer` - optimise the query body

See [GitHub Copilot setup](../GitHub/GitHub-Copilot.md) for the full layout.
