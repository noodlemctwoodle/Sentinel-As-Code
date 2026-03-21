# Defender XDR Custom Detection Rules

Custom detection rules for Microsoft Defender XDR, deployed via the Microsoft Graph Security API.

## Overview

These rules run Advanced Hunting (KQL) queries on a schedule in the Defender XDR portal. They can trigger alerts and take automated response actions such as isolating devices, disabling users, or collecting investigation packages.

> **Important**: Defender custom detections use the **Advanced Hunting** KQL schema (e.g. `DeviceProcessEvents`, `IdentityLogonEvents`), which is different from the **Log Analytics** schema used by Sentinel analytics rules.

## Folder Structure

```
DefenderCustomDetections/
  README.md                     # This file
  <RuleName>.yaml               # One YAML file per detection rule
```

Rules can also be organised into subfolders by category:

```
DefenderCustomDetections/
  Endpoint/
    SuspiciousProcessExecution.yaml
  Identity/
    BruteForceEntraIDAccounts.yaml
  Email/
    PhishingLinkClicked.yaml
```

## YAML Schema

Each YAML file defines a single custom detection rule. The schema maps directly to the [Microsoft Graph Security API `detectionRule` resource](https://learn.microsoft.com/en-us/graph/api/resources/security-detectionrule).

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `displayName` | string | Rule display name |
| `queryCondition.queryText` | string | Advanced Hunting KQL query |
| `schedule.period` | string | Run frequency: `0` (NRT), `1H`, `3H`, `12H`, `24H` |
| `detectionAction.alertTemplate.title` | string | Alert title |
| `detectionAction.alertTemplate.severity` | string | `informational`, `low`, `medium`, `high` |
| `detectionAction.alertTemplate.category` | string | Alert category (e.g. `Execution`, `Persistence`) |
| `detectionAction.alertTemplate.mitreTechniques` | array | MITRE ATT&CK technique IDs |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `isEnabled` | boolean | Whether the rule is active (default: `true`) |
| `detectionAction.alertTemplate.description` | string | Alert description |
| `detectionAction.alertTemplate.recommendedActions` | string | Recommended investigation steps |
| `detectionAction.alertTemplate.impactedAssets` | array | Entity mappings for alerts |
| `detectionAction.responseActions` | array | Automated response actions |

### Required Query Output Columns

Depending on the source table, your query **must** return certain columns or the rule will fail:

| Source Table Type | Required Columns |
|-------------------|-----------------|
| Defender for Endpoint (`Device*`) | `Timestamp`, `DeviceId`, `ReportId` |
| Identity tables (`Identity*`) | `Timestamp`, `ReportId` |
| Email tables (`Email*`) | `Timestamp`, `ReportId` |
| Alert tables (`Alert*`) | `Timestamp` only |
| Sentinel tables | `Timestamp` or `TimeGenerated` |

> **Alert limit**: Each rule can generate a maximum of **150 alerts per run**.

### Schedule Periods

| Value | Description |
|-------|-------------|
| `0` | Near real-time (NRT) |
| `1H` | Every hour |
| `3H` | Every 3 hours |
| `12H` | Every 12 hours |
| `24H` | Every 24 hours |

### Impacted Assets (Entity Mappings)

Map query columns to alert entities using the `impactedAssets` array:

```yaml
impactedAssets:
  - "@odata.type": "#microsoft.graph.security.impactedDeviceAsset"
    identifier: deviceId
  - "@odata.type": "#microsoft.graph.security.impactedUserAsset"
    identifier: accountObjectId
```

**Device identifiers**: `deviceId`, `deviceName`, `remoteDeviceName`, `targetDeviceName`, `destinationDeviceName`
**User identifiers**: `accountObjectId`, `accountSid`, `accountUpn`, `accountName`, `accountDomain`, `accountId`, `recipientObjectId`, `initiatingAccountSid`, `initiatingProcessAccountUpn`, `servicePrincipalId`, `servicePrincipalName`, `targetAccountUpn`
**Mailbox identifiers**: `recipientEmailAddress`, `senderFromAddress`, `senderDisplayName`, `senderMailFromAddress`, `accountUpn`, `targetAccountUpn`

### Response Actions

Automated actions taken when the rule triggers. Each action requires `@odata.type` and `identifier`. Some actions require additional fields.

> **Important**: The `identifier` field is an enum value that tells Defender which query column to read — it is NOT a free-form column name. Each action type has its own set of valid identifier values.

#### Device Actions

```yaml
responseActions:
  - "@odata.type": "#microsoft.graph.security.isolateDeviceResponseAction"
    identifier: deviceId
    isolationType: full        # REQUIRED: "full" or "selective"
  - "@odata.type": "#microsoft.graph.security.collectInvestigationPackageResponseAction"
    identifier: deviceId
  - "@odata.type": "#microsoft.graph.security.runAntivirusScanResponseAction"
    identifier: deviceId
  - "@odata.type": "#microsoft.graph.security.initiateInvestigationResponseAction"
    identifier: deviceId
  - "@odata.type": "#microsoft.graph.security.restrictAppExecutionResponseAction"
    identifier: deviceId
```

Device action `identifier` values: `deviceId`

#### User Actions

```yaml
responseActions:
  - "@odata.type": "#microsoft.graph.security.forceUserPasswordResetResponseAction"
    identifier: accountSid     # Uses SID-based enum, NOT accountObjectId
  - "@odata.type": "#microsoft.graph.security.markUserAsCompromisedResponseAction"
    identifier: accountObjectId
  - "@odata.type": "#microsoft.graph.security.disableUserResponseAction"
    identifier: accountSid
```

`forceUserPasswordResetResponseAction` identifiers: `accountSid`, `initiatingProcessAccountSid`, `requestAccountSid`, `onPremSid`
`markUserAsCompromisedResponseAction` identifiers: `accountObjectId`, `initiatingProcessAccountObjectId`, `servicePrincipalId`, `recipientObjectId`

#### Email Actions

Email action identifiers use a **comma-separated string** of two values:

```yaml
responseActions:
  - "@odata.type": "#microsoft.graph.security.softDeleteResponseAction"
    identifier: "networkMessageId, recipientEmailAddress"
  - "@odata.type": "#microsoft.graph.security.hardDeleteResponseAction"
    identifier: "networkMessageId, recipientEmailAddress"
  - "@odata.type": "#microsoft.graph.security.moveToJunkResponseAction"
    identifier: "networkMessageId, recipientEmailAddress"
```

#### File Actions

```yaml
responseActions:
  - "@odata.type": "#microsoft.graph.security.stopAndQuarantineFileResponseAction"
    identifier: sha1
  - "@odata.type": "#microsoft.graph.security.blockFileResponseAction"
    identifier: sha256
  - "@odata.type": "#microsoft.graph.security.allowFileResponseAction"
    identifier: sha256
```

#### Complete Action Reference

| Action | `@odata.type` suffix | Required Fields |
|--------|---------------------|-----------------|
| Isolate device | `isolateDeviceResponseAction` | `identifier`, `isolationType` |
| Collect investigation package | `collectInvestigationPackageResponseAction` | `identifier` |
| Run AV scan | `runAntivirusScanResponseAction` | `identifier` |
| Initiate investigation | `initiateInvestigationResponseAction` | `identifier` |
| Restrict app execution | `restrictAppExecutionResponseAction` | `identifier` |
| Force password reset | `forceUserPasswordResetResponseAction` | `identifier` (SID-based) |
| Mark user compromised | `markUserAsCompromisedResponseAction` | `identifier` (ObjectId-based) |
| Disable user | `disableUserResponseAction` | `identifier` |
| Soft delete email | `softDeleteResponseAction` | `identifier` (comma-separated pair) |
| Hard delete email | `hardDeleteResponseAction` | `identifier` (comma-separated pair) |
| Move to junk | `moveToJunkResponseAction` | `identifier` (comma-separated pair) |
| Move to deleted items | `moveToDeletedItemsResponseAction` | `identifier` (comma-separated pair) |
| Move to inbox | `moveToInboxResponseAction` | `identifier` (comma-separated pair) |
| Stop and quarantine file | `stopAndQuarantineFileResponseAction` | `identifier` |
| Block file | `blockFileResponseAction` | `identifier` |
| Allow file | `allowFileResponseAction` | `identifier` |

## Example Rule

```yaml
displayName: Suspicious encoded PowerShell execution
isEnabled: true
queryCondition:
  queryText: |
    DeviceProcessEvents
    | where Timestamp > ago(1h)
    | where FileName =~ "powershell.exe"
    | where ProcessCommandLine has_any ("-enc", "-encodedcommand", "-e ")
    | project Timestamp, DeviceId, ReportId, DeviceName, AccountUpn, ProcessCommandLine
  lastModifiedDateTime: "2026-01-01T00:00:00Z"
schedule:
  period: "1H"
detectionAction:
  alertTemplate:
    title: "Suspicious encoded PowerShell execution"
    description: "A PowerShell process was launched with an encoded command."
    severity: medium
    category: Execution
    mitreTechniques:
      - T1059.001
    recommendedActions: "Review the encoded command. Check parent process and user context."
    impactedAssets:
      - "@odata.type": "#microsoft.graph.security.impactedDeviceAsset"
        identifier: deviceId
  responseActions:
    - "@odata.type": "#microsoft.graph.security.isolateDeviceResponseAction"
      identifier: deviceId
      isolationType: full
    - "@odata.type": "#microsoft.graph.security.collectInvestigationPackageResponseAction"
      identifier: deviceId
    - "@odata.type": "#microsoft.graph.security.runAntivirusScanResponseAction"
      identifier: deviceId
```

## Adding New Rules

### From the Defender XDR Portal

1. Navigate to **Hunting > Custom detection rules** in the Defender portal
2. Create and test your rule in the portal
3. Export the rule configuration
4. Convert to the YAML format documented above
5. Save as `DefenderCustomDetections/<Category>/<RuleName>.yaml`

### From Scratch

1. Develop your Advanced Hunting query in the Defender portal's **Hunting** page
2. Ensure the query returns the required entity columns for your impacted asset types
3. Create a YAML file following the schema above
4. Test with `WhatIf` mode in the pipeline before deploying

## Sentinel Data Limitations

If your Sentinel workspace is onboarded to the unified Defender portal, you can query Sentinel tables in custom detections, but with restrictions:

- **No response actions** on detections based purely on Sentinel data
- **No NRT frequency** for Sentinel-only queries
- **No device scoping** for Sentinel data
- **Custom frequency** (5min–14 days) is portal-only and not available via the Graph API

For full feature support (response actions, NRT, device scoping), use Defender XDR native Advanced Hunting tables.

## Prerequisites

### Graph API Permissions

The service principal used by the pipeline requires:

| Permission | Type | Description |
|------------|------|-------------|
| `CustomDetection.ReadWrite.All` | Application | Create, read, update, and delete custom detections |

Grant this in **Entra ID > App Registrations > API Permissions > Microsoft Graph**.

### Authentication

The pipeline acquires a Graph API token separately from the ARM token used for Sentinel operations. The service principal must be granted the Graph permission above and admin consent must be provided.

## API Reference

- [Custom detection rules overview](https://learn.microsoft.com/en-us/defender-xdr/custom-detections-overview)
- [Graph API: detectionRule resource](https://learn.microsoft.com/en-us/graph/api/resources/security-detectionrule)
- [Graph API: Create detectionRule](https://learn.microsoft.com/en-us/graph/api/security-detectionrule-post)
- [Advanced Hunting schema reference](https://learn.microsoft.com/en-us/defender-xdr/advanced-hunting-schema-tables)
