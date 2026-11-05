# iSOCDeployments docs

`iSOCDeployments` is the PowerShell module that will deploy, export,
compare and sync every content type in this repository, replacing the
scripts under `Deploy/` and `Tools/` in release 26.11.0. It is being built
beside those scripts; the pipelines keep running the scripts until the
module has been proved against a lab workspace and the cut-over removes
them.

"iSOC" here is this repository's name for its security operations tooling,
shared with the iSOC Blueprint. It is not Microsoft's Intelligent SOC
(ISOC) product, though the module works with ISOC workspaces as it does
with any Sentinel workspace.

| Page | What it covers |
| --- | --- |
| [Module README](../../../Modules/iSOCDeployments/README.md) | Quick start, the commands so far, what each step needs, the layout |
| [Architecture](Architecture.md) | The context, the REST client, the content type definition and its handlers, the comparers, the API versions, and how to add a content type |
| [Content types](Content-Types.md) | Each content type and what the module can do with it so far: all eight that `Deploy-CustomContent.ps1` deploys, the Defender XDR custom detections `Deploy-DefenderDetections.ps1` does, and the workspace settings the pipelines configure |
| [Deploying content](Deploy.md) | `Deploy-iSOCContent`: what a run does, the result, and how it maps to `Deploy/content/Deploy-CustomContent.ps1` and `Deploy/content/Deploy-DefenderDetections.ps1` |
| [Content Hub solutions](Content-Hub.md) | `Get-iSOCContentHubSolution` and `Install-iSOCContentHubSolution`: what a run does, the result, and how they map to `Deploy/content/Deploy-SentinelContentHub.ps1` |
| [Export](Export.md) | `Export-iSOCContent`: what an export writes and leaves, the result, and how it maps to `Tools/Export-SentinelWorkbooks.ps1` and the unmerged playbook exporter |
| [Drift](Drift.md) | `Compare-iSOCContent`, `Sync-iSOCContent` and `Export-iSOCDriftReport`: what a compare finds, what a sync writes, the report, and how they map to `Tools/Test-SentinelRuleDrift.ps1` |
| [Permissions](Permissions.md) | `Initialize-iSOCServicePrincipal`, `Grant-iSOCPlaybookPermission`, `Grant-iSOCRunbookPermission` and `Revoke-iSOCRunbookPermission`: the grants, the result, and how they map to the setup and permission scripts |
| [Community rule import](Community-Import.md) | `Import-iSOCCommunityRule`: sources, what an import writes, the result, and how it maps to `Tools/Import-CommunityRules.ps1` |
| [Classic table migration](Table-Migration.md) | `Get-iSOCTableMigrationImpact`, `Export-iSOCTableMigrationReport`, `Invoke-iSOCClassicTableMigration` and the rehearsal aids: what the review finds and where its parser chains stop, what a migration does, how to rehearse it, the results, and how they map to the scripts under `Tools/ClassicToDcr/` |
| [Deploying a workspace](Deploy-Workspace.md) | `Deploy-iSOCWorkspace`: the stages, what gates each, the manifest guard, the result, and how it maps to the stage sequence and parameters of the deploy pipelines |
| [Workspace settings and onboarding](Workspace-Settings.md) | `Get-iSOCWorkspaceOnboarding` and the workspace setting type: what the onboarding check reads and decides, the setting files, and how they map to the inline steps of the deploy pipelines |
| [Custom tables from a schema](Dcr-From-Schema.md) | `New-iSOCDcrFromSchema`: the schema file, what is checked and repaired, the templates, deploying, the result, and how it maps to `Tools/DcrFromSchema/New-DcrFromSchema.ps1` |
| [Dependency manifest](Dependency-Manifest.md) | `Test-iSOCDependencyManifest`, `Update-iSOCDependencyManifest` and `Get-iSOCContentDependency`, and how they map to `Tools/Build-DependencyManifest.ps1` |
| [The pipeline switch](Pipeline-Switch.md) | The pipelines' `engine` parameter (scripts, module or compare), which pipelines have it so far, how the module steps run, and how to try it on Azure DevOps |
| [Migration map](../../../Modules/iSOCDeployments/MIGRATION.md) | Where each script and function goes, and every change made on the way |

The iSOC Blueprint ([Docs/Modules/iSOCBlueprint](../iSOCBlueprint/README.md))
is a separate module: it reads a workspace and reports on it, and shares
no code with this one.
