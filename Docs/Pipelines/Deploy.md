# Deploy Pipeline

The main end-to-end deployment pipeline. It provisions Sentinel
infrastructure via Bicep (only when needed), onboards Content Hub
solutions, deploys the repository's custom content (parsers, detections,
watchlists, playbooks, workbooks, hunting queries, automation rules,
summary rules), and deploys Defender XDR custom detections via the Graph
Security API.

This page documents the CI/CD wiring. For what the invoked scripts
actually do, see [Scripts.md](../Deploy/Scripts.md); for the Bicep templates the
infrastructure stage deploys, see [Bicep.md](../Infra/Bicep.md).

Both CI systems run the same five ordered stages against the same
deployment scripts:

| Stage | GitHub job (`.github/workflows/sentinel-deploy.yml`) | ADO stage (`Pipelines/Sentinel-Deploy.yml`) | Script invoked |
| --- | --- | --- | --- |
| 1. Check infrastructure | `check-infrastructure` | `CheckInfrastructure` | (inline probe) |
| 2. Deploy infrastructure | `deploy-infrastructure` | `DeployInfrastructure` | `Infra/sentinel/main.bicep` |
| 3. Deploy Content Hub | `deploy-content-hub` | `DeployContentHub` | `Deploy-SentinelContentHub.ps1` |
| 4. Deploy custom content | `deploy-custom-content` | `DeployCustomContent` | `Deploy-CustomContent.ps1` |
| 5. Deploy Defender detections | `deploy-defender-detections` | `DeployDefenderDetections` | `Deploy-DefenderDetections.ps1` |

The pipeline supports **greenfield deployments**: you can start from an
empty subscription and it will create everything needed.

## Files

- GitHub workflow: [`.github/workflows/sentinel-deploy.yml`](../../.github/workflows/sentinel-deploy.yml)
- ADO pipeline: [`Pipelines/Sentinel-Deploy.yml`](../../Pipelines/Sentinel-Deploy.yml)

## Triggers

| | GitHub (`sentinel-deploy.yml`) | ADO (`Sentinel-Deploy.yml`) |
| --- | --- | --- |
| Manual | `workflow_dispatch` (with the full input surface below) | Queue-time run (`trigger: none` disables branch CI triggers) |
| Scheduled | `schedule` cron `0 4 * * 1` (weekly Monday 04:00 UTC) | `schedules` cron `0 4 * * 1` (weekly Monday 04:00 UTC, `main` only, `always: false`) |
| Push / PR | None | None |

There is no push or pull-request trigger on either side. The scheduled
run uses the parameter/input defaults; the cron trigger passes no
`inputs.*` on GitHub, so the deploy jobs fall back to their default
values (for example `skip_custom_content_types` falls back to
`community-detections`, matching the `workflow_dispatch` default).

The ADO schedule sets `always: false`, so a scheduled run is skipped when
`main` has not changed since the last successful scheduled run.

## Authentication

Both systems authenticate with **workload identity federation (OIDC)** -
no stored client secret. Per-job tokens are minted with a short TTL.

**GitHub** uses the local composite action
[`./.github/actions/azure-login-oidc`](../../.github/actions/azure-login-oidc/action.yml),
which wraps `Azure/login@v3`. Every job that touches Azure re-runs it as
its own step (composite actions run inside a job's step list, so the
login does not persist across jobs). The parent workflow declares the
required token permissions once:

```yaml
permissions:
  id-token: write
  contents: read
```

Because the composite action lives under `.github/actions/` in this repo,
even the `check-infrastructure` job (which reads no repository files)
still runs `actions/checkout` first so the runner can resolve the local
action from disk.

**ADO** uses an ARM service connection named `sc-sentinel-as-code` (the
`serviceConnection` pipeline variable). Configure it for workload
identity federation rather than a stored secret. Full setup:
[ADO OIDC Setup](../Deploy/ADO-OIDC-Setup.md).

