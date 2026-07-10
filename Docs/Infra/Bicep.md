# Bicep Infrastructure

Subscription-scoped Bicep templates that provision the foundational
Sentinel infrastructure: the resource group, Log Analytics workspace,
Sentinel onboarding, diagnostic settings, and an optional separate
resource group for playbooks.

| File | Scope | Purpose |
| --- | --- | --- |
| [`Infra/sentinel/main.bicep`](../../Infra/sentinel/main.bicep) | Subscription | Orchestrator — creates resource groups and invokes the Sentinel module |
| [`Infra/sentinel/sentinel.bicep`](../../Infra/sentinel/sentinel.bicep) | Resource group | Workspace, Sentinel onboarding, diagnostic settings |

These are invoked by Stage 2 of [`Pipelines/Sentinel-Deploy.yml`](../../Pipelines/Sentinel-Deploy.yml) — see [Pipelines](../Pipelines/README.md). Sentinel feature settings that are not exposed by Bicep (Entity Analytics, UEBA, Anomalies, EyesOn) are configured via REST in a follow-on pipeline step in the same stage.

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
| `sentinelModuleEnabled` | bool | Echoes the `deploySentinel` input parameter — reports whether the Sentinel module was *enabled* on this run, not whether Sentinel was successfully *deployed*. Consumers should branch on this before reading `sentinelResourceId` / `logAnalyticsWorkspace`; for an end-to-end "Sentinel is deployed" signal, combine this flag with a non-empty `sentinelResourceId` |
| `sentinelResourceId` | string | Bubbled up from the Sentinel module — the OMS solution resource ID. Collapses to `''` when `deploySentinel = false` (module skipped); use `sentinelModuleEnabled` to distinguish "module skipped" from "module ran and produced an empty string" |
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

## Infra/test-workspace/main.bicep

A third, separate Bicep stack used only by PR validation, not by Stage 2 of `Sentinel-Deploy.yml`. [`Infra/test-workspace/main.bicep`](../../Infra/test-workspace/main.bicep) is a resource-group-scoped template that provisions a minimal Free-tier Sentinel-enabled workspace, deployed once by hand and then reused as the target for the `arm-validate` job's `Test-AzResourceGroupDeployment` calls in `pr-validation.yml` (see [PR Validation Setup](../Deploy/PR-Validation-Setup.md)). `Test-AzResourceGroupDeployment` is a template-validation cmdlet, not a `-WhatIf` execution; it validates every changed Playbook ARM template against this real workspace without deploying anything.

### Parameters

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `location` | string | `resourceGroup().location` | Azure region for the test workspace |
| `workspaceName` | string | `law-sentinel-pr-test` | 4-63 chars. Name of the test Log Analytics workspace |
| `tags` | object | `{ Purpose: 'PR-Validation-Test', ManagedBy: 'Sentinel-As-Code' }` | Resource tags |

Retention (`30` days) and the daily ingestion cap (`1` GB) are not parameterised: they are hardcoded literals on the workspace resource, kept deliberately small since the workspace never ingests real data.

### Resources created

| Resource | API version | Notes |
| --- | --- | --- |
| `Microsoft.OperationalInsights/workspaces` | `2023-09-01` | PerGB2018 SKU, `retentionInDays: 30`, `workspaceCapping.dailyQuotaGb: 1`, public network access enabled for both ingestion and query |
| `Microsoft.SecurityInsights/onboardingStates` | `2024-09-01` | `default` onboarding state, scoped to the workspace (the same modern onboarding mechanism used by `sentinel.bicep`) |

### Outputs

| Output | Type | Description |
| --- | --- | --- |
| `workspaceId` | string | Resource ID of the workspace (same value as `workspaceResourceId`) |
| `workspaceName` | string | Name of the workspace |
| `workspaceResourceId` | string | Resource ID of the workspace |

## Why two onboarding mechanisms?

Sentinel onboarding has historically used `Microsoft.OperationsManagement/solutions` with a `SecurityInsights({workspace})` solution name. This is the canonical Bicep/ARM idiom and remains idempotent on re-runs.

Newer API versions (`2024-09-01+`) of the SecurityInsights provider also expect a `Microsoft.SecurityInsights/onboardingStates/default` resource to be present on the workspace before downstream operations (some content templates, some metadata reads) will recognise the workspace as fully onboarded. Both resources can co-exist; the onboardingState declares the workspace's onboarding intent in the modern model, while the solution provides the legacy bootstrap.

The `dependsOn: [sentinel]` on the onboardingState ensures it deploys after the OMS solution so the workspace is in a consistent state at all times. The same `dependsOn: [sentinel]` is also declared on both diagnostic-settings resources (`law-diagnostics` and `sentinel-health-diagnostics`), so the full deploy order within `sentinel.bicep` is: workspace, then OMS solution, then (in parallel, once the solution exists) the onboardingState and both diagnostic settings.

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

