---
name: Analytical rules
description: Schema and authoring rules for AnalyticalRules/**/*.yaml files.
applyTo: "AnalyticalRules/**/*.yaml"
---

# Analytical rule authoring

Custom Sentinel analytical rules in YAML. Loaded automatically when
editing any file under `AnalyticalRules/`. Full schema and worked
examples in
[`Docs/Content/Analytical-Rules.md`](../../Docs/Content/Analytical-Rules.md).

## Required fields (Scheduled rule)

```yaml
id: <unique GUID, never reuse across the analytical-rule tree>
name: <human-readable rule title>
description: |
  Multi-paragraph plain-prose description. What does it detect, and
  what should an analyst do with the alert?
severity: High | Medium | Low | Informational
requiredDataConnectors:
- connectorId: <ConnectorId>
  dataTypes:
  - <TableName>
queryFrequency: PT15M | PT1H | P1D       # ISO 8601 duration
queryPeriod:    PT1H | P1D | P7D
triggerOperator: gt | lt | eq | ne
triggerThreshold: 0
enabled: true                            # true = rule runs after deploy; false = deploys disabled
tactics:
- <MITRE tactic, PascalCase>
relevantTechniques:
- T1078
- T1078.004
query: |
  // KQL query body
  TableName
  | where TimeGenerated > ago(1h)
  | summarize count() by Account
  | where count_ > 10
entityMappings:
- entityType: Account
  fieldMappings:
  - identifier: Name
    columnName: Account
```

For NRT rules, set `kind: NRT` (top-level alongside `id` / `name`)
and remove `queryFrequency` / `queryPeriod` — NRT rules run
continuously. Scheduled rules don't need `kind:` set; the deployer
defaults to Scheduled.

## Hard rules

1. **`id` must be a fresh GUID.** Never reuse one from another rule.
   The schema test enforces uniqueness across the entire
   `AnalyticalRules/` tree.
2. **`enabled: true | false`.** This is the field name (not `status`,
   not `state`). Rules deploy enabled by default; set
   `enabled: false` to deploy disabled for review. The deployer also
   auto-falls-back to disabled if KQL validation fails at deploy
   time (e.g. a freshly deployed watchlist column isn't queryable
   yet).
3. **`tactics` use MITRE PascalCase**: `Persistence`, `LateralMovement`,
   `CredentialAccess`, `InitialAccess`, `Discovery`,
   `PrivilegeEscalation`, etc. Not `lateral-movement` or `Lateral movement`.
4. **`relevantTechniques` use MITRE technique IDs only**: `T1078`,
   `T1078.004`. Not technique names.
5. **`severity` must be one of**: `High`, `Medium`, `Low`,
   `Informational` (case-sensitive).
6. **`queryFrequency` ≤ `queryPeriod`** (you can't query a longer
   window than you sample at).
7. **`triggerOperator` + `triggerThreshold` must agree with the query**.
   If your query already filters with a threshold, set the operator
   to `gt` and threshold to `0`.

## After editing

1. Re-run the dep manifest:
   ```powershell
   ./Scripts/Build-DependencyManifest.ps1 -Mode Generate
   ```
2. Stage the rule + the regenerated `dependencies.json` together.
3. Run Pester locally: `Invoke-Pester -Path Tests/Test-AnalyticalRuleYaml.Tests.ps1`.

## KQL query body conventions

See [`.github/instructions/kql-queries.instructions.md`](./kql-queries.instructions.md)
for KQL conventions. Key points:

- Avoid `search *` and `union *` — they're slow and expensive.
- Use `bin(TimeGenerated, 1h)` not arbitrary buckets.
- Project a stable column set before the final pipe.
- Reference watchlists with `_GetWatchlist('alias')`, never via
  inline `dynamic([...])` hardcoding.

## Where this rule will run

The deploy pipeline reads this YAML, converts it to the Sentinel REST
API JSON shape, and `PUT`s it under
`/providers/Microsoft.SecurityInsights/alertRules/<ruleId>`. The script
that does this is
[`Scripts/Deploy-CustomContent.ps1`](../../Scripts/Deploy-CustomContent.ps1).

## Cross-references

- Full schema: [`Docs/Content/Analytical-Rules.md`](../../Docs/Content/Analytical-Rules.md)
- KQL conventions: [`./kql-queries.instructions.md`](./kql-queries.instructions.md)
- Test suite: [`Tests/Test-AnalyticalRuleYaml.Tests.ps1`](../../Tests/Test-AnalyticalRuleYaml.Tests.ps1)
- Discovery model: [`Docs/Operations/Dependency-Manifest.md`](../../Docs/Operations/Dependency-Manifest.md)
