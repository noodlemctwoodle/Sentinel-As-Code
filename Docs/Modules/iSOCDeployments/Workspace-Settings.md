# Workspace settings and onboarding

Two pieces of the deploy pipelines' first stages, which until now were
PowerShell written inline in the pipeline YAML, are in the module:

| Module | Replaces |
| --- | --- |
| `Get-iSOCWorkspaceOnboarding` | The Check for Existing Resources step of `.github/workflows/sentinel-deploy.yml` and the Check for Existing Log Analytics Workspace step of `Pipelines/Sentinel-Deploy.yml` |
| `Deploy-iSOCContent -ContentType WorkspaceSetting`, with the files in `Content/WorkspaceSettings/` | The Configure Sentinel Settings step of both pipelines |

The pipelines keep running their own steps until they move to the module
in the pipeline switch. Registering the resource providers and running
`Infra/sentinel/main.bicep` stay pipeline steps.

## Onboarding

```powershell
Import-Module ./Modules/iSOCDeployments
Connect-AzAccount

Get-iSOCWorkspaceOnboarding -ResourceGroup rg-sentinel -WorkspaceName law-sentinel -PlaybookResourceGroup rg-playbooks
```

The command reads the Sentinel resource group, the workspace, and the two
resources that onboard Sentinel: the SecurityInsights solution
(`Microsoft.OperationsManagement/solutions/SecurityInsights(<workspace>)`)
and the onboarding state
(`Microsoft.SecurityInsights/onboardingStates/default`). When playbooks
have a resource group of their own, it reads that too. It needs only an Az
sign-in, not `Connect-iSOCWorkspace`, because the workspace may not exist
yet. Nothing changes in Azure.

The result says what `main.bicep` must do:

| Status | What the workspace has | InfrastructureNeeded | DeploySentinel |
| --- | --- | --- | --- |
| `Onboarded` | Everything | Only if the playbook group is missing | `false` |
| `NotOnboarded` | A workspace, neither onboarding resource | `true` | `true` |
| `StateMissing` | The solution, not the onboarding state | `true` | `true` |
| `SolutionMissing` | The onboarding state, not the solution | `false` | `false` |
| `NoWorkspace` | The resource group, no workspace | `true` | `true` |
| `NoResourceGroup` | Nothing | `true` | `true` |

`DeploySentinel` is `main.bicep`'s `deploySentinel`. The onboarding state
cannot be deployed twice (a second deployment returns Conflict), so the
Sentinel module runs only when Sentinel is not fully onboarded. A missing
onboarding state is repaired by deploying the module again, because the
solution deploys again harmlessly. A missing solution with the onboarding
state still there cannot be repaired by the template. The command logs
the two ways out as errors and returns `ExitCode` 1, so the pipeline stops
before Bicep. [Bicep](../../Infra/Bicep.md) explains why there are two
onboarding resources.

A resource that cannot be read for want of permission stops the command.
It is not read as missing and sent to Bicep to deploy over. Nothing the
command logs names the subscription.

In a pipeline:

```powershell
$onboarding = Get-iSOCWorkspaceOnboarding -ResourceGroup $rg -WorkspaceName $ws -PlaybookResourceGroup $playbookRg
"bicep_needed=$($onboarding.InfrastructureNeeded.ToString().ToLower())" >> $env:GITHUB_OUTPUT
"deploy_sentinel=$($onboarding.DeploySentinel.ToString().ToLower())" >> $env:GITHUB_OUTPUT
exit $onboarding.ExitCode
```

## Settings

`Content/WorkspaceSettings/` holds one JSON file for each Microsoft
Sentinel setting the repository manages, named after the setting's kind:

| File | What it turns on |
| --- | --- |
| `Anomalies.json` | Anomalies |
| `EyesOn.json` | EyesOn |
| `EntityAnalytics.json` | Entity Analytics, syncing the entity providers listed in `entityProviders` (`AzureActiveDirectory`, `ActiveDirectory`) |
| `Ueba.json` | UEBA, over the data sources listed in `dataSources` (`AuditLogs`, `AzureActivity`, `SecurityEvent`, `SigninLogs`) |

```json
{
  "name": "Ueba",
  "kind": "Ueba",
  "properties": {
    "dataSources": ["AuditLogs", "AzureActivity", "SigninLogs", "SecurityEvent"]
  }
}
```

The files hold what the pipelines send today, and
`Tests/iSOCDeployments/WorkspaceSetting.Tests.ps1` keeps the two equal
until the pipelines move to the module. Until then, a change to a file
does nothing in a pipeline run, and the test fails until the pipelines'
values change with it.

`Deploy-iSOCContent` deploys the settings before every other content type,
so UEBA is on before the rules that read its tables, and
`Deploy-iSOCWorkspace` deploys them as its first stage, before the Content
Hub solutions, as the pipelines did ([Deploying a
workspace](Deploy-Workspace.md)):

```powershell
Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel
Deploy-iSOCContent -ContentType WorkspaceSetting -WhatIf
Deploy-iSOCContent -ContentType WorkspaceSetting
```

- **Validate**: a kind of `Anomalies`, `EntityAnalytics`, `EyesOn` or
  `Ueba`, and a name the same as the kind, which is how the settings API
  names them. `properties`, when present, is an object. Entity Analytics
  needs a list in `entityProviders`, and UEBA one in `dataSources`. Which
  names Sentinel accepts in those lists is left to Sentinel, which names
  the one it refuses.
- **Request**: the kind and the file's properties, at api-version
  2025-07-01-preview. The settings API has no GA version.
- **Deploy**: each setting is read first. When the workspace has it, its
  etag goes in the request, so the write replaces that version. When it
  does not, the setting is created.
- **Refused**: UEBA and Entity Analytics need the Security Administrator
  directory role, which `Initialize-iSOCServicePrincipal -SkipEntraRole`
  leaves out. A setting refused with 401 or 403 is skipped with a warning
  saying what is needed, and the rest of the run goes on. The next run
  tries it again. Any other failure fails the setting, and the run's
  `ExitCode` is 1.

Settings are never deleted. Anomalies and EyesOn are on when their setting
exists, so removing a file stops the repository managing the setting but
does not turn it off. Turn it off in the portal.

## From the pipelines

| Pipeline step | Module |
| --- | --- |
| `$(azureSubscriptionId)`, `$(sentinelResourceGroup)`, `$(sentinelWorkspaceName)`, `$(playbookResourceGroup)` (Azure DevOps); `RESOURCE_GROUP`, `WORKSPACE_NAME`, `PLAYBOOK_RESOURCE_GROUP` (GitHub) | `Get-iSOCWorkspaceOnboarding -SubscriptionId -ResourceGroup -WorkspaceName -PlaybookResourceGroup` |
| The `RESOURCES_EXIST` output (Azure DevOps) | `-not $onboarding.InfrastructureNeeded` |
| The `bicep_needed` and `deploy_sentinel` outputs (GitHub) | `InfrastructureNeeded` and `DeploySentinel` |
| The settings list in the Configure Sentinel Settings step | `Content/WorkspaceSettings/` |

`Tests/iSOCDeployments/WorkspaceOnboarding.Tests.ps1` and
`WorkspaceSetting.Tests.ps1` lift each step out of the pipeline YAML
unchanged and run it in a child pwsh, beside the module, over a stand-in
subscription. The module must read and decide as the GitHub step does, and
write the settings as both steps do. `MIGRATION.md` edits E42 and E43 list
how it differs: the Azure DevOps check gains the onboarding checks and
`DeploySentinel` that the GitHub check already had, and a refused setting
is skipped while a rejected one fails the run.
