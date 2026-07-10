# DCR Inventory Pipeline

CI/CD wiring for the **DCR Watchlist Sync** automation. This pipeline
deploys (and updates) the Azure Automation Account, PowerShell runbook,
and recurring schedule that inventory Data Collection Rule (DCR)
associations into a Sentinel watchlist. It provisions the plumbing; it
does not run the inventory sync itself - that happens on an
Automation-side schedule created by the Bicep stack.

Two mirrored definitions drive it:

| CI system | File | Auth |
| --- | --- | --- |
| GitHub Actions | [`.github/workflows/sentinel-dcr-inventory.yml`](../../.github/workflows/sentinel-dcr-inventory.yml) | OIDC federated credential (composite action) |
| Azure DevOps | [`Pipelines/Sentinel-DCR-Inventory.yml`](../../Pipelines/Sentinel-DCR-Inventory.yml) | Service connection `sc-sentinel-as-code` (workload identity federation) |

For what the deployed runbook actually does (the DCR enumeration, the
watchlist schema, the billing-safe merge/upsert, and the `DCRName` search
key), see [DCR Watchlist Sync](../Tools/DCR-Watchlist.md). This
document covers only the pipeline mechanics.

## What it provisions

Both definitions run the same subscription-scoped Bicep deployment
([`Infra/dcr-watchlist/main.bicep`](../../Infra/dcr-watchlist/main.bicep))
and the same runbook-update logic:

- Resource group for the Automation Account (default
  `rg-dcr-watchlist-sync`)
- Automation Account (default `aa-dcr-watchlist-sync`) with a
  system-assigned managed identity
- The `Invoke-DCRWatchlistSync` PowerShell 7.2 runbook, imported from
  [`Tools/Invoke-DCRWatchlistSync.ps1`](../../Tools/Invoke-DCRWatchlistSync.ps1)
- A recurring Automation schedule (daily by default, 03:00 UTC start) and
  the job schedule that links the runbook to it with its runtime
  parameters, including `SearchKey=DCRName`

## Triggers

| Trigger | GitHub | Azure DevOps |
| --- | --- | --- |
| Push to `main` (path-filtered) | Yes | Yes |
| `workflow_dispatch` / manual queue | Yes | Yes |
| Scheduled cron | **No** | **No** |

There is **no cron schedule on either definition.** The pipeline fires on
change, not on a timer. The recurring behaviour of the inventory belongs
to the Automation Account schedule that the Bicep stack creates, not to
CI. Do not confuse the two: CI redeploys the runbook when its code or
infrastructure changes; Azure Automation runs the runbook daily.

### Path filter

Both definitions watch the same three paths on push to `main`:

- `Infra/dcr-watchlist/**` (the Bicep stack)
- `Tools/Invoke-DCRWatchlistSync.ps1` (the runbook body)
- `Deploy/permissions/Set-RunbookPermissions.ps1` (the RBAC helper)

The GitHub workflow adds a fourth path, `.github/workflows/sentinel-dcr-inventory.yml`
(the workflow file itself), so edits to the workflow re-trigger it. The
ADO pipeline has no self-referencing path (ADO cannot watch its own
definition file the same way).

## Parameters and inputs

