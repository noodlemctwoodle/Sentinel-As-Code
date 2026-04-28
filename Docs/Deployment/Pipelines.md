# Pipelines

Azure DevOps pipelines that drive infrastructure provisioning, content
deployment, and operational tooling.

| Pipeline | Purpose | Schedule |
| --- | --- | --- |
| [`Pipelines/Sentinel-Deploy.yml`](../../Pipelines/Sentinel-Deploy.yml) | End-to-end deploy: Bicep infra + Content Hub + custom content + Defender XDR | Weekly, Mon 04:00 UTC |
| [`Pipelines/Sentinel-Drift-Detect.yml`](../../Pipelines/Sentinel-Drift-Detect.yml) | Detect rules edited in the portal, auto-PR Custom drift back into the repo | Daily, 06:00 UTC. See [Sentinel Drift Detection](../Operations/Sentinel-Drift-Detection.md) |
| [`Pipelines/DCR-Watchlist-Deploy.yml`](../../Pipelines/DCR-Watchlist-Deploy.yml) | Deploy the DCR-watchlist sync runbook | On change to `Automation/DCR-Watchlist/**`. See [DCR Watchlist](../Operations/DCR-Watchlist.md) |

## Sentinel-Deploy.yml

Azure DevOps pipeline for provisioning Microsoft Sentinel infrastructure via Bicep, deploying Content Hub solutions and their associated content, deploying custom Sentinel content (detections, watchlists, playbooks, workbooks, hunting queries, automation rules, summary rules), and deploying Defender XDR custom detection rules via the Graph Security API.

### Pipeline Stages

```
Stage 1: Check Existing Infrastructure
  └─ Checks if Resource Group, Log Analytics Workspace, and optional Playbook
     Resource Group already exist
  └─ Handles greenfield (nothing exists) through to existing environments
  └─ If any required resource is missing, triggers Bicep deployment

Stage 2: Deploy Sentinel Infrastructure (Bicep)
  ├─ Registers required resource providers (Microsoft.OperationsManagement,
  │   Microsoft.SecurityInsights)
  ├─ Provisions Resource Group (and optional Playbook Resource Group),
  │   Log Analytics Workspace, Sentinel onboarding
  ├─ Configures Sentinel settings via REST API (Entity Analytics, UEBA,
  │   Anomalies, EyesOn) with automatic ETag handling
  ├─ Waits 60s for workspace indexing on new deployments
  └─ Skipped if workspace already exists or deployInfrastructure is false

Stage 3: Deploy Sentinel Content Hub
  └─ Deploys solutions, analytics rules, workbooks, automation rules, hunting queries
  └─ Runs regardless of whether infrastructure was deployed or already existed

Stage 4: Deploy Custom Content
  ├─ Installs powershell-yaml module
  ├─ Loads sentinel-deployment.config for smart deployment configuration
  ├─ Loads dependencies.json for content dependency validation
  └─ Deploys custom content in order: KQL parsers (YAML) → watchlists (JSON+CSV)
     → detections (YAML, disabled if dependencies missing) → hunting queries (YAML)
     → playbooks (ARM, module-first ordering) → workbooks (gallery JSON) →
     automation rules (JSON) → summary rules (JSON)
  ├─ Uses git diff for smart deployment (skip unchanged files when enabled)
  ├─ Tracks deployment outcomes in .deployment-state.json (persisted as
  │   pipeline artifact) — automatically retries previously failed items
  ├─ Validates dependencies before deployment (pre-flight checks)
  ├─ Supports deploying playbooks to a separate resource group
  └─ Runs after Content Hub stage succeeds or is skipped

Stage 5: Deploy Defender XDR Custom Detections
  ├─ Installs powershell-yaml module
  └─ Deploys custom detection rules to Defender XDR via Microsoft Graph
     Security API (beta) from DefenderCustomDetections/ YAML files
  └─ Acquires Graph token (separate from ARM token)
  └─ Creates new rules or updates existing rules (matched by displayName)
  └─ Runs after Custom Content stage succeeds or is skipped
```

The pipeline supports **greenfield deployments** — you can start from an empty subscription and the pipeline will create everything needed.

### Trigger

- **Manual**: Run on demand from Azure DevOps
- **Scheduled**: Weekly on Monday at 04:00 UTC (main branch only)

### Prerequisites

- Azure Service Connection with the following roles:

| Role | Scope | Purpose |
|------|-------|---------|
| **Contributor** | Subscription | Resource group, workspace, Bicep deployments, Sentinel content, and summary rules |
| **User Access Administrator** (ABAC-conditioned) | Subscription | Playbook managed identity role assignments *(restricted to 5 roles)* |
| **Security Administrator** (Entra ID) | Tenant | UEBA and Entity Analytics settings *(optional — see note)* |
| **CustomDetection.ReadWrite.All** (Graph) | Tenant | Defender XDR custom detection rules *(Stage 5)* |

