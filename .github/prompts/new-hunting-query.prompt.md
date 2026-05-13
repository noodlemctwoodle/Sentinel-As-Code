---
description: Bootstraps a new Sentinel hunting query YAML.
argument-hint: <one-line threat-hunt scenario>
agent: agent
tools: ['search/codebase', 'edit/applyPatch', 'terminal/run']
---

# New hunting query

Bootstrap a fresh Sentinel hunting query under
`HuntingQueries/<SourceFolder>/<QueryName>.yaml`.

## Hunting vs analytical rule

If the user describes a high-confidence detection that warrants an
incident, it should be an analytical rule (`/new-analytical-rule`),
not a hunting query.

Hunting queries are for **exploratory** patterns: too noisy to alert
on, but valuable for analyst-driven investigation. If you're
uncertain, ask: "Should this fire as an alert, or does an analyst
need to interpret the results?"

## Inputs to gather (ask if not provided)

- **Hunt scenario** — one-line summary. Example: "Find Azure resource
  modifications by service principals that haven't authenticated
  from an interactive context in 30 days."
- **Source data table(s)** — Sentinel tables the hunt queries.
- **MITRE tactic + technique** — same conventions as analytical
  rules. PascalCase tactic, technique IDs only.

## Steps

1. **Confirm the source folder** under `HuntingQueries/`. Pick by
   data source (`HuntingQueries/SigninLogs/`,
   `HuntingQueries/AzureActivity/`, etc.).

2. **Pick a file name** that describes the *hunt question*, not
   the technique. Example: `OrphanedServicePrincipalActivity.yaml`.

3. **Generate a fresh GUID** for `id`.

4. **Write the YAML** following the schema in
   [`.github/instructions/hunting-queries.instructions.md`](../instructions/hunting-queries.instructions.md).

5. **Write the KQL** following
   [`.github/instructions/kql-queries.instructions.md`](../instructions/kql-queries.instructions.md).
   Hunting queries can be more permissive than alert rules
   (returning more rows is OK; an analyst will sift), but still
   avoid `search *` and `union *`.

6. **Regenerate dependencies + run tests:**
   ```powershell
   ./Scripts/Build-DependencyManifest.ps1 -Mode Generate
   Invoke-Pester -Path Tests/Test-AnalyticalRuleYaml.Tests.ps1
   Invoke-Pester -Path Tests/Test-DependencyManifest.Tests.ps1
   ```

7. **Stage** the query + regenerated `dependencies.json`.

## Reference template

```yaml
id: <fresh GUID>
name: <Hunt question phrased as a statement>
description: |
  <What does this hunt look for? What should an analyst look for
  in the results?>
requiredDataConnectors:
- connectorId: <ConnectorId>
  dataTypes:
  - <TableName>
tactics:
- <Tactic>
relevantTechniques:
- <Txxxx>
query: |
  <TableName>
  | where TimeGenerated > ago(7d)
  | where <condition>
  | project Timestamp = TimeGenerated, <columns>
tags:
- Description: <short summary>
- Tactics: <Tactic>
- Techniques: <Txxxx>
```

Hunting queries don't have `severity`, `triggerThreshold`,
`triggerOperator`, `enabled`, or `entityMappings`. Don't add them
even if you copy from an analytical rule template.