The GitHub `workflow_dispatch` inputs and the ADO `parameters` block carry
the same nine settings with identical defaults. The GitHub definition also
normalises them (see [Push-vs-dispatch normalisation](#push-vs-dispatch-normalisation-github-only)
below).

| Parameter | Type | Default | Purpose |
| --- | --- | --- | --- |
| `deployInfrastructure` | boolean | `true` | Run the Bicep infrastructure stage |
| `updateRunbook` | boolean | `false` | Update the runbook body only, skipping Bicep |
| `automationResourceGroup` | string | `rg-dcr-watchlist-sync` | Resource group for the Automation Account |
| `automationAccountName` | string | `aa-dcr-watchlist-sync` | Automation Account name |
| `watchlistAlias` | string | `CustomerResources` | Watchlist alias (no spaces) passed to the runbook schedule |
| `watchlistDisplayName` | string | `Customer DCR Resources` | Watchlist display name shown in the Sentinel portal |
| `scheduleFrequencyHours` | `24` / `168` | `24` | Automation schedule cadence: 24 = daily, 168 = weekly |
| `location` | string | `uksouth` | Azure region for the deployment |
| `whatIf` | boolean | `false` | Dry run: `--what-if` on the Bicep deploy, and the runbook-update stage is skipped |

On GitHub, `scheduleFrequencyHours` is a `choice` input; on ADO it is a
`number` parameter constrained to the values `24` and `168`. Both resolve
to the same two options.

The Bicep template itself computes `scheduleStartTime` from the pipeline
(tomorrow at 03:00 UTC, always at least five minutes in the future, which
Azure Automation requires) rather than exposing it as a queue-time input.

## Jobs / stages

The two definitions are structured identically: an infrastructure stage
followed by a runbook-update stage that depends on it.

### Stage 1: Deploy infrastructure

- GitHub job `deploy-infrastructure`; ADO stage `DeployInfrastructure`
  (job `DeployBicep`).
- **Runs when** the event is a push, or `deployInfrastructure` is `true`.
- Steps, in order:
  1. Checkout.
  2. Azure login (see [Authentication](#authentication)).
  3. `az deployment sub create` against
     `Infra/dcr-watchlist/main.bicep`, passing `location`,
     `automationResourceGroup`, `automationAccountName`,
     `scheduleFrequencyHours`, and the computed `scheduleStartTime`. When
     `whatIf` is `true` the deploy adds `--what-if` and applies nothing.
- GitHub runs this in `Azure/cli@v3`; ADO runs it in the `AzureCLI@2`
  task. The inline bash body is the same on both.

### Stage 2: Update runbook

- GitHub job `update-runbook` (`needs: deploy-infrastructure`); ADO stage
  `UpdateRunbook` (`dependsOn: DeployInfrastructure`, job `UpdateScript`).
- **Runs when** Stage 1 did not fail, `whatIf` is not `true`, and at least
  one of `deployInfrastructure` or `updateRunbook` is `true` (a push
  satisfies this too). The GitHub gate uses `always() && needs...result != 'failure'`
  so it still runs when Stage 1 was skipped (for example an
  `updateRunbook`-only run); the ADO gate uses
  `not(failed('DeployInfrastructure'))` for the same effect.
- Steps, in order:
  1. Checkout.
  2. Azure login.
  3. In an Azure PowerShell session (`Azure/powershell@v3` on GitHub,
     `AzurePowerShell@5` on ADO):
     - `Import-AzAutomationRunbook` imports
       `Tools/Invoke-DCRWatchlistSync.ps1` into the existing runbook as
       PowerShell 7.2 (`-Force`).
     - `Publish-AzAutomationRunbook` publishes the imported draft.
     - The job schedule is linked idempotently: `Get-AzAutomationScheduledRunbook`
       checks for an existing link to schedule `dcr-watchlist-sync-schedule`;
       if none exists, `Register-AzAutomationScheduledRunbook` links the
       runbook with its runtime parameters (`SubscriptionId`,
       `WorkspaceResourceGroup`, `WorkspaceName`, `WatchlistAlias`,
       `WatchlistDisplayName`, and `SearchKey = DCRName`). If already
       linked, the step logs a skip.

`SearchKey` is hard-coded to `DCRName` in both definitions. The watchlist
holds one row per DCR, so `DCRName` is the only stable per-row key; see
[DCR Watchlist Sync](../Tools/DCR-Watchlist.md) for why passing
`ResourceId` here would fault the sync.

## Variables, secrets, and repo variables

The two CI systems source the same three runtime facts (subscription,
Sentinel resource group, Sentinel workspace) from different places.

### GitHub

- **Secrets** (used for OIDC login and passed to the runbook-link step):
  `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.
- **Repository variables** (`vars.*`), consumed only by Stage 2 to build
  the schedule parameters: `SENTINEL_RESOURCE_GROUP`,
  `SENTINEL_WORKSPACE_NAME`.
- A top-level `env:` block normalises every input into an environment
  variable the jobs read uniformly, plus `BICEP_PATH: Infra/dcr-watchlist`.

### Azure DevOps

- **Variable group `sentinel-deployment`** (linked under Pipelines >
  Library) supplies `azureSubscriptionId`, `sentinelResourceGroup`, and
  `sentinelWorkspaceName`.
- Pipeline-local variables: `serviceConnection` (`sc-sentinel-as-code`),
  `SuppressAzurePowerShellBreakingChangeWarnings` (`true`), and
  `bicepPath` (`$(Build.SourcesDirectory)/Infra/dcr-watchlist`).

## Authentication

- **GitHub** logs in through the local composite action
  [`./.github/actions/azure-login-oidc`](../../.github/actions/azure-login-oidc/action.yml),
  which wraps `Azure/login@v3` with the OIDC parameter set
  (`client-id`, `tenant-id`, `subscription-id`). It requests a federated
  token, so no client secret is stored. Both jobs declare the required
  `permissions: id-token: write` / `contents: read` at the top of the
  workflow. The matching service principal needs a federated credential
  in Entra ID trusting the repo's OIDC subject.
- **Azure DevOps** uses the `sc-sentinel-as-code` service connection,
  which should itself be configured for workload identity federation
  (OIDC) rather than a stored secret. See
  [ADO OIDC Setup](../Deploy/ADO-OIDC-Setup.md).

## Post-deployment RBAC (manual, one-time)

Neither pipeline grants the Automation Account's managed identity its
runtime roles: the deploying service principal does not hold
`Microsoft.Authorization/roleAssignments/write`. After the first
successful deployment, assign the following to the Automation Account's
system-assigned identity (helper:
[`Deploy/permissions/Set-RunbookPermissions.ps1`](../../Deploy/permissions/Set-RunbookPermissions.ps1)):

- **Monitoring Reader** on the subscription (to enumerate DCRs and
  associations).
- **Microsoft Sentinel Contributor** on the subscription (to upsert the
  watchlist).

Once granted, the runbook runs autonomously on its Automation schedule.

## Artefacts and outputs

Neither definition publishes a pipeline artefact. The Bicep template
returns two outputs (`automationAccountName`, `managedIdentityPrincipalId`)
that surface in the deployment result and are useful when running the
manual RBAC grant above, but they are not exported as CI artefacts.

## GitHub <-> ADO mapping and asymmetries

The two definitions are close mirrors, but they are not byte-identical:

| Aspect | GitHub | Azure DevOps |
| --- | --- | --- |
| Auth | OIDC composite action `azure-login-oidc` | Service connection `sc-sentinel-as-code` |
| Subscription / workspace source | Secret + repo variables | Variable group `sentinel-deployment` |
| Push path filter | Includes the workflow file itself | Three content paths only (no self-reference) |
| Input handling | `workflow_dispatch` inputs normalised via an `env:` block for push-vs-dispatch | `parameters` resolve to defaults on push automatically |
| Stage 1 runner | `Azure/cli@v3` | `AzureCLI@2` task |
| Stage 2 runner | `Azure/powershell@v3` | `AzurePowerShell@5` task |
| Cron schedule | None | None |

### Push-vs-dispatch normalisation (GitHub only)

A push event does not supply `workflow_dispatch` inputs, so the GitHub
workflow uses a top-level `env:` block of the form
`${{ github.event_name == 'workflow_dispatch' && inputs.X || '<default>' }}`
to resolve every setting to either its dispatched value or its default.
The jobs then read the normalised `env` vars uniformly. ADO does not need
this pattern: pipeline `parameters` always carry their defaults, whatever
the trigger.

---

## Authoring with GitHub Copilot

When editing this pipeline pair (or any file under
`.github/workflows/`, `.github/actions/`, or `Pipelines/`), Copilot loads
[`.github/instructions/workflows.instructions.md`](../../.github/instructions/workflows.instructions.md),
which codifies ADO-as-source-of-truth, the composite-action adoption rule,
and the ADO to GitHub Actions translation table. The
`Sentinel-As-Code: Pipeline Engineer` agent owns parity between the two
definitions; the `Sentinel-As-Code: Bicep Engineer` agent owns the
`Infra/dcr-watchlist/` stack. See
[GitHub Copilot setup](../GitHub/GitHub-Copilot.md).
