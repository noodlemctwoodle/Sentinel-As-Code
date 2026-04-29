---
description: Reviews an analytical rule, hunting query, or Defender detection for schema correctness, KQL quality, and convention compliance.
argument-hint: <path to rule YAML or open the file in the editor>
agent: ask
tools: ['search/codebase', 'search/usages']
---

# Review rule

Review the supplied rule (analytical / hunting / Defender) against:

1. **Schema correctness** — required fields, field types, cross-file
   uniqueness (the `id` GUID).
2. **KQL quality** — performance footguns, discovery-friendliness,
   filter precision.
3. **Convention compliance** — repo style, MITRE conventions,
   commit-ready state.

You do not modify the file. You produce a structured review the
user can act on.

## Review checklist

### Schema (analytical rules)

- [ ] `id` is a fresh GUID, no copy-paste from another rule
- [ ] `name` is human-readable and matches the file name's intent
- [ ] `description` is multi-line plain prose, explains what
      triggers the alert and what an analyst should do
- [ ] `severity` is `High` / `Medium` / `Low` / `Informational`
      (PascalCase, exact match)
- [ ] `enabled: true|false` (the field is `enabled`, **not**
      `status`)
- [ ] `requiredDataConnectors` lists every connector the query
      uses
- [ ] `queryFrequency` ≤ `queryPeriod`
- [ ] `triggerOperator` and `triggerThreshold` agree with the query
      (if the query already filters, threshold should be `0`)
- [ ] `tactics` are PascalCase MITRE tactics
- [ ] `relevantTechniques` are technique IDs only (`T1078`,
      `T1078.004` — no names)
- [ ] `entityMappings` cover every column an analyst would pivot on

### Schema (hunting queries)

- [ ] No `severity`, `triggerThreshold`, `triggerOperator`,
      `enabled`, or `entityMappings` (those are analytical-rule
      fields)
- [ ] Has `tactics` and `relevantTechniques` only

### Schema (Defender XDR detections)

- [ ] `isEnabled: true|false` (Defender uses `isEnabled`)
- [ ] `severity` is **lowercase** (`high`, `medium`, `low`,
      `informational`)
- [ ] `schedule.period` is `"0"` (NRT) or ISO 8601 duration
- [ ] Tables come from the Defender XDR Advanced Hunting schema —
      not Sentinel tables
- [ ] `impactedAssets[].identifier` matches a column the query
      `project`s

### KQL

- [ ] No `search *` or `union *`
- [ ] `join` calls specify `kind=`
- [ ] Time window bound with `where TimeGenerated > ago(...)`
      matching `queryPeriod`
- [ ] Final `project` produces a stable, narrow column set
- [ ] Watchlist references via `_GetWatchlist('alias')`, not
      hardcoded `dynamic([...])` (when the list should be
      analyst-tunable)
- [ ] Discovery-friendly: bare table identifier at start of
      statement / after `let X =` / inside `materialize` etc.
      (see KQL conventions doc)

### Repo conventions

- [ ] File path matches `<ContentDir>/<Source>/<RuleName>.yaml`
      pattern
- [ ] File name is PascalCase, no spaces, no hyphens (Wave 4
      convention)
- [ ] If the rule references a watchlist, the watchlist exists
      under `Watchlists/<alias>/watchlist.json` with matching
      `watchlistAlias`
- [ ] If the rule was edited, `dependencies.json` was regenerated
      in the same change

## Output format

Produce a structured review in this shape:

```
## <FilePath>

### Schema
- ✅ <pass>
- ⚠️ <warning with line ref>
- ❌ <fail with line ref + fix>

### KQL
- (same shape)

### Conventions
- (same shape)

### Suggested fixes
1. <ordered list, copy-pasteable>
```

Use plain text bullets if your tool doesn't render the icons.
Always quote the relevant line / field, never gesture vaguely.

## Cross-references

- Schema docs:
  [`Docs/Content/Analytical-Rules.md`](../../Docs/Content/Analytical-Rules.md),
  [`Docs/Content/Hunting-Queries.md`](../../Docs/Content/Hunting-Queries.md),
  [`Docs/Content/Defender-Custom-Detections.md`](../../Docs/Content/Defender-Custom-Detections.md)
- KQL conventions:
  [`.github/instructions/kql-queries.instructions.md`](../instructions/kql-queries.instructions.md)
- Discovery model:
  [`Docs/Operations/Dependency-Manifest.md`](../../Docs/Operations/Dependency-Manifest.md)
