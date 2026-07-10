---
name: Watchlists
description: Schema for Content/Watchlists/<alias>/watchlist.json + data.csv pairs.
applyTo: "Content/Watchlists/**"
---

# Watchlist authoring

Reusable data lists (IP ranges, account lists, allowlists) that
analytical rules and hunting queries reference via
`_GetWatchlist('alias')`. Each watchlist lives in its own subfolder
with two files. Full schema in
[`Docs/Content/Watchlists.md`](../../Docs/Content/Watchlists.md).

## Folder layout

```
Content/Watchlists/
└── <alias>/
    ├── watchlist.json   # metadata
    └── data.csv         # the actual data
```

By convention the folder name matches the `watchlistAlias` inside
`watchlist.json`. Deployment and `_GetWatchlist()` resolution both key off
the `watchlistAlias` value in the JSON (not the folder name), so keep the
two identical to avoid confusion. Note: no test compares the folder name to
the alias. What IS enforced is that a `_GetWatchlist('alias')` reference
resolves to a `watchlist.json` whose `watchlistAlias` matches (see
Cross-validation below).

## watchlist.json

```jsonc
{
  "watchlistAlias":  "<alias, matches folder name>",
  "displayName":     "<human-readable name>",
  "description":     "<one-line description, plain prose>",
  "provider":        "Custom",
  "itemsSearchKey":  "<column from data.csv used for lookup>"
}
```

### Hard rules

1. **Keep `watchlistAlias` equal to the folder name (convention).** Not
   enforced by a test, but every `_GetWatchlist()` call and the dependency
   manifest key off the `watchlistAlias` value, so a divergent folder name
   is confusing. See Cross-validation below for what IS enforced.
2. **`watchlistAlias` is also the value used in
   `_GetWatchlist('alias')` calls.** Renaming the alias breaks every rule that references it; renaming the folder alone does not, because resolution keys off the `watchlistAlias` value in `watchlist.json`, not the folder name (though divergent names are confusing).
3. **`itemsSearchKey` must be a column in `data.csv`.** Otherwise
   the watchlist deploys but `_GetWatchlist()` lookups don't resolve.
4. **`provider`** is almost always `"Custom"`. Use `"Microsoft"` only
   when re-publishing a Microsoft-provided watchlist.

## data.csv

- First row is the header. Column names become Sentinel KQL field
  names — pick names you'd write in a query (`UserPrincipalName`,
  `IPAddress`, `Hostname`).
- One value per cell. CSV quoting is mandatory if a value contains a
  comma, quote, or newline.
- No trailing whitespace, no BOM.

## Cross-validation by the dependency manifest

When a rule's KQL contains `_GetWatchlist('Foo')`,
`Build-DependencyManifest.ps1` checks that
`Content/Watchlists/Foo/watchlist.json` exists with `watchlistAlias: Foo`.
If not, the build script logs a warning. The Pester test
([`Tests/Test-DependencyManifest.Tests.ps1`](../../Tests/Test-DependencyManifest.Tests.ps1))
turns that warning into a hard fail.

To add a new watchlist that's referenced by a rule:

1. Create the `Content/Watchlists/<alias>/` folder with both files.
2. Re-run the dep manifest:
   ```powershell
   ./Tools/Build-DependencyManifest.ps1 -Mode Generate
   ```
3. Run schema tests:
   ```powershell
   Invoke-Pester -Path Tests/Test-WatchlistJson.Tests.ps1
   Invoke-Pester -Path Tests/Test-DependencyManifest.Tests.ps1
   ```

## Cross-references

- Schema: [`Docs/Content/Watchlists.md`](../../Docs/Content/Watchlists.md)
- Tests: [`Tests/Test-WatchlistJson.Tests.ps1`](../../Tests/Test-WatchlistJson.Tests.ps1)
- Discovery / cross-validation: [`Docs/Tools/Dependency-Manifest.md`](../../Docs/Tools/Dependency-Manifest.md)
