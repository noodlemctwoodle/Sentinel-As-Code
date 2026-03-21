# Scripts

## Setup-ServicePrincipal.ps1

One-time bootstrap script that grants the service principal all required Azure, Entra ID, and Microsoft Graph permissions needed for the pipeline to operate autonomously.

### Key Features

- **Automated Permission Grant**: Grants Contributor, User Access Administrator (ABAC-conditioned), Security Administrator (Entra ID), and CustomDetection.ReadWrite.All (Graph) roles
- **Permission Summary**: Displays full summary of permissions before requesting consent
- **User Consent**: Y/N prompt with disclaimer before applying changes
- **Selective Steps**: Skip optional Entra ID or Graph permissions with `-SkipEntraRole` and `-SkipGraphPermission` switches
- **ABAC-Conditioned UAA**: User Access Administrator is condition-restricted to 5 specific roles (reader, contributor, owner, user access administrator, logic app contributor)
- **One-Time Setup**: After running once, the pipeline is fully autonomous and requires no manual intervention

### Prerequisites

- Service Principal (app registration) already created
- User with Global Administrator (Entra ID) and Owner (Azure subscription) roles to grant permissions
- `Az.Accounts`, `Az.Resources`, `Az.ManagedServiceIdentity`, and `Az.KeyVault` PowerShell modules

### Parameter Reference

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `SubscriptionId` | string | No | Current context | Azure Subscription ID |
| `ServicePrincipalId` | string | No | Detected from context | Service Principal client/app ID |
| `TenantId` | string | No | Detected from context | Entra ID tenant ID |
| `SkipEntraRole` | switch | No | `$false` | Skip granting Security Administrator (Entra ID) role |
| `SkipGraphPermission` | switch | No | `$false` | Skip granting CustomDetection.ReadWrite.All (Graph) permission |

### Usage Examples

#### Full setup (all permissions)
```powershell
.\Setup-ServicePrincipal.ps1
```

#### Skip Entra ID role (if not needed)
```powershell
.\Setup-ServicePrincipal.ps1 -SkipEntraRole
```

#### Skip Graph permission (for environments without Defender XDR)
```powershell
.\Setup-ServicePrincipal.ps1 -SkipGraphPermission
```

#### Skip both optional permissions
```powershell
.\Setup-ServicePrincipal.ps1 -SkipEntraRole -SkipGraphPermission
```

### How It Works

1. **Prompt for Confirmation**: Displays a comprehensive permission summary and requests Y/N consent before proceeding
2. **Grant Contributor**: Grants subscription-level Contributor role for resource group, workspace, Bicep, and content deployment
3. **Grant UAA (ABAC-Conditioned)**: Grants User Access Administrator at resource group scope with ABAC conditions restricting assignment to 5 specific roles
4. **Grant Security Administrator** (optional): Grants Entra ID Security Administrator role for UEBA and Entity Analytics settings
5. **Grant Graph Permission** (optional): Grants CustomDetection.ReadWrite.All Graph application permission for Defender XDR custom detection rules
6. **Completion**: Prints confirmation that setup is complete and the pipeline is ready to run autonomously

---

## Deploy-SentinelContentHub.ps1

Automates the end-to-end deployment of Microsoft Sentinel Content Hub solutions and their packaged content via the Azure REST API (API version `2025-09-01`).

### Key Features

- **Full Content Type Support**: Solutions, analytics rules, workbooks, automation rules, and hunting queries
- **Customisation Protection**: Detects locally modified analytics rules and skips them with pipeline warnings
- **Disabled Rule Deployment**: Deploy analytics rules in a disabled state for review before enabling
- **Dry Run Mode**: `WhatIf` parameter to preview all changes without applying them
- **Semantic Version Comparison**: Detects solutions that require updates
- **ADO Pipeline Integration**: Emits pipeline warnings, section messages, and structured output
- **Azure Government Support**: Targets Azure Government cloud with the `-IsGov` switch
- **Metadata Linking**: Proper metadata association so content appears correctly in Content Hub

### Prerequisites

