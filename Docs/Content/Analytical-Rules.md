# Analytical Rules

Custom analytics rules authored in YAML, following the
[Azure-Sentinel Query Style Guide](https://github.com/Azure/Azure-Sentinel/wiki/Query-Style-Guide).
YAML files are converted to REST API JSON at deploy time by
[`Deploy/content/Deploy-CustomContent.ps1`](../../Deploy/content/Deploy-CustomContent.ps1).

The authoring contract for this content type (field names, required-vs-optional,
types, enums, patterns, and canonical field order) is defined by the Sentinel as
Code Toolkit, whose VS Code extension scaffolds a rule from a template and
validates it in the editor. See [Toolkit templates](../Toolkit/Templates.md)
(the `standard-rule` and `nrt-rule` templates) and
[schemas and validation](../Toolkit/Schemas-and-Validation.md)
(`sentinel-analytics-rule-schema.json`). The Toolkit authors and validates; it
does not deploy - deployment is this repository's pipeline.

| Concern | Where |
| --- | --- |
| Rule files | [`Content/AnalyticalRules/`](../../Content/AnalyticalRules) |
| Deploy logic | [`Deploy/content/Deploy-CustomContent.ps1`](../../Deploy/content/Deploy-CustomContent.ps1) (function `Deploy-CustomDetections`) |
| Drift detection | See [Sentinel Drift Detection](../Tools/Sentinel-Drift-Detection.md) |
| Community contributions | See [Community Rules](Community-Rules.md) |

## Folder structure

Rules are organised by category using subfolders. The category name is purely
organisational — it does not affect deploy behaviour.

```
Content/AnalyticalRules/
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
[`Content/AnalyticalRules/`](../../Content/AnalyticalRules). Add new ones as needed; the deploy
script walks all `*.yaml` and `*.yml` recursively.

## YAML schema

### Canonical field order

The order below is the one the Toolkit template uses and the extension's
field-ordering formatter enforces. Fields are marked **REQUIRED** or *optional*
per `sentinel-analytics-rule-schema.json`.

```yaml
id:                      # REQUIRED. GUID (8-4-4-4-12 hex), stable per rule
name:                    # REQUIRED. Display name, 1-260 chars
description: |           # REQUIRED. Block style (|), 1-5000 chars
severity:                # REQUIRED. Informational | Low | Medium | High
requiredDataConnectors:  # REQUIRED. >= 1 { connectorId, dataTypes } entry
queryFrequency:          # REQUIRED (Scheduled). ISO 8601 duration (PT1H, P1D)
queryPeriod:             # REQUIRED (Scheduled). ISO 8601 duration
triggerOperator:         # REQUIRED (Scheduled). gt | lt | eq | ne
triggerThreshold:        # REQUIRED (Scheduled). Integer >= 0
enabled:                 # Optional. Boolean, defaults true
tactics:                 # REQUIRED. >= 1 MITRE tactic (camelCase, no spaces)
relevantTechniques:      # Optional. MITRE technique IDs (T####, T####.###)
query: |                 # REQUIRED. KQL, block style (|), non-empty
entityMappings:          # Optional. >= 1 mapping, each with >= 1 field mapping
alertDetailsOverride:    # Optional. Per-row alert title/description/severity
customDetails:           # Optional. Surface extra query columns as key/value
eventGroupingSettings:   # Optional. aggregationKind: SingleAlert | AlertPerResult
incidentConfiguration:   # Optional. Incident creation + grouping
suppressionDuration:     # Optional. ISO 8601 duration
suppressionEnabled:      # Optional. Boolean
version:                 # REQUIRED. Semver (a.b.c)
kind:                    # REQUIRED. Scheduled | NRT
tags:                    # Optional. Freeform labels
```

Under the Toolkit schema the required fields are `id`, `name`, `description`,
`severity`, `requiredDataConnectors`, `tactics`, `query`, `version`, and `kind`.
`Scheduled` rules additionally require `queryFrequency`, `queryPeriod`,
`triggerOperator`, and `triggerThreshold` (`NRT` rules omit all four -
Sentinel manages their cadence). The extension flags any missing required field,
any unknown field (the schema is `additionalProperties: false`), and any value
that breaks an enum or pattern.

**Deploy-time note:** the deploy script is looser than the authoring schema.
`Deploy-CustomDetections` hard-requires only five fields (`id`, `name`, `kind`,
`severity`, `query`), plus the four scheduling fields for `Scheduled` rules; a
rule missing anything else still deploys. Author to the Toolkit schema
regardless - the Pester schema test also enforces a stricter contract before a
PR can merge (see [CI schema enforcement](#ci-schema-enforcement) below).

### Style rules

- **`triggerOperator`** should use short form (`gt`, `lt`, `eq`, `ne`). The
  `$operatorMap` hashtable inside `Deploy-CustomDetections` maps these to
  API form (`GreaterThan`, `LessThan`, `Equal`, `NotEqual`) at deploy time.
  The map also accepts the long forms (`greaterthan`, `lessthan`, `equal`,
  `notequal`), and the lookup is case-insensitive; an unrecognised value is
  passed through to the API verbatim.
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

  | Case | Where in `Deploy-CustomDetections` |
  | --- | --- |
  | Rule lives under `Content/AnalyticalRules/Community/**` | The `$isCommunityRule` path (matched from the file path) forces `$ruleEnabled = $false` |
  | A required data type / watchlist / function dependency is missing at deploy time | `Test-ContentDependencies` returns `Passed = $false`, setting `$missingDeps` and forcing `$ruleEnabled = $false` |
  | KQL validation fails at deploy (e.g. a freshly deployed watchlist isn't queryable yet) | The `catch` block re-PUTs the rule with `enabled = $false` when the error looks like a KQL resolution failure |

  Because `enabled` is routinely overridden at deploy time, the [drift
  detector](../Tools/Sentinel-Drift-Detection.md) deliberately excludes it from
  comparison — flipping a rule on/off in the portal is not treated as drift.

- **`[Deprecated]` display names** — note that hand-authored rules under
  `Content/AnalyticalRules/**` are **never** skipped for having `[Deprecated]`
  in the name. `Deploy-CustomDetections` has no such filter. The `[Deprecated]`
  skip exists only in the separate
  [`Deploy-SentinelContentHub.ps1`](../../Deploy/content/Deploy-SentinelContentHub.ps1)
  (its `Deploy-*` loop over Microsoft Content-Hub packaged ARM-template
  solutions), which is a different deploy path. If you want a custom rule gone,
  delete or disable the YAML file rather than renaming it.
- **Tactics casing** — camelCase, no spaces: `InitialAccess`,
  `LateralMovement`, `PrivilegeEscalation`, `CredentialAccess`, etc.
- **`entityMappings`** - optional, but when the key is present the Toolkit
  schema requires at least one mapping (`minItems: 1`), each with at least one
  field mapping (an `identifier` plus a `columnName`). Sentinel itself caps a
  rule at 10 entity mappings with up to 3 field mappings each; the Toolkit
  schema does not enforce those upper bounds.
- **`sentinelEntitiesMappings`** - this is **not** part of the Toolkit authoring
  schema. Because the schema is `additionalProperties: false`, the extension
  flags a `sentinelEntitiesMappings` block as an unknown field and does not
  scaffold or format it.

  **Deploy-time note:** if a rule nonetheless carries a
  `sentinelEntitiesMappings` block, `Deploy-CustomDetections` forwards it to the
  API verbatim (in addition to any `entityMappings`). Treat it as a
  compatibility escape hatch for rules imported from sources that use the legacy
  shape, not a field to author by hand.
- **`alertDetailsOverride`** - the Toolkit schema accepts the four sub-fields
  `alertDisplayNameFormat`, `alertDescriptionFormat`, `alertSeverityColumnName`,
  and `alertTacticsColumnName`, all optional. The "max 3 `{{columnName}}`
  placeholders per field" cap is a Sentinel service limit, not a schema rule.
- **`customDetails`** - the Toolkit schema accepts an object of string values.
  Sentinel limits this to 20 key-value pairs with keys of at most 20 characters;
  the schema does not enforce those limits.

### Field details

| Field | Type | Notes |
| --- | --- | --- |
| `id` | GUID | Generate with `New-Guid` (PowerShell) or `uuidgen` (bash) |
| `name` | string | Required. 1-260 chars (schema `maxLength: 260`). House style: sentence case, no trailing period. |
| `description` | string | Required. 1-5000 chars (schema). Block style (`\|`). By convention starts with "Detects" or "Identifies", but this wording is a house style aspiration only - it is not enforced by the deploy script or the Pester tests, and several in-repo rules do not follow it. The Pester test only requires the description to be present and non-empty. |
| `severity` | string | `Informational`, `Low`, `Medium`, or `High` |
| `enabled` | boolean | `true` (default) or `false`. Force-disabled by the deploy script for community rules, missing dependencies, and KQL validation failures (see Style rules above) |
| `kind` | string | `Scheduled` (requires queryFrequency, queryPeriod, triggerOperator, triggerThreshold) or `NRT` |
| `queryFrequency` | string | ISO 8601 duration (e.g., `PT1H`, `P1D`). Scheduled only. |
| `queryPeriod` | string | ISO 8601 duration; should be >= `queryFrequency`. Scheduled only. The schema validates the duration format only; the `P14D` maximum is a Sentinel service limit, not a schema rule. |
| `triggerOperator` | string | Short form: `gt`, `lt`, `eq`, or `ne` (schema enum). Scheduled only. |
| `triggerThreshold` | integer | Minimum 0; the schema sets no upper bound. Scheduled only. |
| `tactics` | string[] | Required, >= 1 entry. MITRE ATT&CK tactic names (camelCase, e.g., `CredentialAccess`, `Persistence`) |
| `relevantTechniques` | string[] | MITRE IDs (e.g., `T1110`, `T1078.004`). Use `relevantTechniques`, not `techniques`. At deploy the list is split: parent IDs (`T####`) go to the API `techniques` property, and any sub-technique IDs (`T####.###`) are additionally sent to the preview `subTechniques` property. This is why the portal may display parent and sub-techniques in separate fields. |
| `requiredDataConnectors` | array | Required. >= 1 `{ connectorId, dataTypes }` object; each `dataTypes` array needs >= 1 entry. `connectorId` matches `^[A-Za-z][A-Za-z0-9]*$`. |
| `query` | string | Required. Block style (`\|`). KQL query, non-empty (schema `minLength: 1`); the schema sets no maximum length. |
| `entityMappings` | array | Optional. When present, >= 1 mapping, each with >= 1 field mapping of `identifier` + `columnName` (see reference below). The 10-mapping / 3-identifier caps are Sentinel limits, not schema rules. |
| `customDetails` | object | Optional. Object of string values. The 20-pair / 20-char-key limits are Sentinel limits, not schema rules. |
| `alertDetailsOverride` | object | Optional. Sub-fields (all optional): `alertDisplayNameFormat`, `alertDescriptionFormat`, `alertSeverityColumnName`, `alertTacticsColumnName`. The 3-placeholder-per-field cap is a Sentinel limit. |
| `eventGroupingSettings` | object | Optional. `aggregationKind`: `SingleAlert` or `AlertPerResult`. |
| `incidentConfiguration` | object | Optional. `createIncident`, plus `groupingConfiguration` (`enabled`, `reopenClosedIncident`, `lookbackDuration`, `matchingMethod`: `AllEntities` \| `AnyAlert` \| `Selected`, `groupByEntities`). |
| `suppressionEnabled` | boolean | Optional. Defaults to `false` at deploy. When `true`, alerting is suppressed for `suppressionDuration` after a rule fires. |
| `suppressionDuration` | string | Optional. ISO 8601 duration. Defaults to `PT5H` at deploy. Only meaningful when `suppressionEnabled` is `true`. |
| `version` | string | Semver (e.g., `1.0.0`). The drift sync bumps the patch component when it absorbs portal edits — see [Sentinel Drift Detection](../Tools/Sentinel-Drift-Detection.md#how-custom-drift-gets-absorbed). |
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

The deploy logic lives in [`Deploy/content/Deploy-CustomContent.ps1`](../../Deploy/content/Deploy-CustomContent.ps1)
(function `Deploy-CustomDetections`). Notable behaviours that affect how
you should author rules:

| Behaviour | Where |
| --- | --- |
| Rules deploy `enabled: true` by default. Override with `enabled: false` in the YAML. | The `$ruleEnabled` resolution in `Deploy-CustomDetections` |
| Rules under `Content/AnalyticalRules/Community/**` always deploy disabled. | The `$isCommunityRule` path in `Deploy-CustomDetections` - see [Community Rules](Community-Rules.md) |
| If a dependency (required table / watchlist / function) is missing, the rule deploys disabled and waits. | `Test-ContentDependencies` sets `$missingDeps` in `Deploy-CustomDetections` |
| If KQL validation fails at deploy time (e.g. a freshly deployed watchlist column isn't queryable yet), the rule retries deployment with `enabled: false`. | The KQL-error `catch` block in `Deploy-CustomDetections` |
| Smart deployment is opt-in (`-SmartDeployment`) and **off by default** - a normal run deploys all content. When enabled, only files changed since the last successful run are redeployed, via the `Test-ShouldDeployFile` helper. Bumping `version` is not required, but the drift sync bumps it automatically when absorbing portal edits. | The `$SmartDeployment` switch and `Initialize-SmartDeployment` / `Test-ShouldDeployFile` in `Deploy-CustomContent.ps1` |

### Dependency gating

The "missing dependency deploys disabled" behaviour is implemented by
`Test-ContentDependencies`, which checks a rule's declared prerequisites
(tables, watchlists, and KQL functions/parsers) against the dependency manifest
loaded into `$script:DependencyGraph`. If no manifest is loaded, or a rule has
no manifest entry, the rule deploys unconditionally. Only rules with an entry
whose prerequisites are not yet present are forced to `enabled: false`. This is
the same manifest that the `dependency-manifest` PR-validation job verifies for
drift.

## CI schema enforcement

`Deploy-CustomDetections` only hard-requires five fields, but a PR will not pass
CI unless the rule also satisfies the stricter Pester contract in
[`Tests/Test-AnalyticalRuleYaml.Tests.ps1`](../../Tests/Test-AnalyticalRuleYaml.Tests.ps1),
which runs in the `validate` job of `pr-validation.yml`. On top of the deploy
script's checks it requires:

- a non-empty `description`;
- a SemVer `version` (matching `X.Y.Z`, no pre-release/build metadata);
- a GUID-format `id` (8-4-4-4-12 hex). This check is **skipped** for rules
  under `Content/AnalyticalRules/Community/**`, which are imported from
  third-party repos that use non-GUID identifiers;
- valid `severity` and `kind` values, and, for `Scheduled` rules, ISO 8601
  `queryFrequency`/`queryPeriod`, a valid `triggerOperator`, and an integer
  `triggerThreshold`.

Treat these as effectively required for any rule you author, even though the
deploy script alone would not reject their absence.

## Authoring with GitHub Copilot

When editing files under `Content/AnalyticalRules/**`, Copilot automatically
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

See [GitHub Copilot setup](../GitHub/GitHub-Copilot.md) for the full layout.

## Related docs

- [Toolkit Templates](../Toolkit/Templates.md) - the `standard-rule` and
  `nrt-rule` templates the extension scaffolds this type from
- [Toolkit Schemas and Validation](../Toolkit/Schemas-and-Validation.md) -
  `sentinel-analytics-rule-schema.json`, the authoring contract the extension
  validates against
- [Sentinel Drift Detection](../Tools/Sentinel-Drift-Detection.md) — daily detection of
  portal-edited rules, with auto-PR back into the repo for Custom drift
- [Community Rules](Community-Rules.md) — opt-in third-party contributions
  under `Content/AnalyticalRules/Community/`
- [Pester Tests](../Tests/Pester-Tests.md) — running and extending the test suite for
  the drift-detection logic
