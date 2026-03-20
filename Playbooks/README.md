# Playbooks

Custom playbooks (Azure Logic Apps) for automated incident response. Each playbook is a subfolder containing an ARM JSON template and an optional parameters file.

## Folder Structure

```
Playbooks/
  Block-AADUser-OnIncident/
    azuredeploy.json                # ARM template (Logic App + API connections)
    azuredeploy.parameters.json     # Optional environment-specific parameters
  Post-TeamsMessage-OnAlert/
    azuredeploy.json
    azuredeploy.parameters.json
```

## ARM Template Requirements

The `azuredeploy.json` file must be a valid ARM template containing:

1. **API connections** (`Microsoft.Web/connections`) — for Sentinel, Teams, Office 365, etc.
2. **Logic App workflow** (`Microsoft.Logic/workflows`) — the automation definition

### Managed Identity (Recommended)

Use Managed Identity for the Sentinel connection to avoid storing credentials:

```json
{
  "type": "Microsoft.Web/connections",
  "apiVersion": "2016-06-01",
  "name": "azuresentinel-connection",
  "properties": {
    "displayName": "azuresentinel-connection",
    "parameterValueType": "Alternative",
    "api": {
      "id": "[concat('/subscriptions/', subscription().subscriptionId, '/providers/Microsoft.Web/locations/', resourceGroup().location, '/managedApis/azuresentinel')]"
    }
  }
}
```

After deployment, grant the Logic App's Managed Identity the **Microsoft Sentinel Responder** role on the workspace.

## Parameters File (azuredeploy.parameters.json)

Optional. If present, the pipeline passes it automatically. Common parameters:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "PlaybookName": { "value": "Block-AADUser-OnIncident" },
    "WorkspaceName": { "value": "law-sentinel-prod" }
  }
}
```

## Exporting from Sentinel

Use the [Playbook ARM Template Generator](https://github.com/Azure/Azure-Sentinel/tree/master/Tools/Playbook-ARM-Template-Generator) to export existing playbooks with properly parameterised API connections.

Alternatively:
1. Navigate to the Logic App in the Azure Portal
2. Click **Export template**
3. Parameterise connection references and workspace-specific values
4. Save as `azuredeploy.json` in a new subfolder

## Notes

- Playbooks deploy via `New-AzResourceGroupDeployment` (ARM deployment), not REST API
- API connections for third-party services (Teams, ServiceNow) may require interactive authorisation after first deployment
- Sentinel Managed Identity connections deploy fully automated
- WhatIf mode validates the template without deploying
