# iSOCBlueprint migration map

Where every file under `Tools/Blueprint` went when the Blueprint became the
`iSOCBlueprint` module (release 26.10.0). In release 26.09 the folder was
`Tools/Documenter` (with `Documenter.psd1` for `Blueprint.psd1`); it took the
product's name while this release was built, so a 26.09 path maps through
`Tools/Blueprint` below. The move was made file by file: the
module was built beside the old folder, its engine held byte-identical to the
old scripts apart from the edits below, its output compared with the old
scripts' over the test fixture, the pipelines switched to it, and the old
folder removed only after a pipeline run on the module passed.
[`Tests/iSOCBlueprint/Migration-Map.Tests.ps1`](../../Tests/iSOCBlueprint/Migration-Map.Tests.ps1)
reads this table and fails if a source path comes back or a destination goes
missing.

Actions:

- **Copy** - copied into the module's `Engine/` folder with the same relative
  layout, unchanged apart from the edits named in the Edits column. Release
  26.10 shipped that way; in 26.11 every copied file moved on (the static
  files to `Resources/`, the scripts into functions under `Private/`), so no
  row is a Copy any more.
- **Move** - moved elsewhere in the repository with `git mv`.
- **Retire** - not carried into the module; deleted with the old folder.
- **Vendor** - functions or files from elsewhere in the repository that the
  module ships its own copy of.
  [`Tests/iSOCBlueprint/Vendored.Tests.ps1`](../../Tests/iSOCBlueprint/Vendored.Tests.ps1)
  keeps each identical to its original.
- **Adopted** - a vendored copy whose original has been removed from the
  repository, so the copy is the module's own code.

Edits made in the copy:

| Id | File | Change |
| --- | --- | --- |
| G1 | every `.ps1` | The `File:` key in the help block names the new path |
| E1 | `Export-SentinelInventory.ps1` (now `Invoke-iSOCBlueprintCollect`) | Uses the vendored KQL helpers instead of importing `Modules/Sentinel.Common` from the repository |
| E2 | `Export-SentinelInventory.ps1` (now `Invoke-iSOCBlueprintCollect`) | `-OutputRoot` defaults to `./SecurityDocs` under the current directory, not two folders above the script |
| E3 | `Export-SentinelInventory.ps1` (now `Invoke-iSOCBlueprintCollect`) | `BlueprintVersion` is the module manifest version (it was `0.2.0`); `ScriptCommit` is recorded only when git is installed |
| E4 | `Convert-SentinelInventoryToMarkdown.ps1` (now `Invoke-iSOCBlueprintRender`) | `-InputRoot` defaults to `./SecurityDocs/<workspace>` under the current directory |
| E5 | `Convert-SentinelInventoryToMarkdown.ps1` (now `Invoke-iSOCBlueprintRender`) | Page 99 is read from the copy the module ships, not from the repository docs |
| E6 | `Convert-SentinelInventoryToMarkdown.ps1` (now `Invoke-iSOCBlueprintRender`) | The four links into the repository (pages 20, 90 and 91) point at GitHub |
| E7 | `Blueprint.psd1` | Its own `Version` (`0.1.0`) removed; the manifest is the only version |

Paths are repository-relative. A source ending in `/**` covers every file
beneath it.

