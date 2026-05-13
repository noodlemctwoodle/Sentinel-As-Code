# Analytical Rules

Custom analytics rules authored in YAML, following the
[Azure-Sentinel Query Style Guide](https://github.com/Azure/Azure-Sentinel/wiki/Query-Style-Guide).
YAML files are converted to REST API JSON at deploy time by
[`Scripts/Deploy-CustomContent.ps1`](../../Scripts/Deploy-CustomContent.ps1).

| Concern | Where |
| --- | --- |
| Rule files | [`AnalyticalRules/`](../../AnalyticalRules/) |
| Deploy logic | [`Scripts/Deploy-CustomContent.ps1`](../../Scripts/Deploy-CustomContent.ps1) (function `Deploy-CustomDetections`, ~line 1077) |
| Drift detection | See [Sentinel Drift Detection](../Operations/Sentinel-Drift-Detection.md) |
| Community contributions | See [Community Rules](Community-Rules.md) |

## Folder structure

Rules are organised by category using subfolders. The category name is purely
organisational — it does not affect deploy behaviour.

```
AnalyticalRules/
├── AzureActivity/
├── AzureWAF/
├── Custom/                                # Hand-authored, in-house rules
├── Community/                             # Opt-in contributions (see Community-Rules.md)
│   └── Dalonso/
├── DNS/
├── Identity/
├── M365Defender/
├── Microsoft365/
├── MicrosoftEntraID/
├── MicrosoftGraphActivityLogs/
├── PrivilegeEscalation/
├── SecurityEvent/
├── Usage/
└── …
```

Categories that exist today are visible in
[`AnalyticalRules/`](../../AnalyticalRules/). Add new ones as needed; the deploy
script walks all `*.yaml` and `*.yml` recursively.

## YAML schema

### Required field order

```yaml
id:                      # GUID — unique per rule
name:                    # Sentence case, no trailing period
description: |           # Block style, starts with 'Identifies' or 'Detects'
severity:                # Informational | Low | Medium | High
requiredDataConnectors:  # connectorId + dataTypes
queryFrequency:          # ISO 8601 duration (PT1H, P1D) — Scheduled only
queryPeriod:             # ISO 8601 duration, max P14D — Scheduled only
triggerOperator:         # gt | lt | eq | ne (short form only)
triggerThreshold:        # Integer 0-10000 — Scheduled only
enabled:                 # true (rule runs after deploy) or false (deploys disabled)
tactics:                 # MITRE ATT&CK tactics (camelCase, no spaces)
relevantTechniques:      # MITRE technique IDs (T####, T####.###)
query: |                 # KQL, block style, max 10000 chars
entityMappings:          # Optional: 1-10 mappings, 1-3 identifiers each
alertDetailsOverride:    # Optional: max 3 {{column}} placeholders per field
customDetails:           # Optional: key max 20 chars
eventGroupingSettings:   # Optional
incidentConfiguration:   # Optional
version:                 # Semver (a.b.c)
kind:                    # Scheduled | NRT
tags:                    # Optional: freeform labels
```

### Style rules

- **`triggerOperator`** must use short form (`gt`, `lt`, `eq`, `ne`). The
  deploy script maps these to API form (`GreaterThan`, etc.) at deploy time
  — see the table at [`Deploy-CustomContent.ps1:1185-1192`](../../Scripts/Deploy-CustomContent.ps1).
- **`relevantTechniques`** — use this name, not `techniques`. Both are
  accepted by the deploy script for compatibility, but `relevantTechniques`
  is canonical.
- **Block style** — `description` and `query` must use YAML literal block
  style (`|`). Folded scalars (`>`) are not handled by the drift detector's
  surgical-rewrite logic.
- **`enabled`** — boolean. `true` means the rule runs immediately after
  deploy; `false` means it lands disabled and a reviewer enables it in the
  Sentinel portal. The deploy script overrides the YAML value to `false` in
  three cases regardless of what's authored:

  | Case | Reference |
  | --- | --- |
  | Rule lives under `AnalyticalRules/Community/**` | [`Deploy-CustomContent.ps1:1155`](../../Scripts/Deploy-CustomContent.ps1) |
  | A required data type / watchlist / parser dependency is missing at deploy time | [`Deploy-CustomContent.ps1:1146`](../../Scripts/Deploy-CustomContent.ps1) |
  | KQL validation fails at deploy (e.g. a freshly deployed watchlist isn't queryable yet) | [`Deploy-CustomContent.ps1:1259`](../../Scripts/Deploy-CustomContent.ps1) |

  Because `enabled` is routinely overridden at deploy time, the [drift
  detector](../Operations/Sentinel-Drift-Detection.md) deliberately excludes it from
  comparison — flipping a rule on/off in the portal is not treated as drift.

- **Deprecated rules** — rules with `[Deprecated]` in the display name are
  skipped at deploy time
  ([`Deploy-SentinelContentHub.ps1:1153-1157`](../../Scripts/Deploy-SentinelContentHub.ps1)).
- **Tactics casing** — camelCase, no spaces: `InitialAccess`,
  `LateralMovement`, `PrivilegeEscalation`, `CredentialAccess`, etc.
- **`alertDetailsOverride`** — max 3 `{{columnName}}` placeholders per
  field if present.
- **`customDetails`** — max 20 key-value pairs; keys max 20 characters.
- **`entityMappings`** — 1-10 entries (cannot be empty if the key is
  present).

### Field details

| Field | Type | Notes |
| --- | --- | --- |
| `id` | GUID | Generate with `New-Guid` (PowerShell) or `uuidgen` (bash) |
| `name` | string | Sentence case, max ~50 chars, no trailing period |
| `description` | string | Block style (`\|`). Starts with "Detects" or "Identifies" |
| `severity` | string | `Informational`, `Low`, `Medium`, or `High` |
| `enabled` | boolean | `true` (default) or `false`. Force-disabled by the deploy script for community rules, missing dependencies, and KQL validation failures (see Style rules above) |
| `kind` | string | `Scheduled` (requires queryFrequency, queryPeriod, triggerOperator, triggerThreshold) or `NRT` |
| `queryFrequency` | string | ISO 8601 duration (e.g., `PT1H`, `P1D`). Scheduled only. |
| `queryPeriod` | string | ISO 8601 duration, max `P14D`. Scheduled only. |
| `triggerOperator` | string | Short form: `gt`, `lt`, `eq`, or `ne`. Scheduled only. |
| `triggerThreshold` | integer | 0–10000. Scheduled only. |
| `tactics` | string[] | MITRE ATT&CK tactic names (camelCase, e.g., `CredentialAccess`, `Persistence`) |
| `relevantTechniques` | string[] | MITRE IDs (e.g., `T1110`, `T1078.004`). Use `relevantTechniques`, not `techniques`. |
| `requiredDataConnectors` | array | Array of `{connectorId, dataTypes}` objects |
| `query` | string | Block style (`\|`). KQL query, max 10,000 chars. |
| `entityMappings` | array | Optional. 1-10 entity mappings (see reference below) |
| `customDetails` | object | Optional. Max 20 key-value pairs; key max 20 chars. |
| `alertDetailsOverride` | object | Optional. Override alert title/description with query columns (max 3 placeholders per field) |
| `eventGroupingSettings` | object | Optional. `SingleAlert` (default) or `AlertPerResult`. |
| `incidentConfiguration` | object | Optional. Incident grouping and lookup behaviour. |
| `version` | string | Semver (e.g., `1.0.0`). The drift sync bumps the patch component when it absorbs portal edits — see [Sentinel Drift Detection](../Operations/Sentinel-Drift-Detection.md#how-custom-drift-gets-absorbed). |
| `tags` | string[] | Optional. Freeform labels (e.g., `DEV-0537`, `Solorigate`) |

### Entity mapping reference

| Entity Type | Common Identifiers |
| --- | --- |
| `Account` | `Name`, `FullName`, `UPNSuffix`, `AadUserId`, `Sid`, `ObjectGuid`, `DisplayName` |
| `IP` | `Address` |
| `Host` | `HostName`, `DnsDomain`, `AzureID`, `OMSAgentID`, `OSFamily` |
| `URL` | `Url` |
| `FileHash` | `Algorithm`, `Value` |
| `File` | `Name`, `Directory` |
| `Process` | `ProcessId`, `CommandLine`, `CreationTimeUtc` |
| `CloudApplication` | `AppId`, `Name`, `InstanceName` |
| `DNS` | `DomainName` |
| `MailMessage` | `Recipient`, `Sender`, `Subject`, `NetworkMessageId` |
| `Mailbox` | `MailboxPrimaryAddress`, `DisplayName` |
| `RegistryKey` | `Hive`, `Key` |
| `RegistryValue` | `Name`, `Value`, `ValueType` |
| `SecurityGroup` | `DistinguishedName`, `SID`, `ObjectGuid` |
| `AzureResource` | `ResourceId` |
| `Malware` | `Name`, `Category` |

## Examples

### Scheduled rule

```yaml
id: 28b42356-45af-40a6-a0b4-a554cdfd5d8a
name: Brute Force Attack against Azure Portal
description: |
  Detects Azure Portal brute force attacks by monitoring for multiple
  authentication failures followed by a successful login.
severity: Medium
requiredDataConnectors:
  - connectorId: AzureActiveDirectory
    dataTypes:
      - SigninLogs
  - connectorId: AzureActiveDirectory
    dataTypes:
      - AADNonInteractiveUserSignInLogs
queryFrequency: P1D
queryPeriod: P7D
triggerOperator: gt
triggerThreshold: 0
enabled: true
tactics:
  - CredentialAccess
relevantTechniques:
  - T1110
query: |
  SigninLogs
  | where AppDisplayName has "Azure Portal"
  | where ResultType !in ("0", "50125", "50140")
  | summarize FailureCount = count() by UserPrincipalName, IPAddress
  | where FailureCount > 10
entityMappings:
  - entityType: Account
    fieldMappings:
      - identifier: FullName
        columnName: UserPrincipalName
  - entityType: IP
    fieldMappings:
      - identifier: Address
        columnName: IPAddress
incidentConfiguration:
  createIncident: true
  groupingConfiguration:
    enabled: true
    reopenClosedIncident: false
    lookbackDuration: PT5H
    matchingMethod: Selected
    groupByEntities:
      - Account
      - IP
version: 1.0.0
kind: Scheduled
```

### NRT rule

```yaml
id: 70fc7201-f28e-4ba7-b9ea-c04b96701f13
name: User Added to Microsoft Entra ID Privileged Groups
description: |
  Detects when a user is added to any privileged Entra ID group.
severity: Medium
requiredDataConnectors:
  - connectorId: AzureActiveDirectory
    dataTypes:
      - AuditLogs
enabled: true
tactics:
  - Persistence
  - PrivilegeEscalation
relevantTechniques:
  - T1098
  - T1078
query: |
  let OperationList = dynamic(["Add member to role", "Add eligible member to role"]);
  AuditLogs
  | where Category =~ "RoleManagement"
  | where OperationName in~ (OperationList)
entityMappings:
  - entityType: Account
    fieldMappings:
      - identifier: FullName
        columnName: TargetUserPrincipalName
  - entityType: IP
    fieldMappings:
      - identifier: Address
        columnName: InitiatingIpAddress
version: 1.0.0
kind: NRT
tags:
  - DEV-0537
```

NRT rules omit `queryFrequency`, `queryPeriod`, `triggerOperator`, and
`triggerThreshold` — they are not scheduling-driven.

## Adding rules

### From the Azure-Sentinel GitHub

Rules in the [Azure-Sentinel Solutions folder](https://github.com/Azure/Azure-Sentinel/tree/master/Solutions)
already use this YAML format. Copy the file directly into an appropriate
category subfolder.

### From the Sentinel Portal

1. Navigate to **Microsoft Sentinel → Analytics**
2. Select an existing rule and click **Export**
3. Convert the exported ARM JSON to YAML following the schema above
4. Generate a stable GUID for the `id` field with `New-Guid`
5. Place the YAML file in an appropriate category subfolder

### From scratch

1. Generate a GUID: `New-Guid` (PowerShell) or `uuidgen` (bash)
2. Follow the [Azure-Sentinel Query Style Guide](https://github.com/Azure/Azure-Sentinel/wiki/Query-Style-Guide)
   for naming, description, and query conventions
3. Test the KQL in the Sentinel **Logs** blade before committing
4. Place the YAML file in an appropriate category subfolder

## Deploy behaviour

The deploy logic lives in [`Scripts/Deploy-CustomContent.ps1`](../../Scripts/Deploy-CustomContent.ps1)
(function `Deploy-CustomDetections`). Notable behaviours that affect how
you should author rules:

| Behaviour | Reference |
| --- | --- |
| Rules deploy `enabled: true` by default. Override with `enabled: false` in the YAML. | [`Deploy-CustomContent.ps1:1155`](../../Scripts/Deploy-CustomContent.ps1) |
| Rules under `AnalyticalRules/Community/**` always deploy disabled. | [`Deploy-CustomContent.ps1:1155`](../../Scripts/Deploy-CustomContent.ps1) — see [Community Rules](Community-Rules.md) |
| If `requiredDataConnectors` reference data types that aren't present yet, the rule deploys disabled and waits. | [`Deploy-CustomContent.ps1:1146`](../../Scripts/Deploy-CustomContent.ps1) |
| If KQL validation fails at deploy time (e.g. a freshly deployed watchlist column isn't queryable yet), the rule retries deployment with `enabled: false`. | [`Deploy-CustomContent.ps1:1259`](../../Scripts/Deploy-CustomContent.ps1) |
| Smart-deploy mode (`-SmartDeployment`) only redeploys files changed since the last successful run. Bumping `version` is not required but the drift sync bumps it automatically when absorbing portal edits. | [`Deploy-CustomContent.ps1:292`](../../Scripts/Deploy-CustomContent.ps1) |

## Authoring with GitHub Copilot

When editing files under `AnalyticalRules/**`, Copilot automatically
loads [`.github/instructions/analytical-rules.instructions.md`](../../.github/instructions/analytical-rules.instructions.md).
For the KQL body, the cross-cutting
[`.github/instructions/kql-queries.instructions.md`](../../.github/instructions/kql-queries.instructions.md)
also loads.

Copilot tooling for analytical rules:

- Slash command `/new-analytical-rule` (VS Code) — bootstrap a fresh rule
- Slash command `/review-rule` (VS Code) — schema + KQL + convention review
- Agent `Sentinel-As-Code: Rule Author` — author end-to-end (cross-platform)
- Agent `Sentinel-As-Code: Rule Tuner` — adjust threshold / severity / filters
- Agent `Sentinel-As-Code: KQL Engineer` — optimise the query body

See [GitHub Copilot setup](../Development/GitHub-Copilot.md) for the full layout.

## Related docs

- [Sentinel Drift Detection](../Operations/Sentinel-Drift-Detection.md) — daily detection of
  portal-edited rules, with auto-PR back into the repo for Custom drift
- [Community Rules](Community-Rules.md) — opt-in third-party contributions
  under `AnalyticalRules/Community/`
- [Pester Tests](../Development/Pester-Tests.md) — running and extending the test suite for
  the drift-detection logic
