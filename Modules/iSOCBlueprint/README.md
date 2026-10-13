# iSOCBlueprint

A PowerShell module that documents a security operations workspace and
assesses it against best practice and a maturity model. One command produces
the Blueprint as JSON, Markdown, a Word report, a SharePoint site, or any mix
of them. Today it documents Microsoft Sentinel workspaces; the public commands
avoid the product name so other sources can be added.

```powershell
Import-Module ./Modules/iSOCBlueprint
Connect-AzAccount

New-iSOCBlueprint -ResourceGroup rg-sentinel -WorkspaceName law-sentinel-prod -Format Json
New-iSOCBlueprint -ResourceGroup rg-sentinel -WorkspaceName law-sentinel-prod -Format Markdown
New-iSOCBlueprint -ResourceGroup rg-sentinel -WorkspaceName law-sentinel-prod -Format Word -ChartImages
New-iSOCBlueprint -ResourceGroup rg-sentinel -WorkspaceName law-sentinel-prod -Format SharePoint `
    -SiteUrl https://contoso.sharepoint.com/sites/isoc-prod -Interactive -ClientId '<app-id>' -Tenant contoso.onmicrosoft.com
```

Output goes to `./SecurityDocs/<workspace>/` under the current directory
unless `-OutputPath` says otherwise. That folder holds tenant configuration,
so keep it out of source control and share it as you would the workspace
itself.

## Commands

| Command | What it does | Needs |
| --- | --- | --- |
| `New-iSOCBlueprint` | Everything below, for the formats asked, in one line | Whatever those steps need |
| `Export-iSOCBlueprintInventory` | Collects the workspace into `<workspace>/_raw/`; the only step that talks to Azure | Az modules, `Connect-AzAccount` |
| `ConvertTo-iSOCBlueprint` | Renders the inventory as the section model (`-Format Json`) and the Markdown report | powershell-yaml |
| `ConvertTo-iSOCBlueprintChartImage` | Replaces the Markdown's Mermaid charts with PNG or SVG images | mmdc |
| `Export-iSOCBlueprintWord` | Combines the Markdown report into one `.docx` | pandoc; LibreOffice for page numbers |
| `New-iSOCBlueprintSite` | Builds the SharePoint bundle (dashboard, pages, findings) offline | Nothing extra |
| `Publish-iSOCBlueprintSite` | Makes a SharePoint site match a bundle | PowerShell 7.4, PnP.PowerShell 3.4.1 |
| `Initialize-iSOCBlueprintSite` | One-time set-up of the SharePoint site, by an administrator | PowerShell 7.4, PnP.PowerShell 3.4.1 |
| `Get-iSOCBlueprintFinding` | The gap-analysis findings for an inventory, as objects | Nothing extra |
| `Get-iSOCBlueprintMaturity` | The maturity assessment for an inventory, as an object | Nothing extra |
| `Test-iSOCBlueprintPrerequisite` | What this machine can produce and what is missing | Nothing |
| `Update-iSOCBlueprintConnectorCatalogue` | Maintainers: refreshes the connector catalogue from the Toolkit | Network |

Every command has full help: `Get-Help New-iSOCBlueprint -Full`.

The commands chain on the pipeline:

```powershell
Export-iSOCBlueprintInventory -ResourceGroup rg-sentinel -WorkspaceName law-sentinel-prod |
    ConvertTo-iSOCBlueprint -Format Json |
    New-iSOCBlueprintSite -SkipWhatsNew