> **Critical ADO prerequisite**: ADO will not save the service connection
> unless the service principal can already see the subscription (at least
> **Reader**). `Deploy/setup/Setup-ServicePrincipal.ps1` grants
> Contributor at subscription scope (which implies Reader), so the
> standard bootstrap satisfies this. See
> [Scripts.md](../Deploy/Scripts.md#setup-serviceprincipalps1).

## Secrets, variables, and the variable group

### GitHub

Configure under **Settings > Secrets and variables > Actions**.

| Kind | Name | Purpose |
| --- | --- | --- |
| Secret | `AZURE_CLIENT_ID` | Service principal application (client) ID |
| Secret | `AZURE_TENANT_ID` | Entra ID tenant ID |
| Secret | `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| Variable | `SENTINEL_RESOURCE_GROUP` | Resource group name (mapped to the `RESOURCE_GROUP` workflow env var) |
| Variable | `SENTINEL_WORKSPACE_NAME` | Log Analytics workspace name (mapped to `WORKSPACE_NAME`) |
| Variable | `SENTINEL_REGION` | Azure region, e.g. `uksouth` (mapped to `REGION`) |
| Variable | `PLAYBOOK_RESOURCE_GROUP` | Optional. Separate resource group for playbooks; defaults to the Sentinel RG when empty |

The workflow also pins `YAML_VERSION: "0.4.12"` at the `env` level so a
PSGallery release of `powershell-yaml` cannot silently change parser
behaviour on a scheduled deploy. Bumping the pin is a one-line PR.

### ADO

The pipeline links a variable group named **`sentinel-deployment`**
(create it under **Pipelines > Library**):

| Variable | Required | Description | Example |
| --- | --- | --- | --- |
| `azureSubscriptionId` | Yes | Azure subscription ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `sentinelResourceGroup` | Yes | Desired resource group name | `rg-sentinel-prod` |
| `sentinelWorkspaceName` | Yes | Desired Log Analytics workspace name | `law-sentinel-prod` |
| `sentinelRegion` | Yes | Azure region to deploy into | `uksouth` |
| `playbookResourceGroup` | No | Resource group for playbooks (defaults to `sentinelResourceGroup`) | `rg-playbooks-prod` |

Two further pipeline-level variables are set inline: `serviceConnection`
(`sc-sentinel-as-code`) and `SuppressAzurePowerShellBreakingChangeWarnings`
(`true`). The pipeline also declares a block of compile-time `flag*`
variables (`${{ if eq(...) }}`) that map each boolean parameter to either
the corresponding switch name (for example `-SkipWorkbooks`) or an empty
string. The deploy stages read those strings to decide which switches to
splat onto the script call.

> The ADO pipeline treats an unset optional variable as the literal
> `$(playbookResourceGroup)` string and normalises it to empty before use,
> so leaving `playbookResourceGroup` out of the variable group is safe.

## Permissions the service principal needs

| Role / permission | Scope | Purpose |
| --- | --- | --- |
| **Contributor** | Subscription | Resource group, workspace, Bicep deployments, Sentinel content, summary rules |
| **User Access Administrator** (ABAC-conditioned) | Subscription | Playbook managed-identity role assignments (restricted to 5 roles) |
| **Security Administrator** (Entra ID) | Tenant | UEBA and Entity Analytics settings (optional - can be set manually in the portal instead) |
| **CustomDetection.ReadWrite.All** (Microsoft Graph) | Tenant | Defender XDR custom detections (Stage 5) |

Run `Deploy/setup/Setup-ServicePrincipal.ps1` once to grant these; after
that the pipeline is autonomous. See
[Scripts.md](../Deploy/Scripts.md#setup-serviceprincipalps1) for the exact
parameters and grant semantics.

## Inputs / parameters

Both systems expose the same deployment surface; only the shape differs.
Defaults are identical across GitHub and ADO unless noted.

### Stage toggles

| GitHub input | ADO parameter | Type | Default | Effect |
| --- | --- | --- | --- | --- |
| `deploy_infrastructure` | `deployInfrastructure` | boolean | `true` | Run Stages 1-2 (Bicep) |
| `deploy_content_hub` | `deployContentHub` | boolean | `true` | Run Stage 3 |
| `deploy_custom_content` | `deployCustomContent` | boolean | `true` | Run Stage 4 |
| `deploy_defender_detections` | `deployDefenderDetections` | boolean | `true` | Run Stage 5 |

### Infrastructure (Stage 2)

| GitHub input | ADO parameter | Type | Default | Description |
| --- | --- | --- | --- | --- |
| `daily_quota` | `dailyQuota` | number | `0` | Daily ingestion quota in GB (`0` = unlimited) |
| `retention_in_days` | `retentionInDays` | number | `90` | Interactive retention in days (30-730) |
| `total_retention_in_days` | `totalRetentionInDays` | number | `0` | Total retention incl. archive (`0` = same as interactive) |

### Content Hub (Stage 3)

| GitHub input | ADO parameter | Type | Default | Description |
| --- | --- | --- | --- | --- |
| `solutions` | `solutions` | string | 26-solution list (below) | Comma-separated Content Hub solution names |
| `severities_to_include` | `severitiesToInclude` | string | `High,Medium,Low,Informational` | Analytics rule severities to deploy |
| `disable_rules` | `disableRules` | boolean | `true` | Deploy analytics rules disabled |
| `protect_customised_rules` | `protectCustomisedRules` | boolean | `true` | Skip overwriting locally modified rules |
| `skip_analytics_rules` | `skipAnalyticsRules` | boolean | `false` | Skip analytics rule deployment |
| `skip_workbooks` | `skipWorkbooks` | boolean | `false` | Skip workbook deployment |
| `skip_automation_rules` | `skipAutomationRules` | boolean | `false` | Skip automation rule deployment |
| `skip_hunting_queries` | `skipHuntingQueries` | boolean | `false` | Skip hunting query deployment |
| `force_solution_update` | `forceSolutionUpdate` | boolean | `false` | Force solution update even if current |
| `force_content_deployment` | `forceContentDeployment` | boolean | `false` | Force content redeployment even if current |

The default `solutions` value is a **26-solution** list, identical in
both files: Analytics Health & Audit, Azure Activity, Azure DevOps
Auditing, Azure Key Vault, Azure Logic Apps, Azure Network Security
Groups, Azure Resource Graph, Azure Storage, Common Event Format, Data
Collection Rule Toolkit, Microsoft 365, Microsoft Defender for Cloud,
Microsoft Defender for Cloud Apps, Microsoft Defender for Endpoint,
Microsoft Defender for Identity, Microsoft Defender Threat Intelligence,
Microsoft Defender XDR, Microsoft Entra ID, Microsoft Sentinel
Optimization Workbook, SOC Handbook, Summary Rules Workbook, Syslog,
Threat Intelligence (NEW), Windows Security Events, Windows Server DNS,
Workspace Usage Report. Override at queue time to target a narrower set.

### Custom content (Stage 4)

This is the one place the two input surfaces genuinely diverge.

ADO exposes **nine individual booleans**, each defaulting `false` except
`skipCommunityDetections` which defaults `true`:

| ADO parameter | Default | Switch passed to `Deploy-CustomContent.ps1` |
| --- | --- | --- |
| `skipCustomParsers` | `false` | `-SkipParsers` |
| `skipCustomDetections` | `false` | `-SkipDetections` |
| `skipCommunityDetections` | `true` | `-SkipCommunityDetections` |
| `skipCustomWatchlists` | `false` | `-SkipWatchlists` |
| `skipCustomPlaybooks` | `false` | `-SkipPlaybooks` |
| `skipCustomWorkbooks` | `false` | `-SkipWorkbooks` |
| `skipCustomHuntingQueries` | `false` | `-SkipHuntingQueries` |
| `skipCustomAutomationRules` | `false` | `-SkipAutomationRules` |
| `skipCustomSummaryRules` | `false` | `-SkipSummaryRules` |
| `smartDeployment` | `true` | `-SmartDeployment` |

`workflow_dispatch` caps at 25 inputs, so GitHub cannot expose that many
separate booleans. It collapses the nine skip toggles into a single
comma-separated string input:

| GitHub input | Default | Accepted values (comma-separated subset) |
| --- | --- | --- |
| `skip_custom_content_types` | `community-detections` | `parsers, detections, community-detections, watchlists, playbooks, workbooks, hunting-queries, automation-rules, summary-rules` |
| `smart_deployment` | `true` | (boolean) |

The `deploy-custom-content` job splits that string, trims and lowercases
each token, and sets the matching `-Skip*` script parameter. The net
effect on `Deploy-CustomContent.ps1` is identical to ADO: community
detections are excluded unless you opt in, and every other type deploys
by default.

> **Smart deployment**: both systems default the flag on and pass
> `-SmartDeployment`. The underlying `Deploy-CustomContent.ps1` switch is
> **opt-in** and defaults to a full deploy when the flag is not passed;
> the pipeline is what turns it on. See
> [Scripts.md](../Deploy/Scripts.md) for what smart deployment actually skips.

### Defender detections (Stage 5)

No additional parameters. Stage 5 is gated solely by the
`deploy_defender_detections` / `deployDefenderDetections` toggle and the
dry-run flag. Rules are read from `Content/DefenderCustomDetections/`.

### General

| GitHub input | ADO parameter | Type | Default | Description |
| --- | --- | --- | --- | --- |
| `what_if` | `whatIf` | boolean | `false` | Dry run: preview changes without applying (passed to every script as `-WhatIf`) |

## Stages and steps, in order

### Stage 1 - Check infrastructure

Runs when the infrastructure toggle is not `false`. Probes Azure for the
resource group, the Log Analytics workspace, and the optional playbook
resource group, then decides whether Bicep needs to run.

**GitHub** (`check-infrastructure`, `Azure/powershell@v3`) exports two
job outputs and carries richer dual-onboarding logic:

- `bicep_needed` - `true` if any component (RG, workspace, onboarding, or
  the optional playbook RG) is missing.
- `deploy_sentinel` - whether the Sentinel module should run inside Bicep.
  It inspects **both** onboarding resources: the legacy
  `Microsoft.OperationsManagement/solutions/SecurityInsights(<workspace>)`
  and the modern
  `Microsoft.SecurityInsights/onboardingStates/default`. A three-case
  truth table decides the outcome. Because `onboardingStates` is
  non-idempotent (re-deploying it returns Conflict) while the OMS solution
  is idempotent, the "OMS present, state missing" case is auto-repaired by
  re-running the Sentinel module, whereas the inverse "state survived, OMS
  deleted out of band" case is **unrecoverable** and the job aborts with a
  remediation message. Background:
  [Bicep.md](../Infra/Bicep.md) "Why two onboarding mechanisms?".

**ADO** (`CheckResources`, `AzurePowerShell@5`) performs the simpler
existence probe: RG, workspace, and optional playbook RG. It sets a single
output variable `RESOURCES_EXIST` (`true`/`false`), and Stage 2 runs when
that is `false`.

### Stage 2 - Deploy infrastructure (Bicep)

Runs only when Stage 1 signals that Bicep is needed
(`bicep_needed == 'true'` on GitHub; `RESOURCES_EXIST == 'false'` on ADO).
Steps, in order:

1. **Checkout** the repository.
2. **Azure login (OIDC)**.
3. **Register resource providers** - `az provider register` for
   `Microsoft.OperationsManagement` and `Microsoft.SecurityInsights`
   (`Azure/cli@v3` on GitHub, `AzureCLI@2` on ADO).
4. **Deploy Bicep** - `az deployment sub create` (subscription-scoped)
   against `Infra/sentinel/main.bicep`, passing `rgLocation`, `rgName`,
   `lawName`, `dailyQuota`, `retentionInDays`, `totalRetentionInDays`,
   and the optional `playbookRgName`. GitHub additionally passes
   `deploySentinel` from the Stage 1 `deploy_sentinel` output. Both
   systems defensively strip whitespace from the optional playbook RG
   variable before the ARM call. See [Bicep.md](../Infra/Bicep.md) for
   what the template provisions.
5. **Wait for workspace indexing** - a 60-second sleep so a freshly
   created workspace becomes queryable.
6. **Configure Sentinel settings** - a REST loop
   (`api-version=2024-01-01-preview`) that PUTs four settings with
   automatic ETag handling: `Anomalies`, `EyesOn`, `EntityAnalytics`
   (Entra ID provider), and `Ueba` (AuditLogs, AzureActivity, SigninLogs,
   SecurityEvent). Failures are logged as warnings and do not fail the
   stage, so a tenant that cannot grant Security Administrator to the SP
   still completes the rest of the deploy.

### Stage 3 - Deploy Content Hub

Runs when the Content Hub toggle is not `false` **and** Stage 2 either
succeeded or was skipped (both systems use `always()` / `Succeeded, Skipped`
gating so a skipped Bicep stage does not block content). Timeout: 120
minutes.

Steps: checkout, Azure login, then invoke
`Deploy/content/Deploy-SentinelContentHub.ps1` with a splatted parameter
hashtable. `SubscriptionId`, `ResourceGroup`, `Workspace`, `Region`,
`Solutions`, and `SeveritiesToInclude` are always passed; the boolean
toggles (`DisableRules`, `ProtectCustomisedRules`, the `Skip*` switches,
`ForceSolutionUpdate`, `ForceContentDeployment`, `WhatIf`) are added only
when their input/parameter is set. See [Scripts.md](../Deploy/Scripts.md) for
what the script does.

### Stage 4 - Deploy custom content

Runs when the custom-content toggle is not `false` and Stage 3 succeeded
or was skipped. Timeout: 60 minutes. Steps, in order:

1. **Checkout** with `fetch-depth: 2` - smart deployment needs the parent
   commit for its `git diff`.
2. **Restore deployment state** - the state file from the previous run.
   GitHub uses `actions/cache/restore` keyed on the workspace name; ADO
   uses `DownloadPipelineArtifact@2` (`latestFromBranch`). Both are
   `continue-on-error`, so a first run with no prior state proceeds.
3. **Set up PowerShell modules** - installs `powershell-yaml` only
   (GitHub uses the [`setup-pwsh-modules`](../../.github/actions/setup-pwsh-modules/action.yml)
   composite with `install-pester: 'false'` and the pinned
   `YAML_VERSION`; ADO installs it inline).
4. **Verify dependency manifest is current** - runs
   `Tools/Build-DependencyManifest.ps1 -Mode Verify` and fails the stage
   if `dependencies.json` is out of sync with current content. This is the
   same drift gate the PR-validation workflow enforces on every PR to main,
   repeated here so a scheduled deploy from `main` cannot race a
   non-deploy commit that bypassed the PR gate. See
   [Dependency Manifest](../Tools/Dependency-Manifest.md).
5. **Azure login (OIDC)**.
6. **Deploy custom content** - invokes
   `Deploy/content/Deploy-CustomContent.ps1` with the base parameters
   plus the resolved `-Skip*`, `-SmartDeployment`, and `-WhatIf` switches
   (GitHub derives the skips by parsing `skip_custom_content_types`; ADO
   reads its compile-time `flag*` variables). The optional playbook RG is
   passed as `-PlaybookResourceGroup` when set.
7. **Save deployment state** - always runs (`if: always()` /
   `condition: always()`, both `continue-on-error`). GitHub caches
   `.deployment-state.json`; ADO publishes `deployment-state.json` as a
   pipeline artefact named `deployment-state`.

`Deploy-CustomContent.ps1` deploys eight content types in a fixed order:
parsers -> watchlists -> detections -> hunting queries -> playbooks ->
workbooks -> automation rules -> summary rules. The `Test-ContentDependencies`
pre-flight gate and the smart-deployment skip apply to every content type
(missing dependencies deploy detections disabled and skip other types).
See [Scripts.md](../Deploy/Scripts.md) for the full ordering and gate behaviour.

> **Deployment-state filename divergence**: GitHub caches the state file
> as `.deployment-state.json` (leading dot); ADO publishes it as
> `deployment-state.json` (no dot). Neither is canonical - they simply
> differ per CI system.

### Stage 5 - Deploy Defender XDR custom detections

Runs when the Defender toggle is not `false` and Stage 4 succeeded or was
skipped. Timeout: 30 minutes. Steps: checkout, Azure login, set up
`powershell-yaml`, then invoke
`Deploy/content/Deploy-DefenderDetections.ps1` (only `BasePath` and the
optional `-WhatIf` are passed). The script reads YAML from
`Content/DefenderCustomDetections/` and deploys to Defender XDR via the
Microsoft Graph Security API (`beta`), creating or updating rules matched
by `displayName`. This stage needs the `CustomDetection.ReadWrite.All`
Graph application permission with admin consent. See
[Scripts.md](../Deploy/Scripts.md) for details.

## Artefacts and outputs

- **Stage 1 job outputs (GitHub)**: `bicep_needed` and `deploy_sentinel`,
  consumed by the Stage 2 `if:` gate and the `deploySentinel` Bicep
  parameter. ADO's equivalent is the single `RESOURCES_EXIST` output
  variable.
- **Deployment state**: `.deployment-state.json` (GitHub Actions cache) /
  `deployment-state.json` (ADO pipeline artefact `deployment-state`),
  carried between runs so smart deployment can retry previously failed
  items.
- There are no other published build artefacts; the pipeline's real output
  is the deployed Sentinel and Defender content.

## GitHub <-> ADO mapping and asymmetry

Both files run the same five stages against the same three deployment
scripts with identical stage gating (`always()` / `Succeeded, Skipped`)
and the same weekly cron. The differences are:

- **Input surface**: ADO exposes nine individual custom-content skip
  booleans; GitHub collapses them into one comma-separated
  `skip_custom_content_types` input to stay under the
  `workflow_dispatch` 25-input cap. Same downstream script behaviour.
- **Stage 1 depth**: GitHub carries dual-onboarding logic (OMS solution +
  onboarding state) and can abort on an unrecoverable partial-onboarding
  state; ADO does a simpler existence probe.
- **Auth plumbing**: GitHub uses the `azure-login-oidc` composite action
  per job; ADO uses the `sc-sentinel-as-code` service connection.
- **State transport**: GitHub Actions cache vs ADO pipeline artefact, with
  the dot/no-dot filename divergence noted above.

This Deploy pipeline is one of the paired pipelines: it has both a GitHub
workflow and an ADO pipeline. For the full inventory of pipelines and
which ones are single-platform, see the
[Pipelines index](README.md).

## Usage

Both systems run with defaults for a full deploy; override toggles at
queue time for narrower runs.

- **Full deploy** (infra if needed + all content): run with defaults.
- **Content only**: set the infrastructure toggle to `false`.
- **Specific solutions, skip workbooks**: set `solutions` to your subset
  and the workbook skip toggle to `true`.
- **Dry run**: set the dry-run flag (`what_if` / `whatIf`) to `true` - every
  script receives `-WhatIf`.
- **Custom content only**: set the infrastructure, Content Hub, and
  Defender toggles to `false`.
- **Defender detections only**: set the infrastructure, Content Hub, and
  custom-content toggles to `false`.
- **Playbooks to a separate RG**: set `PLAYBOOK_RESOURCE_GROUP` (GitHub) /
  `playbookResourceGroup` (ADO variable group).
- **Force full redeployment**: set `force_solution_update` /
  `forceSolutionUpdate` and `force_content_deployment` /
  `forceContentDeployment` to `true`.

## Related

- [Scripts.md](../Deploy/Scripts.md) - what the invoked deployment scripts do.
- [Bicep.md](../Infra/Bicep.md) - the infrastructure templates and the
  dual-onboarding design.
- [ADO OIDC Setup](../Deploy/ADO-OIDC-Setup.md) - wiring the service connection
  for workload identity federation.
- [Dependency Manifest](../Tools/Dependency-Manifest.md) - the
  `dependencies.json` drift gate reused in Stage 4.
- [Pipelines index](README.md) - the full pipeline inventory and
  GitHub/ADO parity map.
