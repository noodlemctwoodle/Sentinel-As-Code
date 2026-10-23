---
name: Defender XDR custom detections
description: Schema and authoring rules for Content/DefenderCustomDetections/**/*.yaml files.
applyTo: "Content/DefenderCustomDetections/**/*.yaml"
---

# Defender XDR custom detection authoring

Custom detection rules deployed to Defender XDR via the Microsoft
Graph Security API (beta). Loaded automatically when editing any
file under `Content/DefenderCustomDetections/`. Full schema in
[`Docs/Content/Defender-Custom-Detections.md`](../../Docs/Content/Defender-Custom-Detections.md).

Files use the Graph `detectionRule` shape in place since Microsoft
removed the original fields on 2026-10-01. Never write `isEnabled`,
`schedule.period`, `category`, `mitreTechniques`, `impactedAssets` or
`responseActions`; CI rejects them.

## Required fields

```yaml
id: <lowercase-kebab-case-id>      # client-provided; Graph needs it to create the rule
displayName: <human-readable detection name>
status: enabled                    # or disabled
queryCondition:
  queryText: |
    DeviceProcessEvents
    | where Timestamp > ago(1h)
    | where ProcessCommandLine has_any ("-enc", "-encodedcommand")
    | project Timestamp, ReportId, DeviceId, DeviceName, AccountSid, ProcessCommandLine
schedule:
  frequency: PT1H                  # PT1H, PT3H, PT12H or P1D
detectionAction:
  alertTemplate:
    title: "<alert title>"
    description: |
      Alert description shown in Defender XDR. Plain prose, multi-line.
    severity: high                 # high | medium | low | informational
    tactics:
      - tactic: Execution
        techniques:
          - technique: T1059
            subTechniques:
              - T1059.001
    entityMappings:
      hosts:
        - deviceIdColumn: DeviceId
          nameColumn: DeviceName
  automatedActions:                # optional; see the hard rules
    runAntivirusScans:
      - deviceIdColumn: DeviceId
```

## Hard rules

1. **Tables must come from the Defender XDR Advanced Hunting schema**:
   `DeviceEvents`, `DeviceProcessEvents`, `DeviceLogonEvents`,
   `DeviceFileEvents`, `IdentityLogonEvents`, `EmailEvents`,
   `CloudAppEvents`, `AlertInfo`, etc. Sentinel tables such as
   `SigninLogs` only work when the workspace is onboarded to the
   Defender portal, and then without automated actions or NRT.
2. **`id` is required and unique**, lowercase letters, digits and
   hyphens. It is set when the rule is created and cannot change.
3. **`schedule.frequency`** is one of `PT1H`, `PT3H`, `PT12H` or `P1D`.
   NRT has no API frequency; configure it in the portal.
4. **`severity` is lowercase** here (`high`, `medium`, `low`,
   `informational`), unlike analytical rules where it is PascalCase.
5. **Mappings and actions name query columns.** Every
   `*Column` value in `entityMappings`, `automatedActions` and
   `customDetails` must be a column the query returns (use `project`).
   CI checks each one appears in the query.
6. **Tactics use the MITRE names** (`InitialAccess`, `Execution`,
   `Persistence`, `PrivilegeEscalation`, `DefenseEvasion`,
   `CredentialAccess`, `Discovery`, `LateralMovement`, `Collection`,
   `CommandAndControl`, `Exfiltration`, `Impact`, `Reconnaissance`,
   `ResourceDevelopment`), and each sub-technique sits under its parent
   technique.
7. **Automated actions need explicit consent.** Adding `isolateDevices`,
   `forceUserPasswordResets`, `markUsersAsCompromised` and the like
   requires the deploy SP to have the matching action permission and an
   admin-approved consent flow. Do not add automated actions casually.

## Common column mappings

| Entity or action | Property | Usual column |
| --- | --- | --- |
| `entityMappings.hosts` | `deviceIdColumn` | `DeviceId` |
| `entityMappings.accounts` | `aadUserIdColumn` | `AccountObjectId` |
| `entityMappings.accounts` | `sidColumn` | `AccountSid` |
| `entityMappings.accounts` | `upnColumn` | `AccountUpn` |
| `entityMappings.mailboxes` | `primaryAddressColumn` | `RecipientEmailAddress` |
| `automatedActions.markUsersAsCompromised` | `accountObjectIdColumn` | `AccountObjectId` |
| `automatedActions.forceUserPasswordResets` | `accountSidColumn` | `AccountSid` |
| `automatedActions.hardDeleteEmails` | `networkMessageIdColumn`, `recipientColumn` | `NetworkMessageId`, `RecipientEmailAddress` |

## After editing

1. Run schema tests: `Invoke-Pester -Path Tests/Test-DefenderDetectionYaml.Tests.ps1`
2. The `Content/DefenderCustomDetections/` content is **not** in
   `dependencies.json`. Defender XDR is a separate deploy stage with
   its own table catalogue.

## Cross-references

- Full schema, automated actions and the old-to-new field table: [`Docs/Content/Defender-Custom-Detections.md`](../../Docs/Content/Defender-Custom-Detections.md)
- Deploy script: [`Deploy/content/Deploy-DefenderDetections.ps1`](../../Deploy/content/Deploy-DefenderDetections.ps1)
- Tests: [`Tests/Test-DefenderDetectionYaml.Tests.ps1`](../../Tests/Test-DefenderDetectionYaml.Tests.ps1)
