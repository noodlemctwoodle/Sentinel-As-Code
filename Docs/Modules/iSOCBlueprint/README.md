# iSOC Blueprint documentation

The iSOC Blueprint documents a Microsoft Sentinel workspace and assesses it. It
records every artefact, setting, data collection rule and endpoint, estimates
the monthly cost, raises findings against Microsoft Learn best practice and
scores the workspace on a maturity model. It only reads: nothing it does
changes the workspace.

It ships as the [`iSOCBlueprint`](../../../Modules/iSOCBlueprint/README.md)
PowerShell module, whose README has the quick start, the thirteen commands and
what each one needs. The pages in this folder explain what a run produces, how
to read it, and how each part works.

A run's output is tenant configuration: workspace IDs, rule details, role
assignments and cost figures. Keep it in a private repository and share it as
you would the workspace itself.
[Keeping the output off a public GitHub repo](Sentinel-Blueprint.md#keeping-the-output-off-a-public-github-repo)
covers how the pipelines enforce that.

## Pages in this folder

Using the Blueprint:

| Page | Read it when |
| --- | --- |
| [iSOC Blueprint](Sentinel-Blueprint.md) | You are running it or reading its output. The operating guide: what a run produces, how to read the report, running it in CI or locally, permissions, the gap engine and the cost estimate. Start here. |
| [Maturity Model](Sentinel-Maturity-Model.md) | You want to know where a maturity score comes from: the eleven areas, the levels from 0 to 5, how each criterion resolves, the roadmap and the NIST CSF 2.0 rollup. |
| [SharePoint Site](Sentinel-SharePoint-Site.md) | You are setting up or using the generated site: a tour of the dashboard, the section pages, the findings list and its history, set-up and privacy. |
| [Word Report](Sentinel-Word-Report.md) | You need the report as one page-numbered `.docx`: the pandoc and LibreOffice toolchain and how to run it. |

Building on it or changing it:

| Page | Read it when |
| --- | --- |
| [Section Model](Section-Model.md) | You are reading a run's output from code. The JSON every run writes per section, with its schema; the SharePoint site is built from it. |
| [Renderer Design](Blueprint-Renderer-Design.md) | You are changing the renderer: what drives each chart, the helpers, the Mermaid-safety rules, and how to add a chart or a section. |
| [Conventions](Blueprint-References.md) | An API version, module or KQL query the Blueprint depends on has changed. Every one is recorded here, and each report carries this page as `99-references.md`. |
| [Data Lake Coverage](Sentinel-Data-Lake-Coverage.md) | You want to know what the Blueprint reports about the Sentinel data lake tier, and which captures each part comes from. |
| [Health check cross-reference](Health-Check-Coverage.md) | You are comparing the Blueprint with the contributed Sentinel health-check script: where each of its sections, queries and findings lives here. |

## From a run to its outputs

Each step of a run, what it writes and the pages that cover it.
`New-iSOCBlueprint` runs whichever steps the formats asked for need, in one
command.

| Step | Command | Writes | Covered in |
| --- | --- | --- | --- |
| Collect | `Export-iSOCBlueprintInventory` | `_raw/*.json`, the snapshot of the workspace | [What it produces](Sentinel-Blueprint.md#what-it-produces), [Permissions](Sentinel-Blueprint.md#permissions-for-the-blueprint-sp), [Conventions](Blueprint-References.md) |
| Assess | Run by the collector once it has the snapshot. `Get-iSOCBlueprintFinding` and `Get-iSOCBlueprintMaturity` run it again, offline, over any inventory | `_raw/gap-analysis.json`, `_raw/gap-checks.json`, `_raw/maturity.json` | [How the gap engine works](Sentinel-Blueprint.md#how-the-gap-engine-works), [Maturity Model](Sentinel-Maturity-Model.md) |
| Render | `ConvertTo-iSOCBlueprint` | `sections/*.json` (the section model) and the numbered Markdown pages | [Section Model](Section-Model.md), [Renderer Design](Blueprint-Renderer-Design.md) |
| Word | `ConvertTo-iSOCBlueprintChartImage` to draw the charts, then `Export-iSOCBlueprintWord` | One `.docx` | [Word Report](Sentinel-Word-Report.md) |
| SharePoint | `New-iSOCBlueprintSite` to build the bundle, then `Publish-iSOCBlueprintSite` | The site bundle, then the live site | [SharePoint Site](Sentinel-SharePoint-Site.md) |

## Common tasks

| To | See |
| --- | --- |
| Run it on your own machine | [Locally](Sentinel-Blueprint.md#locally), after the module's [quick start](../../../Modules/iSOCBlueprint/README.md) |
| Run it on a schedule | [In CI](Sentinel-Blueprint.md#in-ci) and the [Blueprint pipeline](../../Pipelines/Blueprint.md) |
| Grant the identity it runs as | [Permissions for the Blueprint SP](Sentinel-Blueprint.md#permissions-for-the-blueprint-sp) |
| Read a report for the first time | [How to read the report](Sentinel-Blueprint.md#how-to-read-the-report) |
| Add a gap rule | [Adding a new rule](Sentinel-Blueprint.md#adding-a-new-rule) |
| Add a maturity criterion | [Adding a criterion](Sentinel-Maturity-Model.md#adding-a-criterion) |
| Add a chart or a section | [How to extend the renderer](Blueprint-Renderer-Design.md#how-to-extend-the-renderer) |
| Set up the SharePoint site | [Setting it up](Sentinel-SharePoint-Site.md#setting-it-up) and the [SharePoint Publish pipeline](../../Pipelines/SharePoint-Publish.md) |
| Change an API version | [API versions in use](Blueprint-References.md#api-versions-in-use) |
| Try it without a tenant | The [demo workspace](../../Tools/Blueprint-Demo-Workspace.md), a synthetic workspace built from this repository's content |

## Elsewhere in the repository

- [Module README](../../../Modules/iSOCBlueprint/README.md): the commands, the
  module's layout and its tests.
- [`MIGRATION.md`](../../../Modules/iSOCBlueprint/MIGRATION.md): where each file
  of the scripts that came before the module went.
- [Web parts](../../../Modules/iSOCBlueprint/WebParts/README.md): the SPFx
  solution behind the dashboard and chart web parts.
- Pipelines: [Blueprint](../../Pipelines/Blueprint.md),
  [Word Report](../../Pipelines/Word-Report.md) and
  [SharePoint Publish](../../Pipelines/SharePoint-Publish.md).
- Tests: the suites in [`Tests/iSOCBlueprint/`](../../../Tests/iSOCBlueprint),
  described in [Pester Tests](../../Tests/Pester-Tests.md).
