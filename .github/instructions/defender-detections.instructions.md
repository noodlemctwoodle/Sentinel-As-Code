---
name: Defender XDR custom detections
description: Schema and authoring rules for DefenderCustomDetections/**/*.yaml files.
applyTo: "DefenderCustomDetections/**/*.yaml"
---

# Defender XDR custom detection authoring

Custom detection rules deployed to Defender XDR via the Microsoft
Graph Security API (beta). Loaded automatically when editing any
file under `DefenderCustomDetections/`. Full schema in
[`Docs/Content/Defender-Custom-Detections.md`](../../Docs/Content/Defender-Custom-Detections.md).

## Required fields

```yaml
displayName: <human-readable detection name>
isEnabled: true
queryCondition:
  queryText: |
    DeviceProcessEvents
    | where Timestamp > ago(1h)
    | where ProcessCommandLine has_any (1, 2)
    | project Timestamp, DeviceId, AccountName, ProcessCommandLine
schedule:
  period: "0"        # "0" = NRT; otherwise ISO 8601 duration
detectionAction:
  alertTemplate:
    title: <alert title>
    description: |
      Alert description shown in Defender XDR. Plain prose, multi-line.
    severity: high | medium | low | informational
    category: Suspicious Activity | Persistence | Discovery | <category>
    mitreTechniques:
      - T1078
    impactedAssets:
      - identifier: deviceId
        '@odata.type': '#microsoft.graph.security.impactedDeviceAsset'
  organizationalScope: null
  responseActions: []
```

## Hard rules

1. **Tables must come from the Defender XDR Advanced Hunting schema**:
   `DeviceEvents`, `DeviceProcessEvents`, `DeviceLogonEvents`,
   `DeviceFileEvents`, `IdentityLogonEvents`, `EmailEvents`,
   `CloudAppEvents`, `AlertInfo`, etc. **Not** Sentinel tables like
   `SecurityAlert` or `SigninLogs` — those don't exist in Defender's
   Advanced Hunting.
2. **`schedule.period`**: use `"0"` for near-real-time. Otherwise an
   ISO 8601 duration (`"PT1H"`, `"P1D"`).
3. **`severity` is lowercase** here (`high`, `medium`, `low`,
   `informational`) — different convention from analytical rules
   where it's PascalCase.
4. **`impactedAssets[].identifier` must match a column in the query
   results.** If the query doesn't `project` the column with the
   exact `@odata.type` shape Defender expects, the rule fails to
   create.
5. **Response actions need explicit consent.** Adding `isolateDevice`,
   `forceUserPasswordReset`, etc. requires the deploy SP to have the
   matching action permission and an admin-approved consent flow. Do
   not add response actions casually.

## Common impacted-asset shapes

| Identifier | `@odata.type` | Source column |
| --- | --- | --- |
| `deviceId` | `#microsoft.graph.security.impactedDeviceAsset` | `DeviceId` |
| `accountObjectId` | `#microsoft.graph.security.impactedUserAsset` | `AccountObjectId` |
| `accountSid` | `#microsoft.graph.security.impactedUserAsset` | `AccountSid` |
| `mailbox` | `#microsoft.graph.security.impactedMailboxAsset` | `RecipientEmailAddress` |
| `url` | `#microsoft.graph.security.impactedUrlAsset` | `Url` |

## After editing

1. Run schema tests: `Invoke-Pester -Path Tests/Test-DefenderDetectionYaml.Tests.ps1`
2. The `DefenderCustomDetections/` content is **not** in
   `dependencies.json` — Defender XDR is a separate deploy stage with
   its own table catalogue.

## Cross-references

- Full schema + response actions: [`Docs/Content/Defender-Custom-Detections.md`](../../Docs/Content/Defender-Custom-Detections.md)
- Deploy script: [`Scripts/Deploy-DefenderDetections.ps1`](../../Scripts/Deploy-DefenderDetections.ps1)
- Tests: [`Tests/Test-DefenderDetectionYaml.Tests.ps1`](../../Tests/Test-DefenderDetectionYaml.Tests.ps1)
