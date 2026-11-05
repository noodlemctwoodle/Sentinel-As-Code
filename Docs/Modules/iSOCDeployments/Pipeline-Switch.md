# The pipeline switch

The pipelines move from the scripts under `Deploy/` and `Tools/` to the
iSOCDeployments module, Azure DevOps first, then GitHub Actions. A pipeline
that has moved takes an `engine` parameter, so both can run on the same
pipeline until the module has been tested there:

| Engine | What runs |
| --- | --- |
| `scripts` | The scripts, as before. The default until the module is signed off |
| `module` | The module's commands in place of the scripts |
| `compare` | The scripts, plus steps that run the module beside them and fail the run when the two disagree |

A scheduled run and a PR build always take the default. To try another
engine, queue the pipeline by hand and pick it under **Run pipeline**.
When the module has run clean, the default becomes `module`, and the
scripts and the parameter go at the cut-over.

## Where it stands

| Azure DevOps pipeline | Engine | Module commands |
| --- | --- | --- |
| `Pipelines/Sentinel-Dependency-Update.yml` | Yes | `Update-iSOCDependencyManifest` |
| `Pipelines/Sentinel-PR-Validation.yml` (the manifest gate) | Yes | `Test-iSOCDependencyManifest` |
| `Pipelines/Sentinel-Drift-Detect.yml` | Yes | `Compare-iSOCContent`, `Sync-iSOCContent`, `Export-iSOCDriftReport`, `Update-iSOCDependencyManifest` |
| `Pipelines/Sentinel-Deploy.yml` | Yes | `Get-iSOCWorkspaceOnboarding`, `Connect-iSOCWorkspace`, `Deploy-iSOCWorkspace` |
| `Pipelines/Sentinel-DCR-Inventory.yml` | Not needed | It runs no script the module replaces; the one-time runbook grant in its header can be `Grant-iSOCRunbookPermission` |

The GitHub workflows follow once Azure DevOps has been signed off.
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

## Drift

With `module`, one step connects, runs `Compare-iSOCContent`, absorbs the
drift with `Sync-iSOCContent` (left out when `reportOnly` is on) and writes
the report with `Export-iSOCDriftReport`; the bucket toggles become
`-ExcludeSource ContentHub`, `Custom` and `Orphan`, and `failOnDrift` exits
1 when anything drifted. The commit step regenerates the manifest with
`Update-iSOCDependencyManifest`.

With `compare`, the module reads the workspace first, before the script
changes anything, and writes its report to the agent's temporary folder.
The script then runs as usual, and a last step compares the script's new
report with the module's: both finding no drift passes, and so does both
counting it the same; one finding drift and the other not, or any count
differing, fails the run and names MIGRATION.md edits E22 to E24, which
list what the module does differently on purpose.

## Deploy

| Stage | `module` | `compare` |
| --- | --- | --- |
| Check infrastructure | `Get-iSOCWorkspaceOnboarding`, which sets `RESOURCES_EXIST` and, new on Azure DevOps, `DEPLOY_SENTINEL` (E42) | The scripts' check decides; a step then fails the run when the module would decide differently, except where the module's onboarding checks explain it (E42) |
| Deploy infrastructure | Providers, Bicep and the wait, as before; Bicep is given `deploySentinel` from the check | As before |
| Workspace settings | A stage of its own: `Deploy-iSOCWorkspace -Stage WorkspaceSettings` | The same stage, as a dry run; the scripts still configure the settings in the infrastructure stage |
| Content Hub | `Deploy-iSOCWorkspace -Stage ContentHub` | The scripts deploy, then the module runs with `-WhatIf` |
| Custom content | `Deploy-iSOCWorkspace -Stage CustomContent`, which checks `dependencies.json` itself; the deployment state is restored and saved as before | The scripts' guard and deploy, then the module with `-WhatIf` |
| Defender XDR detections | `Deploy-iSOCWorkspace -Stage DefenderDetections` | The scripts deploy, then the module with `-WhatIf` |

