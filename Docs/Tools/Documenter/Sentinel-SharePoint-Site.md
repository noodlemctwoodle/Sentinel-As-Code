# Sentinel SharePoint Site

Generates and publishes an **iSOC Blueprint** SharePoint Online site for one
Sentinel workspace from the Sentinel Documenter's output. Every page, the
navigation, the findings list and the dashboard home page are generated; a
pipeline keeps the site in step with every Documenter run.

> Companion pages: [Sentinel Documenter](Sentinel-Documenter.md) produces the
> snapshot and Markdown this site is built from.
> [SharePoint Publish pipeline](../../Pipelines/SharePoint-Publish.md) covers
> the CI/CD wiring, identity and secrets.

## What gets generated

One communication site per workspace, containing:

| Part | What it is | Where |
| --- | --- | --- |
| **Dashboard** (home page) | The interactive dashboard: an executive overview (glance tiles, posture cards, the four estate pipeline rings, the estate flow, the maturity card with quick wins, the billing flow, top findings and a contents card per family), the data flow, insights, a Maturity tab, every section with charts and table filters, and findings. Each section links to its native page. | `SitePages/Dashboard.aspx`, set as the home page |
| **Section pages** | One modern page per Documenter section (39 or so), as native text and image web parts, so they are searchable, printable and readable without JavaScript. | `SitePages/sac-<NN>-<name>.aspx` |
| **Navigation** | The top navigation (mega menu): Dashboard, one heading per section family (Overview, Data sources, Operational health, Detection, Hunting & content, Automation, Workspace & data, Cost & access, Maturity, Findings & references) with its pages, and Findings. | Top navigation bar |
| **Findings list** | Every gap-analysis finding, with severity, category, evidence, remediation and Learn link, plus history: `FirstSeen`, `LastSeen`, `Status` (Open, Resolved, Retired) and `ResolvedOn`. Finding links on the pages open the list filtered to that finding. | `Lists/SentinelFindings` |
| **Assets** | The dashboard HTML and data, the pre-rendered diagrams, the publisher's state file and the maturity score history. | `DocumenterAssets` library |

The generator owns all of the above. Manual edits to generated pages or the
top navigation are overwritten on the next run that changes them.

### Finding history

A finding that stops firing is not deleted. The Documenter's gap engine now
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

All under [`Tools/Documenter/SharePoint/`](../../../Tools/Documenter/SharePoint):

| File | Job |
| --- | --- |
| [`Build-SentinelDocsSite.ps1`](../../../Tools/Documenter/SharePoint/Build-SentinelDocsSite.ps1) | Offline. Turns a Documenter workspace folder into a site bundle in `<workspace>/sharepoint/`. |
| [`Publish-SentinelDocsSite.ps1`](../../../Tools/Documenter/SharePoint/Publish-SentinelDocsSite.ps1) | Makes a site match a bundle. Idempotent; `-WhatIf` reads and plans only. |
| [`Initialize-SentinelDocsSite.ps1`](../../../Tools/Documenter/SharePoint/Initialize-SentinelDocsSite.ps1) | One-time admin bootstrap of the site and the publisher's access. |
| [`templates/sharepoint-dashboard.html`](../../../Tools/Documenter/SharePoint/templates/sharepoint-dashboard.html) | The dashboard template the build fills in. |
| [`webpart/sentinel-navigator/`](../../../Tools/Documenter/SharePoint/webpart/sentinel-navigator) | The SPFx web part that hosts the dashboard on the home page. See its [README](../../../Tools/Documenter/SharePoint/webpart/sentinel-navigator/README.md). |
| `Private/` | Section families, Markdown-to-page conversion, the sync planners and the PnP wrappers. |

### The bundle

`Build-SentinelDocsSite.ps1 -Source <workspace>` writes:

| File | Contents |
| --- | --- |
| `index.html` | The self-contained dashboard (inline CSS and JS, data embedded as JSON with HTML-safe escaping) |
| `model.json` | The dashboard's data model |
| `site.json` | Product name, workspace, section list with page names, families and content hashes, diagrams, build warnings |
| `pages/<page>.json` | Per section: title and ordered segments (HTML for text web parts, image references for image web parts) |
| `diagrams/*.png` | The pre-rendered diagrams the pages use |
| `findings.json` | Findings plus per-check outcomes |

