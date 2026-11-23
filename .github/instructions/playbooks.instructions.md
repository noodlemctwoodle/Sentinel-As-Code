---
name: Playbooks
description: Bicep requirements for Logic App playbooks under Content/Playbooks/.
applyTo: "Content/Playbooks/**/*.bicep,Content/Playbooks/**/*.json"
---

# Playbook authoring (Logic App Bicep files)

Logic App playbooks are Bicep files under
`Content/Playbooks/<Trigger-Type>/<Name>.bicep`, deployed by
`Deploy-iSOCContent` (Modules/iSOCDeployments). Trigger-type folders are:

- `Alert/`: playbooks triggered by analytical rule alerts
- `Entity/`: entity-trigger playbooks (run from an entity timeline)
- `Incident/`: incident-trigger playbooks
- `Module/`: sub-flow modules invoked by other playbooks
- `Other/`: manual-trigger or scheduled playbooks
- `Template/`: *not deployed*; `Template.bicep` is the starting point for a new playbook
- `Watchlist/`: playbooks that mutate watchlists

`Content/Playbooks/bicepconfig.json` holds the Bicep settings every
playbook builds with. A `.json` file in these folders is an ARM template
from before the move to Bicep; the module still deploys it, and
`Convert-iSOCPlaybook` converts it.

Full guide in [`Docs/Content/Playbooks.md`](../../Docs/Content/Playbooks.md).

## Required Bicep structure

```bicep
metadata title = '<Playbook-Name>'
metadata description = '<one-line description>'
metadata lastUpdateTime = 'DD-MM-YYYY'
metadata entities = []
metadata tags = [
  '<Trigger-Type>'
  'Source: Sentinel-As-Code'
]
metadata support = {
  tier: 'community'
}
metadata author = {
  name: '<author>'
}

@description('The Logic App\'s name.')
param PlaybookName string = '<Name>'

@description('The playbook resource group; the deploy fills it in.')
param AutomationResourceGroup string = ''

@description('The Sentinel workspace\'s name; the deploy fills it in.')
param SentinelWorkpaceName string = ''

// Add playbook-specific parameters here, each with a @description

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var microsoftSentinelConnectionName = 'MicrosoftSentinel-${PlaybookName}'

resource workflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: PlaybookName
  location: location
  tags: {
    Source: 'Sentinel-As-Code'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: { ... }
}
```

## Hard rules

1. **The workflow resource's `tags` must include `Source: 'Sentinel-As-Code'`.**
   `Grant-iSOCPlaybookPermission` only assigns roles to Logic Apps
   carrying this tag. Untagged playbooks are ignored by the post-deploy
   RBAC step.
2. **Use the auto-injected parameters by name.** The deploy fills
   `AutomationResourceGroup`, `PlaybookResourceGroup`,
   `SentinelWorkpaceName` (note the typo, kept for the templates that use
   it), `SentinelWorkspaceName` (correctly spelled, also accepted),
   `SentinelResourceGroup`, `SentinelResourceGroupName`, `SubscriptionId`
   and `WorkspaceId` when the playbook declares them. Never rename a
   parameter: they are matched by name.
3. **Keep `PlaybookName` defaults to 64 characters or fewer.** Logic App
   resource names are limited to 64 characters.
4. **Module playbooks deploy first.** Files under
   `Content/Playbooks/Module/` are sub-flows other playbooks invoke. The
   deploy orders them first, each after the modules it calls, from their
   `Microsoft.Logic/workflows/Module-<name>` references, so keep those
   references as literal paths.
5. **Files under `Content/Playbooks/Template/` do not deploy.** That
   folder is for the authoring template only. Don't put real playbooks
   there.
6. **Use system-assigned managed identity** for connections to
   Sentinel, Defender, Graph and Key Vault (`parameterValueType: 'Alternative'`
   on the connection). Avoid user-credential connections in repo-managed
   playbooks.
7. **Keep the `#disable-next-line` lines.** They mark where Bicep's type
   data for API connections `2016-06-01` is missing (`BCP187` for `kind`,
   `BCP037` for `parameterValueType`), so the file builds without
   warnings. The PR checks fail a playbook that builds with a warning.
   Keep the Logic App at `Microsoft.Logic/workflows@2019-05-01`.
8. **Never embed secrets.** Use Key Vault references for runtime
   secrets. The connector identity needs `Key Vault Secrets User`;
   `Grant-iSOCPlaybookPermission` grants it when the playbook uses the
   Key Vault connector.
9. **Follow the repository's Bicep style**, as `Export-iSOCContent` and
   `Convert-iSOCPlaybook` write it: a `@description` on every parameter;
   `location` for the region, never `resourceGroup().location` outside
   its default (the linter warns); variables and resources in lower camel
   case, each API connection named after its managed API
   (`microsoftSentinelConnection`, `office365Connection`); and managed API
   ids as `subscriptionResourceId('Microsoft.Web/locations/managedApis', location, '<api>')`.

## After editing

1. Build it, and run the content tests:
   ```powershell
   bicep build Content/Playbooks/<Trigger-Type>/<Name>.bicep --stdout > $null
   Invoke-Pester -Path Tests/Test-PlaybookArm.Tests.ps1
   ```
2. The `bicep-build` PR-validation job builds every playbook, and
   `arm-validate` runs `Test-AzResourceGroupDeployment` against each,
   automatically.

## Post-deploy permission grant

After deploy, `Grant-iSOCPlaybookPermission` runs separately (not in the
deploy pipeline) under a higher-privilege identity. It inspects each
playbook's workflow and grants the playbook's managed identity the
minimum role set it needs. See
[`Docs/Modules/iSOCDeployments/Permissions.md`](../../Docs/Modules/iSOCDeployments/Permissions.md)
for the role mapping.

## Cross-references

- Full guide and connector mapping: [`Docs/Content/Playbooks.md`](../../Docs/Content/Playbooks.md)
- Export and conversion: [`Docs/Modules/iSOCDeployments/Export.md`](../../Docs/Modules/iSOCDeployments/Export.md)
- Tests: [`Tests/Test-PlaybookArm.Tests.ps1`](../../Tests/Test-PlaybookArm.Tests.ps1)