- `Az.Accounts` PowerShell module
- Authenticated Azure context (`Connect-AzAccount` or Azure DevOps service connection)

### Parameter Reference

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `SubscriptionId` | string | No | Current context | Azure Subscription ID |
| `ResourceGroup` | string | Yes | - | Resource Group containing the Sentinel workspace |
| `Workspace` | string | Yes | - | Log Analytics workspace name |
| `Region` | string | Yes | - | Azure region (e.g., `uksouth`, `eastus`) |
| `Solutions` | string[] | Yes | - | Content Hub solution names to deploy |
| `SeveritiesToInclude` | string[] | No | `High,Medium,Low,Informational` | Analytics rule severities to include |
| `DisableRules` | switch | No | `$false` | Deploy analytics rules as disabled |
| `SkipSolutionDeployment` | switch | No | `$false` | Skip deploying/updating solutions |
| `SkipAnalyticsRules` | switch | No | `$false` | Skip analytics rule deployment |
| `SkipWorkbooks` | switch | No | `$false` | Skip workbook deployment |
| `SkipAutomationRules` | switch | No | `$false` | Skip automation rule deployment |
| `SkipHuntingQueries` | switch | No | `$false` | Skip hunting query deployment |
| `ForceSolutionUpdate` | switch | No | `$false` | Force update even if version matches |
| `ForceContentDeployment` | switch | No | `$false` | Force redeployment of all content |
| `ProtectCustomisedRules` | switch | No | `$true` | Skip updating locally modified rules |
| `IsGov` | switch | No | `$false` | Target Azure Government cloud |
| `WhatIf` | switch | No | `$false` | Dry run (no changes applied) |

### Usage Examples

#### Basic Deployment
```powershell
.\Deploy-SentinelContentHub.ps1 `
    -ResourceGroup "rg-sentinel-prod" `
    -Workspace "law-sentinel-prod" `
    -Region "uksouth" `
    -Solutions "Microsoft Defender XDR", "Azure Activity" `
    -DisableRules
```

#### Selective Content Deployment
```powershell
.\Deploy-SentinelContentHub.ps1 `
    -ResourceGroup "rg-sentinel-prod" `
    -Workspace "law-sentinel-prod" `
    -Region "uksouth" `
    -Solutions "Microsoft Defender XDR" `
    -SkipWorkbooks `
    -SkipAutomationRules `
    -SeveritiesToInclude "High", "Medium"
```

#### Dry Run
```powershell
.\Deploy-SentinelContentHub.ps1 `
    -ResourceGroup "rg-sentinel-prod" `
    -Workspace "law-sentinel-prod" `
    -Region "uksouth" `
    -Solutions "Microsoft 365" `
    -WhatIf
```

#### Azure Government
```powershell
.\Deploy-SentinelContentHub.ps1 `
    -ResourceGroup "rg-sentinel-gov" `
    -Workspace "law-sentinel-gov" `
    -Region "USGovVirginia" `
    -Solutions "Azure Activity" `
    -IsGov
```

### How It Works

1. **Authentication and Setup**: Validates Azure context, resolves subscription ID, and configures API endpoints
2. **Solution Deployment**: Retrieves Content Hub catalogue, compares installed versions, and deploys or updates solutions
3. **Analytics Rule Deployment**: Fetches rule templates, filters by severity, detects customised rules, and deploys with metadata
4. **Workbook Deployment**: Retrieves workbook templates and deploys with proper metadata linking
5. **Automation Rule Deployment**: Discovers and deploys automation rules from solution packages
6. **Hunting Query Deployment**: Discovers and deploys hunting queries from solution packages
7. **Status Reporting**: Provides detailed deployment summaries with ADO pipeline integration

### Tested Solutions

- Azure Activity
- Azure Key Vault
- Azure Logic Apps
- Azure Network Security Groups
- Microsoft 365
- Microsoft Defender for Cloud
- Microsoft Defender for Cloud Apps
- Microsoft Defender for Endpoint
- Microsoft Defender for Identity
- Microsoft Defender Threat Intelligence
- Microsoft Defender XDR
- Microsoft Entra ID
- Microsoft Purview Insider Risk Management
- Syslog
- Threat Intelligence
- Windows Security Events
- Windows Server DNS

