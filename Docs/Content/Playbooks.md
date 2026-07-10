# Playbooks

Custom playbooks (Azure Logic Apps) for automated incident response, entity enrichment, and scheduled automation. Each playbook is an ARM JSON template under [`Content/Playbooks/`](../../Content/Playbooks) organised by trigger category.

## Folder Structure

```
Content/Playbooks/
├── Module/       # 31 reusable child workflows (called by other playbooks)
├── Incident/     # 36 incident-triggered playbooks
├── Entity/       # 16 entity enrichment playbooks
├── Alert/        #  1 alert-triggered playbook
├── Watchlist/    #  3 watchlist management playbooks
├── Other/        #  3 utility/standalone playbooks
└── Template/     #  1 reference template (excluded from deployment)
```

## Naming Convention

Playbooks follow a `{Category}-{Name}` naming convention when deployed to Azure:

- **Module playbooks** deploy as `Module-{Name}` (e.g., `Module-AddSentinelComment`)
- **Incident playbooks** deploy as `{Name}` with the `PlaybookName` parameter
- **Entity/Alert/Watchlist/Other** follow the same pattern

## ARM Template Structure

Each playbook is a single JSON file containing a complete ARM template:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "metadata": { ... },
  "parameters": {
    "PlaybookName": { "defaultValue": "Module-AddSentinelComment", "type": "string" },
    "SentinelWorkpaceName": { "defaultValue": "", "type": "string" },
    "AutomationResourceGroup": { "defaultValue": "", "type": "string" }
  },
  "variables": { ... },
  "resources": [ ... ]
}
```

### Auto-Injected Parameters

`Deploy-CustomPlaybooks` (in `Deploy/content/Deploy-CustomContent.ps1`) builds a `$knownParams` map from the pipeline context and injects a value only when the target template actually declares a parameter of that name. The deployer inspects `$templateContent.parameters` and passes through the intersection, so a template that omits a parameter is never handed one it does not expect. No manual configuration is needed.

| Parameter | Injected value |
|-----------|----------------|
| `AutomationResourceGroup` | Playbook resource group (`$script:PlaybookRG`) |
| `PlaybookResourceGroup` | Playbook resource group (`$script:PlaybookRG`) |
| `SentinelResourceGroup` | Sentinel (main) resource group |
| `SentinelResourceGroupName` | Sentinel (main) resource group |
| `SentinelWorkpaceName` | Sentinel workspace name (misspelling kept for back-compat with older templates) |
| `SentinelWorkspaceName` | Sentinel workspace name (correct spelling) |
| `SubscriptionId` | Target subscription ID |
| `WorkspaceId` | Sentinel workspace GUID (`customerId`), injected only when it was resolved during connection (non-fatal if lookup fails) |

`$script:PlaybookRG` resolves to the value passed in `-PlaybookResourceGroup` if a separate playbook resource group is configured, otherwise to the main Sentinel resource group. There is no `SentinelWorkspaceId` parameter in the code; the workspace GUID is injected as `WorkspaceId`.

### Resource Tags

All deployed playbooks receive a single tag:

```json
"tags": {
  "Source": "Sentinel-As-Code"
}
```

## Connection Types

### Managed Identity (MSI) Connections

Connectors that support managed identity use `parameterValueType: Alternative`:

- Microsoft Sentinel (`azuresentinel`)
- Microsoft Defender XDR (`wdatp`)
- Azure Key Vault (`keyvault`)

### Standard Connections

Connectors that do NOT support MSI deploy without `parameterValueType` and require manual authorisation after first deployment:

- Office 365 (`office365`)
- Microsoft Teams (`teams`)
- Azure Monitor Logs (`azuremonitorlogs`)
- Azure Log Analytics Data Collector (`azureloganalyticsdatacollector`)
- VirusTotal (`virustotal`)
- SharePoint Online (`sharepointonline`)

## Deployment

### Pipeline Deployment

Playbooks deploy automatically via the pipeline's Stage 4 (Custom Content), which is where `Deploy-CustomContent.ps1` runs its playbook stage. The deploy script:

1. Discovers all `.json` files recursively, excluding `*.parameters.json`, `.DS_Store`, and anything inside a `Template/` folder
2. Builds a dependency graph and deploys **Module** playbooks first (in dependency order), followed by all non-module categories (Incident, Entity, Alert, Watchlist, Other)
3. Auto-injects known parameters (only those the template declares) and truncates the ARM deployment name to fit the 64-character limit
4. Optionally deploys to a separate resource group (set `playbookResourceGroup` in the variable group)

#### Dependency-ordered Module deployment

The order of Module playbooks is computed automatically, not hand-maintained. `Deploy-CustomPlaybooks` scans every template for `Microsoft.Logic/workflows/{name}` references to build a directed dependency graph, then topologically sorts the Module playbooks with Kahn's algorithm so that leaf modules (those referencing no other module) deploy before the modules that call them. The log reports the split, for example `Deploying 31 Module playbook(s) first (N leaf, M dependent) in dependency order`. If a circular dependency is detected the affected modules cannot be sorted, so the script logs a warning and appends them in file order rather than failing. A pre-flight pass also warns when a playbook references a module that is not present in the repo.

#### Smart deployment (unchanged-file skip)

Each candidate file is passed through `Test-ShouldDeployFile` before deployment. When smart deployment is active, a file whose content is unchanged since the last successful deploy is logged as `Unchanged` and counted as skipped (the log line ends `skipping (smart deployment)`), so a pipeline run only redeploys playbooks that have actually changed. Smart deployment is an opt-in `-SmartDeployment` switch on the deploy entry point and defaults to OFF (a full deploy of every playbook); see [Deploy-CustomContent.ps1](../Deploy/Scripts.md#deploy-customcontentps1).

#### Deployment name and validation

For each deployed template the script builds an ARM deployment name of the form `Playbook-{truncatedName}-{timestamp}` (the base name is truncated so the whole deployment name stays within Azure's 64-character limit). Under normal runs it calls `New-AzResourceGroupDeployment`; under `-WhatIf` it calls `Test-AzResourceGroupDeployment` to validate the template without deploying. A `Test-ContentDependencies` pre-flight check runs per template and skips any playbook whose declared dependencies are missing.

### Separate Resource Group

To deploy playbooks to a dedicated resource group:

1. Add `playbookResourceGroup` to the `sentinel-deployment` variable group
2. Add `playbookRgName` to the Bicep parameters (the Bicep template creates the RG)
3. The pipeline validates the RG exists before deployment

If `playbookResourceGroup` is empty or not set, playbooks deploy to the Sentinel resource group.

## Post-Deploy Permissions (manual)

RBAC for playbook managed identities is deliberately kept out of the deploy pipeline. [`Set-PlaybookPermissions.ps1`](../../Deploy/permissions/Set-PlaybookPermissions.ps1) is a standalone post-deploy script and is not referenced by any GitHub workflow or Azure DevOps pipeline. It must be run as a separate, manually elevated identity: the deployment service principal's ABAC-conditioned User Access Administrator grant cannot assign Sentinel-tier roles, so the script requires an executing principal with **User Access Administrator** or **Owner** on the target scope.

The script discovers Logic Apps in the playbook resource group carrying the `Source: Sentinel-As-Code` tag, inspects each workflow's `$connections` block and HTTP actions, and assigns the minimum roles it infers:

| Detected in the workflow | Role assigned | Scope |
|--------------------------|---------------|-------|
| `azuresentinel` / `microsoftsentinel` connector | Microsoft Sentinel Responder | Resource group |
| Mutating Sentinel actions (`/Incidents`, `/Watchlists`, an `Update_incident` action, or a PUT request) | Microsoft Sentinel Contributor (upgraded from Responder) | Resource group |
| `keyvault` connector | Key Vault Secrets User | Key Vault (requires `-KeyVaultName`) |
| `azuremonitorlogs` / `azureloganalyticsdatacollector` connector, or an HTTP action to `api.loganalytics.io` | Log Analytics Reader | Resource group |
| HTTP action (MSI) to `management.azure.com` | Microsoft Sentinel Contributor | Resource group |

HTTP actions targeting Microsoft Graph (`graph.microsoft.com`) or the Defender API (`api.securitycenter.microsoft.com`) are intentionally mapped to no RBAC role, because those permissions are granted through the playbook's app registration rather than Azure RBAC. Existing assignments are detected and skipped, and `-WhatIf` previews the assignments without applying them.

Parameters: `-PlaybookResourceGroup` and `-SentinelWorkspaceName` are mandatory; `-SentinelResourceGroup` defaults to the playbook resource group; `-SubscriptionId` falls back to the current Az context; `-KeyVaultName` is required only when playbooks reference Key Vault.

## Exporting from Azure

To pull existing playbooks out of an Azure resource group as ARM
templates, use the Azure CLI or `Export-AzResourceGroup` against
individual Logic Apps:

```powershell
# Single Logic App
Export-AzResourceGroup `
    -ResourceGroupName "rg-sentinel-prod" `
    -Resource "/subscriptions/<sub>/resourceGroups/rg-sentinel-prod/providers/Microsoft.Logic/workflows/<playbookName>" `
    -Path "./Content/Playbooks/<Category>"
```

