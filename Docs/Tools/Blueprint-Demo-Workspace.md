# Blueprint Demo Workspace

[`Tools/New-BlueprintDemoWorkspace.ps1`](../../Tools/New-BlueprintDemoWorkspace.ps1)
writes a complete, synthetic iSOC Blueprint inventory for a large
fictitious workspace (sentinel-blog-uks-law, 2 TB a day), so the report and the
SharePoint dashboard can be developed, demonstrated and screenshotted
without a tenant. Nothing in it comes from a real workspace, so it is safe
to show and share; a live run's output never is.

It runs offline: it reads this repository and writes files, and calls no
Azure API.

## Running it

From the repository root:

```powershell
./Tools/New-BlueprintDemoWorkspace.ps1 -Build
```

That writes `SecurityDocs/sentinel-blog-uks-law/_raw` (git ignores
`SecurityDocs/`), renders the report beside it and builds the dashboard
bundle under `SecurityDocs/sentinel-blog-uks-law/sharepoint`. Serve that
folder to open the dashboard in a browser, so it can also read the
maturity history beside it:

```powershell
python3 -m http.server 8080 --directory SecurityDocs/sentinel-blog-uks-law/sharepoint
```

The command returns the workspace folder, its `_raw` folder, the bundle
(with `-Build`) and a summary of what it wrote.

| Parameter | Default | What it sets |
| --- | --- | --- |
| `-OutputPath` | `SecurityDocs/<WorkspaceName>` | The workspace folder; the inventory goes to its `_raw` |
| `-WorkspaceName` | `sentinel-blog-uks-law` | The demo workspace's name |
| `-DailyGb` | `2048` | Average GB a day over the last 30 days, every table included |
| `-LookbackDays` | `90` | Days of activity, 7 to 90; the daily series and the dashboard's date range cover the same days |
| `-AsOf` | now (UTC) | When the demo was "collected"; every date counts back from it |
| `-Seed` | `2048` | The random seed: the same seed, date and content give the same inventory |
| `-Build` | off | Render the report and build the bundle, and return the bundle's folder |

## What it holds

**The repository's content, deployed.** Every rule under
`Content/AnalyticalRules` is deployed as the deploy script would deploy
it. The Community rules become Content Hub templates, grouped into
solutions by the data they read; about half of those whose data the estate
has are deployed from their template, and the rest are the templates ready
to enable on the detection opportunities page. The Azure Storage solution
is left uninstalled, so its template shows as one whose solution is not
installed. Also deployed: the hunting queries, the Defender XDR custom
detections, the playbooks (each Logic App with its trigger and managed
identity), the workbooks, the watchlists (a quarter of them stale), the
automation rules (the repository's two, and three that run its
enrichment, notification and vulnerability playbooks), the summary rules,
the parser and the Sophos codeless connector.

**A large estate's data.** About 60 tables ingest `-DailyGb` a day: CEF
firewalls, Defender XDR streaming, Windows and Linux servers, Entra ID,
Microsoft Graph, Azure Firewall and diagnostics, AWS, Google Workspace and
the custom tables the content reads. Weekends are quieter where people
drive the volume, it grows about 6% across 90 days, a Syslog source runs at
debug level for five days, and a proxy feed stopped three weeks ago. Most
tables are on the Analytics plan; container logs are on Basic, a web proxy
on Auxiliary and raw NetFlow in the data lake only, and several tables keep
data in the lake for a year. One custom table has a schema and no data, and
one still uses the legacy HTTP Data Collector API.

**Cost on a commitment tier.** At this volume the workspace is on the
commitment tier nearest its billable Analytics-plan ingest (2,000 GB a day
by default, from `commitment-tiers.json`). The price list holds
illustrative UK South prices in GBP, with the Analytics-plan meters at
that tier's effective rate per GB, since the cost estimate prices by the
GB. Below about 80 GB a day of Analytics ingest it stays on pay-as-you-go.

**Activity that agrees with itself.** Each enabled rule fires at its own
rate (about a quarter never fire; a few are noisy; High-severity rules fire
less), and Defender for Endpoint, Office 365, Identity, Cloud Apps, Entra
ID Protection, Defender for Cloud and the custom detections raise their own
alerts, with a phishing wave in week three. Incidents are sampled one by
one from those alerts: open or closed, closed by an automation rule, an
analyst, Defender XDR or someone else, classified per rule, with
acknowledge and resolve times by severity. Every capture is aggregated from
the same samples, so the alert volumes, rules fired, rule effectiveness,
incident summary, MTTR, title statistics and the daily series behind the
dashboard's date range all agree. Playbooks run when automation rules call
them (the Teams notification playbook's connection expired five days ago;
a VirusTotal lookup is rate-limited now and then), health events cover
every rule run, connector fetch, automation run and playbook trigger, and
two rules fail.

**The engine's own steps.** The table references, the cost estimate, the
gap analysis (the gap checks run as they do after a collection) and the
maturity assessment run over the demo inventory, so the findings and the
score are what the Blueprint makes of it. With `-Build`, the bundle also
carries a quarter of runs about a week apart, the first 90 days back, so
the maturity trend and the Progress tab show: maturity scores climbing to
today's (each area at its own pace, one slipping), and progress records
with findings since fixed, fewer rules enabled, fewer criteria met, less
ATT&CK coverage and more tables no detection reads, plus one finding new
this week and one criterion that has become a gap. Every Progress baseline
(previous run, 7, 30 and 90 days, first run) has a run. On SharePoint
these histories come from the site.

**Shapes no content drives** (subscription, locks, linked services, data
exports, SOC optimisation, threat intelligence metrics and What's new)
come from the test fixture under `Tests/iSOCBlueprint/Fixtures/sample/_raw`,
with the demo's names in place of the fixture's.

## Keeping it in step

The demo reads the content as it is, so a new rule, hunting query or
playbook appears in it on the next run. When the collector gains a
capture, add it to the generator: the test suite
([`Tests/iSOCBlueprint/Demo-Workspace.Tests.ps1`](../../Tests/iSOCBlueprint/Demo-Workspace.Tests.ps1))
fails until every file the collector writes is in the demo. It also checks
the volume, the deployed content, the commitment tier, that the daily
series agree with the captures, that the same seed gives the same data,
that no fixture name is left, and that the bundle carries its date-range series
and maturity trend.

## Related

- [Sentinel-SharePoint-Site.md](../Modules/iSOCBlueprint/Sentinel-SharePoint-Site.md): the dashboard the demo feeds
- [Sentinel-Blueprint.md](../Modules/iSOCBlueprint/Sentinel-Blueprint.md): the collector whose output the demo imitates
- [Blueprint-References.md](../Modules/iSOCBlueprint/Blueprint-References.md): every capture and the window it reads
