---
name: Watchlists
description: Schema for Watchlists/<alias>/watchlist.json + data.csv pairs.
applyTo: "Watchlists/**"
---

# Watchlist authoring

Reusable data lists (IP ranges, account lists, allowlists) that
analytical rules and hunting queries reference via
`_GetWatchlist('alias')`. Each watchlist lives in its own subfolder
with two files. Full schema in
[`Docs/Content/Watchlists.md`](../../Docs/Content/Watchlists.md).

## Folder layout

```
Watchlists/
└── <alias>/
    ├── watchlist.json   # metadata
    └── data.csv         # the actual data
```

The folder name `<alias>` must match `watchlistAlias` inside
`watchlist.json` exactly. The Pester test enforces this and aborts
the deploy on mismatch.

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

1. **`watchlistAlias` must equal the folder name.** Cross-validation
   test enforces this.
2. **`watchlistAlias` is also the value used in
   `_GetWatchlist('alias')` calls.** Renaming the folder breaks every
   rule that references it.
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
`Watchlists/Foo/watchlist.json` exists with `watchlistAlias: Foo`.
If not, the build script logs a warning. The Pester test
([`Tests/Test-DependencyManifest.Tests.ps1`](../../Tests/Test-DependencyManifest.Tests.ps1))
turns that warning into a hard fail.

To add a new watchlist that's referenced by a rule:

1. Create the `Watchlists/<alias>/` folder with both files.
2. Re-run the dep manifest:
   ```powershell
   ./Scripts/Build-DependencyManifest.ps1 -Mode Generate
   ```
3. Run schema tests:
   ```powershell
   Invoke-Pester -Path Tests/Test-WatchlistJson.Tests.ps1
   Invoke-Pester -Path Tests/Test-DependencyManifest.Tests.ps1
   ```

## Cross-references

- Schema: [`Docs/Content/Watchlists.md`](../../Docs/Content/Watchlists.md)
- Tests: [`Tests/Test-WatchlistJson.Tests.ps1`](../../Tests/Test-WatchlistJson.Tests.ps1)
- Discovery / cross-validation: [`Docs/Operations/Dependency-Manifest.md`](../../Docs/Operations/Dependency-Manifest.md)