1. Add `playbookResourceGroup` to the [`sentinel-deployment` variable group](../Pipelines/README.md#variable-group-sentinel-deployment) with the desired RG name.
2. The pipeline passes it through to `main.bicep` as the `playbookRgName` parameter.
3. Bicep creates the separate RG only when:
   - `playbookRgName` is non-empty, AND
   - `playbookRgName` differs from `rgName`

If those conditions aren't met, the conditional resource is skipped and playbooks land in the main Sentinel RG.

The deploy script ([`Deploy/content/Deploy-CustomContent.ps1`](../../Deploy/content/Deploy-CustomContent.ps1)) reads the same `playbookResourceGroup` variable and routes Logic App ARM deployments accordingly. See [Playbooks](../Content/Playbooks.md) for the deploy-side detail.

## Pipeline invocation

Stage 2 of `Sentinel-Deploy.yml` runs the equivalent of:

```bash
az deployment sub create \
    --location "$(sentinelRegion)" \
    --template-file Infra/sentinel/main.bicep \
    --parameters \
        rgLocation=$(sentinelRegion) \
        rgName=$(sentinelResourceGroup) \
        lawName=$(sentinelWorkspaceName) \
        dailyQuota=${{ parameters.dailyQuota }} \
        retentionInDays=${{ parameters.retentionInDays }} \
        totalRetentionInDays=${{ parameters.totalRetentionInDays }}
        # playbookRgName=... is appended only when the guard below is met
```

`playbookRgName` is **not** an unconditional part of the parameter list: the pipeline task builds the `--parameters` string incrementally and only appends `playbookRgName=$PLAYBOOK_RG` when `$PLAYBOOK_RG` is non-empty and differs from `$(sentinelResourceGroup)`. Before that check, the task also treats ADO's unexpanded literal `$(playbookResourceGroup)` (the placeholder text itself, when the variable was never set) as empty, so an unset variable group value does not accidentally pass a literal `$(playbookResourceGroup)` string through to Bicep.

`deploySentinel` is intentionally omitted from this ADO invocation — see the paragraph below for the asymmetric handling between platforms.

Stage 1 first checks for existing infrastructure and skips Stage 2 entirely when everything required is already present — see [Pipelines](../Pipelines/README.md) for the conditional logic. The two pipelines differ in probe granularity:

- **ADO** checks the resource group and workspace only.
- **GitHub Actions** additionally probes both Sentinel onboarding resources (`Microsoft.OperationsManagement/solutions` *and* `Microsoft.SecurityInsights/onboardingStates/default`) and the optional separate playbook RG. When Sentinel is fully onboarded but the playbook RG is missing, GH passes `deploySentinel=false` to Bicep so the Sentinel module is skipped and only the playbook RG is provisioned.

`deploySentinel` defaults to `true` and is omitted by the ADO pipeline today (it relies on the default). The GitHub Actions workflow's Stage 1 runs a finer per-component probe and passes `deploySentinel=false` when Sentinel is already onboarded but other infrastructure (most commonly the optional playbook RG) is missing — this lets Bicep provision only the gap without re-attempting the non-idempotent `Microsoft.SecurityInsights/onboardingStates` resource. ADO porting is allowed per [`instructions/workflows.instructions.md`](../../.github/instructions/workflows.instructions.md) Hard rule 1 ("one-direction-first bug fixes").

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
- **No role assignments**. RBAC for the deploy service principal is granted via [`Deploy/setup/Setup-ServicePrincipal.ps1`](../../Deploy/setup/Setup-ServicePrincipal.ps1) — see [Scripts](../Deploy/Scripts.md#setup-serviceprincipalps1).

## Related docs

- [Pipelines](../Pipelines/README.md) — how Stage 2 runs Bicep and the post-Bicep settings step
- [Scripts](../Deploy/Scripts.md#setup-serviceprincipalps1) — service principal RBAC bootstrap
- [Playbooks](../Content/Playbooks.md) — how the optional playbook RG is consumed
- [DCR Watchlist](../Tools/DCR-Watchlist.md) — separate Bicep stack for the DCR-watchlist runbook (Bicep lives under `Infra/dcr-watchlist/` (runbook + permissions scripts under `Tools/` and `Deploy/`), not this folder)

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
  template at `Infra/test-workspace/main.bicep`. Knows the local validation
  tools (`az bicep build`, `az deployment sub validate`).
- Agent `Sentinel-As-Code: Pipeline Engineer` — for the
  `deploy-infrastructure` workflow stage that consumes the
  template and any new parameters surfaced through the pipeline.
- Agent `Sentinel-As-Code: Security Reviewer` — for RBAC, Key
  Vault, network rules, and any high-privilege resource additions.

See [GitHub Copilot setup](../GitHub/GitHub-Copilot.md) for the full layout.
