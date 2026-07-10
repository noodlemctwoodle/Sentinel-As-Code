# Deploy Nightly (E2E Smoke Test)

GitHub workflow
[`.github/workflows/sentinel-deploy-nightly.yml`](../../.github/workflows/sentinel-deploy-nightly.yml)
(`name: Sentinel Nightly E2E Deploy Validation`).

A nightly end-to-end smoke test that exercises the real deploy code
paths against the throwaway test workspace provisioned by
[`Infra/test-workspace/main.bicep`](../../Infra/test-workspace/main.bicep).
The PR-merge gate ([`pr-validation.yml`](../../.github/workflows/pr-validation.yml))
catches schema and pure-function regressions but deliberately does not
run the deploy scripts against a live workspace, so a class of
deploy-time bugs (Sentinel API contract drift, deploy-script branching
regressions, permission drift on the deploy service principal, or PRs
that pass in isolation but interact badly) would stay invisible until
the weekly Monday production deploy. This workflow runs those paths
every night, six days ahead of the production deploy.

This workflow is **GitHub-only**. There is no Azure DevOps equivalent
under [`Pipelines/`](../../Pipelines); see
[GitHub <-> ADO mapping](#github---ado-mapping) below.

This page documents the pipeline mechanics. For what the invoked scripts
actually do, see [Scripts](../Deploy/Scripts.md); for the test-workspace Bicep
stack, see [Bicep](../Infra/Bicep.md).

## Triggers

| Trigger | Configuration | Notes |
| --- | --- | --- |
| `schedule` | `cron: "0 3 * * *"` | Daily at 03:00 UTC |
| `workflow_dispatch` | no inputs | Manual run from the Actions tab |

There is no `push`, `pull_request`, or `paths` trigger. The only
automatic run is the nightly cron; every other run is a manual
`workflow_dispatch`.

## Configuration

The workflow takes no parameters. All inputs come from workflow-level
`env`, repository variables, and secrets.

### Workflow `env`

| Variable | Value | Source |
| --- | --- | --- |
| `RESOURCE_GROUP` | `${{ vars.PR_VALIDATION_RESOURCE_GROUP }}` | Repo variable |
| `WORKSPACE_NAME` | `law-sentinel-pr-test` | Hard-coded (matches the test-workspace Bicep default) |
| `REGION` | `${{ vars.SENTINEL_REGION }}` | Repo variable |
| `TEST_SOLUTION` | `Azure Activity` | Hard-coded. A single small Content Hub solution, chosen to keep wall-clock under ten minutes |
| `YAML_VERSION` | `0.4.12` | Hard-coded. `powershell-yaml` pin for the setup-modules action |

### Repository variables

| Variable | Used for |
| --- | --- |
| `PR_VALIDATION_RESOURCE_GROUP` | Resource group holding the reusable test workspace |
| `SENTINEL_REGION` | Azure region passed to the Bicep deploy and the content scripts |

### Secrets

| Secret | Used for |
| --- | --- |
| `AZURE_CLIENT_ID` | OIDC federated login (client/app ID of the deploy SP) |
| `AZURE_TENANT_ID` | OIDC federated login |
| `AZURE_SUBSCRIPTION_ID` | OIDC federated login and `-SubscriptionId` for the content scripts |
| `GITHUB_TOKEN` | `report-failure` uses it (as `GH_TOKEN`) to open / refresh the failure issue |

### Workflow-level `permissions`

```
id-token: write     # OIDC against Azure
contents: read
issues:   write     # gh issue create on failure
```

### Concurrency

```
concurrency:
  group: sentinel-deploy-nightly
  cancel-in-progress: false
```

`cancel-in-progress: false` means consecutive nightly runs do not cancel
each other, so multiple failures each keep their own context for
diagnosing intermittent versus persistent problems.

## Jobs

Six jobs run in a linear chain. Each deploy job gates on the previous one
succeeding *or* being skipped (`always() && (...success || ...skipped)`),
so a skipped Bicep deploy (workspace already exists) does not block the
content stages, but a genuine failure short-circuits the rest.

```
check-infrastructure        Read-only probe: does the RG + workspace exist?
        │  (outputs.resources_exist)
        ▼
deploy-infrastructure       Bicep deploy of the test workspace.
        │                   Runs ONLY if resources_exist == 'false'.
        ▼
deploy-content-hub          Deploy one Content Hub solution (Azure Activity).
        ▼
deploy-custom-content       Deploy-CustomContent.ps1 -WhatIf (no mutation).
        ▼
deploy-defender-detections  Deploy-DefenderDetections.ps1 -WhatIf.
        ▼
report-failure              Runs only if any prior job failed.
```

Every deploy job first checks out the repo (`actions/checkout@v5`) and
logs into Azure via the [`azure-login-oidc`](#authentication) composite
action before doing its work. Checkout is required even on the read-only
probe because the local composite action can only be resolved once the
runner has the repo on disk.

### 1. `check-infrastructure`

Read-only probe, `runs-on: ubuntu-latest`. Output:
`resources_exist` (`"true"` / `"false"`).

Runs an `Azure/powershell@v3` (`azPSVersion: latest`) inline script that
calls `Get-AzResourceGroup` for `RESOURCE_GROUP`, then (if the group
exists) `Get-AzOperationalInsightsWorkspace` for `WORKSPACE_NAME`. If the
workspace is found it sets `resources_exist=true`; otherwise `false`.
Both lookups use `-ErrorAction SilentlyContinue`, so a missing group or
workspace is a normal `false`, not a failure.

### 2. `deploy-infrastructure`

`needs: check-infrastructure`. Conditional:

```
if: always() &&
    needs.check-infrastructure.result == 'success' &&
    needs.check-infrastructure.outputs.resources_exist == 'false'
```

Deploys the test workspace via `Azure/cli@v3`:

```
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file Infra/test-workspace/main.bicep \
  --parameters location="$REGION"
```

The deploy is idempotent, so on a normal night the probe reports the
workspace already exists and this job is skipped. It only runs when the
workspace is genuinely absent (first run, or after a manual teardown).
See [Bicep](../Infra/Bicep.md) for what the template provisions.

### 3. `deploy-content-hub`

`needs: [check-infrastructure, deploy-infrastructure]`. Runs when the
Bicep deploy succeeded or was skipped. Invokes
[`Deploy-SentinelContentHub.ps1`](../Deploy/Scripts.md#deploy-sentinelcontenthubps1)
via `Azure/powershell@v3` with a single solution:

```
Deploy/content/Deploy-SentinelContentHub.ps1 `
  -SubscriptionId $AZURE_SUBSCRIPTION_ID `
  -ResourceGroup  $RESOURCE_GROUP `
  -Workspace      $WORKSPACE_NAME `
  -Region         $REGION `
  -Solutions      $TEST_SOLUTION      # "Azure Activity"
```

Deploying one small solution keeps the run short while still exercising
the Content Hub install path end to end.

### 4. `deploy-custom-content`

`needs: [check-infrastructure, deploy-infrastructure, deploy-content-hub]`.
Runs when Content Hub succeeded or was skipped. This is the only job that
checks out with `fetch-depth: 2`, because smart deployment compares
against the parent commit.

Steps, in order:

1. Checkout (`fetch-depth: 2`).
2. [`setup-pwsh-modules`](#composite-actions) with `install-pester: 'false'`
   (installs `powershell-yaml` only, pinned to `YAML_VERSION`).
3. Verify the dependency manifest is current: runs
   [`Tools/Build-DependencyManifest.ps1 -Mode Verify`](../Tools/Dependency-Manifest.md)
   and fails the job if `dependencies.json` is stale, refusing to run E2E
   against a drifted manifest.
4. Azure login (OIDC).
5. Run [`Deploy-CustomContent.ps1`](../Deploy/Scripts.md#deploy-customcontentps1)
   with `-WhatIf`:

```
Deploy/content/Deploy-CustomContent.ps1 `
  -SubscriptionId $AZURE_SUBSCRIPTION_ID `
  -ResourceGroup  $RESOURCE_GROUP `
  -Workspace      $WORKSPACE_NAME `
  -Region         $REGION `
  -BasePath       $GITHUB_WORKSPACE `
  -WhatIf
```

`-WhatIf` means the deploy decision tree (all eight content stages, the
dependency pre-flight, and the smart-deployment branching) runs against
the real workspace state, but no resources are mutated.

### 5. `deploy-defender-detections`

`needs: [check-infrastructure, deploy-infrastructure, deploy-content-hub, deploy-custom-content]`.
Runs when custom content succeeded or was skipped. Checks out, runs
`setup-pwsh-modules` (`install-pester: 'false'`), logs in, then runs
[`Deploy-DefenderDetections.ps1`](../Deploy/Scripts.md#deploy-defenderdetectionsps1)
with `-WhatIf`:

```
Deploy/content/Deploy-DefenderDetections.ps1 `
  -BasePath $GITHUB_WORKSPACE `
  -WhatIf
```

It takes no subscription or workspace arguments; Defender detections
deploy against Microsoft Graph, not the Log Analytics workspace.

### 6. `report-failure`

`needs:` all five prior jobs. Conditional fires only when any of them has
`result == 'failure'`. It declares its own job-level
`permissions: { issues: write, contents: read }`.

Steps: checkout, then a bash step (`GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`)
that:

1. Identifies the first failing job in the chain and names it
   (`FAILED_STAGE`).
2. Builds an issue body containing the failing stage, a link to the
   workflow run, the workspace / resource-group, and triage guidance.
3. Searches open issues for a matching title
   (`Nightly E2E deploy validation failed: <stage>`). If one exists it
   edits the body and adds a "Re-failed" comment; otherwise it opens a
   new issue with labels `ci,nightly-failure`.

De-duplicating on title means repeated failures at the same stage refresh
one issue instead of spamming new ones.

## Authentication

Azure access is federated OIDC, not a stored secret credential. Every
Azure-touching job calls the local composite action
[`./.github/actions/azure-login-oidc`](../../.github/actions/azure-login-oidc):

```
- name: Azure Login (OIDC)
  uses: ./.github/actions/azure-login-oidc
  with:
    client-id:       ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id:       ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

The action wraps `Azure/login@v3` and enables both the `az` CLI session
and the Az PowerShell session by default, which is why the same one-line
call works for the `Azure/cli@v3` Bicep step and the `Azure/powershell@v3`
content steps. It depends on the workflow-level `id-token: write`
permission declared above. Issuing the token requires a federated
credential on the deploy service principal that trusts this repository;
see [ADO OIDC Setup](../Deploy/ADO-OIDC-Setup.md) and
[PR Validation Setup](../Deploy/PR-Validation-Setup.md) for how that trust and
the test workspace are provisioned.

### Composite actions

| Action | Role in this workflow |
| --- | --- |
| [`azure-login-oidc`](../../.github/actions/azure-login-oidc) | Federated Azure login (`az` CLI + Az PowerShell) |
| [`setup-pwsh-modules`](../../.github/actions/setup-pwsh-modules) | Cache + pin-install `powershell-yaml` (`install-pester: 'false'` here) for the two `-WhatIf` content jobs |

## Outputs and artefacts

This workflow publishes no build artefacts. Its outputs are:

- `check-infrastructure.outputs.resources_exist` (`"true"` / `"false"`),
  consumed by the conditional on `deploy-infrastructure`.
- On success: idempotent Bicep + one Content Hub solution deployed to the
  test workspace; the two custom/Defender stages run `-WhatIf` and mutate
  nothing.
- On failure: a GitHub issue opened or refreshed by `report-failure`.

## GitHub <-> ADO mapping

| GitHub workflow | ADO pipeline |
| --- | --- |
| `sentinel-deploy-nightly.yml` | none (GitHub-only) |

This nightly E2E smoke test has **no Azure DevOps counterpart**. It is one
of the two documented asymmetries between the CI systems: it is
GitHub-only, and `Sentinel-Word-Report.yml` is ADO-only. See
[Pipelines](README.md#github-actions-parity) for the full mapping.

Note it is distinct from the weekly production deploy
([`sentinel-deploy.yml`](../../.github/workflows/sentinel-deploy.yml) /
[`Sentinel-Deploy.yml`](../../Pipelines/Sentinel-Deploy.yml)), which
does deploy for real and does have an ADO mirror. This nightly workflow
runs the same class of code against a throwaway workspace, in `-WhatIf`
mode for the mutating stages, purely as an early-warning smoke test.

## See also

- [Pipelines](README.md) - full pipeline / workflow inventory and parity table
- [Scripts](../Deploy/Scripts.md) - what the invoked deploy scripts do
- [Bicep](../Infra/Bicep.md) - the `Infra/test-workspace` stack
- [Dependency Manifest](../Tools/Dependency-Manifest.md) - the `Build-DependencyManifest -Mode Verify` gate