Nothing in the build contacts SharePoint or Azure, so you can inspect a
bundle before anything is published. The one network call is the optional
"What's new" feed for the dashboard; `-SkipWhatsNew` turns it off.

### Dashboard panels

The dashboard reads one embedded JSON model. Beyond the workspace headline,
counts, cost, findings, MITRE coverage and the billing flow, the model
carries the health-check views the Documenter computes:

| Model key | Panel | Source captures |
| --- | --- | --- |
| `estate` | Overview: the four pipeline rings (tables still receiving data, active tables read by a rule, enabled rules that fired, incidents closed) and the estate flow (source families to ingestion, detection, alerts, incidents; red strands pool under "Not monitored") | `tables-with-data`, `rule-table-references`, `rules-fired`, `incidents-summary` |
| `maturity` | Overview: the maturity card (score, level band, target marker) and quick wins. Maturity tab: overall donut, one bar per area against the target, roadmap, NIST CSF 2.0 rollup, every criterion with status and evidence (filter and search), and the score history once two runs have published | `maturity.json` |
| `detectionOpportunities` | Insights: tables with data but no detection and the templates that would cover them (top 12; the page has the full list) | `rule-table-references`, `template-table-references`, `tables-with-data` |
| `effectiveness`, `incidentsByClassification` | Insights: rule effectiveness and incident outcomes | `rule-effectiveness`, `incidents-summary` |
| `usageDaily` | Insights: the daily ingestion trend | `workspace-usage-daily` |
| `playbookHealth` | Insights: runs and failures per playbook | `playbook-runs` |
| `tiBySource`, `tiObjects` | Insights: indicators per feed | `threat-intel-counts`, `threat-intel-objects` |
| `familyOrder`, `sections[].headline` | Overview: the contents cards, one per family, each page linking to its native page | the rendered sections |

Every panel has an empty state: a snapshot without a capture shows "not
available" or "not assessed" rather than a zero dressed up as a result.
The source families used by the estate flow come from
`Tools/Documenter/Private/Get-TableFamily.ps1`, which the Markdown renderer
also uses, so the Markdown pack and the dashboard agree.

Run [`Convert-MermaidToImage.ps1`](../../../Tools/Documenter/Convert-MermaidToImage.ps1)
against the snapshot before building. Any diagram that was not pre-rendered
shows on its page as a "diagram not rendered" note, and the build warns.

### How a section becomes a page

The Markdown is converted with PowerShell's built-in `ConvertFrom-Markdown`,
then cut down to what a SharePoint text web part keeps:

- The H1 becomes the page title; the metadata banner under it is dropped.
- Headings are clamped to h2 to h4, and ids, classes and anchor stubs are
  removed.
- Tables use the SharePoint editor's responsive table markup and are capped
  at 500 rows (`-MaxTableRows`), with a note pointing at the Markdown output.
- Links to other sections go to their page. `SENT-NNN` links go to the
  findings list filtered on that id. Repository-relative links become plain
  text.
- The content is split into one text web part per H2, with an image web part
  wherever a diagram sits.

### What a publish does

In this order, so a failure part-way leaves the site consistent:

1. **Structure.** Ensure the `DocumenterAssets` library and the
   `Sentinel Findings` list and columns exist.
2. **App.** Deploy the web part package to the site collection app catalog,
   only when its version differs from the deployed one.
3. **Assets.** Upload the dashboard and any new diagrams. When the bundle
   carries a maturity assessment, append its score to the history (see
   below).
4. **Pages.** Create or rebuild each section page, skipping pages whose
   content hash matches the last publish. Pages are rebuilt in place (cleared
   and refilled, then published once), so URLs and version history survive
   and a failed publish leaves the last good version live.
5. **Dashboard.** Point the home page's web part at the uploaded dashboard,
   publish, and set it as the home page.
6. **Findings.** Add, update, reopen, resolve and retire list items in one
   batch.
7. **Navigation.** Rebuild the top navigation from the pages that exist,
   only when it differs from the plan.
8. **Prune.** Send pages and diagrams the bundle no longer has to the recycle
   bin, only when every page published.

A failed section page is reported and retried on the next run; it never
stops the rest of the publish.

### Maturity history

Every publish of a bundle that carries a maturity assessment appends one
entry to `DocumenterAssets/_state/maturity-history.json`:

