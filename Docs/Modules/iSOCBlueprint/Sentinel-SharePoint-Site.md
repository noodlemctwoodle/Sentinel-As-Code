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
| **Dashboard** (home page) | The interactive dashboard: an executive overview (glance tiles, posture cards, the four estate pipeline rings, the estate flow, the maturity card with quick wins, top findings and a contents card per family), the data flow, insights, every section with charts and table filters, and an Assessment tab that switches between the maturity assessment and the findings. The maturity view states what the score is based on and that it covers the Sentinel workspace only. The findings view opens with a summary (by severity, by effect on the maturity score, by area, by category, and every scored finding ranked by its lift), where every legend entry, bar and row filters the list below; each finding shows what closing it does to the maturity score, and the list filters by severity, area, category and that effect. Each section links to its native page. | `SitePages/Dashboard.aspx`, set as the home page |
| **Section pages** | One modern page per Blueprint section (35 or so): the text as native text web parts, so it is searchable, printable and readable without JavaScript, and each chart as the iSOC Blueprint chart web part, which draws it from the chart's data. | `SitePages/sac-<NN>-<name>.aspx` |
| **Navigation** | The top navigation (mega menu): Dashboard, one heading per section family (Overview, Data sources, Operational health, Detection, Hunting & content, Automation, Workspace & data, Cost & access, Assessment, References) with its pages. Assessment holds the gap analysis, the maturity assessment and the findings list. | Top navigation bar |
| **Findings list** | Every gap-analysis finding, with severity, category, evidence, remediation and Learn link, plus history: `FirstSeen`, `LastSeen`, `Status` (Open, Resolved, Retired) and `ResolvedOn`. Finding links on the pages open the list filtered to that finding. An item still filed under a retired `SENT-NNN` id is recognised through the rule's `legacyId` and updated in place under its `SAC-<AREA>-NN` id, so history carries over the rename. | `Lists/SentinelFindings` |
| **Assets** | The dashboard HTML and data, the publisher's state file and the maturity score history. | `BlueprintAssets` library |

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
| `New-iSOCBlueprintSite` ([`Build-SentinelDocsSite.ps1`](../../../Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1)) | Offline. Turns a Blueprint workspace folder into a site bundle in `<workspace>/sharepoint/`. |
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

Nothing in the build contacts SharePoint or Azure, so you can inspect a
bundle before anything is published. The one network call is the optional
"What's new" feed for the dashboard; `-SkipWhatsNew` turns it off.

### Dashboard panels

The dashboard reads one embedded JSON model. Beyond the workspace headline,
counts, cost, findings, MITRE coverage and the billing flow, the model
carries the health-check views the Blueprint computes:

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

Every list on the dashboard is complete. Panels show their first entries
(eight bars, eight table rows, twelve opportunity tables with three
templates each, six findings on the Overview, ten roadmap gaps) and a
"Show all N" control reveals the rest; nothing is folded into an "N more"
badge that cannot be opened. The model carries the full lists (every
effectiveness row, every uncovered table with every template that reads
it, every alerting rule, every extended-retention table, every roadmap
entry, every table by cost).

The Insights tab lays its cards out in bands of similar height (donut and
pie cards, bar-list cards, table cards), with the full-width panels
(MITRE matrix, content inventory, detection opportunities, what's new)
between them, so a long table never shares a row with a short donut.
Every card grid balances its rows (five cards become three and two,
never four and one) and a short last row widens to fill the band. The
Sankey sizes each column to its longest label and stacks the GB value
under the label when the two cannot share a line.

The Report tab shows every section from the section model. It draws the
section's own pie and xy (bar) charts from their data; the other chart
kinds appear on the section's SharePoint page, where the chart web part
draws them. A section with no chart of its own gets one drawn from a short
table, and only when a column clearly holds an amount (a count, cost,
volume or total); a table with no such column gets no chart. A link to
another section opens it in the Report tab, and a link to a finding opens
it in the findings view, or the gap analysis page when this run's
findings list does not hold it.

Following a link or a tab starts at the top of what it opens. On
SharePoint the web part grows its iframe to the dashboard's full height
and the SharePoint page does the scrolling, so the dashboard scrolls the
host page (with `scrollIntoView`) rather than its own window.

| Model key | Panel | Source captures |
| --- | --- | --- |
| `estate` | Overview: the four pipeline rings (tables still receiving data, active tables read by a rule, enabled rules that fired, incidents closed) and the estate flow (source families to ingestion, detection, alerts, incidents; red strands pool under "Not monitored") | `tables-with-data`, `rule-table-references`, `rules-fired`, `incidents-summary` |
| `maturity` | Overview: the maturity card (score, level band, target marker, the Sentinel-only scope) and quick wins. Assessment tab, maturity view: the basis and scope note, overall donut, one bar per area against the target, roadmap, NIST CSF 2.0 rollup, every criterion with status and evidence (filter and search), and the score history once two runs have published | `maturity.json` |
| `detectionOpportunities` | Insights: tables with data but no detection and the templates that would cover them (every table; the panel shows twelve with a Show all control, and each table lists every candidate template) | `rule-table-references`, `template-table-references`, `tables-with-data` |
| `effectiveness`, `incidentsByClassification` | Insights: rule effectiveness and incident outcomes | `rule-effectiveness`, `incidents-summary` |
| `usageDaily` | Insights: the daily ingestion trend | `workspace-usage-daily` |
| `playbookHealth` | Insights: runs and failures per playbook; playbooks whose run history could not be read are counted as unavailable, not as zero runs | `playbook-runs` |
| `dataLake`, `dataLakeEnrolled` | Overview: the "Data lake" glance tile. Insights: enrolment status, the tier distribution donut (Analytics only, Analytics + Lake mirror, Analytics + Lake extended, Lake only), the top tables by lake-only retention and the lake cost split; counted over the operational tables through `Private/Get-TableTierProfile.ps1`, the same helper page 88 uses | `sentinel-data-lake`, `workspace`, `workspace-tables`, `tables-with-data`, `cost-estimate` |
| `flowTables` | Data flow: every ingesting table with its family, plan label, GB and billed GB. The dashboard rebuilds the Sankey from this list: the default view keeps the nine largest tables and folds the rest into "Other"; clicking a source family (or its chip above the chart) shows every table in that family, clicking "Other" or the "Every table" chip shows them all | `cost-estimate`, `workspace-tables` |
| `flow` | Data flow: the billing-flow Sankey as built by the site (the default view; kept for bundles built before `flowTables` existed). Its "Plan and tier" column names the lake tier each table lands in (Analytics plan, Analytics + Lake mirror, Analytics + Lake extended, Data lake only, Basic plan, Auxiliary plan), so an enrolled workspace shows its lake rather than one Analytics box; lake nodes are drawn teal and the long-tail "Other" node fans out to every tier its tables use | `cost-estimate`, `workspace-tables`, `sentinel-data-lake`, `workspace` |
| `tiBySource`, `tiObjects` | Insights: indicators per feed | `threat-intel-counts`, `threat-intel-objects` |
| `familyOrder`, `sections[].headline` | Overview: the contents cards, one per family, each page linking to its native page | the rendered sections |

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
Assessment tab's maturity view fetches it from beside its own page and draws the overall
score as a trend once two entries exist. Opened from disk, the fetch
cannot run and the trend panel stays hidden. Both files are readable by
anyone who can read the dashboard, which is the same audience. `-WhatIf`
reports what it would append and writes nothing.

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
`sharepoint/index.html` to preview the dashboard.

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
