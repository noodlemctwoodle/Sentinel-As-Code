# Bicep Infrastructure

Subscription-scoped Bicep templates that provision the foundational
Sentinel infrastructure: the resource group, Log Analytics workspace,
Sentinel onboarding, diagnostic settings, and an optional separate
resource group for playbooks.

| File | Scope | Purpose |
| --- | --- | --- |
| [`Bicep/main.bicep`](../../Bicep/main.bicep) | Subscription | Orchestrator — creates resource groups and invokes the Sentinel module |
| [`Bicep/sentinel.bicep`](../../Bicep/sentinel.bicep) | Resource group | Workspace, Sentinel onboarding, diagnostic settings |

These are invoked by Stage 2 of [`Pipelines/Sentinel-Deploy.yml`](../../Pipelines/Sentinel-Deploy.yml) — see [Pipelines](Pipelines.md). Sentinel feature settings that are not exposed by Bicep (Entity Analytics, UEBA, Anomalies, EyesOn) are configured via REST in a follow-on pipeline step in the same stage.

## main.bicep

Subscription-scoped orchestrator. Creates the main resource group, an optional separate playbook resource group, and invokes the Sentinel module against the main RG.

### Parameters

| Parameter | Type | Default | Constraints | Description |
| --- | --- | --- | --- | --- |
| `rgName` | string | — | 1-90 chars | Name of the main Sentinel resource group to create |
| `rgLocation` | string | — | — | Azure region for all resources (e.g. `uksouth`) |
| `lawName` | string | — | 4-63 chars | Log Analytics workspace name (passed through to the module) |
| `dailyQuota` | int | `0` | 0-5120 | Daily ingestion cap in GB. `0` = unlimited |
| `retentionInDays` | int | `90` | 30-730 | Interactive retention period |
| `totalRetentionInDays` | int | `0` | 0-2555 | Total retention including archive tier. `0` = use platform default (matches `retentionInDays`) |
| `playbookRgName` | string | `''` | — | Optional separate Resource Group for playbooks/Logic Apps. Empty or equal to `rgName` means playbooks land in the main RG |
| `deploySentinel` | bool | `true` | — | Whether to deploy the `sentinel.bicep` module. Set `false` by the deployment pipeline when Sentinel onboarding already exists on the target workspace; the `Microsoft.SecurityInsights/onboardingStates` resource is not idempotent and re-deploying it returns `Conflict`. Setting `false` lets `main.bicep` provision only the missing pieces (most commonly the optional playbook RG) without touching an existing Sentinel deployment |
| `tags` | object | `{}` | — | Resource tags applied to all resources |

### Resources created

| Resource | API version | Notes |
| --- | --- | --- |
| `Microsoft.Resources/resourceGroups` (main) | `2024-07-01` | Always created |
| `Microsoft.Resources/resourceGroups` (playbook) | `2024-07-01` | Conditional — only when `playbookRgName` is non-empty AND differs from `rgName` |
| `sentinel.bicep` module | n/a | Conditional — invoked only when `deploySentinel = true`. Skipped on targeted partial deploys (e.g. provisioning a missing playbook RG while leaving an already-onboarded Sentinel workspace untouched) |

### Outputs

| Output | Type | Source / behaviour |
| --- | --- | --- |
| `sentinelDeployed` | bool | Echoes the `deploySentinel` parameter. Consumers should branch on this before reading `sentinelResourceId` / `logAnalyticsWorkspace` — those values are only meaningful when `sentinelDeployed = true` |
| `sentinelResourceId` | string | Bubbled up from the Sentinel module — the OMS solution resource ID. Collapses to `''` when `deploySentinel = false` (module skipped); use `sentinelDeployed` to distinguish "module skipped" from "module ran and produced an empty string" |
| `logAnalyticsWorkspace` | object | Bubbled up from the Sentinel module — `{ name, id, location, retentionInDays }`. Collapses to `{}` when `deploySentinel = false` (same caveat as above) |

## sentinel.bicep

Resource-group-scoped module. Creates the workspace, both onboarding mechanisms, and diagnostic settings.

### Parameters

| Parameter | Type | Default | Constraints | Description |
| --- | --- | --- | --- | --- |
| `lawName` | string | — | 4-63 chars | Log Analytics workspace name |
| `dailyQuota` | int | `0` | 0-5120 | Daily ingestion cap in GB. `0` = unlimited |
| `retentionInDays` | int | `90` | 30-730 | Interactive retention period |
| `totalRetentionInDays` | int | `0` | 0-2555 | Total retention including archive tier. `0` = use `retentionInDays` |
| `tags` | object | `{}` | — | Resource tags applied to the workspace |

