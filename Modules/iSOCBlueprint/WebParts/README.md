# iSOC Blueprint web parts

The SharePoint Framework (SPFx) solution behind a generated iSOC Blueprint
site. One package, two web parts:

| Web part | Component id | Where | What it does |
| --- | --- | --- | --- |
| **Sentinel workspace dashboard** (`src/webparts/isocBlueprint`) | `a2fd5aa3-01c5-431e-8c98-66f76c89803a` | The home page | Fetches the dashboard HTML the publisher uploaded to the site's **Blueprint Assets** library (by default `BlueprintAssets/dashboard/index.html`) with the viewer's own SharePoint session, and renders it in a same-origin iframe that grows to the dashboard's full height. |
| **iSOC Blueprint chart** (`src/webparts/isocBlueprintChart`) | `4ae8707c-ca6f-40cb-a974-c94d023de6e5` | Each chart on a section page | Draws one chart from the chart block the publisher stores in its `chartJson` property (kind, title and data from the [section model](../../../Docs/Modules/iSOCBlueprint/Section-Model.md#charts)), as SVG and HTML, with no script libraries and nothing fetched. |

You do not normally build or deploy this by hand. The SharePoint publish
pipelines build the `.sppkg` on every run and
`Publish-SentinelDocsSite.ps1` deploys it to the site's own app catalog
whenever its version changes. See
[iSOC Blueprint SharePoint Site](../../../Docs/Modules/iSOCBlueprint/Sentinel-SharePoint-Site.md).

## Build locally

Needs Node 22 (SPFx 1.21.1 supports `>=22.14.0 <23`).

```bash
npm ci
npm run package
```

The package lands at `sharepoint/solution/isoc-blueprint.sppkg`.
`npm run package` cleans first, so the package never carries stale bundles
from earlier builds. `.npmrc` pins the public npm registry so the lockfile
resolves the same way everywhere.

## Releasing a change

The publisher deploys the package only when its version differs from the
one in the site's app catalog. Bump all of:

- `version` in `package.json`, and the two copies of it at the top of
  `package-lock.json`
- `solution.version` and `features[0].version` in
  `config/package-solution.json` (four-part, for example `1.4.0.0`)

`Tests/iSOCBlueprint/SharePoint-Site.Tests.ps1` fails when they disagree. Keep
`solution.id` and each web part's `id` as they are: the publisher finds
the web parts by those ids. Renaming the
solution (its `name` or the `.sppkg` file) is fine: the publisher sees the
different title on the deployed package, removes the old one and adds the
new one, since SharePoint allows only one catalog file per solution id.

A ship build (`npm run package`) fails on any lint warning, not only on
errors, so run it before pushing a change to the TypeScript.

## How the dashboard renders

- **Script.** SharePoint's page content security policy applies inside the
  iframe and blocks inline `<script>`, but allows `eval`. The web part
  takes the dashboard's script out of the HTML, loads the rest through
  `srcdoc`, then runs the script inside the iframe with `eval`.
- **Height.** The iframe is sized to the dashboard body's height (not the
  document's, which never shrinks), kept current by a `ResizeObserver`
  and a `fitIframe` hook the dashboard calls after tab switches.
- **Width.** The manifest declares `supportsFullBleed`, and the publisher
  puts the web part in a full-width section, so it fills the page.

## How the charts render

`src/webparts/isocBlueprintChart/charts/` holds one module per chart kind
and nothing that depends on SPFx, so the drawing code can be compiled and
tried in a plain browser page:

| Kind | Drawn as |
| --- | --- |
| `pie` | A donut with the total in the middle; every slice in the legend, zeros included |
| `xy` | Columns and lines on a shared axis; horizontal bars when the labels would not fit under columns |
| `sankey` | Flows between columns, each node in the column of its longest path from a source |
| `timeline` | A vertical list of dated events |
| `gantt` | Bars and milestones on a date axis, each labelled with the date it marks |
| `mindmap` | A tree read left to right |
| `flowchart`, `state`, `class` | A layered layout ([`GraphLayout.ts`](src/webparts/isocBlueprintChart/charts/GraphLayout.ts)): cycles broken, an edge that skips ranks routed round the nodes in between, groups boxed |
| `sequence` | Lifelines with numbered messages, notes and blocks |
| `journey` | A card per step, by stage, with its score |

Colours come from the section's theme (`supportsThemeVariants`), so a chart
reads on a dark or coloured section. A label that carries a meaning
(Critical, Failed, TruePositive and so on) takes the colour it has
elsewhere in the Blueprint. A drawing scales down with its column to two
thirds of its size and then scrolls sideways, so its text stays readable
on a phone. A kind the web part does not draw shows its Mermaid source.

## Security

Because the dashboard's iframe shares the page's origin and the script runs
with `eval`, whoever can edit the dashboard file can run script for everyone
who opens the home page. The chart web part runs no script from its data:
every value is escaped into the markup, and a node link is kept only when
it is a web URL, a mail link or a site path. Keep write access to the Blueprint Assets
library to the publisher identity and site owners. The site itself holds
tenant configuration, so keep its membership to the people who should
read it.
