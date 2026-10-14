# iSOC Blueprint SharePoint Site

Generates and publishes an **iSOC Blueprint** SharePoint Online site for one
Sentinel workspace from the iSOC Blueprint's output. Every page, the
navigation, the findings list and the dashboard home page are generated; a
pipeline keeps the site in step with every Blueprint run.

> Companion pages: [iSOC Blueprint](Sentinel-Blueprint.md) produces the
> snapshot and the [section model](Section-Model.md) this site is built from.
> [SharePoint Publish pipeline](../../Pipelines/SharePoint-Publish.md) covers
> the CI/CD wiring, identity and secrets.

## What gets generated

One communication site per workspace, containing:

| Part | What it is | Where |
| --- | --- | --- |
| **Dashboard** (home page) | The interactive dashboard: an executive overview (glance tiles, the alert lifecycle, posture cards, the estate flow with its pipeline figures, the maturity card with quick wins, and the critical findings with a button to every finding), the data flow, insights, every section with charts and table filters, and an Assessment tab that switches between the maturity assessment and the findings. The maturity view states what the score is based on and that it covers the Sentinel workspace only. The findings view opens with a summary (by severity, by effect on the maturity score, by area, by category, and every scored finding ranked by its lift), where every legend entry, bar and row filters the list below; each finding shows what closing it does to the maturity score, and the list filters by severity, area, category and that effect. Each section links to its native page. | `SitePages/Dashboard.aspx`, set as the home page |
| **Section pages** | One modern page per Blueprint section (35 or so): the text as native text web parts, so it is searchable, printable and readable without JavaScript, and each chart as the iSOC Blueprint chart web part, which draws it from the chart's data. | `SitePages/sac-<NN>-<name>.aspx` |
| **Navigation** | The top navigation (mega menu): Dashboard, one heading per section family (Overview, Data sources, Operational health, Detection, Hunting & content, Automation, Workspace & data, Cost & access, Assessment, References) with its pages. Assessment holds the gap analysis, the maturity assessment and the findings list. | Top navigation bar |
| **Findings list** | Every gap-analysis finding, with severity, category, evidence, remediation and Learn link, plus history: `FirstSeen`, `LastSeen`, `Status` (Open, Resolved, Retired) and `ResolvedOn`. Finding links on the pages open the list filtered to that finding. An item still filed under a retired `SENT-NNN` id is recognised through the rule's `legacyId` and updated in place under its `SAC-<AREA>-NN` id, so history carries over the rename. | `Lists/SentinelFindings` |
| **Assets** | The dashboard HTML and data, the publisher's state file, the maturity score history, and a copy of the dashboard per day for its date picker (`dashboard/history/`). | `BlueprintAssets` library |

The generator owns all of the above. Manual edits to generated pages or the
top navigation are overwritten on the next run that changes them.

### Finding history

A finding that stops firing is not deleted. The Blueprint's gap engine now
records an outcome for every rule in `_raw/gap-checks.json` (Fired, Passed,
Errored, Undefined), and the publisher uses it:

| This run | Open item | Resolved or retired item |
| --- | --- | --- |
| Fired | Updated (`LastSeen`) | Reopened |
| Passed | **Resolved** (`ResolvedOn` set) | Unchanged |
| Errored or Undefined | Left open: the check could not tell | Unchanged |
| Rule no longer in the rule set | **Retired** | Unchanged |

Snapshots collected before `gap-checks.json` existed fall back to "not fired
means resolved". A snapshot with no gap analysis at all resolves nothing.

## The pieces

The three SharePoint commands of the [iSOCBlueprint module](../../../Modules/iSOCBlueprint/README.md),
each running a script under
[`Modules/iSOCBlueprint/Engine/SharePoint/`](../../../Modules/iSOCBlueprint/Engine/SharePoint),
with the dashboard template and the web part source:

| Command (script) | Job |
| --- | --- |
| `New-iSOCBlueprintSite` ([`Build-SentinelDocsSite.ps1`](../../../Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1)) | Offline. Turns a Blueprint run (a day folder, or a workspace folder, whose newest day it uses) into a site bundle in that run's `sharepoint/` folder, with the earlier days' dashboards in `history/`. |
| `Publish-iSOCBlueprintSite` ([`Publish-SentinelDocsSite.ps1`](../../../Modules/iSOCBlueprint/Engine/SharePoint/Publish-SentinelDocsSite.ps1)) | Makes a site match a bundle. Idempotent; `-WhatIf` reads and plans only. |
| `Initialize-iSOCBlueprintSite` ([`Initialize-SentinelDocsSite.ps1`](../../../Modules/iSOCBlueprint/Engine/SharePoint/Initialize-SentinelDocsSite.ps1)) | One-time admin bootstrap of the site and the publisher's access. |
| [`templates/sharepoint-dashboard.html`](../../../Modules/iSOCBlueprint/Engine/SharePoint/templates/sharepoint-dashboard.html) | The dashboard template the build fills in. |
| [`Modules/iSOCBlueprint/WebParts/`](../../../Modules/iSOCBlueprint/WebParts) | The SPFx solution: the web part that hosts the dashboard on the home page and the chart web part on the section pages. See its [README](../../../Modules/iSOCBlueprint/WebParts/README.md). |
| `Private/` | Section families, section-to-page conversion, the sync planners and the PnP wrappers. |

