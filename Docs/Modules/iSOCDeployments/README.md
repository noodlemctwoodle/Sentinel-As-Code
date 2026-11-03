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
| [Content types](Content-Types.md) | Each content type and what the module can do with it so far |
| [Dependency manifest](Dependency-Manifest.md) | `Test-iSOCDependencyManifest`, `Update-iSOCDependencyManifest` and `Get-iSOCContentDependency`, and how they map to `Tools/Build-DependencyManifest.ps1` |
| [Migration map](../../../Modules/iSOCDeployments/MIGRATION.md) | Where each script and function goes, and every change made on the way |

The iSOC Blueprint ([Docs/Modules/iSOCBlueprint](../iSOCBlueprint/README.md))
is a separate module: it reads a workspace and reports on it, and shares
no code with this one.
