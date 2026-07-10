# Automation Rules

## Overview

Automation rules run automatically when incidents or alerts are created or updated in Microsoft Sentinel. They allow you to triage incidents at scale (closing false positives, adjusting severity, assigning owners, triggering playbooks, and adding investigation tasks) without manual intervention.

Rules are evaluated in order (ascending by the `order` field). The first matching rule runs; subsequent rules may also run unless a terminal action (such as closing the incident) stops further evaluation.

Source files live under [`Content/AutomationRules/`](../../Content/AutomationRules).

The Sentinel as Code Toolkit scaffolds and validates this content type. Its bundled `automation-rule` template and `sentinel-automation-rule-schema.json` are the authoring contract this page documents; the fields, required-vs-optional flags, types, enums and field order below all come from that schema and template. See [Templates](../Toolkit/Templates.md) and [Schemas and Validation](../Toolkit/Schemas-and-Validation.md). The Toolkit authors and validates only; deployment to Sentinel is handled by the pipeline described under [Deployment Behaviour](#deployment-behaviour).

---

## Folder Structure

Each automation rule is stored as a single JSON file. The Toolkit's `automation-rule` template is authored as commented YAML for readability; you run its Convert Content YAML to JSON command to produce the JSON stored on disk when you are ready to deploy (automation rules are one of the three content types the pipeline stores as JSON rather than YAML). Files can be placed directly in the folder or organised into subfolders by function or environment:

```
Content/AutomationRules/
├── AutoCloseInformational.json
├── AddTaskOnHighSeverity.json
├── Triage/
│   └── AssignOwnerByProvider.json
└── Playbooks/
    └── RunEnrichmentPlaybook.json
```

The two rules that ship in this repository, `AddTaskOnHighSeverity.json` and `AutoCloseInformational.json`, both sit flat in `Content/AutomationRules/`; subfolders are optional and purely organisational.

The `Deploy-CustomAutomationRules` function in [`Deploy/content/Deploy-CustomContent.ps1`](../../Deploy/content/Deploy-CustomContent.ps1) discovers all `*.json` files recursively under this directory (automation rules are stage 7 of the 8-stage deploy order, after Workbooks and before Summary Rules) and deploys each one via the REST API.

---

## Deployment Behaviour

`Deploy-CustomAutomationRules` applies two pre-deployment checks to every rule file before it PUTs anything to Sentinel:

- **Smart (incremental) deployment.** Each file is passed through `Test-ShouldDeployFile`, which skips it if it is unchanged since the last successful deployment run. A skipped file is logged as `Unchanged: <file> - skipping (smart deployment)` and counted as skipped, not deployed. This skip only happens when smart deployment is active (`-SmartDeployment`, which is off by default); a normal run deploys every file regardless of whether it changed.
- **Dependency-graph gating.** Each file also goes through `Test-ContentDependencies`, the same generic pre-flight gate used for every content type. It checks the rule's entry in the dependency manifest for `tables`/`watchlists`/`functions` it references and skips the rule (logging the missing dependencies) if any are absent from the workspace or the repo's internal watchlists. This check does **not** understand `RunPlaybook`'s `logicAppResourceId`, so a rule that triggers a playbook will deploy successfully even if the referenced Logic App was never deployed; treat the RBAC note under [`RunPlaybook`](#runplaybook) as the only real guardrail for that action type.

Only the presence of `automationRuleId`, `displayName`, `order`, `triggeringLogic`, and `actions` is validated by the deploy script itself; a file missing any of these is skipped with a warning. The deploy script does not validate the `actionType`/`conditionType` enum values described below - that validation, plus a cross-file check that every `automationRuleId` is unique across `Content/AutomationRules/` (Sentinel uses the GUID as the resource name, so a collision would silently overwrite an existing rule), is enforced by the Pester suite `Tests/Test-AutomationRuleJson.Tests.ps1`, which runs in the PR-validation gate.

When deploying, the script re-wraps each file into a PUT body containing only `{displayName, order, triggeringLogic, actions}` under a `properties` object; `automationRuleId` is used solely as the URL resource name and is never sent in the request body. A successful deployment records the file's state via `Set-DeploymentItemState`, which is what the next run's smart-deployment check reads.

---

## JSON Schema

The Toolkit schema validates the outer envelope: the five top-level fields, the `triggeringLogic` sub-fields, and each action's `actionType` and `order`. It treats `conditions` and `actionConfiguration` as free-form (an array and an object respectively), so the condition, property and action-configuration values documented further down reflect what Sentinel accepts at runtime, not values the Toolkit enforces. The schema also sets `additionalProperties: false` at the top level, so no fields other than the five below are permitted.

### Top-Level Fields

Fields appear in the canonical order the Toolkit template lays them out and its Fix Field Order command enforces: `automationRuleId`, `displayName`, `order`, `triggeringLogic`, `actions`.

| Field | Type | Required | Description |
|---|---|---|---|
| `automationRuleId` | string (GUID) | Yes | Stable unique identifier for the rule. Generate once with `New-Guid` and do not change it, this is the resource name used in the PUT URL. Must match the GUID pattern `^[0-9a-fA-F]{8}-...-[0-9a-fA-F]{12}$`. Must be unique across `Content/AutomationRules/`; CI fails the build on a duplicate. |
| `displayName` | string | Yes | Human-readable name shown in the Sentinel portal. Must be non-empty. |
| `order` | integer | Yes | Execution priority. Lower numbers run first. Valid range: 1–1000. |
| `triggeringLogic` | object | Yes | Defines when the rule fires. See below. |
| `actions` | array | Yes | One or more actions to perform when the rule matches (at least one is required). See below. |

---

### `triggeringLogic` Object

| Field | Type | Required | Description |
|---|---|---|---|
| `isEnabled` | boolean | Yes | Set to `false` to disable the rule without removing it. |
| `triggersOn` | string | Yes | `"Incidents"` or `"Alerts"`. |
| `triggersWhen` | string | Yes | `"Created"` or `"Updated"`. |
| `expirationTimeUtc` | string | No | ISO 8601 datetime after which the rule stops firing. Example: `"2025-12-31T23:59:59Z"`. |
| `conditions` | array | No | Zero or more conditions that must all match (AND logic) for the rule to fire. Omit or leave empty to match all incidents/alerts. |

---

### Condition Types

All conditions share the top-level `conditionType` discriminator field.

#### `Property` Condition

Evaluates a scalar property of the incident or alert against a set of values.

```json
{
  "conditionType": "Property",
  "conditionProperties": {
    "propertyName": "<PropertyName>",
    "operator": "<Operator>",
    "propertyValues": ["<value1>", "<value2>"]
  }
}
```

**`propertyName` values for Incidents (`triggersOn: "Incidents"`)**

| Value | Description |
|---|---|
| `IncidentSeverity` | Severity of the incident |
| `IncidentStatus` | Current status |
| `IncidentProvider` | Alert provider/product name |
| `IncidentTitle` | Title of the incident |
| `IncidentDescription` | Description text |
| `IncidentTactics` | MITRE ATT&CK tactic tags |
| `IncidentLabel` | Custom label/tag values |
| `IncidentRelatedAnalyticRuleIds` | Resource IDs of the analytics rules that generated alerts |
| `IncidentCustomDetailsKey` | Key name from custom details |
| `IncidentCustomDetailsValue` | Value from custom details |

**`propertyName` values for Alerts (`triggersOn: "Alerts"`)**

| Value | Description |
|---|---|
| `AlertSeverity` | Severity of the alert |
| `AlertStatus` | Current status |
| `AlertProductName` | Product that generated the alert |
| `AlertAnalyticRuleIds` | Resource ID of the analytics rule |

**`operator` values**

| Value | Description |
|---|---|
| `Equals` | Exact match (case-insensitive) against any value in `propertyValues` |
| `NotEquals` | Does not match any value in `propertyValues` |
| `Contains` | Property value contains the string |
| `NotContains` | Property value does not contain the string |
| `StartsWith` | Property value starts with the string |
| `NotStartsWith` | Property value does not start with the string |
| `EndsWith` | Property value ends with the string |
| `NotEndsWith` | Property value does not end with the string |

---

#### `PropertyArrayChanged` Condition

Fires on `triggersWhen: "Updated"` when an array-type property has items added or removed.

```json
{
  "conditionType": "PropertyArrayChanged",
  "conditionProperties": {
    "arrayType": "Labels",
    "changeType": "Added"
  }
}
```

| Field | Values |
|---|---|
| `arrayType` | `Labels`, `Tactics`, `Alerts`, `Comments` |
| `changeType` | `Added`, `Removed` |

---

#### `PropertyChanged` Condition

Fires on `triggersWhen: "Updated"` when a scalar property changes to a specific value.

```json
{
  "conditionType": "PropertyChanged",
  "conditionProperties": {
    "propertyName": "IncidentSeverity",
    "changeType": "ChangedTo",
    "propertyValues": ["High"]
  }
}
```

| Field | Values |
|---|---|
| `propertyName` | Same enum as the `Property` condition above |
| `changeType` | `ChangedFrom`, `ChangedTo` |

---

### Action Types

Each action in the `actions` array has an `actionType` and an `order` (both required; `order` is the execution order within the rule and must be at least 1). The `actionConfiguration` object is optional in the schema, but in practice every action type below needs it to carry its settings. `actionType` must be one of `ModifyProperties`, `RunPlaybook`, or `AddIncidentTask`.

#### `ModifyProperties`

Modifies one or more properties of the incident. All fields within `actionConfiguration` are optional; only include the properties you want to change.

```json
{
  "actionType": "ModifyProperties",
  "order": 1,
  "actionConfiguration": {
    "status": "Closed",
    "classification": "BenignPositive",
    "classificationReason": "SuspiciousButExpected",
    "severity": "High",
    "owner": {
      "assignedTo": "user@contoso.com",
      "objectId": "<AAD object ID>",
      "userPrincipalName": "user@contoso.com"
    }
  }
}
```

**`status` values**

| Value | Description |
|---|---|
| `New` | Incident is newly created |
| `Active` | Incident is being investigated |
| `Closed` | Incident is resolved |

**`classification` values** (required when `status` is `Closed`)

| Value | Description |
|---|---|
| `TruePositive` | Confirmed malicious activity |
| `BenignPositive` | Expected or benign behaviour |
| `FalsePositive` | Incorrect detection |
| `Undetermined` | Unable to determine |

**`classificationReason` values**

| Value | Applicable Classifications |
|---|---|
| `SuspiciousActivity` | TruePositive |
| `SuspiciousButExpected` | BenignPositive |
| `IncorrectAlertLogic` | FalsePositive |
| `InaccurateData` | FalsePositive |
| `Undetermined` | Undetermined |

**`severity` values**: `High`, `Medium`, `Low`, `Informational`

---

#### `RunPlaybook`

Triggers a Logic App playbook. The playbook must be accessible from the Sentinel workspace and have the Sentinel trigger configured. See [Playbooks](Playbooks.md) for playbook authoring conventions.

```json
{
  "actionType": "RunPlaybook",
  "order": 1,
  "actionConfiguration": {
    "tenantId": "<AAD tenant GUID>",
    "logicAppResourceId": "/subscriptions/<subId>/resourceGroups/<rg>/providers/Microsoft.Logic/workflows/<playbookName>"
  }
}
```

| Field | Description |
|---|---|
| `tenantId` | Azure AD tenant ID where the playbook is registered |
| `logicAppResourceId` | Full ARM resource ID of the Logic App |

The service principal or managed identity used for deployment requires the **Microsoft Sentinel Playbook Operator** role on the Logic App resource in addition to the Sentinel Contributor role on the workspace.

---

#### `AddIncidentTask`

Adds a structured task to the incident's task list, visible under the incident's Tasks tab in the portal.

```json
{
  "actionType": "AddIncidentTask",
  "order": 1,
  "actionConfiguration": {
    "title": "Task title (max 150 characters)",
    "description": "Detailed instructions for the analyst.\nSupports newlines with \\n."
  }
}
```

| Field | Required | Description |
|---|---|---|
| `title` | Yes | Short task name shown in the task list |
| `description` | No | Detailed instructions; supports `\n` for line breaks |

---

## Usage Examples

### Close all informational incidents on creation

See [`Content/AutomationRules/AutoCloseInformational.json`](../../Content/AutomationRules/AutoCloseInformational.json).

### Add an investigation task to high severity incidents

See [`Content/AutomationRules/AddTaskOnHighSeverity.json`](../../Content/AutomationRules/AddTaskOnHighSeverity.json).

### Assign owner when severity is changed to High (update trigger)

```json
{
  "automationRuleId": "d4e5f6a7-b8c9-0123-defa-345678901234",
  "displayName": "Assign owner when escalated to High",
  "order": 10,
  "triggeringLogic": {
    "isEnabled": true,
    "triggersOn": "Incidents",
    "triggersWhen": "Updated",
    "conditions": [
      {
        "conditionType": "PropertyChanged",
        "conditionProperties": {
          "propertyName": "IncidentSeverity",
          "changeType": "ChangedTo",
          "propertyValues": ["High"]
        }
      }
    ]
  },
  "actions": [
    {
      "actionType": "ModifyProperties",
      "order": 1,
      "actionConfiguration": {
        "owner": {
          "assignedTo": "soc-team@contoso.com",
          "userPrincipalName": "soc-team@contoso.com"
        }
      }
    }
  ]
}
```

---

## Exporting Rules from the Sentinel Portal

Existing automation rules can be exported for use in this repository:

1. Open **Microsoft Sentinel** > **Automation** > **Automation rules** tab.
2. Select the rule you want to export.
3. Copy the rule name (GUID) from the URL: `.../automationRules/<GUID>`.
4. Use the Azure REST API or Az PowerShell to retrieve the current definition:

```powershell
$rule = Invoke-AzRestMethod -Method GET `
    -Path "/subscriptions/<subId>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<workspace>/providers/Microsoft.SecurityInsights/automationRules/<ruleId>?api-version=2025-09-01"

($rule.Content | ConvertFrom-Json).properties | ConvertTo-Json -Depth 10
```

This matches the `$script:SentinelApiVersion` value the deploy script itself uses for the PUT; if that variable is bumped in `Deploy-CustomContent.ps1`, update the api-version here too.

5. Restructure the output into the schema above (top-level `automationRuleId`, `displayName`, `order`, `triggeringLogic`, `actions`) and save as a `.json` file in [`Content/AutomationRules/`](../../Content/AutomationRules).

---

## Prerequisites

The identity running the deployment pipeline requires the following role assignments on the Microsoft Sentinel workspace:

| Role | Scope | Purpose |
|---|---|---|
| **Microsoft Sentinel Contributor** | Resource group or workspace | Create and update automation rules |
| **Microsoft Sentinel Playbook Operator** | Logic App resource(s) | Required only for `RunPlaybook` actions |

These roles should be assigned to the service principal or managed identity configured in the pipeline. See [Pipelines](../Pipelines/README.md) for pipeline configuration details and [Scripts](../Deploy/Scripts.md#setup-serviceprincipalps1) for the bootstrap script.

## Authoring with GitHub Copilot

Automation rules don't have a dedicated path-scoped instruction
file (the schema is small and the rule body is mostly orchestration);
the repo-wide
[`.github/copilot-instructions.md`](../../.github/copilot-instructions.md)
covers the conventions.

Copilot tooling for automation rules:

- Agent `Sentinel-As-Code: Content Editor` - general edits with
  the right post-edit Pester suite (`Test-AutomationRuleJson.Tests.ps1`)

See [GitHub Copilot setup](../GitHub/GitHub-Copilot.md) for the full layout.