### Resources created

| Resource | API version | Notes |
| --- | --- | --- |
| `Microsoft.OperationalInsights/workspaces` | `2023-09-01` | PerGB2018 SKU. `dailyQuota = 0` is mapped to `-1` (unlimited) per API contract |
| `Microsoft.OperationsManagement/solutions` | `2015-11-01-preview` | Legacy Sentinel onboarding via `SecurityInsights({lawName})` solution. Idempotent on re-run |
| `Microsoft.SecurityInsights/onboardingStates` | `2024-09-01` | Modern onboarding state required by newer SecurityInsights API versions for downstream operations to recognise the workspace as Sentinel-onboarded |
| `Microsoft.Insights/diagnosticSettings` (workspace) | `2021-05-01-preview` | Workspace audit + AllMetrics shipped to itself |
| `Microsoft.SecurityInsights/settings` (existing) | `2023-02-01-preview` | `SentinelHealth` settings reference (read-only — for diagnostic targeting) |
| `Microsoft.Insights/diagnosticSettings` (Sentinel Health) | `2021-05-01-preview` | Populates `SentinelHealth` and `SentinelAudit` tables |

### Outputs

| Output | Type | Description |
| --- | --- | --- |
| `sentinelResourceId` | string | Resource ID of the OMS solution resource |
| `logAnalyticsWorkspace` | object | `{ name, id, location, retentionInDays }` |

## Why two onboarding mechanisms?

Sentinel onboarding has historically used `Microsoft.OperationsManagement/solutions` with a `SecurityInsights({workspace})` solution name. This is the canonical Bicep/ARM idiom and remains idempotent on re-runs.

Newer API versions (`2024-09-01+`) of the SecurityInsights provider also expect a `Microsoft.SecurityInsights/onboardingStates/default` resource to be present on the workspace before downstream operations (some content templates, some metadata reads) will recognise the workspace as fully onboarded. Both resources can co-exist; the onboardingState declares the workspace's onboarding intent in the modern model, while the solution provides the legacy bootstrap.

The `dependsOn: [sentinel]` on the onboardingState ensures it deploys after the OMS solution so the workspace is in a consistent state at all times.

## Diagnostic settings

Two diagnostic settings ship at deploy time:

### Workspace self-diagnostics (`law-diagnostics`)

| Category | Enabled |
| --- | --- |
| `audit` (categoryGroup) | yes |
| `AllMetrics` | yes |

Sends management-plane activity (queries, writes, configuration changes) and platform metrics back into the same workspace. Useful for `LAQueryLogs` analysis, query-cost reporting, and self-monitoring queries.

### Sentinel Health diagnostics (`sentinel-health-diagnostics`)

| Category | Enabled |
| --- | --- |
| `allLogs` (categoryGroup) | yes |

Populates the `SentinelHealth` and `SentinelAudit` tables in the workspace. These power the built-in Sentinel Health workbook and any custom hunting queries that monitor connector / playbook / analytics-rule health.

The setting targets a `Microsoft.SecurityInsights/settings` resource named `SentinelHealth` declared as `existing` — the resource is auto-created by Sentinel onboarding, so the Bicep just references it without re-declaring.

## Optional playbook resource group

The pipeline can deploy playbooks (Logic Apps) to a separate resource group. To enable:

