# iSOC Blueprint section model

Every Blueprint run writes its sections as JSON, under
`SecurityDocs/<workspace>/<yyyy-MM-dd>/sections/` (`SecurityDocs/<workspace>/sections/`
from the pipelines, which pass `-NoDateFolder`), in a shape published as a JSON Schema.
This is the contract for anything that reads a Blueprint: the SharePoint site
is built from it, and you can build on it too, without parsing Markdown.

| File | What it is | Schema |
| --- | --- | --- |
| `sections/index.json` | The run's sections in reading order, with the run's facts | [`section-index.schema.json`](../../../Modules/iSOCBlueprint/Engine/Schemas/section-index.schema.json) |
| `sections/<id>.json` | One section, for example `20-analytics-rules.json` | [`section.schema.json`](../../../Modules/iSOCBlueprint/Engine/Schemas/section.schema.json) |

The Markdown pack (`NN-name.md`) carries the same sections as Markdown, for the
docs pull request and the Word report. The renderer writes both by default;
`ConvertTo-iSOCBlueprint -Format Json` writes only the model, which is all the
SharePoint site needs.

## A section

```json
{
  "schemaVersion": 1,
  "id": "20-analytics-rules",
  "order": 20,
  "title": "Analytics rules",
  "meta": { "workspace": "law-sentinel-prod", "generatedUtc": "2026-10-13T06:00:00Z", "blueprintVersion": "0.2.0" },
  "blocks": [
    { "type": "heading", "level": 2, "text": [{ "text": "By kind" }], "anchor": "by-kind" },
    { "type": "paragraph", "text": [{ "text": "4 rules, " }, { "text": "2 disabled", "bold": true }] },
    { "type": "chart", "kind": "pie", "title": "Rules by kind", "data": { "showData": true, "slices": [{ "label": "Scheduled", "value": 3 }] }, "source": "pie showData title Rules by kind\n ..." }
  ]
}
```

`order` is the number the id starts with. `meta` repeats the run's facts so a
section file stands on its own.

## Blocks