### Known Limitations

- Solutions requiring specific permissions or prerequisites may need additional configuration
- Analytics rules referencing tables/columns not present in your environment will be skipped
- Deprecated rules are skipped by design to prevent deploying outdated content
- Some workbooks may have dependencies on specific data sources being configured

---

## Deploy-CustomContent.ps1

Deploys custom content from the repository to a Microsoft Sentinel workspace: KQL parsers (YAML), analytics rules (YAML), watchlists (JSON+CSV), playbooks (ARM templates), workbooks (gallery JSON), hunting queries (YAML), automation rules (JSON), and summary rules (JSON).

### Key Features

- **Smart Deployment**: Use git diff to detect changed files and skip unchanged content — `.deployment-state.json` tracks deployment outcomes across runs to automatically retry previously failed items
- **Dependency Graph System**: Validates prerequisites per content item (tables, watchlists, functions); detections with missing dependencies deploy disabled, other content types skip
- **KQL Parser Deployment**: Deploy workspace saved searches as reusable KQL functions from YAML
- **YAML Detection Rules**: Author detections in YAML (Azure-Sentinel repo format), converted to REST API JSON at deploy time
- **Watchlist Management**: Deploy watchlists with inline CSV upload via REST API
- **Playbook Deployment**: Deploy Logic App playbooks via ARM template deployments with module-first ordering, ARM parameter auto-injection, optional separate resource group, template folder exclusion, and 64-character name truncation
- **Workbook Deployment**: Deploy workbooks with stable GUIDs for idempotent updates
- **Hunting Query Deployment**: Deploy YAML-based saved searches to the workspace
- **Automation Rule Deployment**: Deploy JSON automation rules for incident auto-response
- **Summary Rule Deployment**: Deploy JSON summary rules to aggregate verbose logs into cost-effective custom tables via the Log Analytics API
- **Selective Deployment**: Skip individual content types with `-Skip*` switches
- **Dry Run Mode**: `WhatIf` parameter previews all changes without applying
- **ADO Pipeline Integration**: Emits pipeline warnings, section messages, and structured output
- **Azure Government Support**: Targets Azure Government cloud with the `-IsGov` switch

### Prerequisites

- `Az.Accounts` PowerShell module
- `powershell-yaml` module (for YAML detection parsing)
- Authenticated Azure context (`Connect-AzAccount` or Azure DevOps service connection)

### Parameter Reference

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `SubscriptionId` | string | No | Current context | Azure Subscription ID |
| `ResourceGroup` | string | Yes | - | Resource Group containing the Sentinel workspace |
| `PlaybookResourceGroup` | string | No | Same as `ResourceGroup` | Resource Group for playbook (Logic App) deployments |
| `Workspace` | string | Yes | - | Log Analytics workspace name |
| `Region` | string | Yes | - | Azure region (e.g., `uksouth`, `eastus`) |
| `BasePath` | string | No | `$env:BUILD_SOURCESDIRECTORY` or `.` | Repo root path |
| `SmartDeployment` | switch | No | `$true` | Use git diff to detect changed files and skip unchanged content |
| `SkipParsers` | switch | No | `$false` | Skip custom KQL parser deployment |
| `SkipDetections` | switch | No | `$false` | Skip custom detection deployment |
| `SkipWatchlists` | switch | No | `$false` | Skip custom watchlist deployment |
| `SkipPlaybooks` | switch | No | `$false` | Skip custom playbook deployment |
| `SkipWorkbooks` | switch | No | `$false` | Skip custom workbook deployment |
| `SkipHuntingQueries` | switch | No | `$false` | Skip custom hunting query deployment |
| `SkipAutomationRules` | switch | No | `$false` | Skip custom automation rule deployment |
| `SkipSummaryRules` | switch | No | `$false` | Skip custom summary rule deployment |
| `IsGov` | switch | No | `$false` | Target Azure Government cloud |
| `WhatIf` | switch | No | `$false` | Dry run (no changes applied) |

### Usage Examples