Get-iSOCBlueprintFinding -Path ./SecurityDocs/law-sentinel-prod | Group-Object Severity
```

Only the steps a run uses need their tools. Check first with:

```powershell
Test-iSOCBlueprintPrerequisite | Format-Table Name, Step, Required, Found, Version
```

## Layout

```
iSOCBlueprint.psd1   manifest; ModuleVersion follows the repository release
iSOCBlueprint.psm1   loads Private/ then Public/
Public/              one file per command
Private/             the engine runner, path defaults, prerequisite checks
Engine/              the Blueprint itself, as scripts
  Export-SentinelInventory.ps1            collector
  Convert-SentinelInventoryToMarkdown.ps1 renderer
  Convert-MermaidToImage.ps1              chart images
  Update-ConnectorCatalogue.ps1           catalogue refresh
  Private/                                gap analysis, maturity, helpers
  Private/Resources/                      rules, criteria, catalogues, page 99
  Private/Vendor/                         KQL helpers copied from Sentinel.Common
  Report/                                 Word conversion
  SharePoint/                             site bundle, publisher, set-up
  Schemas/                                section model JSON schemas
MIGRATION.md         where each file came from
```

The public commands are thin: each maps its parameters onto one engine
script, runs it and returns an object describing what it wrote. The engine
scripts keep the layout and behaviour they had in `Tools/Blueprint`.

## Moving from Tools/Blueprint

The engine is a copy of `Tools/Blueprint`, made file by file. The only
differences are listed in
[`Tests/iSOCBlueprint/Engine-Edits.psd1`](../../Tests/iSOCBlueprint/Engine-Edits.psd1)
and [`MIGRATION.md`](MIGRATION.md): the engine loads its own copy of two
Sentinel.Common KQL helpers, defaults its folders to `./SecurityDocs` under the
current directory, records the module version as the Blueprint version, reads
page 99 from the copy it ships, and links to GitHub where the pages linked into
the repository. While both copies exist,
[`Tests/iSOCBlueprint/Engine-Copy.Tests.ps1`](../../Tests/iSOCBlueprint/Engine-Copy.Tests.ps1)
fails if they drift, so a fix must land in both. The pipelines still call
`Tools/Blueprint` until they are switched to the module; the old folder is
removed after a pipeline run on the module passes.

| Old script | Command |
| --- | --- |
| `Export-SentinelInventory.ps1` | `Export-iSOCBlueprintInventory` (`-OutputRoot` is `-OutputPath`) |
| `Convert-SentinelInventoryToMarkdown.ps1` | `ConvertTo-iSOCBlueprint` (`-InputRoot` is `-Path`, `-OutputFormat` is `-Format`) |
| `Convert-MermaidToImage.ps1` | `ConvertTo-iSOCBlueprintChartImage` (`-Root` is `-Path`) |
| `Report/Convert-MarkdownToWord.ps1` | `Export-iSOCBlueprintWord` (`-Source` is `-Path`) |
| `SharePoint/Build-SentinelDocsSite.ps1` | `New-iSOCBlueprintSite` (`-Source` is `-Path`, `-OutputRoot` is `-OutputPath`) |
| `SharePoint/Publish-SentinelDocsSite.ps1` | `Publish-iSOCBlueprintSite` (`-Bundle` is `-Path`) |
| `SharePoint/Initialize-SentinelDocsSite.ps1` | `Initialize-iSOCBlueprintSite` |
| `Update-ConnectorCatalogue.ps1` | `Update-iSOCBlueprintConnectorCatalogue` |
| `Report/Convert-FolderToWordReport.ps1` | Retired: a generic folder-to-Word dump that nothing called |

## Tests

```powershell
Invoke-Pester -Path Tests/iSOCBlueprint
```

| Suite | Covers |
| --- | --- |
| `Migration-Map.Tests.ps1` | Every file under `Tools/Blueprint` is mapped, and every edit still matches its source |
| `Engine-Copy.Tests.ps1` | The engine equals `Tools/Blueprint` apart from the listed edits; vendored copies equal their originals |
| `Module.Tests.ps1` | Manifest, help, file headers, prerequisites against the engine's `#Requires`, and each command's parameter mapping |
| `Module-Standalone.Tests.ps1` | The module copied outside the repository renders the fixture, builds the site and runs the assessments |
