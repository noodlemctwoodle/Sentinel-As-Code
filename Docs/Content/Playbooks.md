# Playbooks

Custom playbooks (Azure Logic Apps) for automated incident response, entity enrichment, and scheduled automation. Each playbook is a Bicep file under [`Content/Playbooks/`](../../Content/Playbooks), organised by trigger category, deployed by `Deploy-iSOCContent` in the [iSOCDeployments module](../Modules/iSOCDeployments/README.md).

## Folder Structure

```
Content/Playbooks/
├── bicepconfig.json  # Bicep settings for every playbook (see Building and checking)
├── Module/           # 31 reusable child workflows (called by other playbooks)
├── Incident/         # 36 incident-triggered playbooks
├── Entity/           # 16 entity enrichment playbooks
├── Alert/            #  1 alert-triggered playbook
├── Watchlist/        #  3 watchlist management playbooks
├── Other/            #  3 utility/standalone playbooks
└── Template/         # Template.bicep, the starting point for a new playbook (never deployed)
```

## Naming Convention

Playbooks follow a `{Category}-{Name}` naming convention when deployed to Azure:

- **Module playbooks** deploy as `Module-{Name}` (e.g., `Module-AddSentinelComment`)
- **Incident playbooks** deploy as `{Name}` with the `PlaybookName` parameter
- **Entity/Alert/Watchlist/Other** follow the same pattern

The `PlaybookName` parameter's default is the Logic App's name: the deploy updates the workflow of that name, and `Export-iSOCContent` uses it to find the file that holds a Logic App.

## Bicep Structure

Each playbook is one `.bicep` file holding the Logic App and its API connections:

```bicep
metadata title = 'AddSentinelComment'
metadata description = 'Reusable automation module: AddSentinelComment.'

param PlaybookName string = 'Module-AddSentinelComment'
param AutomationResourceGroup string = ''

var MicrosoftSentinelConnectionName = 'azuresentinel-${PlaybookName}'

#disable-next-line BCP081
resource workflow 'Microsoft.Logic/workflows@2017-07-01' = {
  name: PlaybookName
  location: resourceGroup().location
  tags: {
    Source: 'Sentinel-As-Code'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: { ... }
    parameters: {
      '$connections': {
        value: {
          azuresentinel: {
            connectionId: MicrosoftSentinelConnection.id
            ...
          }
        }
      }
    }
  }
}

resource MicrosoftSentinelConnection 'Microsoft.Web/connections@2016-06-01' = { ... }
```

- The workflow definition is the Logic Apps definition, as the designer's code view shows it; its `@{...}` expressions are ordinary Bicep strings.
- A connection is referred to by its symbolic name (`MicrosoftSentinelConnection.id`), so Bicep orders the deployment itself.
- `#disable-next-line` lines sit where Bicep's own type data for these resource types is missing or wrong: there is none for Logic Apps `2017-07-01` (`BCP081`), and API connections `2016-06-01` lack `kind` (`BCP187`) and `parameterValueType` (`BCP037`), though both are valid. Keep them, so the file builds without warnings.
- A playbook whose Logic App needs a value per environment can keep a `<Name>.parameters.json` beside it; the deploy passes it with the template.

