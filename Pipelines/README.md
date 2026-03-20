# Pipelines

## Sentinel-Deploy.yml

Azure DevOps pipeline for provisioning Microsoft Sentinel infrastructure via Bicep, deploying Content Hub solutions and their associated content, deploying custom Sentinel content (detections, watchlists, playbooks, workbooks, hunting queries, automation rules, summary rules), and deploying Defender XDR custom detection rules via the Graph Security API.

### Pipeline Stages

```
Stage 1: Check Existing Infrastructure
  └─ Checks if Resource Group and Log Analytics Workspace already exist
  └─ Handles greenfield (nothing exists) through to existing environments

Stage 2: Deploy Sentinel Infrastructure (Bicep)
  ├─ Registers required resource providers (Microsoft.OperationsManagement,
  │   Microsoft.SecurityInsights)
  └─ Provisions Resource Group, Log Analytics Workspace, Sentinel, Entity
     Analytics, UEBA
  └─ Skipped if workspace already exists or deployInfrastructure is false

Stage 3: Deploy Sentinel Content Hub
  └─ Deploys solutions, analytics rules, workbooks, automation rules, hunting queries
  └─ Runs regardless of whether infrastructure was deployed or already existed

Stage 4: Deploy Custom Content
  ├─ Installs powershell-yaml module
  └─ Deploys custom detections (YAML), watchlists (JSON+CSV), playbooks (ARM),
     workbooks (gallery JSON), hunting queries (YAML), automation rules (JSON),
     and summary rules (JSON) from the repo
  └─ Runs after Content Hub stage succeeds or is skipped

Stage 5: Deploy Defender XDR Custom Detections
  ├─ Installs powershell-yaml module
  └─ Deploys custom detection rules to Defender XDR via Microsoft Graph
     Security API (beta) from DefenderDetections/ YAML files
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
| **Security Administrator** (Entra ID) | Tenant | UEBA and Entity Analytics settings *(optional — see note)* |
| **CustomDetection.ReadWrite.All** (Graph) | Tenant | Defender XDR custom detection rules *(Stage 5)* |

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

| Variable | Description | Example |
|----------|-------------|---------|
| `azureSubscriptionId` | Azure Subscription ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `sentinelResourceGroup` | Desired Resource Group name | `rg-sentinel-prod` |
| `sentinelWorkspaceName` | Desired Log Analytics workspace name | `law-sentinel-prod` |
| `sentinelRegion` | Azure region to deploy into | `uksouth` |

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
| `skipCustomDetections` | boolean | `false` | Skip custom detection rule deployment |
| `skipCustomWatchlists` | boolean | `false` | Skip custom watchlist deployment |
| `skipCustomPlaybooks` | boolean | `false` | Skip custom playbook deployment |
| `skipCustomWorkbooks` | boolean | `false` | Skip custom workbook deployment |
| `skipCustomHuntingQueries` | boolean | `false` | Skip custom hunting query deployment |
| `skipCustomAutomationRules` | boolean | `false` | Skip custom automation rule deployment |
| `skipCustomSummaryRules` | boolean | `false` | Skip custom summary rule deployment |

#### Defender XDR Custom Detections (Stage 5)

No additional parameters — Stage 5 is controlled by the `deployDefenderDetections` toggle and the `whatIf` flag. Rules are read from the `DefenderDetections/` folder. The service principal requires `CustomDetection.ReadWrite.All` Graph application permission with admin consent.

#### General

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `whatIf` | boolean | `false` | Dry run — preview changes without applying |

### Service Connection

The pipeline uses a service connection named `sc-sentinel-as-code` by default. To change this, update the `serviceConnection` variable in the YAML file.

> **Workspace Name**: Must be at least 4 characters (Azure requirement). The Bicep template validates this at deployment time.

### How It Works

1. **Check Infrastructure**: Queries Azure for the resource group and Log Analytics Workspace to determine if Bicep deployment is needed. Handles greenfield (nothing exists) gracefully
2. **Register Providers**: Ensures `Microsoft.OperationsManagement` and `Microsoft.SecurityInsights` resource providers are registered on the subscription
3. **Deploy Bicep**: Runs a subscription-level deployment that creates:
   - Resource Group (with tags)
   - Log Analytics workspace (configurable retention, daily quota)
   - Microsoft Sentinel (onboarding)
   - Entity Analytics (Entra ID provider)
   - UEBA (AuditLogs, AzureActivity, SigninLogs, SecurityEvent)
   - Anomalies (built-in ML anomaly detection)
   - EyesOn (SOC incident review flag)
   - Workspace diagnostic settings (audit logs and metrics)
   - Sentinel Health diagnostics (SentinelHealth and SentinelAudit tables)
4. **Deploy Content Hub**: Pipeline parameters are mapped to PowerShell switch flags at compile time, then the `Deploy-SentinelContentHub.ps1` script is invoked with splatted parameters
5. **Deploy Custom Content**: Installs `powershell-yaml`, then invokes `Deploy-CustomContent.ps1` to deploy custom detections (YAML → REST API), watchlists (JSON+CSV), playbooks (ARM templates), workbooks (gallery JSON), hunting queries (YAML), automation rules (JSON), and summary rules (JSON) from the repo
6. **Deploy Defender XDR Custom Detections**: Installs `powershell-yaml`, acquires a Microsoft Graph token, then invokes `Deploy-DefenderDetections.ps1` to deploy custom detection rules from `DefenderDetections/` YAML files via the Graph Security API. Creates new rules or updates existing ones matched by `displayName`

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

#### Force full redeployment
Override at queue time:
- `forceSolutionUpdate`: `true`
- `forceContentDeployment`: `true`