| Source | Action | Destination | Edits | Notes |
| --- | --- | --- | --- | --- |
| `Tools/Blueprint/Blueprint.psd1` | Move | `Modules/iSOCBlueprint/Resources/Blueprint.psd1` | E7 | Settings data; nothing reads it at run time |
| `Tools/Blueprint/Convert-MermaidToImage.ps1` | Move | `Modules/iSOCBlueprint/Private/ChartImage/Invoke-iSOCBlueprintChartImage.ps1` | | Now a function, with its hash helper in `Get-MermaidHash.ps1`; `ConvertTo-iSOCBlueprintChartImage` |
| `Tools/Blueprint/Convert-SentinelInventoryToMarkdown.ps1` | Move | `Modules/iSOCBlueprint/Private/Render/Invoke-iSOCBlueprintRender.ps1` | E4, E5, E6 | Now a function, with the helpers it loaded in `Private/Render`; checks the YAML module in `ConvertTo-iSOCBlueprint` in place of `#Requires -Modules`; `ConvertTo-iSOCBlueprint` |
| `Tools/Blueprint/Export-SentinelInventory.ps1` | Move | `Modules/iSOCBlueprint/Private/Collector/Invoke-iSOCBlueprintCollect.ps1` | E1, E2, E3 | Now a function that runs strict, with the captures beside it in `Private/Collector`; the Az module check moved to `Export-iSOCBlueprintInventory` in place of `#Requires -Modules`; `Export-iSOCBlueprintInventory` |
| `Tools/Blueprint/Update-ConnectorCatalogue.ps1` | Move | `Modules/iSOCBlueprint/Private/ConnectorCatalogue/Invoke-iSOCBlueprintConnectorCatalogueUpdate.ps1` | | Now a function; `Update-iSOCBlueprintConnectorCatalogue` |
| `Tools/Blueprint/Private/ConvertFrom-BlueprintMermaid.ps1` | Retire | | | Parser split one function per file into `Private/Mermaid`, loaded with the module |
| `Tools/Blueprint/Private/ConvertTo-BlueprintSection.ps1` | Retire | | | Converter split one function per file into `Private/Section`, loaded with the module |
| `Tools/Blueprint/Private/GapChecks.ps1` | Retire | | | Split one check per file into `Private/Gap`, loaded with the module |
| `Tools/Blueprint/Private/Get-AzureRetailPrice.ps1` | Move | `Modules/iSOCBlueprint/Private/Azure/Get-AzureRetailPrice.ps1` | | |
| `Tools/Blueprint/Private/Get-ConnectorCatalogue.ps1` | Move | `Modules/iSOCBlueprint/Private/Lookup/Import-ConnectorCatalogue.ps1` | | Split one function per file in `Private/Lookup` |
| `Tools/Blueprint/Private/Get-DefenderCustomDetections.ps1` | Move | `Modules/iSOCBlueprint/Private/Azure/Get-DefenderCustomDetections.ps1` | | |
| `Tools/Blueprint/Private/Get-EffectiveConnectors.ps1` | Move | `Modules/iSOCBlueprint/Private/Lookup/Get-EffectiveConnectors.ps1` | | |
| `Tools/Blueprint/Private/Get-FindingMaturityLink.ps1` | Move | `Modules/iSOCBlueprint/Private/Lookup/Get-FindingMaturityLink.ps1` | | |
| `Tools/Blueprint/Private/Get-KqlTableReferences.ps1` | Move | `Modules/iSOCBlueprint/Private/Kql/**` | | Split one function per file; its KQL helpers come from the vendored copy |
| `Tools/Blueprint/Private/Get-SentinelCostEstimate.ps1` | Retire | | | Split into steps and helpers in `Private/Cost`, loaded with the module |
| `Tools/Blueprint/Private/Get-SentinelGap.ps1` | Move | `Modules/iSOCBlueprint/Private/GapAnalysis/Get-SentinelGap.ps1` | | `Get-iSOCBlueprintFinding` |
| `Tools/Blueprint/Private/Get-SentinelMaturity.ps1` | Retire | | | Split into `Private/Maturity`, loaded with the module; `Get-iSOCBlueprintMaturity` runs it |
| `Tools/Blueprint/Private/Get-TableFamily.ps1` | Move | `Modules/iSOCBlueprint/Private/Lookup/Get-TableFamily.ps1` | | |
| `Tools/Blueprint/Private/Get-TableTierProfile.ps1` | Move | `Modules/iSOCBlueprint/Private/Lookup/Get-TableTierProfile.ps1` | | |
| `Tools/Blueprint/Private/Invoke-SentinelRest.ps1` | Move | `Modules/iSOCBlueprint/Private/Azure/Invoke-SentinelRest.ps1` | | |
| `Tools/Blueprint/Private/Resources/best-practices.json` | Move | `Modules/iSOCBlueprint/Resources/Data/best-practices.json` | | |
| `Tools/Blueprint/Private/Resources/commitment-tiers.json` | Move | `Modules/iSOCBlueprint/Resources/Data/commitment-tiers.json` | | |
| `Tools/Blueprint/Private/Resources/connector-catalogue.json` | Move | `Modules/iSOCBlueprint/Resources/Data/connector-catalogue.json` | | |
| `Tools/Blueprint/Private/Resources/cost-meters.json` | Move | `Modules/iSOCBlueprint/Resources/Data/cost-meters.json` | | |
| `Tools/Blueprint/Private/Resources/maturity-criteria.json` | Move | `Modules/iSOCBlueprint/Resources/Data/maturity-criteria.json` | | |
| `Tools/Blueprint/Private/Resources/mitre-attack.json` | Move | `Modules/iSOCBlueprint/Resources/Data/mitre-attack.json` | | |
| `Tools/Blueprint/Private/Resources/sentinel-benefit-tables.json` | Move | `Modules/iSOCBlueprint/Resources/Data/sentinel-benefit-tables.json` | | |
| `Tools/Blueprint/Report/Convert-FolderToWordReport.ps1` | Retire | | | Generic folder-to-Word dump, not called anywhere and untested |
| `Tools/Blueprint/Report/Convert-MarkdownToWord.ps1` | Move | `Modules/iSOCBlueprint/Private/Word/Invoke-iSOCBlueprintWordConversion.ps1` | | Now a function; a step that cannot go on throws where the script called `exit`; `Export-iSOCBlueprintWord` |
| `Tools/Blueprint/Report/Update-WordToc.py` | Move | `Modules/iSOCBlueprint/Resources/Report/Update-WordToc.py` | | |
| `Tools/Blueprint/Report/templates/sentinel-report-reference.docx` | Move | `Modules/iSOCBlueprint/Resources/Report/templates/sentinel-report-reference.docx` | | Binary, compared by hash |
| `Tools/Blueprint/Schemas/section-index.schema.json` | Move | `Modules/iSOCBlueprint/Resources/Schemas/section-index.schema.json` | | |
| `Tools/Blueprint/Schemas/section.schema.json` | Move | `Modules/iSOCBlueprint/Resources/Schemas/section.schema.json` | | |
| `Tools/Blueprint/SharePoint/Build-SentinelDocsSite.ps1` | Move | `Modules/iSOCBlueprint/Private/Site/Invoke-iSOCBlueprintSiteBuild.ps1` | | Now a function; `New-iSOCBlueprintSite` |
| `Tools/Blueprint/SharePoint/Initialize-SentinelDocsSite.ps1` | Move | `Modules/iSOCBlueprint/Private/SiteSetup/Invoke-iSOCBlueprintSiteInitialize.ps1` | | Now a function that checks the PnP module itself in place of `#Requires -Modules`; `Initialize-iSOCBlueprintSite` |
| `Tools/Blueprint/SharePoint/Publish-SentinelDocsSite.ps1` | Move | `Modules/iSOCBlueprint/Private/Publish/Invoke-iSOCBlueprintSitePublish.ps1` | | Now a function; the PnP module check moved to `Publish-iSOCBlueprintSite` in place of `#Requires -Modules`; `Publish-iSOCBlueprintSite` |
| `Tools/Blueprint/SharePoint/Private/ConvertTo-SharePointPageSegments.ps1` | Retire | | | Split into `Private/PageSegments`, loaded with the module |
| `Tools/Blueprint/SharePoint/Private/Get-SacSyncPlan.ps1` | Retire | | | Split one planner per file into `Private/SyncPlan`, loaded with the module |
| `Tools/Blueprint/SharePoint/Private/Get-SectionFamily.ps1` | Move | `Modules/iSOCBlueprint/Private/SiteShared/Get-SectionFamily.ps1` | | |
| `Tools/Blueprint/SharePoint/Private/SacSharePoint.ps1` | Retire | | | Split one function per file into `Private/SharePoint`, loaded with the module |
| `Tools/Blueprint/SharePoint/templates/sharepoint-dashboard.html` | Move | `Modules/iSOCBlueprint/Resources/SharePoint/templates/dashboard/**` | | Split into numbered parts that `Get-SiteDashboardTemplate` joins; the joined page is the original file byte for byte |
| `Tools/Blueprint/SharePoint/webpart/isoc-blueprint/**` | Move | `Modules/iSOCBlueprint/WebParts/**` | | SPFx web part source (TypeScript, not PowerShell): beside the engine, outside what the module loads |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | Adopted | `Modules/iSOCBlueprint/Private/Kql/Vendor/**` | | One function per file. `Remove-KqlComments` and `Get-KqlBareIdentifiers` only; the shared module needed Az.Accounts, the renderer does not. Sentinel.Common retired in 26.11.0, so the copy is the Blueprint's own |
| `Docs/Modules/iSOCBlueprint/Blueprint-References.md` | Vendor | `Modules/iSOCBlueprint/Resources/Data/Blueprint-References.md` | | Shipped copy for page 99, so a run outside the repository still has it |
