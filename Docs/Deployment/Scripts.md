# Scripts

PowerShell scripts that drive the deploy and detection pipelines, plus
one-time bootstrap and ad-hoc maintenance tooling.

| Script | Purpose | Doc anchor |
| --- | --- | --- |
| `Setup-ServicePrincipal.ps1` | One-time bootstrap of all required service-principal permissions | [#setup-serviceprincipalps1](#setup-serviceprincipalps1) |
| `Deploy-SentinelContentHub.ps1` | Deploys Content Hub solutions and OoB content | [#deploy-sentinelcontenthubps1](#deploy-sentinelcontenthubps1) |
| `Deploy-CustomContent.ps1` | Deploys repo-authored custom content | [#deploy-customcontentps1](#deploy-customcontentps1) |
| `Deploy-DefenderDetections.ps1` | Deploys Defender XDR custom detections via Graph | [#deploy-defenderdetectionsps1](#deploy-defenderdetectionsps1) |
| `Import-CommunityRules.ps1` | Imports community rule sources (Dalonso) | [#import-communityrulesps1](#import-communityrulesps1) |
| `Set-PlaybookPermissions.ps1` | Post-deploy: grants managed-identity roles based on each playbook's actual workflow content | [#set-playbookpermissionsps1](#set-playbookpermissionsps1) |
| `Build-DependencyManifest.ps1` | Auto-derives `dependencies.json` from KQL discovery (Generate / Verify / Update modes) | [#build-dependencymanifestps1](#build-dependencymanifestps1) |
| `Export-SentinelWorkbooks.ps1` | Exports every Sentinel workbook in a workspace into the `Workbooks/` folder shape that `Deploy-CustomWorkbooks` reads back | [#export-sentinelworkbooksps1](#export-sentinelworkbooksps1) |
| `Invoke-PRValidation.ps1` | Cross-platform PR-validation entrypoint — runs every Pester suite under `Tests/` and emits a JUnit XML report | See [Pester Tests](../Development/Pester-Tests.md) |
| `Test-SentinelRuleDrift.ps1` | Detects portal-edited rules and absorbs Custom drift | See [Sentinel Drift Detection](../Operations/Sentinel-Drift-Detection.md) |

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
2. **Grant Contributor**: Grants subscription-level Contributor role for resource group, workspace, Bicep, and content deployment. (Contributor implies Reader at the same scope, which is what ADO needs to save a workload-identity-federation service connection — see [ADO OIDC Setup](ADO-OIDC-Setup.md) for context.)
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
| `SkipCommunityDetections` | switch | No | `$false` | Skip rules under `AnalyticalRules/Community/**` only — non-community detections still deploy. Used by the pipeline's "Skip Community Detections" toggle |
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

Schema details for each content type:
- [Analytical-Rules.md](../Content/Analytical-Rules.md) — YAML analytics rule schema
- [Watchlists.md](../Content/Watchlists.md) — Watchlist metadata and CSV format
- [Playbooks.md](../Content/Playbooks.md) — ARM template requirements
- [Workbooks.md](../Content/Workbooks.md) — Gallery template JSON format
- [Hunting-Queries.md](../Content/Hunting-Queries.md) — Hunting query YAML schema
- [Automation-Rules.md](../Content/Automation-Rules.md) — Automation rule JSON schema
- [Summary-Rules.md](../Content/Summary-Rules.md) — Summary rule JSON schema

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

See [Defender-Custom-Detections.md](../Content/Defender-Custom-Detections.md) for the full YAML schema, response action types, and impacted asset identifiers.

---

## Import-CommunityRules.ps1

Imports community analytical rules from external repositories into the local codebase. Currently supports the David Alonso (Dalonso) Security repository. See [Community-Rules.md](../Content/Community-Rules.md) for the full contribution model.

### Key Features

- **External Repository Support**: Currently supports David Alonso's Threat Hunting rules (111 published rules)
- **YAML Rule Import**: Clones external Git repositories and copies YAML-format detection rules
- **Format Conversion**: Optionally converts KQL+ARM hybrid rules to YAML format for consistency
- **Attribution Tracking**: Automatically adds source attribution and creation metadata to imported rules
- **Disabled by Default**: All imported rules deploy with `enabled: false` for review before activation
- **Manifest Generation**: Creates `import-manifest.json` (next to the rules) with content hashes for upstream-drift detection
- **Auto-Generated Summary**: Writes a Markdown summary to `Docs/Community/{ContributorName}.md` with rule counts and per-category listings
- **Change Detection**: Uses SHA-256 checksums to track which rules have changed between runs; only updates modified content
- **Idempotent**: Fully re-runnable — unchanged rules are skipped, failed rules are retried on next execution
- **Dry Run Mode**: `DryRun` parameter previews all changes without writing to disk
- **ADO Pipeline Integration**: Emits pipeline warnings and structured output

### Prerequisites

- `powershell-yaml` module (for YAML parsing and generation)
- Git command-line tools (for repository cloning)
- Internet access to external repositories

### Parameter Reference

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `OutputPath` | string | No | `AnalyticalRules/Community/Dalonso` | Target folder for imported rule YAMLs and `import-manifest.json` |
| `DocsPath` | string | No | `Docs/Community/{ContributorName}.md` (auto-derived from `OutputPath` leaf) | Destination for the auto-generated Markdown summary |
| `SourceRepo` | string | No | `https://github.com/davidalonsod/Dalonso-Security-Repo.git` | Git URL of source repository |
| `SourceBranch` | string | No | `main` | Branch name to clone from |
| `IncludeKqlConversion` | switch | No | `$false` | Also convert KQL+ARM rules to YAML format |
| `DryRun` | switch | No | `$false` | Preview changes without writing files |

### Usage Examples

#### Import Default Community Rules
```powershell
.\Import-CommunityRules.ps1
```

#### Import with KQL Conversion
```powershell
.\Import-CommunityRules.ps1 -IncludeKqlConversion
```

#### Dry Run Preview
```powershell
.\Import-CommunityRules.ps1 -DryRun
```

#### Onboard a New Contributor
```powershell
.\Import-CommunityRules.ps1 `
    -OutputPath ./AnalyticalRules/Community/NewContributor `
    -DocsPath   ./Docs/Community/NewContributor.md `
    -SourceRepo "https://github.com/example/threat-rules.git"
```

### How It Works

1. **Repository Cloning**: Clones the source repository to a temporary directory using the specified branch
2. **Rule Discovery**: Scans the cloned repository for YAML-format detection rules
3. **Metadata Extraction**: Reads rule metadata (title, description, tactics, techniques, severity)
4. **Format Conversion** (optional): If `-IncludeKqlConversion` is enabled, converts KQL+ARM hybrid rules to YAML
5. **Attribution**: Adds source repository attribution and original author information to each rule
6. **Deployment State**: Sets `enabled: false` on all imported rules for review before activation
7. **Change Detection**: Compares SHA-256 checksums of each rule against the `import-manifest.json` manifest to detect changes
8. **File Writing**: Writes new and updated rules to `OutputPath`, skips unchanged rules
9. **Manifest Creation**: Updates `import-manifest.json` with metadata for all imported rules including source, rule count, and import timestamp
10. **Summary Generation**: Writes the human-readable summary to `DocsPath` (under `Docs/Community/`) with import source, total rule count, organisation, and instructions for enabling rules
11. **Cleanup**: Removes temporary clone directory

### Import State Tracking

The import process tracks changes using `import-manifest.json` (next to the rules):
- **First Run**: Creates initial manifest; imports all rules
- **Subsequent Runs**: Compares content hashes; only updates changed rules
- **Retries**: Previously failed rules are flagged for retry on next execution
- **Idempotency**: Running multiple times produces the same result with no duplicate imports

### Content Folder Structure

Imported community rules are organised by source:

```
AnalyticalRules/Community/
└── Dalonso/
    ├── *.yaml                    # Imported community detection rules (per category subfolder)
    └── import-manifest.json      # Content-hash manifest

Docs/Community/
└── Dalonso.md                    # Auto-generated summary, governance doc lives at Docs/Community-Rules.md
```

Each imported rule includes:
- Original rule title and description
- Tactics and techniques (MITRE ATT&CK)
- Severity level
- Source repository attribution
- Original author information (where available)
- `enabled: false` flag for review

---

## Set-PlaybookPermissions.ps1

Post-deployment RBAC bootstrap for Logic App playbooks. After
`Deploy-CustomContent.ps1` deploys playbooks (each tagged
`Source: Sentinel-As-Code`), this script scans them, determines what
permissions each playbook actually needs based on its workflow content,
and assigns the minimum required roles to each Logic App's
system-assigned managed identity.

### Why this script exists

`Deploy-CustomContent.ps1` runs as the deployment service principal,
which has `Contributor` on the resource group plus an ABAC-conditioned
`User Access Administrator` role (set up by `Setup-ServicePrincipal.ps1`).
That ABAC condition is intentionally restrictive — the deployer can only
assign a fixed set of low-privilege roles. It cannot, for example,
grant `Microsoft Sentinel Contributor` directly on the workspace.

The role-assignment work is therefore split out:
- **`Deploy-CustomContent.ps1`** deploys the Logic App ARM templates
  (the playbook resource itself), enables system-assigned managed
  identity, and tags it with `Source: Sentinel-As-Code`.
- **`Set-PlaybookPermissions.ps1`** runs separately as a higher-privilege
  identity (User Access Administrator or Owner) and grants the playbook
  MSIs the roles they need to actually function.

### Key features

- **Tag-scoped discovery** — only Logic Apps with the `Source: Sentinel-As-Code` tag are considered, so hand-deployed Logic Apps in the same resource group are left alone.
- **Workflow-content analysis** — instead of granting every role to every playbook, the script inspects each workflow's JSON to derive the minimum role set:
  - **API connectors** (`azuresentinel`, `keyvault`, `wdatp`, `azuremonitorlogs`, `microsoftgraphsecurity`, etc.) → mapped to specific roles per connector type.
  - **HTTP actions using ManagedServiceIdentity** — when a playbook calls Graph, Defender, or Log Analytics REST APIs directly via the HTTP action with `authentication.type: ManagedServiceIdentity`, the script reads the URL prefix to grant the right role for that endpoint.
  - **Sentinel-specific actions** — actions that modify incidents, watchlists, or comments require Sentinel-Contributor-tier roles even when the connector is generic.
- **Idempotent** — re-runs are safe; existing assignments are detected and skipped.
- **WhatIf mode** — preview every assignment before applying.

### Parameter reference

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `SubscriptionId` | string | No | Current Az context | Azure subscription containing the Logic Apps |
| `PlaybookResourceGroup` | string | Yes | - | Resource group where Logic App playbooks are deployed |
| `SentinelResourceGroup` | string | No | Same as `PlaybookResourceGroup` | Resource group containing the Sentinel workspace, if different |
| `SentinelWorkspaceName` | string | Yes | - | Log Analytics workspace name (used to scope Sentinel role assignments) |
| `KeyVaultName` | string | No | - | Key Vault used by playbooks. Required only when at least one playbook references Key Vault |
| `WhatIf` | switch | No | `$false` | Preview role assignments without applying |

### Usage

```powershell
# Standard run — Sentinel + playbooks in the same resource group
./Set-PlaybookPermissions.ps1 `
    -PlaybookResourceGroup "rg-sentinel-prod" `
    -SentinelWorkspaceName "law-sentinel-prod"

# Sentinel and playbooks in separate resource groups, Key Vault in use
./Set-PlaybookPermissions.ps1 `
    -PlaybookResourceGroup "rg-playbooks-prod" `
    -SentinelResourceGroup "rg-sentinel-prod" `
    -SentinelWorkspaceName "law-sentinel-prod" `
    -KeyVaultName "kv-sentinel-prod"

# Dry run
./Set-PlaybookPermissions.ps1 `
    -PlaybookResourceGroup "rg-sentinel-prod" `
    -SentinelWorkspaceName "law-sentinel-prod" `
    -WhatIf
```

### Prerequisites for the executing principal

The identity running this script needs **`User Access Administrator`** or
**`Owner`** on the playbook resource group (and on the Sentinel resource
group if different). The deployment SPN does not have this role by
default — `Setup-ServicePrincipal.ps1` only grants it under an ABAC
condition that doesn't permit Sentinel-tier role assignments. Run this
script under a separate elevated identity (typically a one-off run by
an admin user, not the pipeline SPN).

---

## Build-DependencyManifest.ps1

Walks `AnalyticalRules/` and `HuntingQueries/`, parses every embedded
KQL query, and emits or verifies `dependencies.json` — the manifest the
deploy pipeline reads to drive content-ordering decisions. Replaces the
previously hand-maintained workflow.

See [Operations / Dependency Manifest](../Operations/Dependency-Manifest.md)
for the full discovery model, schema, and reasoning. This section
covers the script's parameter surface and operating modes.

### Key features

- **Three operating modes** — Generate (write the manifest from
  discovery), Verify (drift-check vs the on-disk manifest, used by
  the PR-validation gate), Update (drift-detect + write to disk for
  the daily auto-PR workflow).
- **Repo-driven inventory** — no hard-coded table list. Functions
  come from `Parsers/**/*.yaml`, watchlists from
  `Watchlists/*/watchlist.json`, playbooks from `Playbooks/**/*.json`.
  Tables default to "anything not classified as a function" because
  tables are external (data plane) and not deployable from the repo.
- **KQL pattern coverage** — extracts identifiers from start of
  statement, after `let X =`, after `union`, inside `join` / `lookup`
  / `materialize` / `view` / `toscalar` subqueries, and from
  `table('X')` string-arg patterns (lambda-wrapper invocations).
- **Watchlist cross-validation** — flags `_GetWatchlist('alias')`
  references that don't resolve to an in-repo watchlist as warnings.
- **Offline** — no Azure auth required; reads YAML and JSON only.

### Parameter reference

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `Mode` | string (`Generate` \| `Verify` \| `Update`) | Yes | - | Operating mode (see below) |
| `RepoPath` | string | No | Parent of `Scripts/` folder | Repository root |
| `ManifestPath` | string | No | `<RepoPath>/dependencies.json` | Manifest file path |

### Operating modes

#### Generate

Walks content, builds the manifest, writes `dependencies.json`. Authors
run this locally after editing rules and commit the regenerated file
alongside the rule changes.

```powershell
./Scripts/Build-DependencyManifest.ps1 -Mode Generate
```

#### Verify

Builds the manifest in-memory and compares against the on-disk file.
Exits 0 on match, 1 on drift with a structured diff. Used by:

- The PR-validation `dependency-manifest` job
  ([`.github/workflows/pr-validation.yml`](../../.github/workflows/pr-validation.yml))
  and its ADO equivalent
  ([`Pipelines/Sentinel-PR-Validation.yml`](../../Pipelines/Sentinel-PR-Validation.yml)).
- The pre-deploy guard at the start of the Deploy Custom Content stage
  in both [`sentinel-deploy.yml`](../../.github/workflows/sentinel-deploy.yml)
  and [`Sentinel-Deploy.yml`](../../Pipelines/Sentinel-Deploy.yml).

```powershell
./Scripts/Build-DependencyManifest.ps1 -Mode Verify
# exit 0 = manifest matches; exit 1 = drift (with diff printed)
```

#### Update

Like Verify, but on detected drift writes the regenerated manifest to
disk and exits 0. The calling pipeline owns the commit + branch + PR
step. Used by the daily auto-PR workflow
([`sentinel-dependency-update.yml`](../../.github/workflows/sentinel-dependency-update.yml)
and its ADO equivalent).

```powershell
./Scripts/Build-DependencyManifest.ps1 -Mode Update
```

### Author workflow

After editing or adding a rule that references new tables, watchlists,
or functions:

```powershell
./Scripts/Build-DependencyManifest.ps1 -Mode Generate
git add dependencies.json
git commit
```

If you forget, the PR-validation gate fails with a clear "out of sync"
error and the regenerate command. If you forget AND the gate's path
filter misses the change (rare — happens for doc-only commits that
adjust an inline query), the daily workflow opens a chore PR within
24 hours.

### Prerequisites

- PowerShell 7.2+
- `powershell-yaml` module (auto-installed by the script if missing)
- `Modules/Sentinel.Common` (auto-imported from the script — provides
  `Get-ContentDependencies` and the KQL extractors)

---

## Authoring with GitHub Copilot

When editing files under `Scripts/**` or `Modules/**`, Copilot
automatically loads
[`.github/instructions/powershell-scripts.instructions.md`](../../.github/instructions/powershell-scripts.instructions.md).
The path-scoped instructions cover the file-header convention,
`Sentinel.Common` import patterns, and the foot-gun list
(`[void]` Boolean leak, single-element array indexing, strict-mode
property access, `$script:` scope rules).

Copilot tooling for scripts and modules:

- Agent `Sentinel-As-Code: PowerShell Engineer` — owns
  `Modules/Sentinel.Common` end-to-end. Add functions, refactor
  scripts, modernise legacy patterns, harden against strict-mode
  failures. Knows the module-manifest discipline (version bump +
  ReleaseNotes + Pester tests in lockstep).
- Agent `Sentinel-As-Code: Dependencies Engineer` — when a change
  touches the discovery extractors (`Get-KqlBareIdentifiers`,
  `Get-ContentDependencies`, etc.).
- Agent `Sentinel-As-Code: Security Reviewer` — for review of
  secret-handling, log-leak surface, RBAC-impacting scripts.
- Slash command `/regenerate-deps` (VS Code) — runs
  `Build-DependencyManifest -Mode Generate`.

See [GitHub Copilot setup](../Development/GitHub-Copilot.md) for the full layout.

---

## Export-SentinelWorkbooks.ps1

Exports every Sentinel workbook in a workspace into the
`Workbooks/<FolderName>/` shape that
[`Deploy-CustomContent.ps1`](../../Scripts/Deploy-CustomContent.ps1)'s
`Deploy-CustomWorkbooks` function redeploys from. The exported tree
is byte-compatible with what the deployer reads — round-trip
(export → commit → redeploy) lands updates on the same Azure
resource rather than spawning duplicates.

### Key features

- **Bulk export** — lists every Sentinel-scoped workbook in one
  REST call (`Microsoft.Insights/workbooks` filtered by
  `category=sentinel` and `sourceId={workspaceResourceId}`).
- **Content Hub workbooks excluded by default** — only Custom
  workbooks land in the repo. The script enumerates the
  workspace's `Microsoft.SecurityInsights/metadata` resources to
  identify which workbooks were installed by a Content Hub
  solution (via `source.kind == 'Solution'`), and skips them.
  Override with `-IncludeContentHub` if you have a specific reason
  (e.g. forking a solution-provided workbook into your own
  governance — rare).
- **Folder name = PascalCase compaction of `displayName`** — the
  on-disk folder is the workbook's displayName with non-alphanumeric
  runs (spaces, punctuation, parens) treated as word boundaries
  and each word TitleCased. All-upper acronyms become TitleCase
  (`GBP` → `Gbp`); user-curated camelCase brands (e.g. `pfSense`)
  are preserved. This matches the existing `Workbooks/*` convention
  in the repo (e.g. `MicrosoftSentinelCostGbp`,
  `MicrosoftSentinelMonitoring`).
- **Workspace-name suffix stripped** — Microsoft-published
  workbook templates that get instantiated per-workspace pick up
  a ` - <workspace-name>` suffix on their displayName (e.g.
  `Data Collection Rule Toolkit - stl-eus-siem-law`). The script
  strips this suffix before deriving the folder name AND from
  the metadata.json's displayName. Sentinel re-attaches it at
  display time on redeploy, so the round-trip stays stable.
- **Workspace ARM ID stripped from workbook content** — Sentinel
  bakes the source workspace's full ARM resource ID into
  `fallbackResourceIds` and sometimes inline resource references
  (e.g. `/subscriptions/<sub>/resourceGroups/<rg>/providers/microsoft.operationalinsights/workspaces/<ws>`).
  The script replaces every case-insensitive occurrence with the
  placeholder convention used by hand-curated repo workbooks
  (`/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/your-resource-group/providers/microsoft.operationalinsights/workspaces/your-workspace`),
  so the workbook isn't pinned to one specific workspace. The
  field only affects standalone Workbooks-portal viewing; opening
  the workbook from within a Sentinel workspace uses the
  workspace context regardless.
- **Workbook GUID preservation** — writes the workbook's resource
  GUID into `metadata.json` as `workbookId`. The next deploy
  reads it back and hits the same Azure resource, avoiding the
  duplicate-workbook failure mode.
- **`-OnlyMissing` mode** — skip workbooks that already have a
  folder. Useful for incremental import without overwriting
  in-repo customisations.
- **`-Filter` regex** — narrow the export to a subset by
  `displayName` match.
- **`-WhatIf` mode** — read everything, write nothing.
- **Azure Government Support** — `-IsGov` switch.
- **Existing-metadata preservation** — extra keys in an existing
  `metadata.json` (tags, custom annotations) survive overwrite;
  only the keys this script writes are replaced.

### Parameter reference

| Parameter | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `SubscriptionId` | string | No | Current Az context | Azure Subscription ID |
| `ResourceGroup` | string | Yes | - | Resource group containing the Sentinel workspace |
| `Workspace` | string | Yes | - | Log Analytics workspace name (used to derive `WorkspaceResourceId` for the `sourceId` filter) |
| `Region` | string | Yes | - | Azure region (passed through to `Connect-AzureEnvironment`) |
| `BasePath` | string | No | Parent of `Scripts/` | Repo root path; output is written to `<BasePath>/Workbooks/` |
| `Filter` | string | No | `'.'` | Regex applied to each workbook's `displayName`; non-matching workbooks skipped |
| `OnlyMissing` | switch | No | `$false` | Skip workbooks that already have a folder under `Workbooks/` |
| `IncludeContentHub` | switch | No | `$false` | By default, Content Hub-managed workbooks are excluded. Pass to include them (advanced; usually wrong because Content Hub will overwrite on update) |
| `WhatIf` | switch | No | `$false` | Preview without writing |
| `IsGov` | switch | No | `$false` | Target Azure Government cloud |

### Usage examples

#### Export every workbook in the workspace

```powershell
.\Export-SentinelWorkbooks.ps1 `
    -ResourceGroup 'rg-sentinel-prod' `
    -Workspace     'law-sentinel-prod' `
    -Region        'uksouth'
```

#### Incremental import — only workbooks not in the repo yet

```powershell
.\Export-SentinelWorkbooks.ps1 `
    -ResourceGroup 'rg-sentinel-prod' `
    -Workspace     'law-sentinel-prod' `
    -Region        'uksouth' `
    -OnlyMissing
```

#### Preview without writing

```powershell
.\Export-SentinelWorkbooks.ps1 `
    -ResourceGroup 'rg-sentinel-prod' `
    -Workspace     'law-sentinel-prod' `
    -Region        'uksouth' `
    -WhatIf
```

#### Export only workbooks whose display name starts with 'Identity'

```powershell
.\Export-SentinelWorkbooks.ps1 `
    -ResourceGroup 'rg-sentinel-prod' `
    -Workspace     'law-sentinel-prod' `
    -Region        'uksouth' `
    -Filter        '^Identity'
```

### How it works

1. **Authentication and Setup**: Imports the `Sentinel.Common`
   module and calls `Connect-AzureEnvironment` to acquire an
   access token + workspace resource ID.
2. **Identify Content Hub workbooks**: Unless `-IncludeContentHub`
   was supplied, the script first calls
   `GET .../providers/Microsoft.SecurityInsights/metadata?api-version=2025-09-01`
   (with pagination) and builds a HashSet of workbook resource IDs
   where `properties.kind == 'Workbook'` AND
   `properties.source.kind == 'Solution'`. Any workbook found in
   this set is skipped during the export pass.
3. **List**: Calls
   `GET /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Insights/workbooks?api-version=2022-04-01&category=sentinel&sourceId={workspaceResourceId}&canFetchContent=true`
   to enumerate Sentinel workbooks. **`canFetchContent=true` is
   essential** — without it the LIST API returns only resource
   metadata, omitting the `serializedData` (the gallery template
   content) to keep response sizes small. The flag tells ARM to
   include full content for workbooks the caller has read access to.
4. **Per-workbook GET fallback**: If a workbook's content is still
   absent from the LIST response (rare — typically a Microsoft-
   published Content Hub workbook the workspace inherits, which
   the metadata-based filter in step 2 should have already
   excluded), the script does a per-resource
   `GET /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Insights/workbooks/{name}?canFetchContent=true`
   to resolve content one workbook at a time. Only workbooks where
   neither the list nor the detail fetch returns content get
   skipped (with a clear warning explaining the cause).
5. **Per-workbook export**: For each result:
   - Skip if the workbook ID is in the Content Hub set (unless
     `-IncludeContentHub` was supplied)
   - Filter by regex on `displayName` if `-Filter` was supplied
   - Strip any trailing ` - <WorkspaceName>` suffix from the
     displayName (Microsoft attaches this to workspace-instantiated
     templates; not useful for repo storage)
   - Skip if `-OnlyMissing` and the folder already exists
   - Reformat `serializedData` (a JSON string) via
     `ConvertFrom-Json` + `ConvertTo-Json -Depth 32` so the
     on-disk file is pretty-printed
   - Replace every occurrence of the source workspace's ARM
     resource ID in the JSON with the placeholder
     `/subscriptions/00000000-0000-0000-0000-000000000000/...`
     (case-insensitive) so the workbook isn't pinned to one
     workspace
   - Write `Workbooks/<FolderName>/workbook.json` and
     `Workbooks/<FolderName>/metadata.json` (using the cleaned
     displayName for both folder name and metadata.json)
6. **Status reporting**: Prints a summary table with exported /
   skipped / failed counts.

### Symmetry contract with `Deploy-CustomWorkbooks`

| Concern | Export side | Deploy side |
| --- | --- | --- |
| API version | `2022-04-01` | `2022-04-01` |
| Folder name | PascalCase compaction of `displayName` (with workspace suffix stripped) | Folder name walked as-is; deploy reads `displayName` from `metadata.json` |
| `workbook.json` content | The full gallery template | Read into `serializedData` of the deploy body |
| `metadata.json` keys read | `displayName`, `description`, `category`, `sourceId`, `workbookId` | Same keys consumed |
| Resource GUID | Preserved via `workbookId` | Used as the URI's `{workbookId}` segment |

### Prerequisites

- PowerShell 7.2+
- `Az.Accounts` (auto-imported by `Sentinel.Common`)
- Authenticated Azure context (`Connect-AzAccount` or service-principal context)
- The deploy SP needs at least **Microsoft Sentinel Reader** on the workspace to list workbooks. The standard `Setup-ServicePrincipal.ps1` Contributor grant covers this.

### Known limitations

- Only workbooks where `category == sentinel` are exported. Application Insights / general-purpose workbooks living under the same workspace are filtered out by design.
- Content Hub-managed workbooks are excluded by default (see step 2 of How it works). If the workspace has many Content Hub solutions installed, you may see a long list of "Skipping ... — Content Hub-managed workbook" messages. This is intentional; pass `-IncludeContentHub` only if you have a specific reason.
- Templates that haven't been customised in the workspace don't appear at all — they're served from the Content Hub catalogue, not the workspace's resource list, so there's nothing to export.