### The bundle

`New-iSOCBlueprintSite -Path <workspace>` writes:

| File | Contents |
| --- | --- |
| `index.html` | The self-contained dashboard (inline CSS and JS, data embedded as JSON with HTML-safe escaping) |
| `model.json` | The dashboard's data model |
| `site.json` | Product name, workspace, section list with page names, families and content hashes, build warnings. Its `diagrams` list is always empty now that charts are data; the publisher recycles the images earlier bundles uploaded. |
| `pages/<page>.json` | Per section: title and ordered segments, `html` for a text web part or `chart` (kind, title, data) for the chart web part |
| `findings.json` | Findings plus per-check outcomes |

Nothing in the build contacts SharePoint, Azure or anything else on the
network, so you can inspect a bundle before anything is published. What's
new in Sentinel and Defender is a report page (03), read by the collector;
`-SkipWhatsNew`, `-WhatsNewFeedUrl` and `-WhatsNewCount` are still accepted
so existing scripts run, and do nothing.

### Dashboard panels

The dashboard reads one embedded JSON model. Beyond the workspace headline,
counts, cost, findings, MITRE coverage and the billing flow, the model
carries the health-check views the Blueprint computes:

Under the glance tiles, the **alert lifecycle** follows the light or dark theme
(dark keeps a black "screen" behind the glow):
source families on the left run into the alerts raised on them, split in two:
Sentinel's (strand width = GB) and Defender XDR's (the Microsoft security
products: Entra ID Protection, Defender for Endpoint, Office 365, Identity
and Cloud, Purview and the rest; a strand from each family whose products
raised alerts, width = alerts). Both feed an animated core and the incidents
those became, so alerts and incidents count the same things: in a workspace
joined to the Defender portal every incident is a Defender XDR one,
whichever product raised its alerts. Alerts are counted once each, however
often a status change wrote them again, and every figure is the exact count.
A snapshot with no Defender XDR alerts shows one Alerts node. On the right
each
incident branch shows how it ended, closed by an automation rule, by an
analyst, in Defender XDR or by another identity, or still open with its
severities (strand width = incidents). A strip underneath gives ingestion per
day with a sparkline, alerts per incident (with the Sentinel and Defender
XDR split), open incidents, mean time to
resolve and the share closed by automation. Every part opens its page (the
sources open the Data flow tab). A snapshot collected before the closure
counts shows one Closed branch and says the automation share was not
captured. The particles stop for anyone who asks for reduced motion, and the
drawing pauses while the Overview is not on screen.

In dark mode every card (the header, panels, glance tiles, insight, contents,
section and finding cards) uses the alert lifecycle's screen, a teal-tinted
glow fading to near-black, and the base panel colour is darker to match; the
coloured posture cards keep their colours. The estate flow is drawn in the
same style: glowing source dots, ring arcs with a glow and spaced capitals
for the captions, and the closed and open incidents as glowing nodes with
their counts. When Defender XDR raised alerts, the band splits after
Detection into two rings centred on the line, Defender XDR alerts above
(Defender XDR's share of every alert, in its colour, since a share is not a
score, with the exact count under it) and Sentinel alerts below (the rules
that fired, as before), and the two merge into Incidents, which count both;
Defender XDR's products read no workspace table, so the rings before the
split do not count them. The Alerts figure under the flow gives the rules'
own alerts and Defender XDR's side by side, as does the Alerts stage on the
report's overview page.

The estate flow moves too: beads run along the strands a detection rule
reads, the band between the rings and the incident branches (faster for more
data), the dashed "no detection rule" strands creep towards their pool, and
each ring's arc draws in once when the page opens. Hovering a family dims the
other strands and their beads; none of it runs for reduced motion. The Data
flow tab's Sankey does the same: beads run along the middle of every ribbon
thick enough to carry them, and the ribbons sweep in from the left when the
tab opens and after each filter change (the sweep starts from a fully drawn
chart, so it never leaves the ribbons hidden).