> **Note on Setup**: Run `Scripts/Setup-ServicePrincipal.ps1` once to automatically grant all required permissions. The script provides a permission summary, requests Y/N consent, and supports `-SkipEntraRole` and `-SkipGraphPermission` switches for optional steps. After running once, the pipeline is fully autonomous. See [Scripts.md](Scripts.md#setup-serviceprincipalps1).

> **Note on UEBA/Entity Analytics**: These Sentinel settings require the **Security Administrator** Entra ID directory role on the service principal. If your organisation cannot assign this role to a service principal, UEBA and Entity Analytics can be enabled manually via the Azure portal by a user who holds Security Administrator. All other Bicep resources deploy without it.

> **Note on Defender XDR Detections**: Stage 5 requires the `CustomDetection.ReadWrite.All` Microsoft Graph **application permission** on the service principal's app registration. Grant this in **Entra ID > App Registrations > API Permissions > Microsoft Graph > Application permissions** and provide admin consent.

#### Least-Privilege Alternative

If your organisation requires tighter RBAC, you can replace **Contributor** with more granular roles:

| Role | Scope | Purpose |
|------|-------|---------|
| **Resource Group Contributor** | Resource Group | Create and manage resources within the resource group |
| **Microsoft Sentinel Contributor** | Resource Group | Sentinel settings (Anomalies, EyesOn, analytics rules, content deployment) |
| **Log Analytics Contributor** | Resource Group | Log Analytics workspace management and summary rule deployment *(Stage 4)* |
| **Security Administrator** (Entra ID) | Tenant | UEBA and Entity Analytics settings *(optional)* |
| **CustomDetection.ReadWrite.All** (Graph) | Tenant | Defender XDR custom detection rules *(Stage 5)* |

> **Note**: With the least-privilege approach, the resource group must be pre-created (or use a separate identity with subscription-level Contributor for the initial Bicep deployment). For greenfield deployments that create the resource group, subscription-level **Contributor** is the simplest option.

- Variable group `sentinel-deployment` linked to the pipeline

### Variable Group: `sentinel-deployment`

Create this variable group in Azure DevOps under **Pipelines > Library**.

The Bicep templates handle all resource creation — just provide your subscription ID and choose names for the resources you want deployed.

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `azureSubscriptionId` | Yes | Azure Subscription ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `sentinelResourceGroup` | Yes | Desired Resource Group name | `rg-sentinel-prod` |
| `sentinelWorkspaceName` | Yes | Desired Log Analytics workspace name | `law-sentinel-prod` |
| `sentinelRegion` | Yes | Azure region to deploy into | `uksouth` |
| `playbookResourceGroup` | No | Resource Group for playbooks (defaults to `sentinelResourceGroup`) | `rg-playbooks-prod` |

### Pipeline Parameters

All parameters can be overridden at queue time:

#### Stage Toggles

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `deployInfrastructure` | boolean | `true` | Deploy infrastructure via Bicep (Stages 1-2) |
| `deployContentHub` | boolean | `true` | Deploy Content Hub solutions (Stage 3) |
| `deployCustomContent` | boolean | `true` | Deploy custom Sentinel content (Stage 4) |
| `deployDefenderDetections` | boolean | `true` | Deploy Defender XDR custom detections (Stage 5) |

#### Infrastructure (Stage 2)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `dailyQuota` | number | `0` | Log Analytics daily ingestion quota in GB (`0` = unlimited) |
| `retentionInDays` | number | `90` | Interactive retention period in days (30–730) |
| `totalRetentionInDays` | number | `0` | Total retention including archive tier in days (`0` = same as interactive, no extra cost) |

#### Content Hub

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `solutions` | string | `Microsoft Defender XDR,Azure Activity` | Comma-separated Content Hub solution names |
| `severitiesToInclude` | string | `High,Medium,Low,Informational` | Analytics rule severities to deploy |
| `disableRules` | boolean | `true` | Deploy analytics rules in a disabled state |
| `protectCustomisedRules` | boolean | `true` | Skip overwriting locally modified rules |
| `skipAnalyticsRules` | boolean | `false` | Skip analytics rule deployment |
| `skipWorkbooks` | boolean | `false` | Skip workbook deployment |
| `skipAutomationRules` | boolean | `false` | Skip automation rule deployment |
| `skipHuntingQueries` | boolean | `false` | Skip hunting query deployment |
| `forceSolutionUpdate` | boolean | `false` | Force solution update even if version matches |
| `forceContentDeployment` | boolean | `false` | Force content redeployment even if current |

#### Custom Content (Stage 4)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `smartDeployment` | boolean | `true` | Use git diff to detect changed files and skip unchanged content |
| `skipCustomParsers` | boolean | `false` | Skip custom KQL parser deployment |
| `skipCustomDetections` | boolean | `false` | Skip custom detection rule deployment |
| `skipCustomWatchlists` | boolean | `false` | Skip custom watchlist deployment |
| `skipCustomPlaybooks` | boolean | `false` | Skip custom playbook deployment |
| `skipCustomWorkbooks` | boolean | `false` | Skip custom workbook deployment |
| `skipCustomHuntingQueries` | boolean | `false` | Skip custom hunting query deployment |
| `skipCustomAutomationRules` | boolean | `false` | Skip custom automation rule deployment |
| `skipCustomSummaryRules` | boolean | `false` | Skip custom summary rule deployment |

#### Defender XDR Custom Detections (Stage 5)

No additional parameters — Stage 5 is controlled by the `deployDefenderDetections` toggle and the `whatIf` flag. Rules are read from the `DefenderCustomDetections/` folder. The service principal requires `CustomDetection.ReadWrite.All` Graph application permission with admin consent.

#### General

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `whatIf` | boolean | `false` | Dry run — preview changes without applying |

### Service Connection

The pipeline uses a service connection named `sc-sentinel-as-code` by default. To change this, update the `serviceConnection` variable in the YAML file.

> **Workspace Name**: Must be at least 4 characters (Azure requirement). The Bicep template validates this at deployment time.

### How It Works

1. **Check Infrastructure**: Queries Azure for the resource group, Log Analytics Workspace, and optional playbook resource group to determine if Bicep deployment is needed. If any required resource is missing, Bicep runs. Handles greenfield (nothing exists) gracefully
2. **Register Providers**: Ensures `Microsoft.OperationsManagement` and `Microsoft.SecurityInsights` resource providers are registered on the subscription
3. **Deploy Bicep**: Runs a subscription-level deployment that creates:
   - Resource Group (with tags)
   - Playbook Resource Group (if `playbookResourceGroup` is set and differs from the main RG)
   - Log Analytics workspace (configurable retention, daily quota)
   - Microsoft Sentinel onboarding (via `Microsoft.OperationsManagement/solutions` for idempotent re-runs)
   - Workspace diagnostic settings (audit logs and metrics)
   - Sentinel Health diagnostics (SentinelHealth and SentinelAudit tables)
4. **Configure Sentinel Settings**: Configures settings via REST API with automatic ETag handling:
   - Entity Analytics (Entra ID provider)
   - UEBA (AuditLogs, AzureActivity, SigninLogs, SecurityEvent)
   - Anomalies (built-in ML anomaly detection)
   - EyesOn (SOC incident review flag)
5. **Wait for Workspace Indexing**: 60-second delay after infrastructure deployment to allow the workspace to become queryable for KQL validation
6. **Deploy Content Hub**: Pipeline parameters are mapped to PowerShell switch flags at compile time, then the `Deploy-SentinelContentHub.ps1` script is invoked with splatted parameters
7. **Deploy Custom Content**: Installs `powershell-yaml`, loads `sentinel-deployment.config` and `dependencies.json`, then invokes `Deploy-CustomContent.ps1` with smart deployment enabled. Smart deployment uses git diff to detect changed files and a `.deployment-state.json` state file (persisted as a pipeline artifact between runs) to automatically retry previously failed items. Playbooks can optionally deploy to a separate resource group via the `playbookResourceGroup` variable. Deploys in order: KQL parsers (YAML) → watchlists (JSON+CSV) → detections (YAML, disabled if dependencies missing) → hunting queries (YAML) → playbooks (ARM with module-first ordering, parameter auto-injection, template folder exclusion, name truncation) → workbooks (gallery JSON) → automation rules (JSON) → summary rules (JSON). Pre-flight checks validate dependencies (tables, watchlists, functions) before each content type
8. **Deploy Defender XDR Custom Detections**: Installs `powershell-yaml`, acquires a Microsoft Graph token, then invokes `Deploy-DefenderDetections.ps1` to deploy custom detection rules from `DefenderCustomDetections/` YAML files via the Graph Security API. Creates new rules or updates existing ones matched by `displayName`

### Usage Examples

#### Full deployment (infrastructure + content)
Queue the pipeline with default parameters — provisions infrastructure if needed, then deploys Content Hub solutions.

#### Content only (skip infrastructure)
Override at queue time:
- `deployInfrastructure`: `false`

#### Deploy specific solutions, skip workbooks
Override at queue time:
- `solutions`: `Microsoft 365,Threat Intelligence`
- `skipWorkbooks`: `true`

#### Dry run to preview changes
Override at queue time:
- `whatIf`: `true`

#### Deploy only custom content (skip infrastructure and Content Hub)
Override at queue time:
- `deployInfrastructure`: `false`
- `deployContentHub`: `false`
- `deployDefenderDetections`: `false`

#### Skip custom playbooks and workbooks
Override at queue time:
- `skipCustomPlaybooks`: `true`
- `skipCustomWorkbooks`: `true`

#### Skip hunting queries and automation rules
Override at queue time:
- `skipCustomHuntingQueries`: `true`
- `skipCustomAutomationRules`: `true`

#### Deploy only Defender XDR custom detections
Override at queue time:
- `deployInfrastructure`: `false`
- `deployContentHub`: `false`
- `deployCustomContent`: `false`

#### Skip Defender XDR detections
Override at queue time:
- `deployDefenderDetections`: `false`

#### Deploy playbooks to a separate resource group
Add to the `sentinel-deployment` variable group:
- `playbookResourceGroup`: `rg-playbooks-prod`

#### Force full redeployment
Override at queue time:
- `forceSolutionUpdate`: `true`
- `forceContentDeployment`: `true`
