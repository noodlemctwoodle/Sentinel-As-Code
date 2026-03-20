# Scripts

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

Deploys custom content from the repository to a Microsoft Sentinel workspace: analytics rules (YAML), watchlists (JSON+CSV), playbooks (ARM templates), workbooks (gallery JSON), hunting queries (YAML), automation rules (JSON), and summary rules (JSON).

### Key Features

- **YAML Detection Rules**: Author detections in YAML (Azure-Sentinel repo format), converted to REST API JSON at deploy time
- **Watchlist Management**: Deploy watchlists with inline CSV upload via REST API
- **Playbook Deployment**: Deploy Logic App playbooks via ARM template deployments
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
| `Workspace` | string | Yes | - | Log Analytics workspace name |
| `Region` | string | Yes | - | Azure region (e.g., `uksouth`, `eastus`) |
| `BasePath` | string | No | `$env:BUILD_SOURCESDIRECTORY` or `.` | Repo root path |
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
2. **Detection Deployment**: Scans `Detections/` for YAML files, validates required fields, converts to REST API JSON, and deploys via `PUT` to the `alertRules` endpoint
3. **Watchlist Deployment**: Scans `Watchlists/` for subdirectories with `watchlist.json` + `data.csv`, validates metadata, and deploys via `PUT` with inline CSV content
4. **Playbook Deployment**: Scans `Playbooks/` for subdirectories with `azuredeploy.json`, deploys via `New-AzResourceGroupDeployment` (uses `Test-AzResourceGroupDeployment` for WhatIf)
5. **Workbook Deployment**: Scans `Workbooks/` for subdirectories with `workbook.json`, reads optional `metadata.json` for stable GUIDs, and deploys via `PUT` to the `Microsoft.Insights/workbooks` endpoint
6. **Hunting Query Deployment**: Scans `HuntingQueries/` for YAML files, validates required fields, builds saved search body with tactics/techniques tags, and deploys via `PUT` to the `savedSearches` endpoint
7. **Automation Rule Deployment**: Scans `AutomationRules/` for JSON files, validates required fields (automationRuleId, displayName, order, triggeringLogic, actions), and deploys via `PUT` to the `automationRules` endpoint
8. **Summary Rule Deployment**: Scans `SummaryRules/` for JSON files, validates required fields (name, query, binSize, destinationTable), validates binSize against allowed values and `_CL` suffix, and deploys via `PUT` to the `summarylogs` endpoint using the `Microsoft.OperationalInsights` provider
9. **Status Reporting**: Prints a summary table with deployed/skipped/failed counts per content type

### Content Folder Structure

See the individual content READMEs for schema details:
- [Detections/README.md](../Detections/README.md) — YAML analytics rule schema
- [Watchlists/README.md](../Watchlists/README.md) — Watchlist metadata and CSV format
- [Playbooks/README.md](../Playbooks/README.md) — ARM template requirements
- [Workbooks/README.md](../Workbooks/README.md) — Gallery template JSON format
- [HuntingQueries/README.md](../HuntingQueries/README.md) — Hunting query YAML schema
- [AutomationRules/README.md](../AutomationRules/README.md) — Automation rule JSON schema
- [SummaryRules/README.md](../SummaryRules/README.md) — Summary rule JSON schema

---

## Deploy-DefenderDetections.ps1

Deploys custom detection rules to Microsoft Defender XDR via the Microsoft Graph Security API (beta). Rules are authored as YAML files in the `DefenderDetections/` folder and use the Advanced Hunting KQL schema.

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
| `BasePath` | string | No | Parent of Scripts folder | Repo root path containing `DefenderDetections/` |
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
3. **YAML Processing**: Scans `DefenderDetections/` for YAML files, validates required fields (`displayName`, `queryCondition.queryText`, `schedule.period`, `detectionAction.alertTemplate`)
4. **Upsert**: If a rule with the same `displayName` exists, updates it via `PATCH`; otherwise creates via `POST`
5. **Status Reporting**: Prints a summary with created/updated/skipped/failed counts

### Content Folder Structure

See the [DefenderDetections/README.md](../DefenderDetections/README.md) for the full YAML schema, response action types, and impacted asset identifiers.