The exported template needs a small amount of manual cleanup before
committing:
- Replace hardcoded subscription IDs and resource-group names with
  ARM expressions (`[subscription().subscriptionId]`,
  `[resourceGroup().name]`).
- Add a `metadata` block with `title`, `description`, and `author`
  (see existing files in [`Content/Playbooks/Module/`](../../Content/Playbooks/Module)
  for the convention).
- Tag the workflow resource with `"Source": "Sentinel-As-Code"` so
  [`Set-PlaybookPermissions.ps1`](../Deploy/Scripts.md#set-playbookpermissionsps1)
  picks it up post-deployment.

## Notes

- Playbooks deploy via `New-AzResourceGroupDeployment` (ARM), not REST API
- MSI connections deploy fully automated; standard connections require one-time manual authorisation
- Module playbooks are called by parent playbooks via `Workflow` actions; the `Module-` prefix in `PlaybookName` must match the workflow reference
- WhatIf mode validates the template without deploying
- The `Template/` folder is always excluded from deployment
- Managed-identity role assignments are NOT part of the deploy pipeline; they are applied out-of-band by [`Set-PlaybookPermissions.ps1`](../../Deploy/permissions/Set-PlaybookPermissions.ps1) (see [Post-Deploy Permissions](#post-deploy-permissions-manual) below)

## Authoring with GitHub Copilot

When editing files under `Content/Playbooks/**`, Copilot automatically
loads [`.github/instructions/playbooks.instructions.md`](../../.github/instructions/playbooks.instructions.md).
The path-scoped instructions cover the trigger-type folder layout,
the auto-injected ARM parameter set, the `Source: Sentinel-As-Code`
tag requirement that `Set-PlaybookPermissions.ps1` keys off, and
the rule against embedding secrets directly.

Copilot tooling for playbooks:

- Agent `Sentinel-As-Code: Content Editor` for general edits
- Agent `Sentinel-As-Code: Security Reviewer`, strongly recommended
  for any playbook touching Key Vault, Graph, Defender, or
  high-privilege endpoints

See [GitHub Copilot setup](../GitHub/GitHub-Copilot.md) for the full layout.
