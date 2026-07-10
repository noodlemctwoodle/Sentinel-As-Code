# Defender XDR Custom Detection Rules

Custom detection rules for Microsoft Defender XDR, deployed via the Microsoft Graph Security API. Source files live under [`Content/DefenderCustomDetections/`](../../Content/DefenderCustomDetections).

## Overview

These rules run Advanced Hunting (KQL) queries on a schedule in the Defender XDR portal. They can trigger alerts and take automated response actions such as isolating devices, disabling users, or collecting investigation packages.

> **Important**: Defender custom detections use the **Advanced Hunting** KQL schema (e.g. `DeviceProcessEvents`, `IdentityLogonEvents`), which is different from the **Log Analytics** schema used by Sentinel analytics rules. For Sentinel analytics rules, see [Analytical Rules](Analytical-Rules.md).

## Folder Structure

```
Content/DefenderCustomDetections/
  <RuleName>.yaml               # One YAML file per detection rule
```

Rules can also be organised into subfolders by category:

```
Content/DefenderCustomDetections/
  Endpoint/
    SuspiciousProcessExecution.yaml
  Identity/
    BruteForceEntraIDAccounts.yaml
  Email/
    PhishingLinkClicked.yaml
```

## YAML Schema

Each YAML file defines a single custom detection rule. The schema maps directly to the [Microsoft Graph Security API `detectionRule` resource](https://learn.microsoft.com/en-us/graph/api/resources/security-detectionrule).

> **Authoring with the Toolkit**: The Sentinel as Code Toolkit (VS Code extension) scaffolds a starter rule (`Defender-As-Code: Generate Custom Detection Template`) and validates every field, enum, pattern and the canonical field order against its bundled `defender-custom-detection-schema.json`, which is the authoring contract described below. See [Templates](../Toolkit/Templates.md) and [Schemas and Validation](../Toolkit/Schemas-and-Validation.md).

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `displayName` | string | Rule display name (1-255 characters) |
| `queryCondition.queryText` | string | Advanced Hunting KQL query (must be non-empty) |
| `schedule.period` | string | Run frequency, one of: `0` (NRT), `1H`, `3H`, `12H`, `24H` |
| `detectionAction.alertTemplate.title` | string | Alert title (must be non-empty) |
| `detectionAction.alertTemplate.severity` | string | One of: `informational`, `low`, `medium`, `high` |
| `detectionAction.alertTemplate.category` | string | Alert category, a free string; by convention one of the MITRE-tactic-shaped values (see [Alert Categories](#alert-categories)) |
| `detectionAction.alertTemplate.mitreTechniques` | array | MITRE ATT&CK technique IDs. Each must match `^T[0-9]{4}(\.[0-9]{3})?$` (e.g. `T1059` or `T1059.001`) |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `isEnabled` | boolean | Whether the rule is active (default: `true` when the YAML omits it) |
| `detectionAction.alertTemplate.description` | string | Alert description |
| `detectionAction.alertTemplate.recommendedActions` | string | Recommended investigation steps |
| `detectionAction.alertTemplate.impactedAssets` | array | Entity mappings for alerts (see [Impacted Assets](#impacted-assets-entity-mappings)) |
| `detectionAction.responseActions` | array | Automated response actions (defaults to an empty array when omitted) |

The schema is closed (`additionalProperties: false`) at the top level and on each `impactedAssets` / `responseActions` entry, so only the fields documented here are accepted in those positions.

> **Deploy-time note**: The Toolkit schema requires `detectionAction.alertTemplate.mitreTechniques`, but the deploy script (`Deploy-DefenderDetections.ps1`) does **not** enforce it. `Deploy-DefenderDetections` validates only `displayName`, `queryCondition.queryText`, `schedule.period` and the `alertTemplate` `title` / `severity` / `category` before building the Graph body; a rule with no `mitreTechniques` still deploys. Author to the schema (always include `mitreTechniques`) so the Toolkit passes validation.

> **Deploy-time note**: `queryCondition.lastModifiedDateTime` is **not** part of the Toolkit authoring schema, so the Toolkit does not scaffold or require it. The deploy script passes it through verbatim to Graph if present (an ISO 8601 timestamp such as `"2026-03-23T00:00:00Z"` recording when the query body was last touched), and many rules in the tree carry one. It is optional and safe to omit.

> **Not settable via YAML**: `detectionAction.organizationalScope` is always sent as `null` by the deploy script regardless of YAML content, so there is no way to scope a rule to specific device groups or tenants from the repository. Any `organizationalScope` you add to the YAML is silently discarded.

### Field Order

The Toolkit's canonical field order (enforced by `Sentinel-As-Code: Fix Field Order` and drawn from the bundled template) is:

- Top level: `displayName`, `isEnabled`, `queryCondition`, `schedule`, `detectionAction`
- Inside `detectionAction.alertTemplate`: `title`, `description`, `severity`, `category`, `mitreTechniques`, `recommendedActions`, `impactedAssets`
- Inside `detectionAction`: `alertTemplate`, then `responseActions`

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

The deploy script (`Deploy-DefenderDetections.ps1`) validates `schedule.period` against exactly this literal token set (`0`, `1H`, `3H`, `12H`, `24H`); any other value, including ISO 8601 durations such as `PT1H` or `P1D`, is rejected and the file skipped with an `invalid schedule period` warning. Every rule shipped in the tree uses `1H`. Note that `0` (NRT) is accepted because the Graph schema permits it, but Microsoft only documents NRT configuration through the portal UI, so the script emits a warning and NRT rules may not behave as expected when deployed via the API.

### Alert Categories

`detectionAction.alertTemplate.category` takes a single MITRE-tactic-shaped value. The rules currently in the tree use the following set:

`InitialAccess`, `Execution`, `Persistence`, `PrivilegeEscalation`, `DefenseEvasion`, `CredentialAccess`, `LateralMovement`, `Collection`, `CommandAndControl`, `Exfiltration`, `Impact`

Pick the tactic that best matches the behaviour the query detects. The value is not validated by the deploy script, so a typo will be sent to the Graph API as-is.

### Impacted Assets (Entity Mappings)

Map query columns to alert entities using the `impactedAssets` array. Each entry requires `@odata.type` and `identifier` (and accepts no other fields). `@odata.type` must be one of three values:

- `#microsoft.graph.security.impactedDeviceAsset`
- `#microsoft.graph.security.impactedUserAsset`
- `#microsoft.graph.security.impactedMailboxAsset`

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

Automated actions taken when the rule triggers. In the schema, every entry requires `@odata.type` and `identifier`, and the only other fields it accepts are `isolationType` (isolate-device only) and `deviceGroupNames` (allow-file / block-file only). `@odata.type` must be one of the sixteen values in the [Complete Action Reference](#complete-action-reference) below.

> **Important**: The `identifier` field is an enum value that tells Defender which query column to read, not a free-form column name. Each action type has its own set of valid identifier values.

> **Note**: The Toolkit schema marks only `@odata.type` and `identifier` as structurally required. `isolationType` is optional in the schema but Defender requires it at runtime for `isolateDeviceResponseAction`, so always set it (`full` or `selective`).

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
    deviceGroupNames: []       # optional: scope the block to named device groups
  - "@odata.type": "#microsoft.graph.security.allowFileResponseAction"
    identifier: sha256
    deviceGroupNames: []       # optional: scope the allow to named device groups
```

`blockFileResponseAction` and `allowFileResponseAction` accept an optional `deviceGroupNames` array. Leave it empty (`[]`) to apply the action tenant-wide, or list device group names to limit the action to those groups.

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
5. Save as `Content/DefenderCustomDetections/<Category>/<RuleName>.yaml`

### From Scratch

1. Develop your Advanced Hunting query in the Defender portal's **Hunting** page
2. Ensure the query returns the required entity columns for your impacted asset types
3. Create a YAML file following the schema above
4. Test with `WhatIf` mode in the pipeline before deploying

## Sentinel Data Limitations

If your Sentinel workspace is onboarded to the unified Defender portal, you can query Sentinel tables in custom detections, but the Defender platform imposes restrictions:

- **No response actions** on detections based purely on Sentinel data
- **No NRT frequency** for Sentinel-only queries
- **No device scoping** for Sentinel data
- **Custom frequency** (5min to 14 days) is portal-only and not available via the Graph API

For full feature support (response actions, NRT, device scoping), use Defender XDR native Advanced Hunting tables.

> **The deploy script does not enforce these limits.** `Deploy-DefenderDetections.ps1` performs no source-table analysis: it does not detect a Sentinel-only query or strip a `responseActions` block attached to one. The repository even contains such a sample (`Sentinel/VpnConnectionFromTorExitNode.yaml` queries `SigninLogs` and attaches `markUserAsCompromisedResponseAction`). If the Defender platform rejects or silently ignores the response action for a Sentinel-only rule, that happens server-side at or after deploy time, not in the pipeline. Treat the list above as a Defender-platform constraint you are responsible for honouring, not a validated guardrail.

## Prerequisites

### Graph API Permissions

The service principal used by the pipeline requires:

| Permission | Type | Description |
|------------|------|-------------|
| `CustomDetection.ReadWrite.All` | Application | Create, read, update, and delete custom detections |

Grant this in **Entra ID > App Registrations > API Permissions > Microsoft Graph**. The bootstrap script [`Deploy/setup/Setup-ServicePrincipal.ps1`](../../Deploy/setup/Setup-ServicePrincipal.ps1) handles this; see [Scripts](../Deploy/Scripts.md#setup-serviceprincipalps1).

### Authentication

The pipeline acquires a Graph API token separately from the ARM token used for Sentinel operations. The service principal must be granted the Graph permission above and admin consent must be provided.

## Deployment

Handled by [`Deploy/content/Deploy-DefenderDetections.ps1`](../../Deploy/content/Deploy-DefenderDetections.ps1) and Stage 5 of the deploy pipeline. See [Scripts](../Deploy/Scripts.md#deploy-defenderdetectionsps1) and [Pipelines](../Pipelines/README.md).

### How rules are matched (upsert by displayName)

The deploy script targets the Microsoft Graph beta endpoint `security/rules/detectionRules` (or `graph.microsoft.us` with `-IsGov`). It reads every `*.yaml`/`*.yml` file under `Content/DefenderCustomDetections/` recursively (including subfolders), parses each with `powershell-yaml`, and validates the required fields (`displayName`, `queryCondition.queryText`, `schedule.period`, and `detectionAction.alertTemplate` with `title`, `severity`, `category`) before building the Graph request body. Any file missing one of these, or carrying an out-of-range `schedule.period`, is skipped with a warning rather than failing the run.

Rules are upserted by **`displayName`**:

1. Before deploying, the script pages through all existing detection rules (following `@odata.nextLink`) and builds a `displayName → id` map.
2. If a YAML file's `displayName` matches an existing rule, the rule is updated in place with a **PATCH** to `.../detectionRules/{id}`.
3. If there is no match, a new rule is created with a **POST**.

> **Renaming a rule creates a duplicate.** Because matching is by `displayName` and not by file path, changing a rule's `displayName` makes the script treat it as a brand-new rule (POST) while the old rule keeps running in Defender under its previous name. Rename in the portal, or delete the stale rule, to avoid two live copies.

`displayName` must therefore be **unique across the entire content tree**. This is enforced in CI by [`Tests/Test-DefenderDetectionYaml.Tests.ps1`](../../Tests/Test-DefenderDetectionYaml.Tests.ps1), which fails the build if two files (in any category) share a `displayName`, since a collision would cause the two rules to overwrite each other on deploy.

### Retry and throttling

Graph calls go through an `Invoke-GraphApi` wrapper that retries up to **3 attempts** on the retryable status codes `429`, `500`, `502`, `503` and `504`. On a `429` it honours the `Retry-After` response header where present, otherwise it backs off linearly. Persistent failures surface as a `Graph API call failed` error and mark that rule as failed in the deployment summary; the run exits non-zero if any rule fails.

## API Reference

- [Custom detection rules overview](https://learn.microsoft.com/en-us/defender-xdr/custom-detections-overview)
- [Graph API: detectionRule resource](https://learn.microsoft.com/en-us/graph/api/resources/security-detectionrule)
- [Graph API: Create detectionRule](https://learn.microsoft.com/en-us/graph/api/security-detectionrule-post)
- [Advanced Hunting schema reference](https://learn.microsoft.com/en-us/defender-xdr/advanced-hunting-schema-tables)

## Authoring with GitHub Copilot

When editing files under `Content/DefenderCustomDetections/**`, Copilot
automatically loads [`.github/instructions/defender-detections.instructions.md`](../../.github/instructions/defender-detections.instructions.md).
The path-scoped instructions call out the Defender-specific gotchas
(`isEnabled` not `enabled`, lowercase severity, Advanced Hunting
table set, response-action consent requirements). For the KQL
body, [`.github/instructions/kql-queries.instructions.md`](../../.github/instructions/kql-queries.instructions.md)
also loads.

Copilot tooling for Defender XDR detections:

- Slash command `/new-defender-detection` (VS Code) - bootstrap a fresh detection
- Agent `Sentinel-As-Code: Rule Author` - author end-to-end
- Agent `Sentinel-As-Code: KQL Engineer` - optimise the query body
- Agent `Sentinel-As-Code: Security Reviewer` - required when adding response actions
  (isolateDevice, forceUserPasswordReset, etc.)

See [GitHub Copilot setup](../GitHub/GitHub-Copilot.md) for the full layout.
