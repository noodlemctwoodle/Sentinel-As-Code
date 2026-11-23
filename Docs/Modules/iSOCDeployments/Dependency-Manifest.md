# Dependency manifest commands

`dependencies.json` at the repository root records what each analytics
rule and hunting query depends on: tables, watchlists, parser functions and
external data, all discovered from the KQL. Deploy uses it to order content
and to deploy a rule disabled, or skip a hunting query, when something it
needs is missing. [Dependency Manifest](../../Tools/Dependency-Manifest.md)
explains the manifest itself and the gate that keeps it current.

iSOCDeployments has the commands that replaced
`Tools/Build-DependencyManifest.ps1`, which was removed at the 26.11.0
cut-over; the module writes the same file the script wrote, and the Azure
DevOps daily update and PR gate run it
([The pipeline switch](Pipeline-Switch.md)).

| Script | Command | What changes |
| --- | --- | --- |
| `Build-DependencyManifest.ps1 -Mode Verify` | `Test-iSOCDependencyManifest` | Returns a result with `HasDrift` instead of exiting 1 |
| `Build-DependencyManifest.ps1 -Mode Generate` | `Update-iSOCDependencyManifest` | Writes only when an entry differs or the file is missing |
| `Build-DependencyManifest.ps1 -Mode Update` | `Update-iSOCDependencyManifest` | The same command; the pipeline still owns the commit and the PR |
| `Get-ContentDependencies` (Sentinel.Common) | `Get-iSOCContentDependency` | Takes files, from the pipeline too, and reads the parser functions from the repository itself |

## Commands

```powershell
Import-Module ./Modules/iSOCDeployments

# After editing content: rewrite the manifest when it is out of date.
Update-iSOCDependencyManifest

# In a gate: fail the step when the manifest is out of date.
if ((Test-iSOCDependencyManifest).HasDrift) { exit 1 }

# What one file, or a set of files, reads.
Get-ChildItem Content/HuntingQueries -Recurse -Filter *.yaml |
    Get-iSOCContentDependency | Where-Object Watchlists
```

All three find the repository from the current folder (or take
`-RepoPath`), need powershell-yaml 0.4.12 or later, and work offline.
`Update-iSOCDependencyManifest` takes `-WhatIf`; both manifest commands
take `-ManifestPath` for a file other than `dependencies.json`.

The manifest commands return an `iSOCDeployments.ManifestResult`:

| Property | Meaning |
| --- | --- |
| `ManifestPath` | The file, repository-relative |
| `Exists` | Whether the file was there before the run |
| `HasDrift` | Whether the file is missing or its entries differ from what the content needs |
| `Changed` | Whether the command wrote the file (always false for `Test-`) |
| `Entries` | How many content items have dependencies |
| `Diff` | One line per difference: `ADDED:`, `REMOVED:` or `CHANGED:` with a path, and for a change each bucket's members on disk and discovered |
| `MissingWatchlists` | Watchlists the content reads that the repository does not have, with the paths that read them; they fail at deploy unless created another way |

## How discovery works

The content comes from the content type registry: every type with the
`Dependencies` capability (today analytics rules and hunting queries),
read through its ReadRepo handler, with its query from its GetQuery
handler. The parsers' `functionAlias` values are the known functions and
the watchlist folders the known watchlists, both read through their own
content types, so the manifest sees exactly the files deploy reads.

Each query is classified by `Get-iSOCQueryDependency`: watchlists from
`_GetWatchlist('alias')`, URLs from `externaldata(...) [...]`, and every
identifier at a data-source position as a function, when a parser defines
it or it follows the ASIM naming, or a table otherwise. An item with no
dependency gets no entry.

## The file

The file is UTF-8 without a byte order mark, with LF line endings and one
final newline, and its entries are in invariant-culture, case-insensitive
order of their path. That is the order the script's sort produced, and it
is the same on every platform, so a run on Windows writes the same bytes
as one on Linux. Until cut-over the file's description still names the
script, so the two writers produce identical files.
`Tests/iSOCDeployments/Manifest.Tests.ps1` holds the module's output for
this repository to the committed `dependencies.json` byte for byte.
