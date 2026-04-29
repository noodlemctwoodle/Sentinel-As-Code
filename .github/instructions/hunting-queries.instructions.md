---
name: Hunting queries
description: Schema and authoring rules for HuntingQueries/**/*.yaml files.
applyTo: "HuntingQueries/**/*.yaml"
---

# Hunting query authoring

Saved searches that surface in the Sentinel Hunting blade. Loaded
automatically when editing any file under `HuntingQueries/`. Full
schema in
[`Docs/Content/Hunting-Queries.md`](../../Docs/Content/Hunting-Queries.md).

## Required fields

```yaml
id: <unique GUID>
name: <human-readable hunting query title>
description: |
  Plain-prose description of the threat scenario this query helps
  hunt. State what an analyst should look for in the results.
requiredDataConnectors:
  - connectorId: <ConnectorId>
    dataTypes:
      - <TableName>
tactics:
  - <MITRE tactic, PascalCase>
relevantTechniques:
  - T1078
query: |
  // KQL hunting query
  SigninLogs
  | where TimeGenerated > ago(7d)
  | where ResultType !in ("0", "50140")
  | summarize FailureCount = count() by UserPrincipalName
  | where FailureCount > 100
tags:
  - Description: <short summary, optional>
  - Tactics: <comma-joined tactics, optional>
  - Techniques: <comma-joined technique IDs, optional>
```

## Hunting vs analytical rule — when to use which

- **Analytical rule**: alerts an SOC analyst when this happens. Use
  for high-confidence detections that warrant an incident.
- **Hunting query**: lets an analyst proactively look for this
  pattern. Use for exploratory queries, threat-hunt hypotheses, and
  IOC sweeps.

If a query produces too many false positives to alert on, it's a
hunting query, not an analytical rule.

## Hard rules

1. **`id` must be a fresh GUID.** Never reuse from analytical rules
   or other hunting queries.
2. **Hunting queries don't have `severity`, `triggerThreshold`, or
   `enabled`.** They're saved searches, not alert rules.
3. **`tactics` and `relevantTechniques`** follow the same MITRE
   conventions as analytical rules (PascalCase tactics, T#### technique
   IDs).
4. **Don't use `_GetWatchlist` for transient IOC lists.** Hunting is
   for exploring; if you need to pin down IOCs, write an analytical
   rule.

## After editing

1. Re-run the dep manifest:
   ```powershell
   ./Scripts/Build-DependencyManifest.ps1 -Mode Generate
   ```
2. Run schema tests: `Invoke-Pester -Path Tests/Test-AnalyticalRuleYaml.Tests.ps1`
   (the same suite covers hunting queries).

## Cross-references

- Schema: [`Docs/Content/Hunting-Queries.md`](../../Docs/Content/Hunting-Queries.md)
- KQL conventions: [`./kql-queries.instructions.md`](./kql-queries.instructions.md)
- Tests: [`Tests/Test-AnalyticalRuleYaml.Tests.ps1`](../../Tests/Test-AnalyticalRuleYaml.Tests.ps1)
