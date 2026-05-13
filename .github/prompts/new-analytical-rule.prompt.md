---
description: Bootstraps a new Sentinel analytical rule YAML from a threat scenario.
argument-hint: <one-line threat description>
agent: agent
tools: ['search/codebase', 'edit/applyPatch', 'terminal/run']
---

# New analytical rule

Bootstrap a fresh Sentinel analytical rule under
`AnalyticalRules/<SourceFolder>/<RuleName>.yaml`.

## Inputs to gather (ask if not provided)

- **Threat scenario** — one-line summary of what should be detected.
  Example: "Detect successful sign-in from a Tor exit node within
  10 minutes of a failed sign-in from the same account."
- **Source data table** — which Sentinel table surfaces the activity?
  Example: `SigninLogs`, `AzureActivity`, `AADRiskyUsers`, etc. If
  unsure, ask which Microsoft solution / data connector covers the
  activity.
- **Severity** — `High`, `Medium`, `Low`, `Informational`. Default
  to `Medium` and let the user override.
- **Tactic + technique** — MITRE tactic (PascalCase, e.g.
  `CredentialAccess`) and technique ID (`T1078`, `T1078.004`).

## Steps

1. **Confirm the source folder.** Existing analytical rules group
   by data source under `AnalyticalRules/`:
   - `AnalyticalRules/AzureActivity/` for AzureActivity rules
   - `AnalyticalRules/MicrosoftEntraID/` for SigninLogs / AuditLogs
   - `AnalyticalRules/AWS/` for AWS connector tables
   - etc.
   Pick the folder that matches the source data table. If you're
   unsure, run `ls AnalyticalRules/` to see what exists.

2. **Pick a file name.** PascalCase, hyphen-free, descriptive of
   the *detection*, not the technique. Example:
   `SuccessfulSigninFromTorExitNode.yaml`.

3. **Generate a fresh GUID** for the `id` field:
   ```powershell
   [guid]::NewGuid().Guid
   ```

4. **Write the YAML** following the schema in
   [`.github/instructions/analytical-rules.instructions.md`](../instructions/analytical-rules.instructions.md).
   Required fields: `id`, `name`, `description`,
   `requiredDataConnectors`, `queryFrequency`, `queryPeriod`,
   `triggerOperator`, `triggerThreshold`, `enabled`, `tactics`,
   `relevantTechniques`, `query`, `entityMappings`.

   Notable conventions:
   - Field is `enabled: true|false` — **not** `status: ...`
   - `severity` is PascalCase: `High`, `Medium`, `Low`, `Informational`
   - `tactics` are PascalCase MITRE names
   - `relevantTechniques` are technique IDs only

5. **Write the KQL query body** following the conventions in
   [`.github/instructions/kql-queries.instructions.md`](../instructions/kql-queries.instructions.md).
   Don't `search *` or `union *`. Use specific tables. Bound the
   time window with `where TimeGenerated > ago(...)`. Project a
   stable column set before the final pipe. Reference watchlists
   via `_GetWatchlist('alias')`.

6. **Add `entityMappings`** for any column that should be promoted
   to a Sentinel entity (Account, IP, Host, FileHash, URL).
   Without these, alerts don't correlate into incidents properly.

7. **Regenerate the dependency manifest:**
   ```powershell
   ./Scripts/Build-DependencyManifest.ps1 -Mode Generate
   ```

8. **Run the schema tests:**
   ```powershell
   Invoke-Pester -Path Tests/Test-AnalyticalRuleYaml.Tests.ps1
   Invoke-Pester -Path Tests/Test-DependencyManifest.Tests.ps1
   ```

9. **Stage** the rule + the regenerated `dependencies.json` together.

10. **Propose a commit message** in conventional-commit format:

    ```
    feat(rules): add <RuleName> for <ThreatScenario>

    Detects <one-line summary>. Severity <severity>. Tactic:
    <Tactic>. Technique: <T#### + name>.

    Files:
    - AnalyticalRules/<Source>/<RuleName>.yaml (new)
    - dependencies.json (regenerated)

    Testing:
    - Test-AnalyticalRuleYaml.Tests.ps1: pass
    - Test-DependencyManifest.Tests.ps1: pass
    ```

## Reference template

```yaml
id: <fresh GUID>
name: <Detection title>
description: |
  <Multi-paragraph plain-prose description. What does it detect?
  What should an analyst do with the alert?>
severity: Medium
requiredDataConnectors:
- connectorId: <ConnectorId>
  dataTypes:
  - <TableName>
queryFrequency: PT1H
queryPeriod:    PT1H
triggerOperator: gt
triggerThreshold: 0
enabled: true
tactics:
- <Tactic>
relevantTechniques:
- <Txxxx>
query: |
  <TableName>
  | where TimeGenerated > ago(1h)
  | where <condition>
  | project Timestamp = TimeGenerated, <columns>
entityMappings:
- entityType: <Account|IP|Host|FileHash|URL>
  fieldMappings:
  - identifier: <FieldId>
    columnName: <ColumnName>
```
