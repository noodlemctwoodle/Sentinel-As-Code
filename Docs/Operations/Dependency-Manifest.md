# Dependency Manifest

`dependencies.json` is the single source of truth for which Sentinel
content depends on which prerequisites — tables, watchlists, parser
functions, and external data feeds. The deploy script reads it before
every deploy run to decide whether each item can deploy enabled, must
deploy disabled, or fail outright.

The manifest is **auto-generated from content discovery**, not
hand-maintained. Three checks keep it correct:

1. The build script ([`Build-DependencyManifest.ps1`](../../Scripts/Build-DependencyManifest.ps1))
   walks `AnalyticalRules/` and `HuntingQueries/`, parses the embedded
   KQL, and emits the manifest.
2. The PR-validation gate (`dependency-manifest` job) runs the build
   script in `Verify` mode and refuses to merge if the on-disk
   manifest doesn't match what discovery produces.
3. The deploy pipeline runs the same `Verify` mode as a pre-deploy
   step and refuses to deploy with a stale manifest.

Plus a daily auto-PR workflow ([`sentinel-dependency-update.yml`](../../.github/workflows/sentinel-dependency-update.yml))
catches the long-tail edge cases where merges bypassed the gate's path
filter.

## Repo-driven classification model

The build script does **not** carry a hard-coded table catalogue. The
repo itself is the source of truth for what's deployable. Each
discovery pass builds three lookups by walking the repo:

| Lookup | Source | Purpose |
| --- | --- | --- |
| `knownFunctionsLookup` | `Parsers/**/*.yaml` `functionAlias` | In-repo parser functions; rules referencing these depend on the parser deploying first |
| `knownWatchlistsLookup` | `Watchlists/*/watchlist.json` `watchlistAlias` | Cross-validates `_GetWatchlist('alias')` references discovered in rule queries |
| `knownPlaybooksLookup` | `Playbooks/**/*.json` filename | Reserved for Wave 5+ automationRule cross-validation |

Bare identifiers in a KQL query are then classified as either:

- **Function** — matches an in-repo `Parsers/` alias OR matches the
  Microsoft ASIM regex `^(_?ASim|_Im_|im)\w+$`. These are external
  dependencies the deployer needs to know about so it can defer
  deployment of any rule that references them.
- **Table** — anything else at a data-source position. Tables are
  data-plane (external) and not deployable from the repo, so an
  enumeration is unnecessary. Custom-log tables (`_CL` suffix) fall
  here too.

There is no `unclassified` bucket. With the bare-identifier extractor
filtering let-bound names, lambda parameters, KQL keywords, and string
literals, every remaining identifier is a real data-source reference
and is correctly modelled as either a function or a table.

## Discovery patterns the extractor handles

| Pattern | Example KQL | Captured as |
| --- | --- | --- |
| Start of statement | `SecurityAlert \| where ...` | `tables: [SecurityAlert]` |
| RHS of `let X =` | `let recent = SigninLogs \| where ...` | `tables: [SigninLogs]` |
| After `union` / `union isfuzzy=true` / `union kind=outer` | `union isfuzzy=true SigninLogs, AuditLogs` | `tables: [SigninLogs, AuditLogs]` |
| Inside `join` / `lookup` subquery | `SigninLogs \| join (AADRiskyUsers \| ...)` | `tables: [SigninLogs, AADRiskyUsers]` |
| Inside `materialize()` / `view()` / `toscalar()` | `let cached = materialize(MicrosoftGraphActivityLogs \| ...)` | `tables: [MicrosoftGraphActivityLogs]` |
| KQL `table()` with literal name | `table('SigninLogs')` | `tables: [SigninLogs]` |
| Lambda-wrapper string arg | `let f = (t: string) { table(t) }; f("SigninLogs")` | `tables: [SigninLogs]` |
| `_GetWatchlist('alias')` | `let bg = _GetWatchlist('breakGlassAccounts')` | `watchlists: [breakGlassAccounts]` |
| `externaldata(...) ["url"]` | `externaldata(values: dynamic) ["https://example/feed.json"]` | `externalData: [https://example/feed.json]` |

### What the extractor filters out (no false positives)

- Let-bound variables: `let myLocal = SigninLogs ...` → `myLocal` is
  not captured as a table.
- Lambda parameters: `let f = (tableName: string) ...` → `tableName`
  is not captured.
- Column names in continuation lines: `| project AlertName, Severity`
  → neither is captured (statement-based extraction).
- Identifiers inside string literals: `"Other clients; POP"` → `POP`
  is not captured (strings stripped before parsing).
- KQL keywords / function-call sites: `toscalar`, `materialize`,
  `iif`, etc. — never captured (kept in a keyword list and a
  function-called set).

## Operating modes

`Build-DependencyManifest.ps1 -Mode <Mode>`:

- **Generate** — Walk content, build the manifest, write
  `dependencies.json`. Authors run this locally after editing rules
  and commit the regenerated file alongside the rule changes.
- **Verify** — Walk content, build the manifest in-memory, compare
  against the on-disk file. Exits 0 on match, 1 on drift. Used by the
  PR-validation gate and the pre-deploy step.
- **Update** — Like Verify, but on detected drift writes the
  regenerated manifest to disk and exits 0. The calling pipeline owns
  the commit + branch + PR step. Used by the daily auto-PR workflow.

