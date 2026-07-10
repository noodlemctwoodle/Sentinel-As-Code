# Watchlists

Custom watchlists for enriching analytics rules and hunting queries. Each watchlist is a subfolder under [`Content/Watchlists/`](../../Content/Watchlists) containing a JSON metadata file and a CSV data file.

## Folder Structure

```
Content/Watchlists/
  HighValueAssets/
    watchlist.json          # Metadata definition
    data.csv                # Watchlist data
  TorExitNodes/
    watchlist.json
    data.csv
```

Each subfolder holds exactly two files with fixed names: `watchlist.json` and `data.csv`. The deployer looks for both by name (`Join-Path <dir> "watchlist.json"` / `"data.csv"`), so a folder missing either file is skipped with a warning. The folder name is a human-facing label only; the value that identifies the watchlist in Sentinel is `watchlistAlias` inside `watchlist.json`, not the folder name (see [Alias, folder name and cross-validation](#alias-folder-name-and-cross-validation)).

## Metadata Schema (watchlist.json)

The authoring contract is defined by the Toolkit's `sentinel-watchlist-schema.json`, which the Sentinel as Code Toolkit uses to scaffold and validate this file (see [Templates](../Toolkit/Templates.md) and [Schemas and Validation](../Toolkit/Schemas-and-Validation.md)). All five fields are required, and no additional properties are allowed. Fields appear below in the canonical order the template writes them:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `watchlistAlias` | string | Yes | Non-empty. Unique alias used in KQL queries (e.g. `_GetWatchlist('HighValueAssets')`). The Toolkit convention (and its schema description) is that the alias matches the containing folder name; it must also be unique across the whole `Content/Watchlists/` tree |
| `displayName` | string | Yes | Non-empty. Human-readable name shown in the Sentinel UI |
| `description` | string | Yes | Description of the watchlist's purpose |
| `provider` | string | Yes | Set to `Custom` for customer-authored watchlists (Microsoft-provided watchlists ship via Content Hub solutions) |
| `itemsSearchKey` | string | Yes | Non-empty. Column name used as the primary key. Must match a CSV header exactly (case-sensitive) |

**Deploy-time note:** the deploy script is more lenient than the schema. `Deploy-CustomWatchlists` (in `Deploy-CustomContent.ps1`) only hard-requires `watchlistAlias`, `displayName` and `itemsSearchKey`; it fills in defaults for `description` (`""`) and `provider` (`Custom`) when they are absent, and it does not reject a non-`Custom` provider. Author to the schema (all five fields, `provider: Custom`) rather than relying on these defaults.

The PR-validation gate is stricter still. `Test-WatchlistJson.Tests.ps1` requires all five fields to be non-empty and additionally enforces the alias pattern `^[A-Za-z][A-Za-z0-9]*$` (start with a letter, letters and digits only, no hyphens, underscores or spaces), `provider == "Custom"`, and alias uniqueness across the tree. These are repo-specific CI constraints layered on top of the Toolkit schema, so keep aliases to that pattern and `provider` to `Custom`.

### Example

```json
{
  "watchlistAlias": "HighValueAssets",
  "displayName": "High Value Assets",
  "description": "Critical servers requiring elevated monitoring.",
  "provider": "Custom",
  "itemsSearchKey": "Hostname"
}
```

## Data File (data.csv)

Standard CSV format. The first row must be the header row, and one column must match `itemsSearchKey` from the metadata.

```csv
Hostname,IPAddress,Owner,Criticality
DC01,10.0.0.10,Platform Team,Critical
SQL-PROD-01,10.0.1.50,DBA Team,High
```

Notes on the header row:

- Column names become the Sentinel/KQL field names directly, so pick names you would write in a query (`UserPrincipalName`, `IPAddress`, `Hostname`).
- Header names must be unique. Duplicate column names cause KQL ambiguity errors at query time, and `Test-WatchlistJson.Tests.ps1` fails the build if it finds any.
- The suite also fails if the `itemsSearchKey` value is not present as a header column, because a rule that joins on a non-existent key returns empty silently at query time rather than erroring.

The deployer always uploads the file with `contentType = "Text/Csv"`; only a file literally named `data.csv` is read.

## Using Watchlists in KQL

```kql
let HVA = _GetWatchlist('HighValueAssets');
SigninLogs
| join kind=inner HVA on $left.Computer == $right.Hostname
| where Criticality == "Critical"
```

## Notes

- Redeploying a watchlist with the same alias replaces all existing items (idempotent). The deployer PUTs to the Sentinel API keyed by `watchlistAlias`, so a redeploy replaces in place.
- The data file the pipeline deploys must be a CSV named `data.csv`. Although the Toolkit accepts CSV or TSV input and its schema/template mention `data.csv`/`data.tsv`, the deployer hard-codes the filename `data.csv` and always sends `contentType = "Text/Csv"`, so a file named `data.tsv` (or anything else) is ignored and the watchlist is skipped with a "data.csv not found" warning. Ensure a `data.csv` is present for deployment.
- Maximum CSV size for inline upload is approximately 3.5 MB. A file over that limit is skipped with a warning ("exceeds 3.5 MB inline upload limit ... Upload manually via portal"); the deployer then marks the item's state as `success` so it is not retried on the next run. Upload an oversized watchlist manually via the portal.
- The `itemsSearchKey` value is case-sensitive and must exactly match a CSV column header
- Deployment is handled by [`Deploy/content/Deploy-CustomContent.ps1`](../../Deploy/content/Deploy-CustomContent.ps1) — see [Scripts.md](../Deploy/Scripts.md#deploy-customcontentps1)
- For a watchlist that's auto-populated by an Azure Automation runbook (DCR inventory), see [DCR Watchlist](../Tools/DCR-Watchlist.md)

## Deployment behaviour

Watchlists deploy at stage 2 of `Deploy-CustomContent.ps1`'s eight content stages (Parsers, then Watchlists, then Detections, Hunting Queries, Playbooks, Workbooks, Automation Rules, Summary Rules), so they exist before any analytics rule that references them is created. A few behaviours are worth knowing when debugging a deploy:

- **Schema-propagation wait.** After deploying one or more watchlists (and only when at least one was actually deployed and not in `-WhatIf` mode), the script logs "Waiting 30s for watchlist schema propagation..." and sleeps 30 seconds before moving on to rules. This gives Sentinel time to index the new watchlist schema so that rules referencing `_GetWatchlist('...')` resolve on first deploy.
- **Smart-deployment / change detection.** With `-SmartDeployment` enabled (opt-in; it defaults to OFF, in which case everything is deployed), a watchlist folder is skipped entirely if neither `watchlist.json` nor `data.csv` has changed since the last recorded deployment state. When the switch is off the log reads "Smart deployment disabled — all content will be deployed."
- **Dependency gate.** Each watchlist is passed through `Test-ContentDependencies` before deployment. If its declared dependencies are not satisfied, the watchlist is skipped with a "missing dependencies" warning rather than deployed.

## Alias, folder name and cross-validation

The value that binds a watchlist together is `watchlistAlias`, not the
folder name. Nothing in the repo compares the folder name to the alias:
`Deploy-CustomWatchlists` builds its internal watchlist list from the
`watchlistAlias` value read out of each `watchlist.json`, and
`Build-DependencyManifest.ps1` populates its `knownWatchlistsLookup`
keyed off the same JSON alias value (`knownWatchlistsLookup[$w.watchlistAlias] = <path>`).
A folder named `Foo` whose JSON declares `watchlistAlias: Bar` would
deploy and cross-validate as `Bar`.

Keeping the folder name equal to the alias is a useful convention (every
folder under `Content/Watchlists/` follows it today, and the Toolkit's
"Create Watchlist from CSV" command scaffolds a `watchlist.yaml` alongside
its data file for you to set the alias in before converting to
`watchlist.json`) but the deploy pipeline does not enforce it. What is
enforced, by `Test-WatchlistJson.Tests.ps1` in the
PR-validation gate, is:

- the alias matches `^[A-Za-z][A-Za-z0-9]*$`;
- the alias is unique across the whole `Content/Watchlists/` tree (two
  folders declaring the same alias pass their per-directory tests but
  fail the cross-directory invariant);
- `provider` is exactly `Custom`;
- the `itemsSearchKey` column exists in the CSV header and headers are
  unique.

Cross-validation of `_GetWatchlist('alias')` references from rules is a
separate gate: `Build-DependencyManifest.ps1` warns when a referenced
alias does not resolve to any in-repo watchlist, and
[`Tests/Test-DependencyManifest.Tests.ps1`](../../Tests/Test-DependencyManifest.Tests.ps1)
turns that warning into a hard failure. See
[Dependency Manifest](../Tools/Dependency-Manifest.md) for detail.

## Authoring with GitHub Copilot

When editing files under `Content/Watchlists/**`, Copilot automatically
loads [`.github/instructions/watchlists.instructions.md`](../../.github/instructions/watchlists.instructions.md),
the path-scoped instructions covering the watchlist schema and the CSV
rules the deploy logic relies on.

Copilot tooling for watchlists:

- Agent `Sentinel-As-Code: Content Editor` — general edits with
  the right post-edit Pester suite
- Agent `Sentinel-As-Code: Dependencies Engineer` — when an alias
  rename or new alias affects rules that reference it via
  `_GetWatchlist('...')`

See [GitHub Copilot setup](../GitHub/GitHub-Copilot.md) for the full layout.