Forks that have not converted yet can keep JSON playbooks (ARM templates in the same folders): the module reads, deploys and exports both. See [Converting JSON playbooks](#converting-json-playbooks).

### Auto-Injected Parameters

`Deploy-iSOCContent` fills a parameter from the workspace only when the playbook declares one of that name, so a playbook that omits one is never handed it:

| Parameter | Injected value |
|-----------|----------------|
| `AutomationResourceGroup` | Playbook resource group |
| `PlaybookResourceGroup` | Playbook resource group |
| `SentinelResourceGroup` | Sentinel (main) resource group |
| `SentinelResourceGroupName` | Sentinel (main) resource group |
| `SentinelWorkpaceName` | Sentinel workspace name (misspelling kept for the templates that use it) |
| `SentinelWorkspaceName` | Sentinel workspace name (correct spelling) |
| `SubscriptionId` | Target subscription ID |
| `WorkspaceId` | Sentinel workspace GUID (`customerId`), only when the connection resolved it |

The playbook resource group is the one `Connect-iSOCWorkspace -PlaybookResourceGroup` names, or the Sentinel resource group when none is given.

### Resource Tags

Every playbook's workflow carries one tag, which `Grant-iSOCPlaybookPermission` looks for:

```bicep
tags: {
  Source: 'Sentinel-As-Code'
}
```

## Connection Types

### Managed Identity (MSI) Connections

Connectors that support managed identity use `parameterValueType: 'Alternative'`:

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

Playbooks deploy in the deploy pipeline's custom content stage (`Deploy-iSOCWorkspace -Stage CustomContent`), or locally with `Deploy-iSOCContent -ContentType Playbook`. The module:

1. Reads every `.bicep` and `.json` file under `Content/Playbooks/`, leaving out parameter files, `bicepconfig.json` and the `Template/` folder. The Bicep files are compiled together, in one run of the Bicep CLI; one that does not compile fails with the compiler's errors.
2. Deploys **Module** playbooks first, each after the modules it calls (a `Microsoft.Logic/workflows/Module-<name>` reference), then the other categories in repository order. A call to a module the repository does not have is warned about, and modules that call each other in a cycle deploy after the other modules, with a warning.
3. Deploys each as a resource group deployment named `Playbook-<file>-<yyyyMMddHHmmss>` (cut to Azure's 64-character limit) to the playbook resource group, with the parameters above. Under `-WhatIf` each is validated against the resource group instead.

Smart deployment, when the run asks for it, skips a playbook whose file has not changed since its last successful deploy. See [Deploying content](../Modules/iSOCDeployments/Deploy.md).

The machine that deploys needs Az.Resources and the Bicep CLI on the PATH (the pipelines put it there; locally, `az bicep install` puts it in `~/.azure/bin`).

### Separate Resource Group

To deploy playbooks to a dedicated resource group:

1. Add `playbookResourceGroup` to the `sentinel-deployment` variable group
2. Add `playbookRgName` to the Bicep parameters (the Bicep template creates the RG)
3. The pipeline validates the RG exists before deployment

If `playbookResourceGroup` is empty or not set, playbooks deploy to the Sentinel resource group.

## Post-Deploy Permissions (manual)

RBAC for playbook managed identities is deliberately kept out of the deploy pipeline. `Grant-iSOCPlaybookPermission` is run separately by an identity with **User Access Administrator** or **Owner** on the target scope: the deployment service principal's ABAC-conditioned User Access Administrator grant cannot assign Sentinel-tier roles.

It finds the Logic Apps in the playbook resource group that carry the `Source: Sentinel-As-Code` tag, reads each workflow's `$connections` and HTTP actions, and assigns the minimum roles it infers:

| Detected in the workflow | Role assigned | Scope |
|--------------------------|---------------|-------|
| `azuresentinel` / `microsoftsentinel` connector | Microsoft Sentinel Responder | Resource group |
| Mutating Sentinel actions (`/Incidents`, `/Watchlists`, an `Update_incident` action, or a PUT request) | Microsoft Sentinel Contributor (upgraded from Responder) | Resource group |
| `keyvault` connector | Key Vault Secrets User | Key Vault |
| `azuremonitorlogs` / `azureloganalyticsdatacollector` connector, or an HTTP action to `api.loganalytics.io` | Log Analytics Reader | Resource group |
| HTTP action (MSI) to `management.azure.com` | Microsoft Sentinel Contributor | Resource group |

HTTP actions to Microsoft Graph or the Defender API map to no RBAC role, because those permissions are granted through an app registration rather than Azure RBAC. Existing assignments are left alone, and `-WhatIf` previews the assignments. See [Permissions](../Modules/iSOCDeployments/Permissions.md).

## Writing a new playbook

Copy [`Template/Template.bicep`](../../Content/Playbooks/Template/Template.bicep) into the folder for its trigger, give the file the playbook's name, set `PlaybookName`'s default and add the actions. It is a Logic App triggered when a Sentinel incident is created, with a Microsoft Sentinel connection that uses the Logic App's managed identity, the `Source: Sentinel-As-Code` tag and the parameters the deploy fills in.

Or build the Logic App in the portal and export it.

## Exporting from Azure

`Export-iSOCContent -ContentType Playbook` writes each Logic App in the playbook resource group as a Bicep playbook, ready to deploy: new ones to `Content/Playbooks/<Trigger>/<Name>.bicep`, and ones the repository already has only with `-Force`. Subscription, resource group and workspace values become the parameters above, each connection becomes a connection resource, and the workflow keeps its live state and gets the tag and a metadata block. A value that looks like a plain-text secret is warned about, not removed: move it to Key Vault before committing. The export needs no Bicep CLI. See [Export](../Modules/iSOCDeployments/Export.md).

```powershell
Import-Module ./Modules/iSOCDeployments/iSOCDeployments.psd1
Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel -PlaybookResourceGroup rg-automation
Export-iSOCContent -ContentType Playbook -WhatIf
```

`-Format Json` writes a new playbook as an ARM template instead. A playbook the repository already has is written in its own file's format.

## Converting JSON playbooks

The repository's playbooks moved from ARM JSON to Bicep in release 26.11.0. A fork with JSON playbooks keeps deploying them; to move to Bicep, run:

```powershell
Import-Module ./Modules/iSOCDeployments/iSOCDeployments.psd1
Convert-iSOCPlaybook -WhatIf
Convert-iSOCPlaybook
```

Each JSON playbook is written as Bicep, compiled, and compared with the JSON it came from; only when the two deploy the same thing is the `.bicep` written and the JSON removed. One that cannot be converted is left as JSON, with the reason. Copy this repository's [`bicepconfig.json`](../../Content/Playbooks/bicepconfig.json) into your `Content/Playbooks/` first, so the converted files build without warnings. See [Converting JSON playbooks to Bicep](../Modules/iSOCDeployments/Export.md#converting-json-playbooks-to-bicep).

## Building and checking

- [`bicepconfig.json`](../../Content/Playbooks/bicepconfig.json) turns off one Bicep linter rule for playbooks, `no-unused-params`: the deploy fills parameters by name, and the exporter declares the Sentinel parameters on every Sentinel-triggered playbook whether or not its workflow uses them. Every other warning stays on.
- `bicep build Content/Playbooks/Incident/IsolateMachine.bicep --stdout` shows the ARM template a playbook deploys.
- The PR checks build every playbook and fail on an error or a warning (`bicep-build`), validate each against a resource group (`arm-validate`), and hold each compiled template to the playbook invariants in [`Tests/Test-PlaybookArm.Tests.ps1`](../../Tests/Test-PlaybookArm.Tests.ps1).

## Notes

- Playbooks deploy as resource group deployments (`New-AzResourceGroupDeployment`), not through the REST API
- MSI connections deploy fully automated; standard connections require one-time manual authorisation
- Module playbooks are called by parent playbooks via `Workflow` actions; the `Module-` prefix in `PlaybookName` must match the workflow reference
- WhatIf mode validates the template without deploying
- The `Template/` folder is always excluded from deployment
- Managed-identity role assignments are NOT part of the deploy pipeline; `Grant-iSOCPlaybookPermission` applies them out-of-band (see [Post-Deploy Permissions](#post-deploy-permissions-manual))

## Authoring with GitHub Copilot

When editing files under `Content/Playbooks/**`, Copilot automatically
loads [`.github/instructions/playbooks.instructions.md`](../../.github/instructions/playbooks.instructions.md).
The path-scoped instructions cover the trigger-type folder layout, the
Bicep shape, the auto-injected parameter set, the `Source: Sentinel-As-Code`
tag requirement that `Grant-iSOCPlaybookPermission` keys off, and the rule
against embedding secrets directly.

Copilot tooling for playbooks:

- Agent `Sentinel-As-Code: Content Editor` for general edits
- Agent `Sentinel-As-Code: Security Reviewer`, strongly recommended
  for any playbook touching Key Vault, Graph, Defender, or
  high-privilege endpoints

See [GitHub Copilot setup](../GitHub/GitHub-Copilot.md) for the full layout.