The estate flow is interactive: hovering a source family spotlights its
strands, clicking a family or the "Not monitored" pool opens a table of the
tables behind it (GB, rules reading each, monitored or not, with "Show all"),
clicking a ring opens the matching page (table plans, detection
opportunities, analytics rules, incidents) and the Closed and Open boxes open
the incidents page. Unmonitored strands keep their family colour and run
dashed into the pool. The rings count enabled Sentinel analytics rules and
enabled Defender XDR custom detections that read a table
(`estate.customDetections` carries whether the Graph capture ran and the
enabled and total counts); product alerts raised inside Defender XDR, Entra
ID Protection, Defender for Identity or Defender for Cloud do not read
workspace tables, so the detail panel lists them per family
(`estate.productAlerts`, Sentinel's own rules excluded). The coverage column
reads "Sentinel rule reads it", "Custom detection reads it", "Rule and
custom detection" or "No detection rule". The model's `estate.tables` carries every table receiving
data with its family, GB, rule count and coverage.

Findings (on their tab and on the Overview) and the maturity criteria use
one card layout: a card per item with the pill, id and title on the first
line and a chevron at its far right, chips beneath (category, area and
what closing it does to the maturity score; area, kind and effort for
criteria; ids from before the SAC scheme are not shown, though the
findings search still finds a finding by its old id, see
[Sentinel-Blueprint.md](Sentinel-Blueprint.md#ids-before-the-sac-scheme)), the criterion's impact
line, then Evidence beside Remediation (or Guidance), each clamped to
three lines. The Microsoft Learn link sits under the remediation text and
a criterion's "Open finding" link under its evidence. Every card is the
same height when collapsed: each block reserves its three lines and its
link line, and the chevron (shown only when a block is clamped) opens
both blocks; clicking the clamped text does the same. Findings
filter by severity, category and free text; criteria by status, area and
free text, and a criterion whose id a fired finding shares carries an
"Open finding" link.

Every list on the dashboard is complete, either on the card or one click
away. The Insights cards that list things (top tables by volume, top
alerting rules, alerts by detection source, operational health, rule
effectiveness, failing playbooks, the data lake's extended tables) show at
least eight entries and then as many more as fit beside the tallest card
in their row, so a row's cards end level, and close with a button at the
foot of the card (the buttons in a row line up) such as
"All 2,780 rules in the report" that opens the report page holding every
entry (Rule Performance, Alerts, Sentinel Health and Resilience, Estimated
Monthly Cost, Automation Rules and Playbooks, Microsoft Sentinel Data
Lake; the data lake card keeps its button even when every table fits, as
its only link to that page). The Overview's top alerting rules show the
eight busiest, then "All N rules in the report". Detection opportunities
shows twelve tables, then the same kind of
button. Nothing expands in place there, so a list of thousands never
turns into a long scroll; a card whose report page is missing from the
run keeps a Show all control instead. Elsewhere (the Overview's quick
wins, ten roadmap gaps, a table's templates) Show all reveals the rest. In
a table it is a chevron rather than a labelled button, held at the top
right so it does not move as the list opens: in the table's header row when
it opens further rows, or beside the first chips in a cell. It turns over
when open, and "Show all N" or "Show fewer" is its tooltip and what a
screen reader announces. The Overview's top findings are the critical ones only,
with a button to the findings view, which lists every finding. With the
data lake enrolled, the Insights tab's ingestion by billing plan card
shows a Data lake plan row (0 GB when no table is lake-only) and a line
saying how many Analytics-plan tables are mirrored to the lake at no extra
ingestion charge and how many keep data there beyond analytics retention. The model carries the full lists (every effectiveness
row, every uncovered table with every template that reads it, every
alerting rule, every extended-retention table, every roadmap entry, every
table by cost).

Every button is made one way, so they look the same on every tab. The
template's `sbtn(label, attrs, opts)` writes a `.sbtn` button (or a link,
for "Open as a page"): white on the brand gradient a selected tab or
switch takes, one size (12.5px, 7px by 14px padding), one shape (10px
corners), with an arrow when it opens something. `.sbtn.icon` is the
square form for a symbol (zoom, a card's expand chevron, a table's Show
all chevron). That covers
"Show all" and "Show fewer", "Expand", "Clear filters", Close, the
report buttons ("All 2,780 rules in the report"), the finding links on a
criterion, and "Open the assessment", "Open the MITRE page", "Open the
ATT&CK grid" and "Open as a page". Any other class on a button only
places it. Toggles (the tabs, the Assessment switch, the ATT&CK grid's
switches, the data flow's filter chips) sit on a tinted track and take
the same gradient when selected. The gradient is one pair of variables,
`--btn-bg` and `--btn-shadow`, set for light and dark. Links to outside
documentation (Microsoft Learn, ATT&CK) and the contents lists stay plain
links.

The Insights tab lays its cards out in bands of similar height (donut and
pie cards, bar-list cards, table cards), with the full-width panels
(content inventory, the ATT&CK grid directly above detection
opportunities) between them, so a long table never shares a
row with a short donut. The
**ATT&CK grid** is laid out like MITRE's Navigator: a column per tactic in
kill-chain order with the techniques covered out of the total (every
tactic header the same height, so the cells start level), and a cell
per technique an analytics rule maps, shaded by the enabled rules that map
it, with its sub-techniques as chips by their full id. Techniques shade
green and sub-techniques violet, light to dark for 1 rule, 2 to 3 and 4 or
more. "Sub-techniques" switches the grid to list each mapped sub-technique
(full id, name and rule count) under its technique, shaded by its own
rules, and each tactic's header counts sub-techniques covered out of the
total instead; with "Every technique" it lists every sub-technique ATT&CK
defines, so the gaps show at that level too. A tactic a rule names that the
Enterprise matrix does not have (an ATT&CK for ICS one such as Impair
Process Control) gets a column of its own after the fourteen, so every
mapped technique shows. "Include disabled" adds the disabled
rules (a cell only they cover is dashed: covered once they are enabled),
"Every technique" adds the uncovered techniques, the search finds a rule or
a technique, and selecting a cell lists every rule mapped to it with its
status, severity, kind and sub-techniques; selecting a sub-technique lists
only the rules that map it. The grid scrolls sideways with a scrollbar in
the theme's colours. Its switches look like the dashboard's tabs, and an
"Open the MITRE page" button at the right of them opens page 25, which
links back to the grid. The content inventory's tiles
open their pages in the Report tab.
Every card grid balances its rows (five cards become three and two,
never four and one) and a short last row widens to fill the band. The
Sankey sizes each column to its longest label and stacks the GB value
under the label when the two cannot share a line.

The Report tab shows every section from the section model. It draws the
section's own pie and xy (bar) charts from their data, and every other
chart kind (incident lifecycle, journey, state, flowchart, sankey, gantt,
timeline, mindmap, class, sequence) with the chart web part's own renderers, so a diagram
looks the same in the dashboard and on the section's SharePoint page and
has one implementation. The site build puts those renderers into the page
from `templates/dashboard-charts.js`, which
`Modules/iSOCBlueprint/WebParts/Build-DashboardCharts.ps1` bundles from
the web part's TypeScript; a Pester test fails when the TypeScript changes
and the bundle is not regenerated. A diagram follows the light or dark
theme, and a node linking to a section or a finding opens it in the
dashboard. A diagram whose title repeats the heading above it shows the
heading only, here and on the SharePoint pages. Headings run into a
hairline and notes sit in a softly tinted box; nothing in the Report is
marked with a coloured edge bar. A section with no chart of its own gets one drawn from a short
table, and only when a column clearly holds an amount (a count, cost,
volume or total); a table with no such column gets no chart. A link to
another section opens it in the Report tab, and a link to a finding opens
it in the findings view, or the gap analysis page when this run's
findings list does not hold it. Every table's column titles sort it:
select one for ascending, again for descending, and a third time for the
page's own order; a small arrow shows which. A column of numbers sorts by
value, units included (sizes from KB to TB are scaled, so 512 MB sorts
below 65 GB, and days, percentages and currency read as numbers), and any
other column in natural order (Rule 2 before Rule 10); empty cells go last.
Sorting and the row filter work together. No page runs past the bottom
of the contents list beside it. A page that fits reads top to bottom, and
its scrolling tables (cut off at 620px) grow into any space above the
list's foot. A taller page with two or more main sections shows a tab at
a time below its intro: a section with 20 or more table rows starts a
tab, a smaller one (a short table or only text) joins the tab before it
while there is room, under its own heading, and small sections at the
start make an Overview tab (a tall intro opens that tab rather than
sitting above the strip). A tab or page still too tall shrinks its
tallest tables first, to 200px, and as a last resort scrolls inside the
panel. A tab is labelled with its heading (a bracketed qualifier moves
to the tooltip and the top of the tab) and the rows it holds; the arrow
keys move between tabs, and returning to a page reopens its last tab.
The layout is worked out when a page or tab opens, on resize and when
the contents search changes the list; on a narrow screen, where the list
sits above the page, the page reads top to bottom. Every page opens with
a sentence or two saying what it covers, which stays under the title
above any tabs; the renderer writes it for the pages whose opening did
not already say. The tabs are
underlined page tabs on a hairline rule, the selected one in full ink with
the button gradient beneath it. A line of figures in a page ("MTTA: ... ·
MTTR: ... · Closed: ...") shows as a row of tiles, label above figure,
lined up across the row however the labels wrap; a duration in minutes
reads in days and hours with the exact minutes in its tooltip, and a
bracketed qualifier ("last 30d") becomes a caption. A line that is mostly
text, such as a finding's severity and category, stays as text. A table
cell holding a list of four or more items separated by semicolons (the
solutions behind a table's templates, a finding's evidence list) shows as
chips: the first three, then a Show all chevron for the rest, with a lead-in such as
"146 rule(s) disabled:" kept as text above them. A template source that is
ready to enable, a solution marked installed or Built-in (templates that
ship with Sentinel), is tinted green; one whose solution is not installed
stays grey. The table's tool bar carries a key to the two in the
dashboard's filter chips, each with the legend's swatch and how many rows
hold that kind; selecting one shows only those rows, and in each row only
those chips, every one of them (so Not installed shows exactly what is not
installed), alongside the search box; selecting it again brings back the
first chips and the chevron. The search box matches every word,
or "quoted phrase", anywhere in the row. Each solution chip lists the
templates behind it in its tooltip and, selected, opens the page's
Undeployed templates ready to enable list showing exactly those templates
(that solution, that table), with a chip in the list's tool bar to show
every template again. A From solutions cell with one solution is a chip
too, so every row shows its colour. Status words in a table cell show as pills:
green for Up to date and Current, amber for Update available and Stale,
red for Deprecated, Not in catalogue and Stale, used by rules. A chart
with more than one series shows its key above the bars. The Markdown pages refer to one another by
file name (`90-gap-analysis.md`); the Report tab and the native pages show
the section's title instead ("Gap Analysis"), and a file name mentioned in
plain text becomes a link to that section.

Following a link or a tab starts at the top of what it opens. On
SharePoint the web part grows its iframe to the dashboard's full height
and the SharePoint page does the scrolling, so the dashboard scrolls the
host page (with `scrollIntoView`) rather than its own window.

| Model key | Panel | Source captures |
| --- | --- | --- |
| `estate` | Overview: the estate flow and the strip of pipeline figures under it (tables still receiving data, active tables read by a rule, enabled rules that fired, incidents closed; each opens its page) (source families to ingestion, detection, alerts, incidents; red strands pool under "Not monitored"). `alerts` is every product's alerts, split as `alertsSentinel` and `alertsXdr` for the alert lifecycle; `ruleAlerts` is the scheduled and NRT rules' own | `tables-with-data`, `rule-table-references`, `rules-fired`, `analytics-rule-volumes`, `incidents-summary` |
| `alertLifecycle` | Overview: the alert lifecycle's outcome branches and strip (`closedBy`: closed incidents by automation rule, analyst, Defender XDR or other; `openBySeverity`; `mttrMinutes`), beside `estate` for sources, alerts and incidents and `usageDaily` for the sparkline | `incidents-summary` (`ClosedBy`, `OpenBySeverity`), `incidents-mttr` |
| `attack` | Insights: the ATT&CK grid (`tactics` in kill-chain order, every base `technique` with its tactics, sub-technique total and sub-technique ids (`subs`), `subNames` for every sub-technique, every rule with `enabled`, `kind` and `severity`, and `cells`: tactic, technique and sub-techniques with the indices of the rules covering them), from Get-AttackCoverage, which page 25 uses too | `alert-rules`, `mitre-attack.json` |
| `maturity` | Overview: the maturity card (score, level band, target marker, the Sentinel-only scope, and every capability area's score against the target, weakest first, an area below target in amber; selecting an area opens the Assessment with the criteria filtered to it) and quick wins, filled to the maturity card's height so the two cards end level with their buttons in line (the rest behind Show all; when every quick win fits, the button opens the roadmap). Assessment tab, maturity view: the basis and scope as two tiles side by side, overall donut, one bar per area against the target, the score history once two runs have published, NIST CSF 2.0 rollup, roadmap, and every criterion with status, evidence, guidance and links to the findings behind it (filter and search). Selecting a roadmap entry, or a quick win on the Overview, filters the criteria to that one, as a finding does in the findings view; Clear filters brings the list back | `maturity.json` |
| `detectionOpportunities` | Insights: tables with data but no detection and the templates that would cover them (every table; the panel shows twelve with a Show all control, and each table lists every candidate template) | `rule-table-references`, `template-table-references`, `tables-with-data` |
| `effectiveness`, `incidentsByClassification` | Insights: rule effectiveness and incident outcomes | `rule-effectiveness`, `incidents-summary` |
| `usageDaily` | Insights: the daily ingestion trend | `workspace-usage-daily` |
| `playbookHealth` | Insights: runs and failures per playbook; playbooks whose run history could not be read are counted as unavailable, not as zero runs | `playbook-runs` |
| `dataLake`, `dataLakeEnrolled` | Overview: the "Data lake" glance tile. Insights: enrolment status, the tier distribution donut (Analytics only, Analytics + Lake mirror, Analytics + Lake extended, Lake only), the top tables by lake-only retention and the lake cost split; counted over the operational tables through `Private/Get-TableTierProfile.ps1`, the same helper page 88 uses | `sentinel-data-lake`, `workspace`, `workspace-tables`, `tables-with-data`, `cost-estimate` |
| `flowTables` | Data flow: every ingesting table with its family, plan label, GB and billed GB. The dashboard rebuilds the Sankey from this list: the default view keeps the nine largest tables and folds the rest into "Other"; clicking a source family (or its chip above the chart) shows every table in that family, clicking "Other" or the "Every table" chip shows them all | `cost-estimate`, `workspace-tables` |
| `flow` | Data flow: the billing-flow Sankey as built by the site (the default view; kept for bundles built before `flowTables` existed). Its "Plan and tier" column names the lake tier each table lands in (Analytics plan, Analytics + Lake mirror, Analytics + Lake extended, Data lake only, Basic plan, Auxiliary plan), so an enrolled workspace shows its lake rather than one Analytics box; lake nodes are drawn teal and the long-tail "Other" node fans out to every tier its tables use | `cost-estimate`, `workspace-tables`, `sentinel-data-lake`, `workspace` |
| `tiBySource`, `tiObjects` | Insights: indicators per feed | `threat-intel-counts`, `threat-intel-objects` |

Every panel has an empty state: a snapshot without a capture shows "not
available" or "not assessed" rather than a zero dressed up as a result.
The source families used by the estate flow come from
`Modules/iSOCBlueprint/Engine/Private/Get-TableFamily.ps1`, which the Markdown renderer
also uses, so the Markdown pack and the dashboard agree.

Nothing is pre-rendered for the site. Charts reach it as data in the
section model: the dashboard draws its own, and the section pages place the
chart web part.

### How a section becomes a page

The build reads `sections/index.json` and each `sections/<id>.json`, the
[section model](Section-Model.md) the renderer writes. It reads no Markdown,
so a Blueprint rendered with `-Format Json` is all it needs. A
snapshot rendered before the section model existed has only the
`NN-name.md` files; the build converts those with the renderer's own
converter and logs a warning. Each section is then cut down to what a
SharePoint text web part keeps:

- The section's title becomes the page title (the metadata banner is not
  part of the model).
- Headings are clamped to h2 to h4, with no ids or anchor stubs.
- Tables use the SharePoint editor's responsive table markup and are capped
  at 500 rows (`-MaxTableRows`). A longer table says how many rows are not
  shown and links to the dashboard, whose copy has every row and a filter.
- Links follow their target in the model: another section goes to its
  page, a finding (`SAC-<AREA>-NN`) goes to the findings list filtered on
  that id, a web URL is kept, and a repository path or an in-page anchor
  becomes plain text.
- The content is split into one text web part per H2, and each chart gets
  its own web part in the place it sits in the section.

#### Charts on section pages

Each chart is the iSOC Blueprint chart web part (component id
`4ae8707c-ca6f-40cb-a974-c94d023de6e5`, in the same `isoc-blueprint`
package as the dashboard web part from version 1.4.0). Its `chartJson`
property holds the chart block from the section model (kind, title and
data, see [Charts](Section-Model.md#charts)), and the web part draws it in
the browser as SVG and HTML, with no external libraries, in the colours of
the section's theme. A flowchart node's link goes where the same link in
the text would (another page, or the findings list filtered on a finding).
Kinds it cannot draw keep their Mermaid source in `chart.source` and are
shown as text. Labels are never shortened: a long one wraps over as
many lines as it needs, and an xy chart whose Mermaid labels are cut to
fit under the bars takes the full names from a `%% x-labels` comment the
renderer writes beside the axis. How each kind is drawn is in the web part's
[README](../../../Modules/iSOCBlueprint/WebParts/README.md#how-the-charts-render).

While the web part is not on the site yet (a package deployed a moment ago
can take a few minutes to register, or the package on the site predates
it), the publisher writes each chart as a text web part instead: a table of
its data for pie, sankey and bar or line charts, otherwise its title and a
note. Such a page is not recorded as published, so the next run rebuilds it
with the web part.

### What a publish does

In this order, so a failure part-way leaves the site consistent:

1. **Structure.** Ensure the `BlueprintAssets` library and the
   `Sentinel Findings` list and columns exist. Creating a library can
   outlast PnP's 100-second HTTP timeout while SharePoint still finishes;
   when the create call fails, the list is looked up for a minute and the
   run carries on if it is there.
2. **App.** Deploy the web part package (the dashboard and chart web
   parts) to the site collection app catalog,
   only when its version differs from the deployed one (and, on ADO, when
   **SharePoint: deploy the web part if it changed** is ticked). A package
   with the same solution id under an older solution name is removed first,
   because SharePoint keeps one catalog file per solution id.
3. **Assets.** Upload the dashboard. When the bundle carries a maturity
   assessment, append its score to the history (see below).
4. **Pages.** Create or rebuild each section page, skipping pages whose
   content hash matches the last publish. Pages are rebuilt in place (cleared
   and refilled, then published once), so URLs and version history survive
   and a failed publish leaves the last good version live. Before the first
   page with a chart, the publisher checks the chart web part is in the
   component list (`Get-PnPAvailablePageComponents`, read through a page
   that already exists), waiting up to five minutes when step 2 deployed a
   package this run. A lookup that fails is printed rather than taken for a
   slow deployment, and when the wait ends without the chart web part the
   log says whether the dashboard web part from the same package is
   listed. Without it, charts go in as tables (see
   [Charts on section pages](#charts-on-section-pages)). On a first publish
   no page exists to read the list through, so each new page looks the web
   part up as it is built.
5. **Dashboard.** Point the home page's web part at the uploaded dashboard,
   publish, and set it as the home page. On the first publish the web part
   is added to a full-width section; the publisher looks it up in the
   site's component list by id (ignoring braces and case) and waits up to
   five minutes for a freshly deployed package to appear there. The web
   part is stored with an `isFullWidth` property, which PnP needs before it
   will save a page with a custom web part in a full-width section; a
   dashboard page placed without it is rebuilt (the old page goes to the
   recycle bin).
6. **Findings.** Add, update, reopen, resolve and retire list items in one
   batch.
7. **Navigation.** Rebuild the top navigation from the pages that exist,
   only when it differs from the plan.
8. **Prune.** Send pages the bundle no longer has, and the diagram images
   earlier versions uploaded, to the recycle bin, only when every page
   published.

A failed section page is reported and retried on the next run; it never
stops the rest of the publish.

### Maturity history

Every publish of a bundle that carries a maturity assessment appends one
entry to `BlueprintAssets/_state/maturity-history.json`:

```json
{ "entries": [ { "publishedUtc": "2026-10-09T06:12:00Z", "bundleBuiltUtc": "2026-10-09 06:05 UTC",
                 "targetLevel": 3, "overall": { "score": 1.49, "level": 1 },
                 "areas": [ { "id": "DET", "score": 1.11 }, ... ] } ] }
```

The entry is keyed on the bundle's build time, so publishing the same
bundle twice does not add a point, and the file is capped at 180 entries
(`Add-SacMaturityHistoryEntry -MaxEntries`). A copy is written next to the
dashboard (`BlueprintAssets/dashboard/maturity-history.json`); the
Assessment tab's maturity view reads it from beside the live dashboard and
draws the overall score as a trend once two entries exist. On SharePoint
the dashboard runs in a frame whose address is `about:srcdoc`, so the
dashboard web part tells it the folder and reads the file for it (through
SharePoint's REST API, as it reads the dashboard itself); served as files,
the dashboard reads it from beside its own page. Opened from disk there is
nothing to read and the trend panel stays hidden. Both files are readable by
anyone who can read the dashboard, which is the same audience. `-WhatIf`
reports what it would append and writes nothing.

### Dashboard snapshots

Every publish also keeps the day's dashboard as
`BlueprintAssets/dashboard/history/<yyyy-MM-dd>.html` and lists it in
`dashboard/history/index.json` (date, file, generated time, findings,
critical findings, maturity score), newest first. The day is the
inventory's, so a second publish of the same run replaces that day's copy.
The list keeps the last `-HistoryDays` days (90 by default), counting back
from the newest, so with the daily pipeline it grows a day at a time until
it holds 90 days; older days go to the recycle bin. `-HistoryDays 0` keeps
none. A copy is about the size of the dashboard (around 3 MB).

The dashboard reads the list and shows a date picker beside the light and
dark toggle: Latest, then every kept day with its maturity score and
findings. Choosing a day opens the dashboard as it was that day, with a
banner saying so and a Back to latest button. On SharePoint the dashboard
web part loads the day into its frame; served as files, the page goes to
it. Each copy runs the dashboard code of its own day, so it always matches
its data; a later design change does not reach older copies. Only the
dashboard has a history: the section pages and the findings list show the
latest run.

Runs from the module land in a folder per day
(`SecurityDocs/<workspace>/<yyyy-MM-dd>/`), so a machine that runs the
Blueprint daily holds its own history. When `New-iSOCBlueprintSite` builds a
bundle for a day folder, it copies the dashboards of the earlier days in the
same window from the sibling day folders into the bundle's `history/`, with
an `index.json` in the same shape as the site's (each day's figures come from
its `site.json`). That makes the date picker work when the bundle is opened
from disk, and the publisher uploads any of those days the site does not
have yet, so a site first published from a machine with a month of runs
starts with that month. A day the site already holds is left as it is. A
bundle built from a flat folder (the pipelines, `-NoDateFolder`) has no
`history/` and relies on the site's own. `-HistoryDays` on
`New-iSOCBlueprintSite` sets the window (90 by default, `0` for none).

## Setting it up

### 1. App registrations

On Azure DevOps, [`Deploy/setup/Setup-SharePointPublisher.ps1`](../../../Deploy/setup/Setup-SharePointPublisher.ps1)
creates the publisher app, grants its SharePoint permission, creates the
`sc-sentinel-sharepoint` service connection and adds the federated
credential in one idempotent run (`-WhatIf` first). The table below is what
it sets up; on GitHub the federated credential is added by hand as the
[pipeline page](../../Pipelines/SharePoint-Publish.md) describes.

| App | Used by | Needs |
| --- | --- | --- |
| **Publisher** | The pipelines | SharePoint application permission `Sites.Selected` (admin consent). A federated credential per pipeline (see the [pipeline page](../../Pipelines/SharePoint-Publish.md)). No secrets. On ADO, Reader on one empty resource group so the `AzureCLI@2` task can select a subscription; no other Azure role. |
| **Your PnP sign-in app** | You, for the bootstrap and local runs | Delegated SharePoint `AllSites.FullControl` and Microsoft Graph `Sites.FullControl.All` (to grant the publisher access), with admin consent. |

If you do not have a PnP sign-in app yet, PnP.PowerShell creates one and
opens a browser for consent:

```powershell
Register-PnPEntraIDAppForInteractiveLogin -ApplicationName 'PnP PowerShell (Sentinel docs site)' `
    -Tenant 'contoso.onmicrosoft.com' `
    -GraphDelegatePermissions 'Sites.FullControl.All' -SharePointDelegatePermissions 'AllSites.FullControl'
```

Use the `AzureAppId/ClientId` it prints as `-ClientId` below. A placeholder
left in `-ClientId` fails sign-in with `AADSTS90013`.

### 2. Bootstrap the site (once, as a SharePoint administrator)

```powershell
Import-Module ./Modules/iSOCBlueprint
Initialize-iSOCBlueprintSite `
    -SiteUrl        'https://contoso.sharepoint.com/sites/isoc-law-sentinel-prod' `
    -Owner          'secops-lead@contoso.com' `
    -PublisherAppId '<publisher-app-id>' `
    -ClientId       '<your-pnp-app-id>' `
    -Tenant         'contoso.onmicrosoft.com' `
    -WhatIf
```

Drop `-WhatIf` to run it. It creates the communication site if needed,
checks the tenant app catalog exists, adds a site collection app catalog,
grants the publisher FullControl on this site only, turns page comments off
and the mega menu on. Pass `-AppPackagePath` to deploy the web part straight
away. It is safe to re-run.

### 3. Point the pipeline at the site

Set the site URL for the workspace: `sharePointSiteUrl` in the ADO variable
group (the publisher bootstrap sets it when given `-SharePointSiteUrl`), or
`SHAREPOINT_SITE_URL` on GitHub. On ADO, queue `Sentinel-Blueprint` with
**Export: SharePoint site** and **SharePoint: what-if** ticked, read the
plan, then queue it again without what-if; on GitHub, run the workflow with
`what-if` first. See [SharePoint Publish pipeline](../../Pipelines/SharePoint-Publish.md).

## Running it locally

From the repository root, against a downloaded Blueprint artefact:

```powershell
Import-Module ./Modules/iSOCBlueprint

# Build the bundle into ./artefact/law-sentinel-prod/sharepoint, then
# preview the publish, signed in as you
New-iSOCBlueprintSite -Path ./artefact/law-sentinel-prod |
    Publish-iSOCBlueprintSite `
        -SiteUrl 'https://contoso.sharepoint.com/sites/isoc-law-sentinel-prod' `
        -Interactive -ClientId '<your-pnp-app-id>' -Tenant 'contoso.onmicrosoft.com' -WhatIf
```

From a live workspace instead, in one line:
`New-iSOCBlueprint -ResourceGroup <rg> -WorkspaceName <ws> -Format SharePoint -SiteUrl <url> -Interactive -ClientId <app> -Tenant <tenant>`.
Without `-SiteUrl` it builds the bundle and stops, so you can open
`SecurityDocs/<ws>/<yyyy-MM-dd>/sharepoint/index.html` to preview the
dashboard.

The publisher needs PowerShell 7.4 and PnP.PowerShell 3.4.1. To build the
web part package yourself, see its
[README](../../../Modules/iSOCBlueprint/WebParts/README.md).

## Privacy

The site holds tenant configuration: workspace and subscription IDs, cost,
findings, role assignments and every section of the documentation. Its
membership is the privacy boundary, the same way a private repository is for
the Markdown.

- Keep the Visitors and Members groups to the people who should read it.
  The bootstrap leaves Visitors empty.
- The dashboard runs its script inside the home page (same origin), so
  whoever can write to the `BlueprintAssets` library can run script for
  everyone who opens the site. Keep write access to the publisher identity
  and site owners.
- The publisher's identity can reach this one site and nothing else in the
  tenant, and has no Azure access.

## What this is not

- **Not live.** The site shows the last published snapshot, normally the
  Blueprint's 06:00 run.
- **Not a place to edit.** Generated pages and the top navigation are
  overwritten. Add your own pages without the `sac-` prefix and they are
  left alone, but they will not appear in the generated navigation.
- **Not multi-workspace in one site.** One site per workspace, each with its
  own pipeline variables.

## Related

- [iSOC Blueprint](Sentinel-Blueprint.md): the collector and renderer.
- [SharePoint Publish pipeline](../../Pipelines/SharePoint-Publish.md): CI/CD wiring, identity, secrets.
- [Blueprint section model](Section-Model.md): the JSON the pages are built from.
- [iSOC Blueprint Word Report](Sentinel-Word-Report.md): the Blueprint as a `.docx`.
