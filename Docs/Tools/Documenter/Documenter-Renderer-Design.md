# Sentinel Documenter, renderer design spec

> Maintainer-facing reference for [`Tools/Documenter/Convert-SentinelInventoryToMarkdown.ps1`](../../../Tools/Documenter/Convert-SentinelInventoryToMarkdown.ps1).
> The user-facing operating guide is the sibling [`Sentinel-Documenter.md`](Sentinel-Documenter.md).

This doc captures the design of the renderer, what each chart is driven
by, where every helper lives, the Mermaid-safety conventions that govern
chart emission, and how to extend any of it without regressing.

If you've never touched the renderer before, read this once before
opening the PowerShell file. The renderer is ~4,240 lines; this doc is
the map. It has grown substantially over successive waves, so this spec
cites **function and variable names** rather than hard line numbers,
which rot on every edit.

## Architecture overview

The Documenter is a two-stage renderer, with an optional third
ADO-only image pre-render pass:

```
Live workspace → Export-SentinelInventory.ps1     → _raw/*.json
_raw/*.json    → Convert-SentinelInventoryToMarkdown.ps1 → 38 .md files
*.md (ADO only)→ Convert-MermaidToImage.ps1        → assets/*.png + rewritten fences
```

Stage 2 (this spec's subject) emits **38 output files**: 37 numbered
section files (`00-overview.md` through `99-references.md`) plus
`index.md`. Of the 37 numbered files, 36 are written by `Write-Section`
blocks; `99-references.md` is copied verbatim from the resource
catalogue (`Copy-Item`) rather than generated. Stage 3
(`Convert-MermaidToImage.ps1`) is described in
[Mermaid PNG pre-render (ADO only)](#mermaid-png-pre-render-ado-only)
below.

The renderer is a single PowerShell script organised as:

1. **Param block + module bootstrap**: the `param()` block declares
   `-WorkspaceName` (mandatory), `-InputRoot`, `-OutputRoot`,
   `-ResourcesRoot` (defaults to `Private/Resources`); it then dot-sources
   `Private/Get-EffectiveConnectors.ps1`.
2. **Helpers**: the toolbox. Documented in detail below. Note these are
   **not** collected in one block, they are interleaved with the section
   code (from `Read-Raw` near the top down to `Format-MinutesScalar` well
   past the two-thirds mark).
3. **Inventory loading + cross-section hoisting**: every `_raw/*.json` is
   read once into a typed PSObject via `Read-Raw` / `Read-RawArray`; the
   few globals that multiple sections share (`$gapBySeverity`,
   `$gapByCategory`, `$populatedTableNames`) are computed here, and
   `$mitreRowsRich` is built later inside the section-25 block.
4. **Section emit blocks**: one block per `.md` file. Each block builds
   its data, optionally builds a Mermaid chart, then calls
   `Write-Section <filename> <body>` which writes to disk + applies the
   `SENT-NNN` auto-link pass.
5. **Index page**: the final `Write-Section 'index.md'` call emits the
   navigation TOC.

Every section emit block follows the same shape:

```powershell
# Optional pre-computation specific to this section.
# Optional chart-block string ($chartBlock = if (data) { @"..."@ } else { '' }).

Write-Section '<NN>-<slug>.md' (@"
$(Format-Banner -Title "Friendly title")
$chartBlock                                # injected if non-empty
## Subsection
$(Format-Table -Items $rows -Columns ...)
"@)
```

The pattern keeps each section local and grep-able. Helpers compose;
no section reaches into another section's variables (except via the
hoisted globals).

## Chart system

**39 Mermaid chart blocks across 32 of the 37 numbered sections.** Every
chart is driven by data from the captured `_raw/*.json` (no static
decoration) except for a handful of deliberately static, instructional
diagrams (the SOC-analyst `journey`, the alert-to-response
`sequenceDiagram`, the Lake-architecture `flowchart`). Every data-driven
chart guards against empty data, sections with nothing to chart emit the
table only.

### Charts by section

| Section | Chart type | Data source | Conditional guard |
|---|---|---|---|
| `00-overview.md` | pie | `$gapBySeverity` | none (always renders) |
| `01-live-snapshot.md` | pie | `$gapBySeverity` (reused) | none |
| `01-live-snapshot.md` | gantt | static deadlines + `_DaysUntilFromToday` | none |
| `10-data-connectors.md` | pie | `$connectors` grouped by `kind` | none |
| `11-sentinel-health.md` | pie | `$healthSummary` grouped by Status | `$healthSummary.Count -gt 0` |
| `12-soc-optimization.md` | pie | recommendation-category counts | `$socTotal -gt 0` |
| `13-data-source-hygiene.md` | pie | `$cefDevices` grouped by DeviceVendor | `$cefDevices.Count -gt 0` |
| `14-coverage-breakdowns.md` | xychart-beta bar | `$xdrPres` top 12 by RecordCount | `$xdrPres.Count -gt 0` |
| `15-incidents.md` | stateDiagram-v2 | `$incMttr.ClosedCount` + `$incSummary.Count` | none |
| `15-incidents.md` | journey | static SOC analyst flow | none |
| `20-analytics-rules.md` | classDiagram | per-kind deployed-count notes | none |
| `21-analytics-by-volume.md` | xychart-beta bar | `$ruleVolumes` top 10 by Alerts | `$ruleVolumes.Count -gt 0` |
| `22-analytics-microsoft-rules.md` | pie | Microsoft rules grouped by Severity | `$msRules.Count -gt 0` |
| `23-analytics-modifications.md` | xychart-beta bar | per-month bucket counts (last 12mo) | none |
| `24-analytics-by-solution.md` | pie | top 8 solutions by rule count + Other | none |
| `25-mitre-coverage.md` | xychart-beta bar (width 1400) | `$mitreRowsRich.EnabledRules` | none |
| `26-ueba.md` | pie | `$uebaPresenceRows` by table | `$uebaTotalRows -gt 0` |
| `27-threat-intelligence.md` | pie | `$tiRows` top 6 by IndicatorCount | `$tiRows total > 0` |
| `30-hunting-queries.md` | pie | hunting queries grouped by MITRE tactic tag | `$hunting.Count -gt 0` |
| `35-parsers-functions.md` | pie | parsers grouped by Category | `$parserRows.Count -gt 0` |
| `38-summary-rules.md` | pie | summary rules grouped by Active/Status | `$summaryRows.Count -gt 0` |
| `40-workbooks.md` | pie | saved vs available templates | none |
| `50-watchlists.md` | pie | watchlists grouped by Source | `$wlRows.Count -gt 0` |
| `60-automation-rules-playbooks.md` | sequenceDiagram | static alert-to-response chain | none |
| `70-content-hub.md` | pie | packages grouped by source kind | none |
| `80-workspace.md` | timeline | `$wsCreated` + static platform deadlines | none |
| `81-table-plans-retention.md` | pie | tables grouped by plan | none |
| `83-data-collection.md` | flowchart (LR, 3 subgraphs) | `$connectors` → workspace → downstream | none |
| `84-cost-estimate.md` | xychart-beta bar | `$cost.Top10TablesByCost` | inside the `if ($cost)` branch |
| `84-cost-estimate.md` | mindmap | top 8 cost tables tree | inside the `if ($cost)` branch |
| `84-cost-estimate.md` | sankey-beta | source → table → billing tier | inside the `if ($cost)` branch |
| `84-cost-estimate.md` | flowchart (compact) | same data, fallback for dense workspaces | inside the `if ($cost)` branch |
| `85-rbac.md` | flowchart (LR, 2 subgraphs) | `$rbacWs` aggregated by type × role | `$rbacWs.Count -gt 0` |
| `86-subscription-context.md` | pie | resource-providers grouped by State | `$rpRows.Count -gt 0` |
| `87-azure-monitor-agents.md` | xychart-beta bar (conditional) | AMA vs MMA per machine type | `$totalAgents -ge 3` (else sentence) |
| `88-sentinel-data-lake.md` | pie | `$tierPieRows` (tables by tier configuration) | `$tierPieRows.Count -ge 2` |
| `88-sentinel-data-lake.md` | xychart-beta bar (width 1400, height 480) | `$topRetention` Lake-only retention days | inside the same `$tierPieRows.Count -ge 2` branch |
| `88-sentinel-data-lake.md` | flowchart (LR, three tiers) | static Lake ingest / mirror / promote / query paths | `$hasDataLake` |
| `90-gap-analysis.md` | xychart-beta grouped bar | `$gapByCategory` × Warning/Info | `$gapFindings.Count -gt 0` |

### Sections intentionally chart-less

5 of the 37 numbered sections do not emit a chart because the data shape
doesn't support one or the page is pure-reference:

- `36-data-export.md`, `37-search-restore.md`, `82-dedicated-cluster.md`, 
  typically empty on most workspaces.
- `96-references-microsoft.md` (curated Microsoft Learn links) and
  `99-references.md` (the Documenter's own API-version / module list,
  copied verbatim from the resource catalogue).

Two further pages carry no chart but are not counted in the 32 above:

- `index.md`, the navigation TOC (not a numbered section).
- `87-azure-monitor-agents.md` when agent count < 3, renders a sentence
  instead because a 1-vs-0 pie is visually meaningless (it is otherwise
  a chart-bearing section, hence its place in the 32).

The rule: **chart only when data shape justifies it; never as decoration.**

## Helper toolbox

Line numbers are deliberately omitted (they rot on every edit); grep the
function name to locate each definition. The helpers appear in the file
in roughly the order below, interleaved with the section code rather than
grouped in one block.

| Helper | Purpose | Called from |
|---|---|---|
| `Read-Raw` | Reads a single object from `_raw/<file>.json`. Returns `$null` when missing. | Inventory loading; section blocks |
| `Read-RawArray` | Reads an array from `_raw/<file>.json`. Returns `@()` (NOT `@($null)`) when missing, prevents phantom rows. | Every section that consumes an array |
| `Write-Section` | Writes a body to `<OutputRoot>/<FileName>` AND runs the fence-aware, two-pass SENT-NNN auto-link regex on the body before writing. | Every section block |
| `Format-DateUtc` | Accepts `[datetime]` or ISO/culture string; returns `yyyy-MM-dd HH:mm` (invariant culture, UTC, no seconds). Empty/unparseable → `''`. | LastIngested, LastEvent, LastSeen, banner timestamp, AsOfUtc, lastModifiedUtc |
| `Format-Gb` | Numeric-ish input → 3-decimal string. `(0, 0.001)` → `<0.001`, `0` → `0`, non-numeric → passthrough. | BillableLast24h, Gb30d, top-tables-by-cost |
| `Format-Banner` | Section header, title, workspace, generated date, version. Reads `$run` (run-context.json). | Every section emit block |
| `Format-Table` | PSObject array → Markdown table. Empty input → `_None._`. Handles nulls, escapes pipes. | Every section that emits a table |
| `Format-Severity-Badge` | Severity string → coloured emoji (`🔴 Critical`, `🟠 Warning`, `🔵 Info`). | Top-recommendations bullets in 00 / 01, gap-analysis findings table |
| `Format-FeatureFlag` | Workspace feature property → string ("True"/"False"), missing = False. | Workspace feature-flag table (80) |
| `Format-MinutesScalar` | MTTA/MTTR scalar → "X.X min" or "n/a". Handles KQL `NaN` string. | MTTR headline in 15 |
| `Format-MitreTechniqueCell` | Technique ID → `[T1078, Valid Accounts](url)` Markdown link. Falls back to ID-only if catalogue lacks the name. | MITRE tactic-detail tables (25) |
| `_SocOptRow` | Internal, builds a SOC Optimization row PSObject. | SOC Optimization Coverage + DataValue tables (12) |
| `_CostSourceFor` | Inline (within the 84 emit block). Table name regex → cost source category for Sankey aggregation. | Cost Sankey (84) |
| `_DaysUntilFromToday` | ISO date → integer days until. Drives gantt bar widths. | Live-snapshot deprecation gantt (01) |
| `Get-ConnectorFriendlyTitle` | Connector `kind` → user-readable name (e.g. "MicrosoftThreatProtection" → "Microsoft Defender XDR"). Knows the CCF lookup via `$ccfTitleByName`. | 10-data-connectors classic + CCF tables |
| `Get-ConnectorAggregateState` | Per-data-type state → single aggregate (enabled / partial / disabled). | 10-data-connectors State column |
| `Get-ConnectorDataTypes` | Connector → data-type list (classic) or single dataType string (RestApiPoller/Push). | 10-data-connectors DataTypes column |
| `Get-ConnectorTargetTable` | Connector + data type → target workspace table. | Connector-health join + Get-EffectiveConnectors |
| `Get-ConnectorData7d` | Connector + tables-with-data → "Yes/No" for 7-day activity. | 10-data-connectors Data7d column |

External helpers used by the renderer:

- `Get-EffectiveConnectors`, [`Tools/Documenter/Private/Get-EffectiveConnectors.ps1`](../../../Tools/Documenter/Private/Get-EffectiveConnectors.ps1), 
  synthesised connector view that fuses classic + CCF + DCR + diagnostic-settings + active-tables.
- `Get-SentinelCostEstimate`, used by the **exporter** (not the renderer) to
  produce `_raw/cost-estimate.json` which the renderer consumes via `Read-Raw`.
- `Get-SentinelGap` + `GapChecks.ps1`, also exporter-side; produces
  `_raw/gap-analysis.json`.

## Cross-section hoisted globals

These are computed once just after inventory loading (before the section
emit blocks begin) and consumed by multiple section blocks. Hoisting
prevents drift between sections that all need the same numbers.
`$mitreRowsRich` is the exception, it is built inside the section-25
block and read back by the section-01 headline.

- **`$gapBySeverity`**, `@{ Critical = N; Warning = N; Info = N }`. Consumed by
  00-overview pie + 01-live-snapshot pie + 01 KPI table + 01 top-five
  recommendations sort.
- **`$gapByCategory`**, `@{ <Category> = @{ Critical = N; Warning = N; Info = N } }`.
  Consumed by 90-gap-analysis grouped bar chart.
- **`$mitreRowsRich`**, array of `{ ID, Tactic, EnabledRules, Techniques,
  SubTechniques, Coverage }`. Built once in the section-25 block; consumed
  by the 25 matrix table, the 25 bar chart, and the section-01 MITRE
  headline row.
- **`$populatedTableNames`**, hashtable of table names with billable data in
  the last 90 days. Consumed by 81 (operational subset filter) + 84
  (cost calculation gating).

## Conventions and gotchas (Mermaid safety)

Codified in inline comments throughout the renderer. New chart emission
must respect these:

### Pie charts
- Always emit `pie showData title <Title>` (the `showData` flag puts the
  count + percentage next to each slice).
- 2, 6 slices ideal. Above 6 → top-N + "Other" bucket.
- 1 non-zero slice → **skip the chart** and emit a sentence (saw this
  with AMA=1/MMA=0 earlier, visually meaningless).

### xychart-beta
- **Vertical only.** Horizontal mode (`xychart-beta horizontal`) with
  categorical Y-axis is a grammar gap on every Mermaid renderer tested
  (GitHub, ADO Wiki, MkDocs). Use vertical bars with short x-axis labels
  + a fallback Markdown table for full names.
- **No stacking.** Mermaid xychart-beta has no stacked-bar mode. Use
  grouped (adjacent) bars via multiple `bar [...]` directives, or
  switch to a flowchart.
- **Long category labels** truncate at ~10 chars on the X axis. Always
  pair the chart with a table that carries full names.
- **Per-chart width/height config.** Wide charts set an explicit
  `xyChart` config block (`---config: xyChart: width/height---`).
  `width: 1400` is used on charts with 12+ categorical labels (the MITRE
  bar, the XDR coverage bar) and on the cost-estimate bar; the
  data-lake Lake-only-retention bar sets both `width: 1400` and
  `height: 480`.

### flowchart
- **Wrap labels in double quotes** when they contain parens, brackets,
  `<br/>`, or punctuation: `S1["Microsoft 365 (Office 365)"]`. Unquoted
  parens are treated as a node-shape directive and parse-error with
  `Expecting 'SQE', 'PE', 'STADIUMEND' got 'PS'`. This rule applies
  whenever the source data is user-supplied or vendor-supplied (CCF
  titles, table names, etc.).
- **Subgraph labels** must be short, Mermaid clips them when the
  topmost child node is tall. Keep ≤ 30 chars and avoid embedding the
  workspace name (the page banner already carries it).
- **Cap node count** at ≤ 10 per subgraph before falling back to an
  "Other (N)" bucket.

### Sankey
- Sources are aggregated into named buckets via `_CostSourceFor` so the
  diagram has ~8 lanes on the left, not 10 individual tables.
- Config: `showValues: true`, `nodeAlignment: justify`, `nodePadding: 28`,
  `width: 1200`, `useMaxWidth: true`, `linkColor: gradient`. Earlier
  defaults clipped long-tail flows badly.
- **Height is dynamic, not fixed.** `$sankeyHeight =
  [Math]::Max(720, 24 * $tallestColumn + 200)`, so 720 is the floor and
  the diagram grows with the tallest column's node count. A fixed height
  crammed labels together once a column exceeded ~20 nodes.
- Three-column layout: `Source,Table,Value` rows then `Table,Tier,Value`
  rows.

### Mindmap
- **Avoid `(N)` in node text**, Mermaid interprets parens as a shape
  directive. Use `· N` or `[N]` separators instead.

### Experimental types, DO NOT USE
- `quadrantChart`, no anti-overlap. Even 3-4 close points collide.
  Use a 2x2 flowchart (subgraph per quadrant) instead.
- `architecture-beta`, GitHub's Mermaid version errors on otherwise-valid
  syntax. Use flowchart with subgraphs instead.
- `kanban`, GitHub rejects `[brackets]` in card text and may not know
  the `kanban` keyword. Use flowchart with column-shaped subgraphs.
- `block-beta`, `treemap-beta`, `packet-beta`, `radar-beta`, version
  drift between renderers. Use established types until they stabilise.

### General
- **Mermaid blocks live inside fenced `mermaid` code blocks.** The
  auto-link regex in `Write-Section` skips fenced code blocks
  automatically.
- **Always guard charts behind a data-present test.** Empty fixtures or
  quiet workspaces must produce a table-only render, not a featureless
  chart.

## Auto-link rewriting

`Write-Section` runs every section's body through two regex passes
before writing to disk. It walks the body line-by-line tracking
fenced-code state (any line matching `^\s*```` toggles the fence flag),
and rewrites **only outside fences**, so `SENT-NNN` mentions inside
`mermaid` / `kusto` blocks (for example the `click` tooltips in 85-rbac)
render literally rather than being turned into broken links:

1. **Pass 1**: `\[(SENT-\d{3,})\](?!\()`, bracketed-but-unlinked IDs.
   Catches the existing `[SENT-NNN]` bullet shape in 00-overview's
   "Top recommendations" lists and turns them into Markdown links.
2. **Pass 2**: `(?<![\[\(#\-])\b(SENT-\d{3,})\b(?![\]\)])`, bare IDs not
   already inside a Markdown link. Catches mentions in prose. The leading
   `-` exclusion reserves room for future composite IDs (`SENT-AUTH-001`).

Both rewrite to `[SENT-NNN](90-gap-analysis.md#sent-nnn)`. Within
90-gap-analysis.md itself the relative path collapses to just the
anchor (`(#sent-nnn)`).

Anchor targets are written in the same section's
remediation-detail block as `<a id="sent-nnn"></a>` immediately above
each `### SENT-NNN, Title` H3 heading. HTML anchors render to nothing
on every Markdown host but provide stable link targets that don't shift
when titles change.

## Mermaid PNG pre-render (ADO only)

The renderer always ships raw ` ```mermaid ` fences. GitHub renders those
natively in its web UI, so the GitHub `sentinel-document.yml` workflow
does nothing further. Azure DevOps does not: ADO Repos' markdown preview
and "publish code as wiki" treat ` ```mermaid ` as plain code, ADO Wiki
proper lags the Mermaid spec and drops the experimental types the
renderer emits (`xychart-beta`, `sankey-beta`), and ADO blocks inline SVG
for security so an SVG `<img>` shows as a broken image.

[`Tools/Documenter/Convert-MermaidToImage.ps1`](../../../Tools/Documenter/Convert-MermaidToImage.ps1)
is the ADO-only third stage that closes that gap. In the ADO pipeline
([`Pipelines/Sentinel-Documenter.yml`](../../../Pipelines/Sentinel-Documenter.yml))
it runs immediately after the renderer, gated behind the pipeline's
`prerenderChartsToPng` parameter (default on, so it can be switched off
per-run). When enabled the pipeline installs Node 20 and
`@mermaid-js/mermaid-cli@11` (`mmdc`) before invoking it. There is **no
GitHub equivalent** (the ADO Documenter is manual-trigger-only; the
GitHub Documenter runs on a daily schedule plus `workflow_dispatch`).

What the pass does, per workspace folder under `-Root` (the pipeline
passes `SecurityDocs`):

1. Creates an `assets/` sidecar directory (`-AssetsDir`, default
   `assets`).
2. Walks every `*.md` file and extracts each fenced ` ```mermaid ` block
   with the regex `(?ms)```mermaid\s*\r?\n(.*?)\r?\n````.
3. Hashes the block body (SHA-256, first 12 hex chars, lower-case) to
   name the image. Identical diagrams across files therefore share one
   image, and re-runs are **idempotent**, an already-rendered hash is
   reused rather than re-rendered.
4. Runs the block through `mmdc` (`-t` theme `default`, `-b` background
   `white`, `-w` width `1400`, `-p` a puppeteer config that adds
   `--no-sandbox` for root CI agents; `-s` scale `2` is added for PNG
   only) to produce `assets/<hash>.<ext>`.
5. Rewrites the fenced block in-place as `![Diagram](assets/<hash>.png)`.

`-Format` defaults to `png` (the only format ADO renders reliably) but
accepts `svg`. `mmdc` failures are **warnings, not errors**, the
offending fence is left untouched and the summary counts it under
`Failures`, so one bad chart never breaks the whole doc set. The script
prints a per-run summary (charts seen / images emitted / failures /
assets root).

## Critical files referenced

| Path | Role |
|---|---|
| [`Tools/Documenter/Convert-SentinelInventoryToMarkdown.ps1`](../../../Tools/Documenter/Convert-SentinelInventoryToMarkdown.ps1) | The renderer this spec describes |
| [`Tools/Documenter/Export-SentinelInventory.ps1`](../../../Tools/Documenter/Export-SentinelInventory.ps1) | Stage 1, produces `_raw/*.json` |
| [`Tools/Documenter/Convert-MermaidToImage.ps1`](../../../Tools/Documenter/Convert-MermaidToImage.ps1) | Stage 3 (ADO only), pre-renders Mermaid fences to PNG via `mmdc` |
| [`Pipelines/Sentinel-Documenter.yml`](../../../Pipelines/Sentinel-Documenter.yml) | ADO pipeline that runs the renderer + PNG pre-render (`prerenderChartsToPng`) |
| [`Tools/Documenter/Private/Get-EffectiveConnectors.ps1`](../../../Tools/Documenter/Private/Get-EffectiveConnectors.ps1) | Dot-sourced helper for the 10-data-connectors synthesised view |
| [`Tools/Documenter/Private/Get-SentinelGap.ps1`](../../../Tools/Documenter/Private/Get-SentinelGap.ps1) + [`GapChecks.ps1`](../../../Tools/Documenter/Private/GapChecks.ps1) | Gap engine, exporter consumes them to produce `gap-analysis.json` |
| [`Tools/Documenter/Private/Resources/best-practices.json`](../../../Tools/Documenter/Private/Resources/best-practices.json) | 45-rule catalogue driving the gap engine |
| [`Tools/Documenter/Private/Resources/mitre-attack.json`](../../../Tools/Documenter/Private/Resources/mitre-attack.json) | v18 ATT&CK catalogue (tactics + 216 techniques + 475 sub-techniques) |
| [`Tools/Documenter/Private/Resources/sentinel-benefit-tables.json`](../../../Tools/Documenter/Private/Resources/sentinel-benefit-tables.json) | Tables eligible for the Sentinel free-ingest benefit |
| [`Tools/Documenter/Private/Resources/commitment-tiers.json`](../../../Tools/Documenter/Private/Resources/commitment-tiers.json) | Workspace commitment-tier pricing breakpoints |
| [`Tests/Documenter/Convert-SentinelInventoryToMarkdown.Tests.ps1`](../../../Tests/Documenter/Convert-SentinelInventoryToMarkdown.Tests.ps1) | Renderer Pester suite (~140 tests) |
| [`Tests/Documenter/Get-SentinelGap.Tests.ps1`](../../../Tests/Documenter/Get-SentinelGap.Tests.ps1) | Gap-engine Pester suite (~40 tests) |
| [`Tests/Documenter/Invoke-SentinelRest.Tests.ps1`](../../../Tests/Documenter/Invoke-SentinelRest.Tests.ps1) | REST helper Pester suite (~7 tests) |
| `Tests/Documenter/Fixtures/sample/_raw/*.json` | Fixture dataset that all renderer tests run against |

## How to extend the renderer

### Adding a new chart to an existing section
1. Locate the section's `Write-Section '<NN>-...'` block.
2. **Before** the `@" ... "@` body, compute the chart inputs from
   already-loaded inventory variables. Don't add a new `Read-RawArray`
   call unless the data isn't already available.
3. Build a `$chartBlock` variable conditionally:
   ```powershell
   $chartBlock = if (<data-present-test>) { @"

   ## <Subsection heading>

   ``````mermaid
   <chart>
   ``````

   <prose explaining what the chart shows>
   "@ } else { '' }
   ```
4. Inject `$chartBlock` at the desired position inside the section body.
5. Verify rules from "Conventions and gotchas" above, especially
   quote-flowchart-labels and skip-on-empty.

### Adding a new section
1. Add a `Read-RawArray '<file>.json'` for the data source (if not
   already loaded).
2. Add a `Write-Section '<NN>-<slug>.md' (@"...")` block in section-id
   order so the renderer's output enumeration stays sorted.
3. Update the `index.md` TOC table at the bottom of the renderer to
   reference the new section.
4. Add a fixture file in `Tests/Documenter/Fixtures/sample/_raw/` so
   the new section renders during tests.
5. Add a Pester case in
   `Tests/Documenter/Convert-SentinelInventoryToMarkdown.Tests.ps1`
   asserting the section renders (at least its title) cleanly.

### Adding a new helper
1. Place the function ahead of its first caller. Helpers are not gathered
   in one block, nor kept in alphabetical order, they sit next to (or
   just above) the section code that uses them. Generic formatters
   (`Format-*`) live near the top with the inventory loaders; section-
   specific helpers (`_CostSourceFor`, `_SocOptRow`) sit inline with
   their section. Keep new generic helpers with the other `Format-*`
   functions.
2. Add a row to the "Helper toolbox" table in this spec when the next
   maintainer updates the doc.
3. Helpers must be **single-purpose, side-effect-free, and accept any
   reasonable input shape** (`[datetime]` OR string OR null). Return
   `''` for unparseable / empty input rather than throwing.
4. Reserved PowerShell auto-variable names to avoid: `$PID`, `$HOME`,
   `$PSHOME`, `$Error`, `$Args`, etc. The renderer treats variable
   names case-insensitively, so `$pId` collides with `$PID` and
   triggers a read-only-variable write error.

### Adding a new gap rule
Out of scope for this renderer spec, see the [`best-practices.json`](../../../Tools/Documenter/Private/Resources/best-practices.json)
schema and [`GapChecks.ps1`](../../../Tools/Documenter/Private/GapChecks.ps1)
pattern. The renderer consumes the gap output via `_raw/gap-analysis.json`
and writes the 90-gap-analysis.md page; new rules surface automatically.

## Verification

Every renderer change must pass these checks before commit:

### 1. Pester suite passes
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path Tests/Documenter/ -CI"
```
Expected: **187/187 passing**. Any new chart that affects fixture output
needs a matching assertion in the renderer test file.

### 2. Renderer runs against a captured workspace
Assuming a recent `_raw` directory exists from a prior exporter run:
```powershell
& ./Tools/Documenter/Convert-SentinelInventoryToMarkdown.ps1 `
    -WorkspaceName  '<workspace>' `
    -InputRoot      '<output-root>/<workspace>' `
    -OutputRoot     '<output-root>/<workspace>' `
    -ResourcesRoot  ./Tools/Documenter/Private/Resources
```
Expected: every section listed in "Charts by section" emits its chart
block; no parse errors; no stack traces.

### 3. Mermaid blocks render
Open the affected `.md` files in any of:
- VS Code with `bierner.markdown-mermaid` extension.
- Obsidian.
- GitHub (push to a branch + view in the web UI).

Expected: every Mermaid block renders without "Error parsing Mermaid
diagram" messages. Particular attention to:
- Subgraph labels not clipped.
- Long node labels not overflowing.
- Sankey lanes legible at the rendered width.
- No collision on the MITRE 14-tactic bar chart (width=1400 should
  prevent this).

### 4. Auto-link round-trip
Open any section that mentions `SENT-NNN` (00, 01, 90, 38). Click the
link, it must navigate to the matching `<a id="sent-nnn">` anchor in
90-gap-analysis.md.

## Outstanding work (forward-looking)

Items deferred for future passes:

- **Daily incident line chart** (15-incidents.md), needs a new exporter
  capture `incidents-daily-7d.json` with per-day counts. Currently the
  page has scalar avg+peak only.
- **Daily ingest line chart** (80-workspace.md or 84-cost-estimate.md), 
  needs `workspace-usage-14d.json` with per-day GB. Currently scalar
  peak/avg only.
- **More gap rules**, the `best-practices.json` catalogue is at 45
  rules; future v2.x batches can extend per-vendor connector checks,
  detection engineering depth, identity & access depth, and XDR
  migration readiness.
- **CI integration** is already in place, the GitHub `sentinel-document.yml`
  workflow runs the renderer on a daily schedule (plus `workflow_dispatch`),
  and the ADO `Sentinel-Documenter.yml` pipeline runs it manually with the
  optional PNG pre-render. A future refinement would trigger regeneration
  on content-affecting PRs as well as the daily cadence.
- **Renderer-output → vault sync**, a `-EmitTo <path>` parameter on
  the renderer (or a small `Sync-DocsTo.ps1` helper) would remove the
  manual-copy drift class.
