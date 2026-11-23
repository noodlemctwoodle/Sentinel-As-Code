# The pipeline switch

The Azure DevOps pipelines run the iSOCDeployments module. The scripts under
`Deploy/` and `Tools/` that the module replaced, and `Modules/Sentinel.Common`,
were removed at the cut-over; `release/26.11.0` keeps them, and the `engine`
parameter (`scripts`, `module` or `compare`) that let both run side by side
while the module was tested there.

| Azure DevOps pipeline | Module commands |
| --- | --- |
| `Pipelines/Sentinel-Deploy.yml` | `Get-iSOCWorkspaceOnboarding`, `Connect-iSOCWorkspace`, `Deploy-iSOCWorkspace` |
| `Pipelines/Sentinel-Drift-Detect.yml` | `Compare-iSOCContent`, `Sync-iSOCContent`, `Export-iSOCDriftReport`, `Update-iSOCDependencyManifest` |
| `Pipelines/Sentinel-Dependency-Update.yml` | `Update-iSOCDependencyManifest` |
| `Pipelines/Sentinel-PR-Validation.yml` (the manifest gate) | `Test-iSOCDependencyManifest` |
| `Pipelines/Sentinel-DCR-Inventory.yml` | None: it runs no script the module replaced; the one-time runbook grant in its header can be `Grant-iSOCRunbookPermission` |

Still to switch: the GitHub workflows under `.github/workflows/`, which
call the removed scripts until they move to the module the same way.
`Tools/Invoke-PRValidation.ps1`, `Tools/Invoke-DCRWatchlistSync.ps1` and
the Blueprint pipeline stay as they are.

## The dependency manifest

**Daily update** (`Sentinel-Dependency-Update.yml`).
`Update-iSOCDependencyManifest` writes `dependencies.json` when it differs
from what the content needs, and the commit, push and PR step opens or
refreshes the bot PR; the commit names the command that reproduces the
file.

**PR gate** (`Sentinel-PR-Validation.yml`). `Test-iSOCDependencyManifest`
fails the step when the manifest is missing or out of date, with two
errors on the run naming the fix.

## Drift

One step connects, runs `Compare-iSOCContent`, absorbs the drift with
`Sync-iSOCContent` (left out when `reportOnly` is on) and writes the report
with `Export-iSOCDriftReport`; the bucket toggles become `-ExcludeSource
ContentHub`, `Custom` and `Orphan`, and `failOnDrift` exits 1 when anything
drifted. The commit step regenerates the manifest with
`Update-iSOCDependencyManifest`.

## Deploy

| Stage | What runs |
| --- | --- |
| Check infrastructure | `Get-iSOCWorkspaceOnboarding`, which sets `RESOURCES_EXIST` and `DEPLOY_SENTINEL` (E42) |
| Deploy infrastructure | Providers, Bicep and the wait; Bicep is given `deploySentinel` from the check |
| Workspace settings | A stage of its own: `Deploy-iSOCWorkspace -Stage WorkspaceSettings` |
| Content Hub | `Deploy-iSOCWorkspace -Stage ContentHub` |
| Custom content | `Deploy-iSOCWorkspace -Stage CustomContent`, which checks `dependencies.json` itself; the deployment state is restored and saved as before |
| Defender XDR detections | `Deploy-iSOCWorkspace -Stage DefenderDetections` |

The pipeline's parameters become the command's as
[Deploying a workspace](Deploy-Workspace.md) lists them: the Content Hub
skips `-ExcludeSolutionContentType`, the custom content skips
`-ExcludeContentType`, the Community skip `-Exclude
'Content/AnalyticalRules/Community/*'`, `protectCustomisedRules` off
`-OverwriteCustomisedRules`, and `whatIf` `-WhatIf` on every stage.
`smartDeployment` reaches the custom content stage, the one that restores
and saves `deployment-state.json`.

The workspace settings stage runs after the infrastructure stage when it
succeeded or did not run, and before the Content Hub stage, so UEBA is on
before the rules that read its tables. No stage's condition reads its
result, so a failed setting holds nothing back, as `Deploy-iSOCWorkspace`
has it. The settings deploy on every run: the stage has no deployment
state, and smart deployment deploys what the state does not record.

The stage conditions are Azure DevOps' (E44 lists how `Deploy-iSOCWorkspace`
gates when it runs the stages itself). One case they do not cover: when
the check finds the onboarding state without the SecurityInsights solution
(`SolutionMissing`), it fails the check stage so Bicep does not run, but
the content stages' conditions accept a skipped infrastructure stage, so
they still run.

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

## Testing it on Azure DevOps

Queue each pipeline by hand on the branch, the deploy pipeline first with
`whatIf` on and then for real against the lab workspace, twice: the second
run should find everything current. The bot commit steps run only from
`main`, so none of these opens a PR from the branch.

`Tests/iSOCDeployments/Pipelines.Tests.ps1` holds the pipelines to all of
this offline. It reads the stages and steps each pipeline runs, and runs
each module step's inline PowerShell unchanged in a child pwsh, as the
agent would: the manifest steps against a copy of the fixture repository,
and the drift and deploy steps against stand-ins for the module's commands
that carry the real parameter blocks and record what they are given.
