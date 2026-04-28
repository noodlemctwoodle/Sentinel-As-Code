# Hunting Queries

Custom threat hunting queries authored in YAML and deployed to Microsoft Sentinel as saved searches via the Log Analytics REST API. Unlike analytics rules, hunting queries do not generate alerts or incidents — they are executed manually or on-demand by analysts conducting proactive threat hunts.

Source files live under [`HuntingQueries/`](../HuntingQueries/).

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

Organise queries by MITRE ATT&CK tactic using subfolders:

```
HuntingQueries/
  Identity/
    SuspiciousSignInFromNewCountry.yaml
  Persistence/
    NewServicePrincipalCredential.yaml
  LateralMovement/
    AdminShareAccess.yaml
  Exfiltration/
    LargeOutboundTransfer.yaml
```

## YAML Schema

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (GUID) | Stable unique identifier used as the saved search resource name. Generate with `New-Guid`. Must not change after initial deployment — the PUT is idempotent on this value. |
| `name` | string | Display name shown in the Sentinel Hunting blade (sentence case, max ~50 chars). |
| `query` | string | KQL query. There is no scheduling or threshold — the query returns results directly when run by an analyst. |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | Plain-English explanation of what the query hunts for and why it is interesting. Begins with "Identifies" or "Detects". |
| `tactics` | string[] | MITRE ATT&CK tactic names (e.g., `InitialAccess`, `Persistence`). Stored as a tag on the saved search. |
| `techniques` | string[] | MITRE ATT&CK technique IDs (e.g., `T1078`, `T1098.001`). Stored as a tag on the saved search. |
| `tags` | object[] | Additional key-value metadata pairs. Each entry must have a `name` and `value` string. Appended to the tactics/techniques tags at deploy time. |

### API Mapping

The pipeline converts each YAML file to a PUT request against the Log Analytics Saved Searches API:

```
PUT /subscriptions/{sub}/resourceGroups/{rg}/providers/
    Microsoft.OperationalInsights/workspaces/{workspace}/
    savedSearches/{id}?api-version=2020-08-01
```

The request body is constructed as follows:

```json
{
  "properties": {
    "category": "Hunting Queries",
    "displayName": "<name>",
    "query": "<query>",
    "tags": [
      { "name": "description", "value": "<description>" },
      { "name": "tactics",     "value": "InitialAccess,Persistence" },
      { "name": "techniques",  "value": "T1078,T1098.001" }
    ]
  }
}
```

Custom `tags` entries from the YAML are appended to the tags array after the standard fields.

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

## Prerequisites

The identity used by the pipeline (service principal or managed identity) requires one of the following roles on the Log Analytics workspace:

- **Contributor** (resource group or workspace scope)
- **Microsoft Sentinel Contributor** (workspace scope)

The `Microsoft.OperationalInsights/workspaces/savedSearches/write` permission is what the deployment needs specifically. Sentinel Contributor grants this alongside all other Sentinel-scoped permissions.

## Adding Hunting Queries

### From Scratch

1. Generate a stable GUID: `New-Guid` (PowerShell) or `uuidgen` (bash/macOS).
2. Author the KQL query in the Sentinel **Logs** blade to validate results before committing.
3. Create a YAML file following the schema above and place it in the appropriate tactic subfolder.
4. Open a pull request — the pipeline will deploy the query on merge to `main`.

### Exporting Existing Queries from the Sentinel Portal

1. Navigate to **Microsoft Sentinel > Hunting**.
2. Locate the query you want to export.
3. Click the query name to open the details panel, then click **View query results** to confirm it runs.
4. From the query row, select **...** (ellipsis menu) > **Clone query** or note the KQL from the details panel.
5. Create a new YAML file using the schema above, pasting the KQL into the `query` field.
6. Generate a fresh GUID for `id` with `New-Guid` — do not reuse an existing ID unless you intend to overwrite the saved search in place.
7. Commit the file to this repository so it is source-controlled and deployed idempotently going forward.

### From the Azure-Sentinel GitHub

The [Azure-Sentinel Hunting Queries folder](https://github.com/Azure/Azure-Sentinel/tree/master/Hunting%20Queries) contains community queries organised by log source. These are in `.yaml` format but use a different schema (they target the Content Hub, not the Saved Searches API directly). When adapting them:

1. Copy the `description`, `query`, `tactics`, and `relevantTechniques` fields.
2. Generate a new GUID for `id`.
3. Map `relevantTechniques` to the `techniques` field in this schema.
4. Validate the KQL in the Logs blade before committing.
