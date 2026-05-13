---
name: KQL queries
description: KQL conventions across every content type that embeds a query.
applyTo: "AnalyticalRules/**/*.yaml,HuntingQueries/**/*.yaml,Parsers/**/*.yaml,SummaryRules/**/*.json,DefenderCustomDetections/**/*.yaml"
---

# KQL conventions

Cross-cutting rules for any KQL embedded in repo content. Loaded
automatically alongside the type-specific instruction file when
editing analytical rules, hunting queries, parsers, summary rules, or
Defender XDR detections.

## Performance — what to avoid

1. **`search *`** — scans every table in the workspace. Almost always
   wrong. Reach for the specific table.
2. **`union *`** — same problem. Use `union TableA, TableB` with
   explicit table names.
3. **`join` without `kind=`** — defaults to `innerunique` which can
   silently drop rows. Always specify: `kind=inner`, `kind=leftouter`,
   `kind=rightouter`, `kind=fullouter`, `kind=leftsemi`, `kind=leftanti`.
4. **Wide time windows** — bound queries with
   `where TimeGenerated > ago(...)` matching `queryPeriod`. Don't
   query 30 days of data when the rule's `queryPeriod` is 1 day.
5. **High-cardinality `summarize ... by`** — grouping by a field
   like `RawEventData` or per-record GUID summarises billions of
   buckets. Group by sensible keys.
6. **Regex over large strings** — `matches regex` is expensive.
   Prefer `has`, `has_any`, `contains`, `startswith` where they fit.
7. **`bag_unpack`** — heavy for high-volume queries. Consider
   `parse_json` + explicit `extend` for the fields you need.

## Discovery-friendly patterns

The dependency-discovery extractor in `Modules/Sentinel.Common`
recognises specific KQL patterns. Stay within them and the manifest
stays correct without manual intervention:

| Pattern | What discovery captures |
| --- | --- |
| `TableName \| where ...` (start of statement) | `tables: [TableName]` |
| `let recent = SigninLogs \| ...` | `tables: [SigninLogs]` |
| `union SigninLogs, AuditLogs` | `tables: [SigninLogs, AuditLogs]` |
| `union isfuzzy=true SigninLogs, AuditLogs` | both tables captured |
| `SigninLogs \| join (AADRiskyUsers \| ...)` | both captured |
| `materialize(MicrosoftGraphActivityLogs \| ...)` | the inner table captured |
| `_GetWatchlist('alias')` | `watchlists: [alias]` |
| `externaldata(...) ["url"]` | `externalData: [url]` |
| `ASimDnsActivityLogs` (matches `^_?ASim\|_Im_\|im\w+$`) | `functions: [ASimDnsActivityLogs]` |
| `table('SigninLogs')` | `tables: [SigninLogs]` |
| `let f = (t: string) { table(t) }; f("SigninLogs")` | `tables: [SigninLogs]` |

## Discovery-unfriendly patterns

Avoid these — they confuse the extractor:

- **String concatenation to build table names**:
  `let t = strcat("Sig", "ninLogs"); table(t)` — discovery can't
  resolve the runtime string.
- **Indirection via a `dynamic([...])` list**: `let tables =
  dynamic(["A", "B"]); tables | mv-expand t | extend r = table(t)`
  — same problem.
- **Global `let` outside the rule body**: KQL has no module system,
  so don't try.

If you need indirection, extract a parser to `Parsers/` and
reference it by name.

## Watchlists vs `dynamic([...])`

For a fixed list of values used in a query, prefer either:

- **A watchlist** at `Watchlists/<alias>/data.csv`, referenced via
  `_GetWatchlist('alias')`. Right when the list might change without
  a code review (analyst-managed).
- **A `dynamic([...])`** literal in the query body. Right when the
  list is part of the detection logic and shouldn't be swapped at
  runtime (e.g. a list of suspicious LOLBins).

Don't hardcode IPs / accounts / usernames in `dynamic([...])` blocks
that should be tunable — use a watchlist.

## Style

- Two-space indent inside the query body.
- Pipe operators (`|`) at the start of a continuation line, not the
  end of the previous one.
- Comments via `//` on their own line above the operator they
  describe; avoid trailing-line comments (the discovery comment-stripper
  handles them but they're harder to read).
- Single quotes inside strings prefer `"` to escape (so the YAML
  doesn't need extra quoting).

```kusto
SecurityAlert
| where TimeGenerated > ago(1d)
| where Severity in ("High", "Medium")
// Drop duplicate alerts on the same incident
| summarize arg_max(TimeGenerated, *) by SystemAlertId
| project Timestamp = TimeGenerated, AlertName, AlertSeverity = Severity, EntityIds = Entities
```

## Validation

The `kql-validate` PR-validation job parses every embedded KQL via
`Microsoft.Azure.Kusto.Language` and fails on syntax errors. It
won't catch column-existence errors (no schema), so:

- Test queries in the Sentinel portal first.
- Use the `dependency-manifest` job to confirm tables resolve as
  expected.

## Cross-references

- Discovery model: [`Docs/Operations/Dependency-Manifest.md`](../../Docs/Operations/Dependency-Manifest.md)
- Discovery helpers: [`Modules/Sentinel.Common/Sentinel.Common.psm1`](../../Modules/Sentinel.Common/Sentinel.Common.psm1) (see `Get-KqlBareIdentifiers`)
- Discovery tests: [`Tests/Test-SentinelCommon.Tests.ps1`](../../Tests/Test-SentinelCommon.Tests.ps1)