## Author workflow

```
# After editing or adding a rule that references new tables, watchlists,
# or functions:
./Scripts/Build-DependencyManifest.ps1 -Mode Generate

git add dependencies.json
git commit
```

If you forget, the PR-validation `dependency-manifest` job will fail
and tell you exactly what to do. If you forget AND the gate's path
filter misses the change (rare — happens for doc-only commits that
adjust an inline query body), the daily auto-PR workflow will open a
chore PR titled `chore(deps): refresh dependency manifest <date>`
within 24 hours; review and squash-merge.

## Watchlist cross-validation

When discovery finds a `_GetWatchlist('alias')` reference whose alias
does not resolve to an in-repo `Watchlists/<alias>/watchlist.json`,
the build script logs a warning. The PR / scheduled run does not
fail (the watchlist might be provisioned out-of-band), but the
warning is visible in the run log so you can investigate.

To resolve a missing-watchlist warning, either:

- Add the watchlist under `Watchlists/<alias>/watchlist.json` +
  `Watchlists/<alias>/data.csv`, then re-run `-Mode Generate`; or
- Provision the watchlist out-of-band (one-time bootstrap that the
  deploy pipeline doesn't manage), and accept the warning as expected.

## File schema

```jsonc
{
  "version":     "1.0",
  "description": "Auto-generated by Scripts/Build-DependencyManifest.ps1...",
  "dependencies": {
    "<repoRelativePath>": {
      "tables":       ["<tableName>", ...],          // optional
      "watchlists":   ["<watchlistAlias>", ...],     // optional
      "functions":    ["<functionAlias>", ...],      // optional
      "externalData": ["<url>", ...]                 // optional
    },
    ...
  }
}
```

Each entry's buckets are alphabetically ordered. Empty buckets are
not emitted (so a rule with no watchlist references will not have a
`watchlists` field). Top-level keys are insertion-ordered (sorted by
file walk order, which is deterministic across runs).

## Test coverage

`Tests/Test-DependencyManifest.Tests.ps1` runs ~1000 per-entry
assertions, one for every `dependencies` entry, validating:

- Top-level shape (`version`, `description`, `dependencies` keys)
- Path resolution: every key resolves to a real file on disk
- Watchlist resolution: every `watchlists[]` alias maps to a real
  `Watchlists/<alias>/watchlist.json`
- Function resolution: every `functions[]` alias maps to a real
  `Parsers/*.yaml` `functionAlias`, OR matches the ASIM external
  pattern

Plus `Tests/Test-SentinelCommon.Tests.ps1` exercises the discovery
helpers directly (57 assertions) — extractor unit tests for each
pattern shown in the table above.

## Why auto-derived, not hand-maintained

When the manifest was hand-maintained, comparison against discovery
output found:

- 90 rules with no manifest entry at all (mostly community content
  added without backfilling the manifest)
- 14 rules misclassifying ASim functions as tables (the deployer
  needs them in `functions` so it can defer them when the parser
  hasn't deployed yet)
- 22 rules with incomplete table lists (queries referenced tables
  the entry forgot)
- 4 rules where the entry named tables the query never references
  (best-effort guesswork that got it wrong)

Auto-derivation fixes all four classes of problem and keeps them
fixed.

## Authoring with GitHub Copilot

Cross-cutting [`.github/instructions/kql-queries.instructions.md`](../../.github/instructions/kql-queries.instructions.md)
loads automatically when editing any KQL-bearing content; it
includes the discovery-friendly patterns table that maps directly
to what `Get-KqlBareIdentifiers` recognises.

Copilot tooling for the dependency-manifest sub-system:

- Slash command `/regenerate-deps` (VS Code) — runs
  `Build-DependencyManifest -Mode Generate` and explains the diff
- Agent `Sentinel-As-Code: Dependencies Engineer` — owns the whole
  sub-system: extending the discovery extractor, debugging wrong
  manifest output, triaging the daily auto-PR refresh

See [GitHub Copilot setup](../Development/GitHub-Copilot.md) for the full layout.

## Related

- [`Scripts/Build-DependencyManifest.ps1`](../../Scripts/Build-DependencyManifest.ps1) — the build script
- [`Modules/Sentinel.Common/Sentinel.Common.psm1`](../../Modules/Sentinel.Common/Sentinel.Common.psm1) — discovery helpers (`Get-ContentDependencies`, `Get-KqlBareIdentifiers`, etc.)
- [`Tests/Test-DependencyManifest.Tests.ps1`](../../Tests/Test-DependencyManifest.Tests.ps1) — manifest cross-reference tests
- [`Tests/Test-SentinelCommon.Tests.ps1`](../../Tests/Test-SentinelCommon.Tests.ps1) — discovery helper unit tests
- [`.github/workflows/sentinel-dependency-update.yml`](../../.github/workflows/sentinel-dependency-update.yml) — daily auto-PR workflow (GitHub)
- [`Pipelines/Sentinel-Dependency-Update.yml`](../../Pipelines/Sentinel-Dependency-Update.yml) — daily auto-PR pipeline (Azure DevOps)
- [Pester Tests](../Development/Pester-Tests.md) — full test inventory and the gate model
