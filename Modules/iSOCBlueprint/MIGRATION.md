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
  layout, unchanged apart from the edits named in the Edits column.
- **Move** - moved elsewhere in the repository with `git mv`.
- **Retire** - not carried into the module; deleted with the old folder.
- **Vendor** - functions or files from elsewhere in the repository that the
  module ships its own copy of.
  [`Tests/iSOCBlueprint/Vendored.Tests.ps1`](../../Tests/iSOCBlueprint/Vendored.Tests.ps1)
  keeps each identical to its original.

Edits made in the copy:

| Id | File | Change |
| --- | --- | --- |
| G1 | every `.ps1` | The `File:` key in the help block names the new path |
| E1 | `Export-SentinelInventory.ps1` | Dot-sources the vendored KQL helpers instead of importing `Modules/Sentinel.Common` from the repository |
| E2 | `Export-SentinelInventory.ps1` | `-OutputRoot` defaults to `./SecurityDocs` under the current directory, not two folders above the script |
| E3 | `Export-SentinelInventory.ps1` | `BlueprintVersion` is the module manifest version (it was `0.2.0`); `ScriptCommit` is recorded only when git is installed |
| E4 | `Convert-SentinelInventoryToMarkdown.ps1` | `-InputRoot` defaults to `./SecurityDocs/<workspace>` under the current directory |
| E5 | `Convert-SentinelInventoryToMarkdown.ps1` | Page 99 is read from the copy the module ships, not from the repository docs |
| E6 | `Convert-SentinelInventoryToMarkdown.ps1` | The four links into the repository (pages 20, 90 and 91) point at GitHub |
| E7 | `Blueprint.psd1` | Its own `Version` (`0.1.0`) removed; the manifest is the only version |

Paths are repository-relative. A source ending in `/**` covers every file
beneath it.