```json
{ "entries": [ { "publishedUtc": "2026-10-09T06:12:00Z", "bundleBuiltUtc": "2026-10-09 06:05 UTC",
                 "targetLevel": 3, "overall": { "score": 1.49, "level": 1 },
                 "areas": [ { "id": "DET", "score": 1.11 }, ... ] } ] }
```

The entry is keyed on the bundle's build time, so publishing the same
bundle twice does not add a point, and the file is capped at 180 entries
(`Add-SacMaturityHistoryEntry -MaxEntries`). A copy is written next to the
dashboard (`DocumenterAssets/dashboard/maturity-history.json`); the
Maturity tab fetches it from beside its own page and draws the overall
score as a trend once two entries exist. Opened from disk, the fetch
cannot run and the trend panel stays hidden. Both files are readable by
anyone who can read the dashboard, which is the same audience. `-WhatIf`
reports what it would append and writes nothing.

## Setting it up

### 1. App registrations

| App | Used by | Needs |
| --- | --- | --- |
| **Publisher** | The pipelines | SharePoint application permission `Sites.Selected` (admin consent). A federated credential per pipeline (see the [pipeline page](../../Pipelines/SharePoint-Publish.md)). No secrets, no Azure roles. |
| **Your PnP sign-in app** | You, for the bootstrap and local runs | Delegated SharePoint `AllSites.FullControl` and Microsoft Graph `Sites.FullControl.All` (to grant the publisher access), with admin consent. |

### 2. Bootstrap the site (once, as a SharePoint administrator)

```powershell
./Tools/Documenter/SharePoint/Initialize-SentinelDocsSite.ps1 `
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

Set the site URL for the workspace (`sharePointSiteUrl` in ADO,
`SHAREPOINT_SITE_URL` on GitHub) and run the pipeline with **What-if**
ticked first. See [SharePoint Publish pipeline](../../Pipelines/SharePoint-Publish.md).

## Running it locally

From the repository root, against a downloaded Documenter artefact:

```powershell
# Diagrams (needs Node and @mermaid-js/mermaid-cli)
./Tools/Documenter/Convert-MermaidToImage.ps1 -Root ./artefact -Format png

# Build the bundle into ./artefact/law-sentinel-prod/sharepoint
./Tools/Documenter/SharePoint/Build-SentinelDocsSite.ps1 -Source ./artefact/law-sentinel-prod

# Preview the publish, signed in as you
./Tools/Documenter/SharePoint/Publish-SentinelDocsSite.ps1 `
    -SiteUrl 'https://contoso.sharepoint.com/sites/isoc-law-sentinel-prod' `
    -Bundle  ./artefact/law-sentinel-prod/sharepoint `
    -Interactive -ClientId '<your-pnp-app-id>' -Tenant 'contoso.onmicrosoft.com' -WhatIf
```

The publisher needs PowerShell 7.4 and PnP.PowerShell 3.4.1. To build the
web part package yourself, see its
[README](../../../Tools/Documenter/SharePoint/webpart/sentinel-navigator/README.md).

## Privacy

The site holds tenant configuration: workspace and subscription IDs, cost,
findings, role assignments and every section of the documentation. Its
membership is the privacy boundary, the same way a private repository is for
the Markdown.

- Keep the Visitors and Members groups to the people who should read it.
  The bootstrap leaves Visitors empty.
- The dashboard runs its script inside the home page (same origin), so
  whoever can write to the `DocumenterAssets` library can run script for
  everyone who opens the site. Keep write access to the publisher identity
  and site owners.
- The publisher's identity can reach this one site and nothing else in the
  tenant, and has no Azure access.

## What this is not

- **Not live.** The site shows the last published snapshot, normally the
  Documenter's 06:00 run.
- **Not a place to edit.** Generated pages and the top navigation are
  overwritten. Add your own pages without the `sac-` prefix and they are
  left alone, but they will not appear in the generated navigation.
- **Not multi-workspace in one site.** One site per workspace, each with its
  own pipeline variables.

## Related

- [Sentinel Documenter](Sentinel-Documenter.md): the collector and renderer.
- [SharePoint Publish pipeline](../../Pipelines/SharePoint-Publish.md): CI/CD wiring, identity, secrets.
- [Sentinel Word Report](Sentinel-Word-Report.md): the same Markdown as a `.docx`.