#### Deploy All Custom Content
```powershell
.\Deploy-CustomContent.ps1 `
    -ResourceGroup "rg-sentinel-prod" `
    -Workspace "law-sentinel-prod" `
    -Region "uksouth"
```

#### Deploy Only Detections and Watchlists
```powershell
.\Deploy-CustomContent.ps1 `
    -ResourceGroup "rg-sentinel-prod" `
    -Workspace "law-sentinel-prod" `
    -Region "uksouth" `
    -SkipPlaybooks `
    -SkipWorkbooks
```

#### Deploy Only Hunting Queries and Automation Rules
```powershell
.\Deploy-CustomContent.ps1 `
    -ResourceGroup "rg-sentinel-prod" `
    -Workspace "law-sentinel-prod" `
    -Region "uksouth" `
    -SkipDetections `
    -SkipWatchlists `
    -SkipPlaybooks `
    -SkipWorkbooks
```

#### Deploy Playbooks to a Separate Resource Group
```powershell
.\Deploy-CustomContent.ps1 `
    -ResourceGroup "rg-sentinel-prod" `
    -PlaybookResourceGroup "rg-playbooks-prod" `
    -Workspace "law-sentinel-prod" `
    -Region "uksouth"
```

#### Dry Run
```powershell
.\Deploy-CustomContent.ps1 `
    -ResourceGroup "rg-sentinel-prod" `
    -Workspace "law-sentinel-prod" `
    -Region "uksouth" `
    -WhatIf
