# The pipeline switch

The pipelines move from the scripts under `Deploy/` and `Tools/` to the
iSOCDeployments module one at a time, Azure DevOps first, then GitHub
Actions. A pipeline that has moved takes an `engine` parameter, so both
can run on the same pipeline until the module has been tested there:

| Engine | What runs |
| --- | --- |
| `scripts` | The scripts, as before. The default until the module is signed off |
| `module` | The module's commands in place of the scripts |
| `compare` | The scripts, plus a step that runs the module beside them and fails the run when the two disagree |

A scheduled run and a PR build always take the default. To try another
engine, queue the pipeline by hand and pick it under **Run pipeline**.
When the module has run clean, the default becomes `module`, and the
scripts and the parameter go at the cut-over.

## Where it stands

| Pipeline | Engine | Module commands |
| --- | --- | --- |
| `Pipelines/Sentinel-Dependency-Update.yml` | Yes | `Update-iSOCDependencyManifest` |
| `Pipelines/Sentinel-PR-Validation.yml` (the manifest gate) | Yes | `Test-iSOCDependencyManifest` |
| `Pipelines/Sentinel-Deploy.yml` | Not yet | `Get-iSOCWorkspaceOnboarding`, `Connect-iSOCWorkspace`, `Deploy-iSOCWorkspace` |
| `Pipelines/Sentinel-Drift-Detect.yml` | Not yet | `Compare-iSOCContent`, `Sync-iSOCContent`, `Export-iSOCDriftReport`, `Update-iSOCDependencyManifest` |
| `Pipelines/Sentinel-DCR-Inventory.yml` | Not yet | `Grant-iSOCRunbookPermission` |
| GitHub Actions workflows | After Azure DevOps | The same |

`Tools/Invoke-PRValidation.ps1`, `Tools/Invoke-DCRWatchlistSync.ps1` and
the Blueprint pipeline stay as they are.

## The dependency manifest

**Daily update** (`Sentinel-Dependency-Update.yml`). With `module`,
`Update-iSOCDependencyManifest` writes `dependencies.json` when it differs
from what the content needs, and the commit, push and PR step is the one
every engine uses; the commit names the command that reproduces the file.
With `compare`, the script updates the manifest as before, and a further
step has both engines write a fresh manifest from the same content to the
agent's temporary folder: the run fails when the bytes differ.

**PR gate** (`Sentinel-PR-Validation.yml`). With `module`,
`Test-iSOCDependencyManifest` fails the step when the manifest is missing
or out of date, with the same two errors on the run. With `compare`, the
step runs both checks and fails when they disagree, and otherwise fails a
stale manifest as the gate always has.

The two engines read the same files in this repository, so they write the
same bytes. They differ on purpose in one way (MIGRATION.md edit E8): the
module reads `.yml` content files as well as `.yaml`. A fork with `.yml`
rules sees `compare` fail, and the failure names E8.

## How the module steps run

- **No variables, no PATH.** Each step that runs the module has
  `target: { commands: restricted, settableVariables: none }`. It logs text
  read from content files and from Azure, and `Write-iSOCLog` already
  breaks up anything a pipeline would read as a command (MIGRATION.md edit
  E45); the restriction means a command that got through could still not
  set a variable or change PATH for the steps after it. Annotations
  (`task.logissue`) still work.
- **Variables through env.** The module steps read the checkout from
  `$env:BUILD_SOURCESDIRECTORY` rather than a `$(...)` macro, and the bot
  commit step reads `syncBranch`, `targetBranch`, `flagReportOnly` and
  `manifestCommand` through `env:`, so no runtime variable is pasted into a
  script's text.
- **The module is imported from the checkout**:
  `Import-Module (Join-Path $env:BUILD_SOURCESDIRECTORY 'Modules/iSOCDeployments/iSOCDeployments.psd1')`.
  The pipeline's own install step provides powershell-yaml 0.4.12; the
  module installs nothing.

## Trying it on Azure DevOps

On a branch the pipelines can see (for example `release/26.11.0`):

1. Queue **Sentinel-Dependency-Update** with `engine` `compare` and
   `reportOnly` on. The compare step should report that the scripts and
   the module wrote the same `dependencies.json`.
2. Queue it again with `engine` `module` and `reportOnly` on. The update
   step should report the entry count and `already current`.
3. Queue **Sentinel-PR-Validation** with `engine` `compare`, then `module`.
   The manifest step should pass both times.

The commit step runs only from `main`, so none of these opens a PR from a
release branch.

`Tests/iSOCDeployments/Pipelines.Tests.ps1` holds the pipelines to all of
this offline. It reads the steps each engine runs, and runs each module
step's inline PowerShell unchanged in a child pwsh against a copy of the
fixture repository: the module's update must leave the same file as the
script's, the comparisons must pass when the engines agree and fail when
they do not, and the gate must pass a current manifest and fail a stale
one.
