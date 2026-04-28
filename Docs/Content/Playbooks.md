# Playbooks

Custom playbooks (Azure Logic Apps) for automated incident response, entity enrichment, and scheduled automation. Each playbook is an ARM JSON template under [`Playbooks/`](../../Playbooks/) organised by trigger category.

## Folder Structure

```
Playbooks/
├── Module/       # 31 reusable child workflows (called by other playbooks)
├── Incident/     # 38 incident-triggered playbooks
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

The deploy script automatically injects these parameters if present in the template — no manual configuration needed:

| Parameter | Value |
|-----------|-------|
| `AutomationResourceGroup` | Playbook resource group name |
| `SentinelWorkpaceName` | Sentinel workspace name |
| `SentinelWorkspaceId` | Workspace resource ID |

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

Playbooks deploy automatically via the pipeline's Stage 4 (Custom Content). The deploy script:

1. Discovers all `.json` files recursively (excludes `Template/` folder)
2. Deploys **Module** playbooks first (leaf modules before dependent modules)
3. Deploys remaining categories (Incident, Entity, Alert, Watchlist, Other)
4. Auto-injects parameters, truncates names to 64 characters
5. Optionally deploys to a separate resource group (set `playbookResourceGroup` in the variable group)

### Separate Resource Group

To deploy playbooks to a dedicated resource group:

1. Add `playbookResourceGroup` to the `sentinel-deployment` variable group
2. Add `playbookRgName` to the Bicep parameters (the Bicep template creates the RG)
3. The pipeline validates the RG exists before deployment

If `playbookResourceGroup` is empty or not set, playbooks deploy to the Sentinel resource group.

## Exporting from Azure

Use the included export script to pull all playbooks from an existing resource group:

```powershell
./Scripts/Export-Playbooks.ps1 `
    -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -ResourceGroupName "rg-sentinel-prod" `
    -OutputPath "./Playbooks"
```

The export script:
- Discovers all Logic Apps via REST API (with pagination)
- Detects trigger type to categorise (Incident, Entity, Alert, Module, Watchlist, Other)
- Sanitises hardcoded subscription IDs and resource group names into ARM expressions
- Builds clean ARM templates with parameterised connections
- Handles MSI vs standard connections correctly
- Generates metadata with author and description

See [Scripts.md](../Deployment/Scripts.md#export-playbooksps1) for the full Export-Playbooks parameter reference.

## Notes

- Playbooks deploy via `New-AzResourceGroupDeployment` (ARM), not REST API
- MSI connections deploy fully automated; standard connections require one-time manual authorisation
- Module playbooks are called by parent playbooks via `Workflow` actions — the `Module-` prefix in `PlaybookName` must match the workflow reference
- WhatIf mode validates the template without deploying
- The `Template/` folder is always excluded from deployment
- Post-deploy: managed-identity role assignments are handled by [`Scripts/Set-PlaybookPermissions.ps1`](../../Scripts/Set-PlaybookPermissions.ps1) — see [Scripts.md](../Deployment/Scripts.md#set-playbookpermissionsps1)