1. Add `playbookResourceGroup` to the [`sentinel-deployment` variable group](Pipelines.md#variable-group-sentinel-deployment) with the desired RG name.
2. The pipeline passes it through to `main.bicep` as the `playbookRgName` parameter.
3. Bicep creates the separate RG only when:
   - `playbookRgName` is non-empty, AND
   - `playbookRgName` differs from `rgName`

If those conditions aren't met, the conditional resource is skipped and playbooks land in the main Sentinel RG.

The deploy script ([`Scripts/Deploy-CustomContent.ps1`](../../Scripts/Deploy-CustomContent.ps1)) reads the same `playbookResourceGroup` variable and routes Logic App ARM deployments accordingly. See [Playbooks](../Content/Playbooks.md) for the deploy-side detail.

## Pipeline invocation

Stage 2 of `Sentinel-Deploy.yml` runs the equivalent of:

```bash
az deployment sub create \
    --location "$(sentinelRegion)" \
    --template-file Bicep/main.bicep \
    --parameters \
        rgLocation=$(sentinelRegion) \
        rgName=$(sentinelResourceGroup) \
        lawName=$(sentinelWorkspaceName) \
        dailyQuota=${{ parameters.dailyQuota }} \
        retentionInDays=${{ parameters.retentionInDays }} \
        totalRetentionInDays=${{ parameters.totalRetentionInDays }} \
        playbookRgName=$(playbookResourceGroup) \
        deploySentinel=true
```

Stage 1 first checks whether the resource group + workspace already exist, and skips Stage 2 entirely when they do — see [Pipelines](Pipelines.md) for the conditional logic.

`deploySentinel` defaults to `true` and is omitted by the ADO pipeline today (it relies on the default). The GitHub Actions workflow's Stage 1 runs a finer per-component probe and passes `deploySentinel=false` when Sentinel is already onboarded but other infrastructure (most commonly the optional playbook RG) is missing — this lets Bicep provision only the gap without re-attempting the non-idempotent `Microsoft.SecurityInsights/onboardingStates` resource. ADO porting is tracked under [`instructions/workflows.instructions.md`](../../.github/instructions/workflows.instructions.md) Hard rule 1 ("one-direction-first bug fixes").

## Settings configured outside Bicep

The following Sentinel settings are configured via REST API in the same Stage 2 pipeline step (after Bicep finishes), not by Bicep itself:

| Setting | API | Reason it's not in Bicep |
| --- | --- | --- |
| `EntityAnalytics` | `Microsoft.SecurityInsights/settings/EntityAnalytics` | Requires ETag round-trip; cleaner in PowerShell |
| `Ueba` | `Microsoft.SecurityInsights/settings/Ueba` | Same — ETag handling |
| `Anomalies` | `Microsoft.SecurityInsights/settings/Anomalies` | Same |
| `EyesOn` | `Microsoft.SecurityInsights/settings/EyesOn` | Same |

The pipeline GETs the current setting (to capture the ETag) and PUTs the new state with `If-Match`. See the inline `AzurePowerShell@5` task in `Sentinel-Deploy.yml` Stage 2.

## Limitations

- **Workspace SKU is hardcoded** to `PerGB2018`. Capacity Reservation tiers are not supported in this template — modify the SKU block in `sentinel.bicep` if needed.
- **Daily quota of 0 is a sentinel value**. Bicep maps `0` to the API's `-1` (unlimited). Setting an explicit `dailyQuota` of `1` is the smallest valid cap; values below 1 GB are rejected by the platform.
- **Total retention defaulting**: when `totalRetentionInDays = 0`, Bicep substitutes `retentionInDays`. To enable archive-tier retention, pass an explicit `totalRetentionInDays` greater than `retentionInDays`.
- **Sentinel feature settings** (Entity Analytics, UEBA, Anomalies, EyesOn) are configured outside Bicep — see the table above.
- **No role assignments**. RBAC for the deploy service principal is granted via [`Scripts/Setup-ServicePrincipal.ps1`](../../Scripts/Setup-ServicePrincipal.ps1) — see [Scripts](Scripts.md#setup-serviceprincipalps1).

## Related docs

- [Pipelines](Pipelines.md) — how Stage 2 runs Bicep and the post-Bicep settings step
- [Scripts](Scripts.md#setup-serviceprincipalps1) — service principal RBAC bootstrap
- [Playbooks](../Content/Playbooks.md) — how the optional playbook RG is consumed
- [DCR Watchlist](../Operations/DCR-Watchlist.md) — separate Bicep stack for the DCR-watchlist runbook (lives under `Automation/DCR-Watchlist/`, not this folder)

## Authoring with GitHub Copilot

Bicep templates don't have a dedicated path-scoped instruction
file (the convention bar is set by the templates themselves and
Microsoft's documentation); the repo-wide
[`.github/copilot-instructions.md`](../../.github/copilot-instructions.md)
covers commit-message + en-GB conventions.

Copilot tooling for Bicep:

- Agent `Sentinel-As-Code: Bicep Engineer` — owns Bicep IaC
  end-to-end. Adds resources, designs parameters, maintains the
  dual Sentinel onboarding pattern, manages the test-workspace
  template at `Bicep/test/main.bicep`. Knows the local validation
  tools (`az bicep build`, `az deployment sub validate`).
- Agent `Sentinel-As-Code: Pipeline Engineer` — for the
  `deploy-infrastructure` workflow stage that consumes the
  template and any new parameters surfaced through the pipeline.
- Agent `Sentinel-As-Code: Security Reviewer` — for RBAC, Key
  Vault, network rules, and any high-privilege resource additions.

See [GitHub Copilot setup](../Development/GitHub-Copilot.md) for the full layout.
