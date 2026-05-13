---
description: Regenerates dependencies.json from current content via Build-DependencyManifest, runs the cross-validation tests, and explains the diff.
agent: agent
tools: ['terminal/run', 'search/codebase']
---

# Regenerate the dependency manifest

Run the dependency-discovery script to refresh `dependencies.json`
from current content, then validate and explain the result.

## Steps

1. **Generate the manifest:**

   ```powershell
   ./Scripts/Build-DependencyManifest.ps1 -Mode Generate
   ```

   This walks `AnalyticalRules/**/*.yaml` and `HuntingQueries/**/*.yaml`,
   parses every embedded KQL via `Modules/Sentinel.Common`, and
   writes `dependencies.json`. Output includes:

   - In-repo function inventory (from `Parsers/`)
   - Watchlist inventory (from `Watchlists/`)
   - Playbook inventory (from `Playbooks/`)
   - Discovered entry count
   - Any unresolved watchlist references (warnings)

2. **Verify against the now-on-disk file:**

   ```powershell
   ./Scripts/Build-DependencyManifest.ps1 -Mode Verify
   ```

   Should exit 0. If it exits 1, that's a script bug — report
   diff lines and stop.

3. **Run the cross-reference tests:**

   ```powershell
   Invoke-Pester -Path Tests/Test-DependencyManifest.Tests.ps1
   ```

   This runs ~1,000 per-entry assertions: every key resolves to
   a real file, every watchlist alias maps to a real
   `Watchlists/<alias>/watchlist.json`, every function alias maps
   to a `Parsers/*.yaml` `functionAlias` or matches the ASIM
   external pattern.

4. **Explain the diff** if anything changed:

   ```bash
   git diff dependencies.json
   ```

   Categorise the changes as:

   - **Added entries** — rules / hunting queries that previously
     had no manifest entry, now do. Most common cause: a new
     rule was added without running `-Mode Generate`.
   - **Removed entries** — rules / hunting queries that
     previously had a manifest entry, now don't. Most common
     cause: the file was deleted, or its query no longer
     references any tables / watchlists / functions /
     externalData.
   - **Changed entries** — buckets shifted. Most common cause:
     a query was edited.

   For each non-trivial change, state which content file caused
   it and why.

5. **Stage `dependencies.json` together with whatever content
   change drove the regeneration.** Commit the two together —
   the dep manifest must travel with the rule edit.

## When NOT to run this

- If you're not changing rule / hunting-query content. The manifest
  doesn't change for edits to playbooks, watchlists, scripts,
  workflows, or docs. Running it then is harmless but a no-op.

## Convention reminder

`dependencies.json` is **auto-derived**. Never hand-edit it. The
PR-validation `dependency-manifest` job will fail any hand-edit
because discovery output won't match the file on disk.

If discovery is producing the wrong output (e.g. classifying a
real table as unclassified, or missing a watchlist reference your
rule does use), the bug is in the discovery extractors, not the
manifest. Read
[`Docs/Operations/Dependency-Manifest.md`](../../Docs/Operations/Dependency-Manifest.md)
for the discovery model and patterns the extractor handles.