The pipeline's parameters become the command's as
[Deploying a workspace](Deploy-Workspace.md) lists them: the Content Hub
skips `-ExcludeSolutionContentType`, the custom content skips
`-ExcludeContentType`, the Community skip `-Exclude
'Content/AnalyticalRules/Community/*'`, `protectCustomisedRules` off
`-OverwriteCustomisedRules`, and `whatIf` `-WhatIf` on every stage.
`smartDeployment` reaches the custom content stage, the one that restores
and saves `deployment-state.json`, as it did.

The workspace settings stage runs after the infrastructure stage when it
succeeded or did not run, and before the Content Hub stage, so UEBA is on
before the rules that read its tables. No stage's condition reads its
result, so a failed setting holds nothing back, as `Deploy-iSOCWorkspace`
has it. The settings deploy on every run: the stage has no deployment
state, and smart deployment deploys what the state does not record.

The stage conditions are the pipeline's, unchanged, so the gating is
Azure DevOps' (E44 lists how `Deploy-iSOCWorkspace` gates when it runs the
stages itself). One case the conditions do not cover: when the module's
check finds the onboarding state without the SecurityInsights solution
(`SolutionMissing`), it fails the check stage so Bicep does not run, but
the content stages' conditions accept a skipped infrastructure stage, so
they still run. The scripts' check never failed, so this cannot happen
with `scripts`.

## How the module steps run

- **No variables, no PATH.** Each step that runs the module has
  `target: { commands: restricted, settableVariables: none }`; the deploy
  check may set only its two outputs. The steps log text read from content
  files and from Azure, and `Write-iSOCLog` already breaks up anything a
  pipeline would read as a command (MIGRATION.md edit E45); the restriction
  means a command that got through could still not set a variable or
  change PATH for the steps after it. Annotations (`task.logissue`) still
  work.
- **Variables through env.** The module steps read the workspace and the
  checkout from `env:` rather than `$(...)` macros. A variable left unset
  reaches a step as its own macro text, which the steps treat as empty (the
  playbook resource group). The bot commit steps read their branches
  through `env:`, both branch variables are `readonly`, and the drift
  commit step, which prints the report, is restricted too.
- **The module is imported from the checkout**:
  `Import-Module (Join-Path $env:BUILD_SOURCESDIRECTORY 'Modules/iSOCDeployments/iSOCDeployments.psd1')`.
  The pipeline's own install step provides powershell-yaml 0.4.12; the
  module installs nothing. The deploy steps run under `$ErrorActionPreference
  = 'Stop'` and end with `exit $run.ExitCode`, so a failed item fails the
  step.

## Trying it on Azure DevOps

On a branch the pipelines can see (`release/26.11.0`), in this order:

1. **Sentinel-Dependency-Update**, `reportOnly` on: `engine` `compare`, then
   `module`. The compare step should report the same `dependencies.json`;
   the module step the entry count and `already current`.
2. **Sentinel-PR-Validation**: `compare`, then `module`. The manifest step
   should pass both times.
3. **Sentinel-Drift-Detect**, `reportOnly` on: `compare`, then `module`.
   The compare step should report the same drift, or none on both sides.
4. **Sentinel-Deploy**, `whatIf` on: `compare`, then `module`. Every module
   step should succeed and show what it would do; the check comparison
   should pass.
5. **Sentinel-Deploy**, `module`, for real, against the lab workspace, and
   then again: the second run should find everything current.

The bot commit steps run only from `main`, so none of these opens a PR
from the release branch.

Not checked offline, and worth watching on the first runs: that
`AzurePowerShell@5` runs as usual under `commands: restricted`, and that an
`exit` code from the module steps fails the task.

`Tests/iSOCDeployments/Pipelines.Tests.ps1` holds the pipelines to all of
this offline. It reads the stages and steps each engine runs, and runs each
module step's inline PowerShell unchanged in a child pwsh, as the agent
would: the manifest steps against a copy of the fixture repository, and
the drift and deploy steps against stand-ins for the module's commands
that carry the real parameter blocks and record what they are given. So it
checks what each pipeline parameter becomes, what each step does with the
result, and that the compare steps pass when the engines agree and fail
when they do not.