```

### How It Works

1. **Authentication and Setup**: Validates Azure context, resolves subscription ID, and configures API endpoints
2. **Smart Deployment Check**: If enabled (default), uses git diff to detect changed files; unchanged files are skipped unless they were not previously deployed successfully (tracked in `.deployment-state.json`). Failed items are automatically retried on subsequent runs
3. **Dependency Graph Validation**: Loads `dependencies.json` and performs pre-flight checks to bulk-fetch workspace state (tables, watchlists, functions); runs `Test-ContentDependencies` before each content type
4. **Parser Deployment** (Stage 1): Scans `Parsers/` for YAML files, validates required fields including `functionAlias`, converts to saved search body, and deploys via `PUT` to the `savedSearches` endpoint
5. **Watchlist Deployment** (Stage 2): Scans `Watchlists/` for subdirectories with `watchlist.json` + `data.csv`, validates metadata, and deploys via `PUT` with inline CSV content
6. **Detection Deployment** (Stage 3): Scans `AnalyticalRules/` for YAML files, validates required fields, converts to REST API JSON; if dependencies are missing, deploys as disabled (not skipped) — if API rejects disabled state, gracefully skipped
7. **Hunting Query Deployment** (Stage 4): Scans `HuntingQueries/` for YAML files, validates required fields, builds saved search body with tactics/techniques tags, and deploys via `PUT` to the `savedSearches` endpoint
8. **Playbook Deployment** (Stage 5): Scans `Playbooks/` for subdirectories with `azuredeploy.json` (excludes `Template/` directory), orders Module/ playbooks first with leaf modules deployed before dependent modules, auto-injects known ARM parameters (ResourceGroup, Workspace, SubscriptionId, WorkspaceId, PlaybookResourceGroup), truncates names to 64 characters, and deploys via `New-AzResourceGroupDeployment` to the playbook resource group (uses `Test-AzResourceGroupDeployment` for WhatIf)
9. **Workbook Deployment** (Stage 6): Scans `Workbooks/` for subdirectories with `workbook.json`, reads optional `metadata.json` for stable GUIDs, and deploys via `PUT` to the `Microsoft.Insights/workbooks` endpoint
10. **Automation Rule Deployment** (Stage 7): Scans `AutomationRules/` for JSON files, validates required fields (automationRuleId, displayName, order, triggeringLogic, actions), and deploys via `PUT` to the `automationRules` endpoint
11. **Summary Rule Deployment** (Stage 8): Scans `SummaryRules/` for JSON files, validates required fields (name, query, binSize, destinationTable), validates binSize against allowed values and `_CL` suffix, and deploys via `PUT` to the `summarylogs` endpoint using the `Microsoft.OperationalInsights` provider
12. **Status Reporting**: Prints a summary table with deployed/skipped/failed counts per content type

### Content Folder Structure and Deployment Order

Content deploys in the following order (also driven by `dependencies.json`):

1. **Parsers** — KQL parser/function definitions
2. **Watchlists** — Reusable data lists
3. **Detections** — Analytics rules
4. **Hunting Queries** — Saved searches
5. **Playbooks** — Logic App automation
6. **Workbooks** — Visualisation dashboards
7. **Automation Rules** — Incident auto-response
8. **Summary Rules** — Cost-optimised aggregation

See the individual content READMEs for schema details:
- [Parsers/README.md](../Parsers/README.md) — KQL parser YAML schema
- [AnalyticalRules/README.md](../AnalyticalRules/README.md) — YAML analytics rule schema
- [Watchlists/README.md](../Watchlists/README.md) — Watchlist metadata and CSV format
- [Playbooks/README.md](../Playbooks/README.md) — ARM template requirements
- [Workbooks/README.md](../Workbooks/README.md) — Gallery template JSON format
- [HuntingQueries/README.md](../HuntingQueries/README.md) — Hunting query YAML schema
- [AutomationRules/README.md](../AutomationRules/README.md) — Automation rule JSON schema
- [SummaryRules/README.md](../SummaryRules/README.md) — Summary rule JSON schema

---

## Deploy-DefenderDetections.ps1

Deploys custom detection rules to Microsoft Defender XDR via the Microsoft Graph Security API (beta). Rules are authored as YAML files in the `DefenderCustomDetections/` folder and use the Advanced Hunting KQL schema.

### Key Features

- **Graph Security API**: Deploys rules via `POST`/`PATCH` to `/beta/security/rules/detectionRules`
- **Upsert Logic**: Creates new rules or updates existing ones matched by `displayName`
- **Response Actions**: Supports all Defender response actions (isolate device, force password reset, soft-delete email, etc.)
- **Pagination Handling**: Fetches all existing rules with OData pagination
- **Dry Run Mode**: `WhatIf` parameter previews all changes without applying
- **ADO Pipeline Integration**: Emits pipeline warnings, section messages, and structured output
- **Azure Government Support**: Targets Azure Government Graph endpoint with the `-IsGov` switch

### Prerequisites

- `Az.Accounts` PowerShell module
- `powershell-yaml` module (for YAML parsing)
- Authenticated Azure context with `CustomDetection.ReadWrite.All` Graph application permission
- Admin consent granted for the Graph permission

### Parameter Reference

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `BasePath` | string | No | Parent of Scripts folder | Repo root path containing `DefenderCustomDetections/` |
| `IsGov` | switch | No | `$false` | Target Azure Government cloud (`graph.microsoft.us`) |
| `WhatIf` | switch | No | `$false` | Dry run (no changes applied) |

### Usage Examples

#### Deploy All Defender Detections
```powershell
.\Deploy-DefenderDetections.ps1
```

#### Deploy from a Specific Path
```powershell
.\Deploy-DefenderDetections.ps1 -BasePath "C:\Repos\Sentinel-As-Code"
```

#### Dry Run
```powershell
.\Deploy-DefenderDetections.ps1 -WhatIf
```

### How It Works

1. **Authentication**: Acquires a Microsoft Graph token via `Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com"` using the existing Azure context
2. **Fetch Existing Rules**: Queries the Graph API to list all current custom detection rules for upsert matching by `displayName`
3. **YAML Processing**: Scans `DefenderCustomDetections/` for YAML files, validates required fields (`displayName`, `queryCondition.queryText`, `schedule.period`, `detectionAction.alertTemplate`)
4. **Upsert**: If a rule with the same `displayName` exists, updates it via `PATCH`; otherwise creates via `POST`
5. **Status Reporting**: Prints a summary with created/updated/skipped/failed counts

### Content Folder Structure

See the [DefenderCustomDetections/README.md](../DefenderCustomDetections/README.md) for the full YAML schema, response action types, and impacted asset identifiers.
