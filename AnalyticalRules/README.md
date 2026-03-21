# Analytical Rules

Custom analytics rules authored in YAML, following the [Azure-Sentinel Query Style Guide](https://github.com/Azure/Azure-Sentinel/wiki/Query-Style-Guide). YAML files are converted to REST API JSON at deploy time by the pipeline.

## Folder Structure

Organise rules by category using subfolders:

```
AnalyticalRules/
  Identity/
    AzurePortalBruteForce.yaml
  PrivilegeEscalation/
    UserAddedToPrivilegedGroup.yaml
  Network/
    LateralMovementSMB.yaml
  Endpoint/
    RansomwareIndicators.yaml
```

## YAML Schema

The full schema is documented in the [Azure-Sentinel Query Style Guide](https://github.com/Azure/Azure-Sentinel/wiki/Query-Style-Guide). Below is a summary of the fields supported by this pipeline.

### Required Fields (all rule kinds)

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (GUID) | Unique rule identifier. Generate with `New-Guid` |
| `name` | string | Display name (sentence case, max ~50 chars) |
| `kind` | string | `Scheduled` or `NRT` |
| `severity` | string | `High`, `Medium`, `Low`, or `Informational` |
| `query` | string | KQL query (max 10,000 chars) |
| `tactics` | string[] | MITRE ATT&CK tactics (e.g., `CredentialAccess`, `Persistence`) |
| `techniques` | string[] | MITRE ATT&CK technique and sub-technique IDs (e.g., `T1110`, `T1078.004`) |

> **Sub-techniques**: You can include both parent techniques (`T1110`) and sub-techniques (`T1110.001`) in the `techniques` array. The deployment script automatically splits them into the `techniques` and `subTechniques` API properties at deploy time.

### Scheduled-Only Fields (required when `kind: Scheduled`)

| Field | Type | Description |
|-------|------|-------------|
| `queryFrequency` | string | How often the rule runs (ISO 8601, e.g., `PT1H`, `P1D`) |
| `queryPeriod` | string | Time window for the query (ISO 8601, max `P14D`) |
| `triggerOperator` | string | `GreaterThan`, `LessThan`, `Equal`, `NotEqual` |
| `triggerThreshold` | integer | Threshold value (0–10000) |

### Recommended Fields

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | Begins with "Detects" or "Identifies". Max 5 sentences |
| `enabled` | boolean | Whether the rule is enabled on deployment (default: `true`) |
| `version` | string | Semver version (e.g., `1.0.0`) |
| `status` | string | `Available`, `Deprecated`, or `Preview` |
| `requiredDataConnectors` | array | Data connectors and tables the rule depends on |
| `entityMappings` | array | Map query columns to Sentinel entities (max 10 mappings, 3 fields each) |
| `incidentConfiguration` | object | Incident creation and grouping settings |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `tags` | string[] | Freeform labels (e.g., `DEV-0537`, `Solorigate`) |
| `suppressionEnabled` | boolean | Enable alert suppression |
| `suppressionDuration` | string | Suppression window (ISO 8601, e.g., `PT5H`) |
| `customDetails` | object | Key-value pairs surfacing event data in alerts (max 20) |
| `alertDetailsOverride` | object | Dynamic alert title/description from query columns |
| `eventGroupingSettings` | object | `SingleAlert` (default) or `AlertPerResult` |
| `sentinelEntitiesMappings` | array | Include all identified entities |

### Entity Mapping Reference

| Entity Type | Common Identifiers |
|-------------|-------------------|
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

## Example (Scheduled)

```yaml
id: 28b42356-45af-40a6-a0b4-a554cdfd5d8a
name: Brute Force Attack against Azure Portal
description: |
  Detects Azure Portal brute force attacks by monitoring for multiple
  authentication failures followed by a successful login.
severity: Medium
kind: Scheduled
enabled: true
version: 1.0.0
status: Available
queryFrequency: P1D
queryPeriod: P7D
triggerOperator: GreaterThan
triggerThreshold: 0
tactics:
  - CredentialAccess
techniques:
  - T1110
requiredDataConnectors:
  - connectorId: AzureActiveDirectory
    dataTypes:
      - SigninLogs
  - connectorId: AzureActiveDirectory
    dataTypes:
      - AADNonInteractiveUserSignInLogs
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
```

## Example (NRT)

```yaml
id: 70fc7201-f28e-4ba7-b9ea-c04b96701f13
name: User Added to Microsoft Entra ID Privileged Groups
description: |
  Alerts when a user is added to any privileged Entra ID group.
severity: Medium
kind: NRT
enabled: true
version: 1.0.0
tactics:
  - Persistence
  - PrivilegeEscalation
techniques:
  - T1098
  - T1078
tags:
  - DEV-0537
requiredDataConnectors:
  - connectorId: AzureActiveDirectory
    dataTypes:
      - AuditLogs
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
```

## Adding Analytical Rules

### From the Azure-Sentinel GitHub

Rules in the [Azure-Sentinel Solutions folder](https://github.com/Azure/Azure-Sentinel/tree/master/Solutions) already use this YAML format. Copy the file directly into an appropriate category subfolder.

### From the Sentinel Portal

1. Navigate to **Microsoft Sentinel > Analytics**
2. Select an existing rule and click **Export**
3. Convert the exported ARM JSON to YAML following the schema above
4. Generate a stable GUID for the `id` field with `New-Guid`
5. Place the YAML file in an appropriate category subfolder

### From Scratch

1. Generate a GUID: `New-Guid` (PowerShell) or `uuidgen` (bash)
2. Follow the [Azure-Sentinel Query Style Guide](https://github.com/Azure/Azure-Sentinel/wiki/Query-Style-Guide) for naming, description, and query conventions
3. Test your KQL in the Sentinel **Logs** blade before committing