| Source | Action | Destination | Edits | Notes |
| --- | --- | --- | --- | --- |
| `Tools/Blueprint/Blueprint.psd1` | Copy | `Modules/iSOCBlueprint/Engine/Blueprint.psd1` | E7 | Settings data; nothing reads it at run time |
| `Tools/Blueprint/Convert-MermaidToImage.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Convert-MermaidToImage.ps1` | | `ConvertTo-iSOCBlueprintChartImage` |
| `Tools/Blueprint/Convert-SentinelInventoryToMarkdown.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Convert-SentinelInventoryToMarkdown.ps1` | E4, E5, E6 | `ConvertTo-iSOCBlueprint` |
| `Tools/Blueprint/Export-SentinelInventory.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Export-SentinelInventory.ps1` | E1, E2, E3 | `Export-iSOCBlueprintInventory` |
| `Tools/Blueprint/Update-ConnectorCatalogue.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Update-ConnectorCatalogue.ps1` | | `Update-iSOCBlueprintConnectorCatalogue` |
| `Tools/Blueprint/Private/ConvertFrom-BlueprintMermaid.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Private/ConvertFrom-BlueprintMermaid.ps1` | | |
| `Tools/Blueprint/Private/ConvertTo-BlueprintSection.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Private/ConvertTo-BlueprintSection.ps1` | | |
| `Tools/Blueprint/Private/GapChecks.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1` | | |
| `Tools/Blueprint/Private/Get-AzureRetailPrice.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Private/Get-AzureRetailPrice.ps1` | | |
| `Tools/Blueprint/Private/Get-ConnectorCatalogue.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Private/Get-ConnectorCatalogue.ps1` | | |
| `Tools/Blueprint/Private/Get-DefenderCustomDetections.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Private/Get-DefenderCustomDetections.ps1` | | |
| `Tools/Blueprint/Private/Get-EffectiveConnectors.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Private/Get-EffectiveConnectors.ps1` | | |
| `Tools/Blueprint/Private/Get-FindingMaturityLink.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Private/Get-FindingMaturityLink.ps1` | | |
| `Tools/Blueprint/Private/Get-KqlTableReferences.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Private/Get-KqlTableReferences.ps1` | | Its KQL helpers come from the vendored copy |
| `Tools/Blueprint/Private/Get-SentinelCostEstimate.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Private/Get-SentinelCostEstimate.ps1` | | |
| `Tools/Blueprint/Private/Get-SentinelGap.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Private/Get-SentinelGap.ps1` | | `Get-iSOCBlueprintFinding` |
| `Tools/Blueprint/Private/Get-SentinelMaturity.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Private/Get-SentinelMaturity.ps1` | | `Get-iSOCBlueprintMaturity` |
| `Tools/Blueprint/Private/Get-TableFamily.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Private/Get-TableFamily.ps1` | | |
| `Tools/Blueprint/Private/Get-TableTierProfile.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Private/Get-TableTierProfile.ps1` | | |
| `Tools/Blueprint/Private/Invoke-SentinelRest.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Private/Invoke-SentinelRest.ps1` | | |
| `Tools/Blueprint/Private/Resources/best-practices.json` | Copy | `Modules/iSOCBlueprint/Engine/Private/Resources/best-practices.json` | | |
| `Tools/Blueprint/Private/Resources/commitment-tiers.json` | Copy | `Modules/iSOCBlueprint/Engine/Private/Resources/commitment-tiers.json` | | |
| `Tools/Blueprint/Private/Resources/connector-catalogue.json` | Copy | `Modules/iSOCBlueprint/Engine/Private/Resources/connector-catalogue.json` | | |
| `Tools/Blueprint/Private/Resources/cost-meters.json` | Copy | `Modules/iSOCBlueprint/Engine/Private/Resources/cost-meters.json` | | |
| `Tools/Blueprint/Private/Resources/maturity-criteria.json` | Copy | `Modules/iSOCBlueprint/Engine/Private/Resources/maturity-criteria.json` | | |
| `Tools/Blueprint/Private/Resources/mitre-attack.json` | Copy | `Modules/iSOCBlueprint/Engine/Private/Resources/mitre-attack.json` | | |
| `Tools/Blueprint/Private/Resources/sentinel-benefit-tables.json` | Copy | `Modules/iSOCBlueprint/Engine/Private/Resources/sentinel-benefit-tables.json` | | |
| `Tools/Blueprint/Report/Convert-FolderToWordReport.ps1` | Retire | | | Generic folder-to-Word dump, not called anywhere and untested |
| `Tools/Blueprint/Report/Convert-MarkdownToWord.ps1` | Copy | `Modules/iSOCBlueprint/Engine/Report/Convert-MarkdownToWord.ps1` | | `Export-iSOCBlueprintWord` |
| `Tools/Blueprint/Report/Update-WordToc.py` | Copy | `Modules/iSOCBlueprint/Engine/Report/Update-WordToc.py` | | |
| `Tools/Blueprint/Report/templates/sentinel-report-reference.docx` | Copy | `Modules/iSOCBlueprint/Engine/Report/templates/sentinel-report-reference.docx` | | Binary, compared by hash |
| `Tools/Blueprint/Schemas/section-index.schema.json` | Copy | `Modules/iSOCBlueprint/Engine/Schemas/section-index.schema.json` | | |
| `Tools/Blueprint/Schemas/section.schema.json` | Copy | `Modules/iSOCBlueprint/Engine/Schemas/section.schema.json` | | |
| `Tools/Blueprint/SharePoint/Build-SentinelDocsSite.ps1` | Copy | `Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1` | | `New-iSOCBlueprintSite` |
| `Tools/Blueprint/SharePoint/Initialize-SentinelDocsSite.ps1` | Copy | `Modules/iSOCBlueprint/Engine/SharePoint/Initialize-SentinelDocsSite.ps1` | | `Initialize-iSOCBlueprintSite` |
| `Tools/Blueprint/SharePoint/Publish-SentinelDocsSite.ps1` | Copy | `Modules/iSOCBlueprint/Engine/SharePoint/Publish-SentinelDocsSite.ps1` | | `Publish-iSOCBlueprintSite` |
| `Tools/Blueprint/SharePoint/Private/ConvertTo-SharePointPageSegments.ps1` | Copy | `Modules/iSOCBlueprint/Engine/SharePoint/Private/ConvertTo-SharePointPageSegments.ps1` | | |
| `Tools/Blueprint/SharePoint/Private/Get-SacSyncPlan.ps1` | Copy | `Modules/iSOCBlueprint/Engine/SharePoint/Private/Get-SacSyncPlan.ps1` | | |
| `Tools/Blueprint/SharePoint/Private/Get-SectionFamily.ps1` | Copy | `Modules/iSOCBlueprint/Engine/SharePoint/Private/Get-SectionFamily.ps1` | | |
| `Tools/Blueprint/SharePoint/Private/SacSharePoint.ps1` | Copy | `Modules/iSOCBlueprint/Engine/SharePoint/Private/SacSharePoint.ps1` | | |
| `Tools/Blueprint/SharePoint/templates/sharepoint-dashboard.html` | Copy | `Modules/iSOCBlueprint/Engine/SharePoint/templates/sharepoint-dashboard.html` | | |
| `Tools/Blueprint/SharePoint/webpart/isoc-blueprint/**` | Move | `Modules/iSOCBlueprint/WebParts/**` | | SPFx web part source (TypeScript, not PowerShell): beside the engine, outside what the module loads |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | Vendor | `Modules/iSOCBlueprint/Engine/Private/Vendor/SentinelCommon.Kql.ps1` | | `Remove-KqlComments` and `Get-KqlBareIdentifiers` only; the shared module needs Az.Accounts, the renderer does not |
| `Docs/Modules/iSOCBlueprint/Blueprint-References.md` | Vendor | `Modules/iSOCBlueprint/Engine/Private/Resources/Blueprint-References.md` | | Shipped copy for page 99, so a run outside the repository still has it |