| `type` | Fields | Notes |
| --- | --- | --- |
| `heading` | `level` (2 to 6), `text` (runs), `anchor` | `anchor` is the finding id for a gap-analysis finding (`sac-log-03`), otherwise the heading text as GitHub slugs it. The section's H1 is its `title`, not a block. |
| `paragraph` | `text` (runs) | |
| `list` | `ordered`, `start` (ordered lists that do not start at 1), `items` | Each item has `text` (runs) and `blocks` (anything nested under it, such as a sub-list). |
| `table` | `columns`, `rows` | Each column has `text` (runs) and `align` (`left`, `center`, `right` or null). `rows` is an array of rows; a row is an array of cells; a cell is an array of runs. |
| `note` | `blocks` | A callout. The metadata banner under the title is not one: its facts are in `meta`. |
| `chart` | `kind`, `title`, `data`, `source` | See [Charts](#charts). |
| `code` | `language`, `text` | |
| `rule` | | A horizontal rule. |
| `html` | `html` | Raw HTML the Markdown carried. The renderer emits none today. |

## Text runs

Text is never Markdown. Every `text` field is an array of runs:

```json
[
  { "text": "See " },
  { "text": "SAC-LOG-03", "href": "90-gap-analysis.md#sac-log-03", "target": { "kind": "finding", "id": "SAC-LOG-03" } },
  { "text": " for the ", "italic": true },
  { "text": "SigninLogs", "code": true },
  { "break": true },
  { "text": "next line" }
]
```

A run has `text` and, only when true, `bold`, `italic`, `code` and `strike`.
`{ "break": true }` is a line break. A link run keeps the `href` the Markdown
had and adds a `target` that says what it points at:

| `target.kind` | Extra fields | Points at |
| --- | --- | --- |
| `section` | `section`, `anchor` | Another section (`20-analytics-rules`), optionally a heading in it |
| `finding` | `id` | A gap-analysis finding, for example `SAC-LOG-03` |
| `anchor` | `anchor` | A heading on the same section |
| `external` | | A web URL |
| `repo` | `path` | A path in the Sentinel-As-Code repository |

## Charts

A chart block carries its data, shaped by `kind`, and the same chart as
Mermaid in `source` (the Markdown export uses it, and a consumer that renders
Mermaid can too). `data` is null only for kind `other`. Line breaks in labels
are `\n`.

A chart with a purpose-built graphic (the incident lifecycle, rule kinds,
the response chain, the topology, the cost breakdown, the role
assignments, the data lake tiers, the estate, the retirement runway, the
workspace history, and the meters on the detection opportunities and
Content Hub pages) carries
its data on a `%% visual <kind> {json}` line inside its Mermaid. Mermaid
ignores the line, so the Markdown export draws the diagram as before; the
section model gives the chart that kind and the JSON as its data, and
`source` keeps the Mermaid. A visual line whose JSON does not parse is
ignored and the Mermaid is read as usual.

A graphic with no Mermaid behind it (the overview's top findings as cards)
rides on a `<!-- bp:visual <kind> {json} -->` comment instead, which
Markdown does not show; the section model gives it a chart block of that
kind with an empty `source`, and drops a comment whose JSON does not parse.

A table, a list or a line of figures that such a graphic shows in full
follows a `<!-- bp:shown-in-graphic -->` comment. The block then
carries `inGraphic: true`: the Markdown and Word exports keep it, and the
SharePoint pages and the dashboard leave it out rather than show the same
figures twice.

| `kind` | `data` |
| --- | --- |
| `pie` | `showData`, `slices: [{ label, value }]` |
| `sankey` | `links: [{ source, target, value }]` |
| `xy` | `xAxis: { title, labels[] }`, `yAxis: { title, min, max }`, `series: [{ kind: bar or line, name, values[] }]`; when the renderer shortens the Mermaid labels to fit under the bars it writes the full names in a `%% x-labels [...]` comment, and `labels` takes those when the count matches |
| `timeline` | `periods: [{ label, section, events[] }]` |
| `gantt` | `dateFormat`, `axisFormat`, `sections: [{ name, tasks: [{ label, tags[], id, start, length }] }]`; `tags` from done, active, crit, milestone; `length` as Mermaid writes it (`1d`, `260d`) |
| `mindmap` | `root: { text, children[] }`, recursive |
| `flowchart` | `direction`, `groups: [{ id, label, parent }]`, `nodes: [{ id, label, group, class, fill, stroke, color, href, tooltip, target }]`, `edges: [{ from, to, label, style: solid, dotted or thick, arrow }]`; a node's `target` says what its `href` points at, the same as a link run's (null without a link) |
| `sequence` | `autonumber`, `participants: [{ id, label, kind }]`, `steps`: messages `{ kind: message, from, to, text, dashed }`, notes `{ kind: note, position, over[], text }`, blocks `{ kind: block, block, text }` and `{ kind: end }` |
| `state` | `states: [{ id, label, parent }]`, `transitions: [{ from, to, label, parent }]` (`[*]` is start or end), `notes: [{ state, position, text }]` |
| `class` | `classes: [{ name, members[] }]`, `relations: [{ from, to, kind, label }]`, `notes: [{ for, text }]` |
| `journey` | `sections: [{ name, tasks: [{ label, score, actors[] }] }]` |
| `incident-lifecycle` | `days`, `raised`, `new`, `active`, `closed` (the window's incidents at their current status), `acknowledged` and `unacknowledged` (the closed ones picked up first, and those closed straight from New), `mttaMinutes`, `mttrMinutes`, `unified` (raised through Defender XDR), `openBySeverity`, `classification` and `closedBy` as `[{ label, count }]`, and `check: { id, fired }` (SAC-INC-05, and whether it fired in this run); a figure the capture lacks is null |
| `meters` | `meters: [{ title, caption, total, parts: [{ label, value, tone }] }]`, and `figures: [{ label, value, caption }]` for figures that belong with them but are not parts of a whole; `tone` is ok, warn, bad, info, neutral, violet, teal, cyan or rose |
| `rule-kinds` | `total` (all rules), `common[]` (the fields every rule carries), `kinds: [{ kind, label, summary, fields[], deployed, enabled, legacy }]` |
| `response-chain` | `phases: [{ name, figure, steps: [{ n, action, actor, target, state, finding }] }]`; `state` is missing or risk when `finding` fired in this run, otherwise empty |
| `topology` | `sources: [{ name, count }]` (every source family), `sourceTotal`, `rules` (enabled), `plans` and `downstream` as `[{ name, inUse, detail }]` |
| `cost-breakdown` | `currency`, `monthlyTotal`, `totalGb`, `plans: [{ name, gb, cost }]`, `sources: [{ name, gb, tables: [{ table, gb, tier }] }]` (every table, none bucketed) |
| `access` | `bands: [{ name, tone, findings[], roles: [{ role, users, groups, servicePrincipals }] }]`; `findings` lists the fired SAC-GOV-05 and SAC-GOV-06 on the broad-roles band |
| `lake` | `analyticsOnly`, `mirrored`, `extended`, `lakeOnly` (operational tables by tier configuration), `retentionYears`, `uses: [{ name, detail }]` |
| `estate` | `totalGb`, `coveredGb`, `sources: [{ name, gb, coveredGb, tables, covered }]`, `stages: [{ name, value, of, label, detail }]` (ingestion, detection, alerts, incidents) |
| `runway` | `today`, `items: [{ label, date, state, inUse, evidence }]`; `state` is done, crit or active; `inUse` is null when the workspace cannot say |
| `workspace-age` | `created`, `today`, `ageDays`, `sku`, `retentionDays`, `rulesEnabled`, `connectors`, `tablesReceiving`, `tablesCatalogue` |
| `finding-cards` | `total` (all findings), `cards: [{ id, severity, title, category, evidence, remediation, learn, href }]`; carried on a `bp:visual` comment, so `source` is empty |
| `other` | null |

## The index

```json
{
  "schemaVersion": 1,
  "meta": { "workspace": "law-sentinel-prod", "generatedUtc": "...", "blueprintVersion": "0.2.0" },
  "sections": [ { "id": "00-overview", "order": 0, "title": "SIEM Overview", "file": "00-overview.json" } ]
}
```

The Markdown contents page (`index.md`) has no section file: the index is the
list of sections.

## How it is made

The renderer
([`Convert-SentinelInventoryToMarkdown.ps1`](../../../Modules/iSOCBlueprint/Engine/Convert-SentinelInventoryToMarkdown.ps1))
composes each section, then
[`ConvertTo-BlueprintSection`](../../../Modules/iSOCBlueprint/Engine/Private/ConvertTo-BlueprintSection.ps1)
parses it with Markdig (the parser behind `ConvertFrom-Markdown`) into blocks
and runs, and
[`ConvertFrom-BlueprintMermaid`](../../../Modules/iSOCBlueprint/Engine/Private/ConvertFrom-BlueprintMermaid.ps1)
turns each Mermaid chart into data. Consumers only ever see the model, so a
section can later build its blocks directly without changing this contract.

## Compatibility

`schemaVersion` is 1. A change that removes or renames a field, or changes
its meaning, bumps it; adding an optional field or a new block type, run
flag, link kind or chart kind does not, so a consumer should ignore what it
does not know. Tests validate every section the fixture renders against the
schemas ([`Tests/iSOCBlueprint/Section-Model.Tests.ps1`](../../../Tests/iSOCBlueprint/Section-Model.Tests.ps1)).

## Related

- [iSOC Blueprint](Sentinel-Blueprint.md): what the Blueprint collects and renders.
- [Renderer design](Blueprint-Renderer-Design.md): what drives each section and chart.
- [SharePoint site](Sentinel-SharePoint-Site.md): the site built from this model.
