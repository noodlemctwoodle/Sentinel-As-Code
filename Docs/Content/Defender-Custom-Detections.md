# Defender XDR Custom Detection Rules

Custom detection rules for Microsoft Defender XDR, deployed via the Microsoft Graph Security API. Source files live under [`Content/DefenderCustomDetections/`](../../Content/DefenderCustomDetections).

## Overview

These rules run Advanced Hunting (KQL) queries on a schedule in the Defender XDR portal. They can trigger alerts and take automated actions such as isolating devices, disabling users, or collecting investigation packages.

> **Important**: Defender custom detections use the **Advanced Hunting** KQL schema (e.g. `DeviceProcessEvents`, `IdentityLogonEvents`), which is different from the **Log Analytics** schema used by Sentinel analytics rules. For Sentinel analytics rules, see [Analytical Rules](Analytical-Rules.md).

> **The rule shape changed on 1 October 2026.** Microsoft removed the original Graph fields (`isEnabled`, `schedule.period`, `category`, `mitreTechniques`, `impactedAssets`, `responseActions`) and replaced them with `status`, `schedule.frequency`, `tactics`, `entityMappings` and `automatedActions`. Every file in this repository uses the current shape. Files that still use the old names keep deploying, translated with a warning; see [Moving a rule from the old shape](#moving-a-rule-from-the-old-shape).

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

Each YAML file defines a single custom detection rule. The schema maps directly to the [Microsoft Graph Security API `detectionRule` resource](https://learn.microsoft.com/graph/api/resources/security-detectionrule?view=graph-rest-beta) (beta).

> **Toolkit schema**: the Sentinel as Code Toolkit (VS Code extension) bundles `defender-custom-detection-schema.json` and scaffolds rules from it. Its schema and template still describe the old field names, so until the Toolkit is updated its validator will flag files in the current shape. The deployer and the CI suite in this repository are the reference for the current shape.

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Client-provided rule id, lowercase kebab-case (for example `brute-force-entra-id-accounts`). Graph requires it when the rule is created; it cannot change afterwards |
| `displayName` | string | Rule display name (1-255 characters). The deployer matches existing rules by it |
| `queryCondition.queryText` | string | Advanced Hunting KQL query (must be non-empty) |
| `schedule.frequency` | string | ISO 8601 run frequency: `PT1H`, `PT3H`, `PT12H` or `P1D` |
| `detectionAction.alertTemplate.title` | string | Alert title (must be non-empty) |
| `detectionAction.alertTemplate.severity` | string | One of: `informational`, `low`, `medium`, `high` |
| `detectionAction.alertTemplate.tactics` | array | MITRE ATT&CK tactics, each `{ tactic, techniques }` (see [Tactics and techniques](#tactics-and-techniques)) |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `status` | string | `enabled` (the default when omitted) or `disabled`. `autoDisabled` is set by the service, not by you |
| `description` | string | Description of the rule itself |
| `detectionAction.alertTemplate.description` | string | Alert description |
| `detectionAction.alertTemplate.recommendedActions` | string | Recommended investigation steps |
| `detectionAction.alertTemplate.entityMappings` | object | Query columns mapped to alert entities (see [Entity mappings](#entity-mappings)) |
| `detectionAction.alertTemplate.customDetails` | object | Custom detail name to query column, shown on the alert |
| `detectionAction.automatedActions` | object | Automated actions by type (see [Automated actions](#automated-actions)) |
| `detectionAction.incidentConfiguration.isExcludedFromIncidentCorrelation` | boolean | `true` raises every alert as its own single-alert incident |
| `detectionAction.organizationalScope.deviceGroups` | array | Device groups the rule applies to |

When a rule sets no `automatedActions`, the deployer sends an empty set; when it sets no `organizationalScope`, it sends `null`. The repository file is therefore the source of truth on update: actions or scope added in the portal are removed by the next deploy.

### Field Order

Files in this repository use this order:

- Top level: `id`, `displayName`, `description`, `status`, `queryCondition`, `schedule`, `detectionAction`
- Inside `detectionAction.alertTemplate`: `title`, `description`, `severity`, `tactics`, `recommendedActions`, `entityMappings`, `customDetails`
- Inside `detectionAction`: `alertTemplate`, `automatedActions`, `incidentConfiguration`, `organizationalScope`

### Required Query Output Columns

Depending on the source table, your query **must** return certain columns or the rule will fail:

| Source Table Type | Required Columns |
|-------------------|-----------------|
| Defender for Endpoint (`Device*`) | `Timestamp`, `DeviceId`, `ReportId` |
| Identity tables (`Identity*`) | `Timestamp`, `ReportId` |
| Email tables (`Email*`) | `Timestamp`, `ReportId` |
| Alert tables (`Alert*`) | `Timestamp` only |
| Sentinel tables | `Timestamp` or `TimeGenerated` |

Every column named in `entityMappings`, `automatedActions` or `customDetails` must also be one the query returns. CI checks that each one appears in the query.

> **Alert limit**: Each rule can generate a maximum of **150 alerts per run**.

### Schedule Frequencies

| Value | Description |
|-------|-------------|
| `PT1H` | Every hour |
| `PT3H` | Every 3 hours |
| `PT12H` | Every 12 hours |
| `P1D` | Every 24 hours (`PT24H` is accepted and sent as `P1D`) |

Any other duration is rejected and the file skipped with an `invalid schedule.frequency` warning. Near real-time (the old period `0`) has no documented frequency in the API; configure NRT rules in the portal. Every rule shipped in the tree uses `PT1H`.

### Tactics and techniques

`detectionAction.alertTemplate.tactics` lists MITRE ATT&CK tactics. Each entry names one `tactic` and, optionally, its `techniques`; each technique can list `subTechniques`, which must belong to it:

```yaml
tactics:
  - tactic: CredentialAccess
    techniques:
      - technique: T1110
        subTechniques:
          - T1110.001
          - T1110.003
```

Accepted tactic values: `Reconnaissance`, `ResourceDevelopment`, `InitialAccess`, `Execution`, `Persistence`, `PrivilegeEscalation`, `DefenseEvasion`, `CredentialAccess`, `Discovery`, `LateralMovement`, `Collection`, `CommandAndControl`, `Exfiltration`, `Impact`. Techniques match `T` followed by four digits; sub-techniques add `.` and three digits.

### Entity mappings

`detectionAction.alertTemplate.entityMappings` maps query result columns to the entities attached to each alert. Each collection holds one or more mappings, and each mapping names columns, not identifier tokens:

```yaml
entityMappings:
  accounts:
    - aadUserIdColumn: AccountObjectId
      upnColumn: AccountUpn
  hosts:
    - deviceIdColumn: DeviceId
      nameColumn: DeviceName
  mailboxes:
    - primaryAddressColumn: RecipientEmailAddress
```

| Collection | Column properties |
|------------|-------------------|
| `accounts` | `aadUserIdColumn`, `sidColumn`, `upnColumn`, `nameColumn`, `ntDomainColumn`, `dnsDomainColumn`, `upnSuffixColumn` |
| `hosts` | `deviceIdColumn`, `nameColumn`, `netBiosNameColumn`, `ntDomainColumn`, `dnsDomainColumn` |
| `mailboxes` | `primaryAddressColumn` |
| `ips` | `addressColumn`, `scopeColumn` |
| `urls` | `addressColumn` |
| `files` | `nameColumn`, `sha1Column`, `sha256Column` |

Graph also accepts `processes`, `registryValues`, `dns`, `cloudApplications`, `oAuthApplications`, `securityGroups`, `mailClusters`, `mailMessages`, `azureResources`, `amazonResources` and `googleCloudResources`; see the [entityMappingConfiguration reference](https://learn.microsoft.com/graph/api/resources/security-entitymappingconfiguration?view=graph-rest-beta) for their properties.

### Automated actions

`detectionAction.automatedActions` groups actions by type. Each action names the query columns that identify its target:

```yaml
automatedActions:
  isolateDevices:
    - deviceIdColumn: DeviceId
      isolationType: full        # full or selective
  forceUserPasswordResets:
    - accountSidColumn: AccountSid
  markUsersAsCompromised:
    - accountObjectIdColumn: AccountObjectId
  hardDeleteEmails:
    - networkMessageIdColumn: NetworkMessageId
      recipientColumn: RecipientEmailAddress
```

| Action | Member | Required properties |
|--------|--------|---------------------|
| Isolate device | `isolateDevices` | `deviceIdColumn`, `isolationType` |
| Collect investigation package | `collectInvestigationPackages` | `deviceIdColumn` |
| Run antivirus scan | `runAntivirusScans` | `deviceIdColumn` |
| Initiate investigation | `initiateInvestigations` | `deviceIdColumn` |
| Restrict app execution | `restrictAppExecutions` | `deviceIdColumn` |
| Force password reset | `forceUserPasswordResets` | `accountSidColumn` |
| Disable user | `disableUsers` | `accountSidColumn` |
| Mark user compromised | `markUsersAsCompromised` | `accountObjectIdColumn` |
| Soft delete email | `softDeleteEmails` | `networkMessageIdColumn`, `recipientColumn` |
| Hard delete email | `hardDeleteEmails` | `networkMessageIdColumn`, `recipientColumn` |
| Move to junk | `moveEmailsToJunk` | `networkMessageIdColumn`, `recipientColumn` |
| Move to deleted items | `moveEmailsToDeletedItems` | `networkMessageIdColumn`, `recipientColumn` |
| Move to inbox | `moveEmailsToInbox` | `networkMessageIdColumn`, `recipientColumn` |
| Stop and quarantine file | `stopAndQuarantineFiles` | `deviceIdColumn`, `sha1Column` |
| Block file | `blockFiles` | `sha1Column` or `sha256Column`; optional `deviceGroupNames` |
| Allow file | `allowFiles` | `sha1Column` or `sha256Column`; optional `deviceGroupNames` |

## Example Rule

```yaml
id: suspicious-encoded-powershell
displayName: Suspicious encoded PowerShell execution
status: enabled
queryCondition:
  queryText: |
    DeviceProcessEvents
    | where Timestamp > ago(1h)
    | where FileName =~ "powershell.exe"
    | where ProcessCommandLine has_any ("-enc", "-encodedcommand", "-e ")
    | project Timestamp, DeviceId, ReportId, DeviceName, AccountUpn, ProcessCommandLine
schedule:
  frequency: PT1H
detectionAction:
  alertTemplate:
    title: "Suspicious encoded PowerShell execution"
    description: |
      A PowerShell process was launched with an encoded command.
    severity: medium
    tactics:
      - tactic: Execution
        techniques:
          - technique: T1059
            subTechniques:
              - T1059.001
    recommendedActions: |
      Review the encoded command. Check parent process and user context.
    entityMappings:
      hosts:
        - deviceIdColumn: DeviceId
          nameColumn: DeviceName
  automatedActions:
    isolateDevices:
      - deviceIdColumn: DeviceId
        isolationType: full
    collectInvestigationPackages:
      - deviceIdColumn: DeviceId
```

## Adding New Rules

### From the Defender XDR Portal

1. Navigate to **Hunting > Custom detection rules** in the Defender portal
2. Create and test your rule in the portal
3. Export the rule configuration
4. Convert to the YAML format documented above, giving it a new `id`
5. Save as `Content/DefenderCustomDetections/<Category>/<RuleName>.yaml`

### From Scratch

1. Develop your Advanced Hunting query in the Defender portal's **Hunting** page
2. Make sure the query returns every column your entity mappings and actions name
3. Create a YAML file following the schema above, with an `id` no other file uses
4. Test with `WhatIf` mode in the pipeline before deploying

## Moving a rule from the old shape

Graph removed the original fields on 1 October 2026. The deployer translates a file that still uses them before it sends it, and logs a warning naming the file and the fields, so such a file keeps deploying. Convert it to the current shape when you next edit it; CI rejects old field names in this repository. The translation is mechanical:

| Old field | Current field |
|-----------|---------------|
| `isEnabled: true` / `false` | `status: enabled` / `disabled` |
| `schedule.period: "1H"`, `"3H"`, `"12H"`, `"24H"` | `schedule.frequency: PT1H`, `PT3H`, `PT12H`, `P1D` |
| `alertTemplate.category` plus `mitreTechniques` | `alertTemplate.tactics`: the category becomes the tactic, sub-techniques are grouped under their parent technique |
| `alertTemplate.impactedAssets` | `alertTemplate.entityMappings`: `impactedUserAsset` to `accounts`, `impactedDeviceAsset` to `hosts`, `impactedMailboxAsset` to `mailboxes` |
| `detectionAction.responseActions` | `detectionAction.automatedActions`, one member per action type (see the [table above](#automated-actions)) |
| `organizationalScope.scopeNames` | `organizationalScope.deviceGroups` |
| `queryCondition.lastModifiedDateTime` | removed (read-only in Graph) |

Identifier tokens become column names by capitalising the first letter: `accountObjectId` is the column `AccountObjectId`, `deviceId` is `DeviceId`, and the email pair `"networkMessageId, recipientEmailAddress"` becomes `networkMessageIdColumn: NetworkMessageId` with `recipientColumn: RecipientEmailAddress`. The token's suffix picks the property: `ObjectId` maps to `aadUserIdColumn` (or `accountObjectIdColumn` on an action), `Sid` to `sidColumn` (`accountSidColumn`), `Upn` to `upnColumn`, `Name` to `nameColumn`, `Domain` to `ntDomainColumn`, a device `Id` to `deviceIdColumn`, and a mailbox `Address` to `primaryAddressColumn`. These columns are the ones the old identifiers already required the query to return. A new rule also needs an `id`; the deployer cannot create a rule without one, though it still updates an existing rule (matched by `displayName`) that has none.

## Sentinel Data Limitations

If your Sentinel workspace is onboarded to the unified Defender portal, you can query Sentinel tables in custom detections, but the Defender platform imposes restrictions:

- **No automated actions** on detections based purely on Sentinel data
- **No NRT frequency** for Sentinel-only queries
- **No device scoping** for Sentinel data
- **Custom frequency** (5min to 14 days) is portal-only and not available via the Graph API

For full feature support (automated actions, NRT, device scoping), use Defender XDR native Advanced Hunting tables.

> **The deploy script does not enforce these limits.** `Deploy-DefenderDetections.ps1` performs no source-table analysis: it does not detect a Sentinel-only query or strip `automatedActions` attached to one. The repository even contains such a sample (`Sentinel/VpnConnectionFromTorExitNode.yaml` queries `SigninLogs` and marks the user compromised). If the Defender platform rejects or silently ignores the action for a Sentinel-only rule, that happens server-side at or after deploy time, not in the pipeline. Treat the list above as a Defender-platform constraint you are responsible for honouring, not a validated guardrail.

## Prerequisites

### Graph API Permissions

The service principal used by the pipeline requires:

| Permission | Type | Description |
|------------|------|-------------|
| `CustomDetection.ReadWrite.All` | Application | Create, read, update, and delete custom detections |

Grant this in **Entra ID > App Registrations > API Permissions > Microsoft Graph**. The bootstrap script [`Deploy/setup/Setup-ServicePrincipal.ps1`](../../Deploy/setup/Setup-ServicePrincipal.ps1) handles this; see [Scripts](../Deploy/Scripts.md#setup-serviceprincipalps1).

### Authentication

The pipeline acquires a Graph API token separately from the ARM token used for Sentinel operations. The service principal must be granted the Graph permission above and admin consent must be provided. Microsoft offers the custom detection rules API on the global service only, not in US Government (L4, L5) or China clouds, so `-IsGov` runs are expected to fail.

## Deployment

Handled by [`Deploy/content/Deploy-DefenderDetections.ps1`](../../Deploy/content/Deploy-DefenderDetections.ps1) and Stage 5 of the deploy pipeline. See [Scripts](../Deploy/Scripts.md#deploy-defenderdetectionsps1) and [Pipelines](../Pipelines/README.md).

### How rules are validated

The deploy script targets the Microsoft Graph beta endpoint `security/rules/detectionRules`. It reads every `*.yaml`/`*.yml` file under `Content/DefenderCustomDetections/` recursively, parses each with `powershell-yaml`, translates any old field names, and validates the result with `Test-DetectionRule`: the required fields above, the frequency, status, severity and tactic values, technique patterns, entity mapping collections, and the required properties of each automated action. A file that fails is skipped with a warning listing every problem rather than failing the run. The CI suite [`Tests/Test-DefenderDetectionYaml.Tests.ps1`](../../Tests/Test-DefenderDetectionYaml.Tests.ps1) runs the same validation on every file, and also requires an `id`, no old field names, and that every mapped column appears in the query.

### How rules are matched (upsert by displayName)

1. Before deploying, the script pages through all existing detection rules (following `@odata.nextLink`) and builds a `displayName → id` map.
2. If a YAML file's `displayName` matches an existing rule, the rule is updated in place with a **PATCH** to `.../detectionRules/{id}`. The existing rule keeps its id; the file's `id` is not sent.
3. If there is no match, a new rule is created with a **POST** that carries the file's `id`. A file with no `id` cannot be created and counts as a failed deployment.

> **Renaming a rule creates a duplicate.** Because matching is by `displayName` and not by file path or `id`, changing a rule's `displayName` makes the script treat it as a brand-new rule (POST) while the old rule keeps running in Defender under its previous name. Rename in the portal, or delete the stale rule, to avoid two live copies.

`displayName` and `id` must therefore be **unique across the entire content tree**. Both are enforced in CI by [`Tests/Test-DefenderDetectionYaml.Tests.ps1`](../../Tests/Test-DefenderDetectionYaml.Tests.ps1).

### Retry and throttling

Graph calls go through an `Invoke-GraphApi` wrapper that retries up to **3 attempts** on the retryable status codes `429`, `500`, `502`, `503` and `504`. On a `429` it honours the `Retry-After` response header where present, otherwise it backs off linearly. Persistent failures surface as a `Graph API call failed` error and mark that rule as failed in the deployment summary; the run exits non-zero if any rule fails.

## API Reference

- [Custom detection rules overview](https://learn.microsoft.com/defender-xdr/custom-detections-overview)
- [Graph API: detectionRule resource](https://learn.microsoft.com/graph/api/resources/security-detectionrule?view=graph-rest-beta)
- [Graph API: Create detectionRule](https://learn.microsoft.com/graph/api/security-rulesroot-post-detectionrules?view=graph-rest-beta)
- [Graph API: entityMappingConfiguration](https://learn.microsoft.com/graph/api/resources/security-entitymappingconfiguration?view=graph-rest-beta)
- [Graph API: automatedActionSet](https://learn.microsoft.com/graph/api/resources/security-automatedactionset?view=graph-rest-beta)
- [Advanced Hunting schema reference](https://learn.microsoft.com/defender-xdr/advanced-hunting-schema-tables)

## Authoring with GitHub Copilot

When editing files under `Content/DefenderCustomDetections/**`, Copilot
automatically loads [`.github/instructions/defender-detections.instructions.md`](../../.github/instructions/defender-detections.instructions.md).
The path-scoped instructions call out the Defender-specific gotchas
(the current field names, a client-provided `id`, lowercase severity,
columns rather than identifier tokens, the Advanced Hunting table set,
and the consent automated actions need). For the KQL body,
[`.github/instructions/kql-queries.instructions.md`](../../.github/instructions/kql-queries.instructions.md)
also loads.

Copilot tooling for Defender XDR detections:

- Slash command `/new-defender-detection` (VS Code) - bootstrap a fresh detection
- Agent `Sentinel-As-Code: Rule Author` - author end-to-end
- Agent `Sentinel-As-Code: KQL Engineer` - optimise the query body
- Agent `Sentinel-As-Code: Security Reviewer` - required when adding automated actions
  (isolateDevices, forceUserPasswordResets, etc.)

See [GitHub Copilot setup](../GitHub/GitHub-Copilot.md) for the full layout.
