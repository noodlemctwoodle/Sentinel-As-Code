# Automation Rules

## Overview

Automation rules run automatically when incidents or alerts are created or updated in Microsoft Sentinel. They allow you to triage incidents at scale — closing false positives, adjusting severity, assigning owners, triggering playbooks, and adding investigation tasks — without manual intervention.

Rules are evaluated in order (ascending by the `order` field). The first matching rule runs; subsequent rules may also run unless a terminal action (such as closing the incident) stops further evaluation.

---

## Folder Structure

Each automation rule is stored as a single JSON file. Files can be placed directly in this folder or organised into subfolders by function or environment:

```
AutomationRules/
├── README.md
├── AutoCloseInformational.json
├── AddTaskOnHighSeverity.json
├── Triage/
│   └── AssignOwnerByProvider.json
└── Playbooks/
    └── RunEnrichmentPlaybook.json
```

The deployment script (`Scripts/Deploy-CustomContent.ps1`) discovers all `*.json` files recursively under this directory and deploys each one via the REST API.

---

## JSON Schema

### Top-Level Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `automationRuleId` | string (GUID) | Yes | Stable unique identifier for the rule. Generate once with `New-Guid` and do not change it — this is the resource name used in the PUT URL. |
| `displayName` | string | Yes | Human-readable name shown in the Sentinel portal. |
| `order` | integer | Yes | Execution priority. Lower numbers run first. Valid range: 1–1000. |
| `triggeringLogic` | object | Yes | Defines when the rule fires. See below. |
| `actions` | array | Yes | One or more actions to perform when the rule matches. See below. |

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

Each action in the `actions` array has an `actionType`, an `order` (execution order within the rule, starting at 1), and an `actionConfiguration` object.

#### `ModifyProperties`

Modifies one or more properties of the incident. All fields within `actionConfiguration` are optional — only include the properties you want to change.

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

Triggers a Logic App playbook. The playbook must be accessible from the Sentinel workspace and have the Sentinel trigger configured.

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

See [AutoCloseInformational.json](AutoCloseInformational.json).

### Add an investigation task to high severity incidents

See [AddTaskOnHighSeverity.json](AddTaskOnHighSeverity.json).

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
    -Path "/subscriptions/<subId>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<workspace>/providers/Microsoft.SecurityInsights/automationRules/<ruleId>?api-version=2024-09-01"

($rule.Content | ConvertFrom-Json).properties | ConvertTo-Json -Depth 10
```

5. Restructure the output into the schema above (top-level `automationRuleId`, `displayName`, `order`, `triggeringLogic`, `actions`) and save as a `.json` file in this directory.

---

## Prerequisites

The identity running the deployment pipeline requires the following role assignments on the Microsoft Sentinel workspace:

| Role | Scope | Purpose |
|---|---|---|
| **Microsoft Sentinel Contributor** | Resource group or workspace | Create and update automation rules |
| **Microsoft Sentinel Playbook Operator** | Logic App resource(s) | Required only for `RunPlaybook` actions |

These roles should be assigned to the service principal or managed identity configured in the pipeline. See the top-level [`README.md`](../README.md) for pipeline configuration details.
