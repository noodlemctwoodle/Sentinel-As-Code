# Spark Notebooks

Reference documentation for every notebook in the Spark Notebooks kit - a set of Jupyter / PySpark notebooks for the Microsoft Sentinel **data lake** advanced-analytics capability (F16). Each entry lists the technique, the tables it reads, the visual it produces, and why it belongs in a notebook rather than KQL. The **threat hunting running order** (hunt hypotheses, ATT&CK mapping and the 15-minute "wow" cut) is at the end of this document.

Source notebooks and the kit quick-start live under [`Content/SparkNotebooks/`](../../Content/SparkNotebooks) ([README](../../Content/SparkNotebooks/README.md)). This catalogue is generated from the notebooks themselves.

> Set the workspace name once in the git-ignored `.env` (for the **Zava** tenant, run `data_provider.list_databases()`), then `python3 apply_config.py apply`. See the [Configuration](#configuration-apply_configpy) section below for the config workflow.

## Quick index

| # | Notebook | Pool | Visual | Tables |
| --- | --- | --- | --- | --- |
| 1 | `demo01_lake_exploration.ipynb` | Small | - | SigninLogs |
| 2 | `demo02_identity_anomaly_detection.ipynb` | Medium | - | SigninLogs, AADNonInteractiveUserSignInLogs |
| 3 | `demo03_network_beacon_detection.ipynb` | Medium | - | DeviceNetworkEvents |
| 4 | `demo04_scheduled_job_enrichment.ipynb` | Medium | - | SigninLogs, AADNonInteractiveUserSignInLogs |
| 5 | `demo05_signin_activity_heatmap.ipynb` | Small | 2-D heatmap | SigninLogs |
| 6 | `demo06_ueba_peer_clustering.ipynb` | Medium | 2-D PCA cluster scatter | SigninLogs |
| 7 | `demo07_impossible_travel.ipynb` | Medium | speed bars + timeline | SigninLogs |
| 8 | `demo08_signin_volume_forecast.ipynb` | Small | actual vs forecast | SigninLogs |
| 9 | `demo09_lateral_movement_graph.ipynb` | Medium | directed network graph | DeviceLogonEvents |
| 10 | `demo10_commandline_entropy.ipynb` | Medium | entropy histogram + bar | DeviceProcessEvents |
| 11 | `demo11_cross_signal_correlation.ipynb` | Medium | correlation clustermap | DeviceProcessEvents, DeviceNetworkEvents, DeviceLogonEvents |
| 12 | `demo12_failed_logon_zscore.ipynb` | Small | time series with control bands | SigninLogs |
| 13 | `demo13_retrohunt_ioc_sweep.ipynb` | Medium | IOC activity gantt (first-seen -> last-seen) | DeviceProcessEvents, DeviceNetworkEvents, DeviceFileEvents |
| 14 | `demo14_stack_counting_lfo.ipynb` | Medium | long-tail frequency curve + rarest-pairs table | DeviceProcessEvents |
| 15 | `demo15_first_seen_hunt.ipynb` | Medium | new-entity activity bar + first-appearance timeline | DeviceNetworkEvents |
| 16 | `demo16_lolbin_hunt.ipynb` | Medium | LOLBin usage bars + suspicious-execution timeline | DeviceProcessEvents |
| 17 | `demo17_entity_investigation_timeline.ipynb` | Medium | multi-source swimlane timeline | DeviceProcessEvents, DeviceNetworkEvents, DeviceFileEvents, DeviceLogonEvents |
| 18 | `demo18_mitre_attack_coverage.ipynb` | Small | tactic x technique coverage heatmap | DeviceProcessEvents |

## Configuration (`apply_config.py`)

The only tenant-specific value the notebooks need is the **workspace name** (the Log Analytics workspace onboarded to the Sentinel data lake). It lives in one git-ignored file (`.env`) and is stamped into the notebooks by `apply_config.py`. Run the commands below from the `Content/SparkNotebooks` folder.

### Why a script (and not a runtime `.env` read)

The Microsoft Sentinel notebook **kernel runs on a cloud Spark pool**, so a notebook cell
cannot read a local `.env` at run time (`open(".env")` would look on the pool, where the file
doesn't exist), and you can't `pip install python-dotenv` (the runtime is locked to Synapse
Spark 3.4 libraries). So instead of reading config at run time, we **stamp** the workspace
name into the notebooks locally before you run them, and **restore the placeholder** before
you commit - so the real name is never checked in. This mirrors the repo's existing
`.env` / `.env.example` convention.

### Files

| File | Committed? | Purpose |
| --- | --- | --- |
| `.env.example` | yes | Template. Copy it to `.env`. |
| `.env` | **no** (git-ignored) | Your real values. Holds `SENTINEL_WORKSPACE_NAME`. |
| `apply_config.py` | yes | Stamps / restores / checks the workspace name across `demos/*.ipynb`. |

`.env` is ignored by the repo-root `.gitignore` (`.env` / `.env.*` rules), so it can safely
hold the real workspace name. The committed notebooks always carry the placeholder
`your-workspace-name`.

### One-time setup

```bash
cd Content/SparkNotebooks
cp .env.example .env
# edit .env:  SENTINEL_WORKSPACE_NAME=<your data lake workspace>
```

Get the exact workspace name by running this in any notebook (Zava tenant included):

```python
data_provider.list_databases()
```

### Commands

Run from the `Content/SparkNotebooks` folder.

| Command | What it does | When |
| --- | --- | --- |
| `python3 apply_config.py apply` | Replaces `your-workspace-name` → your `.env` value in every `demos/*.ipynb`. | **Before** you run the notebooks. |
| `python3 apply_config.py reset` | Replaces your value → `your-workspace-name` again. | **Before** you commit / push. |
| `python3 apply_config.py check` | Exits **1** if any notebook still contains the real workspace name. | CI / pre-commit guard. |
| `python3 apply_config.py status` | Prints the `.env` value and whether each notebook is `placeholder` or `populated`. | Any time, to see current state. |

### Typical workflow

```bash
# 1. inject your workspace name, then open the notebooks in VS Code and run them
python3 apply_config.py apply

# 2. when you're done, before committing:
python3 apply_config.py reset
python3 apply_config.py check   # should print OK and exit 0
git add demos/ .env.example apply_config.py README.md
git commit -m "docs(sparknotebooks): ..."
```

### Example output

```text
$ python3 apply_config.py status
.env SENTINEL_WORKSPACE_NAME = contoso-sec-law
  demos/demo01_lake_exploration.ipynb            placeholder
  demos/demo02_identity_anomaly_detection.ipynb  placeholder
  ...

$ python3 apply_config.py apply
Injecting workspace 'contoso-sec-law' into 18 notebook(s)...
  updated demos/demo01_lake_exploration.ipynb (1 occurrence(s))
  ...
Done. 18 notebook(s) updated. Remember: run 'reset' before you commit.

$ python3 apply_config.py check
check: FAIL - real workspace name found in:
  - demos/demo01_lake_exploration.ipynb
  ...
Run 'python3 apply_config.py reset' before committing.
```

### Optional: block accidental commits with a pre-commit hook

Add `.git/hooks/pre-commit` (make it executable with `chmod +x`):

```bash
#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel)/Content/SparkNotebooks" || exit 0
python3 apply_config.py check || {
  echo "Refusing to commit: run 'python3 apply_config.py reset' first."; exit 1;
}
```

### How it works

- `apply` / `reset` do a literal text replace of the token `your-workspace-name` across each
  `demos/*.ipynb`, so the notebook JSON stays valid.
- `check` reads `SENTINEL_WORKSPACE_NAME` from `.env`; if it's unset or still the placeholder,
  nothing could leak and it passes.
- New notebooks are picked up automatically - the script globs `demos/*.ipynb`, so all 18 (and
  any you add) are managed with no changes to the script.

### Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `ERROR: SENTINEL_WORKSPACE_NAME not set` | You ran `apply`/`reset` before creating `.env`. `cp .env.example .env` and set the value. |
| `apply` says "still the placeholder; nothing to inject" | `.env` still has `your-workspace-name`. Put your real workspace name in `.env`. |
| Notebook shows the placeholder when you run it | You didn't run `apply`, or you ran `reset`. Run `apply` again. |
| A cell errors trying to read `.env` at run time | Don't - the cloud kernel can't see local files. Use `apply` to stamp the value instead. |
| `check` fails in CI | A real workspace name is committed. Run `reset`, re-commit. |

### Notes

- The workspace name is not a secret, but keeping it out of git avoids leaking tenant details
  and keeps the notebooks portable across tenants - just change the
  one value in `.env` and re-run `apply`.
- Notebook tunables (lookback windows, thresholds) live in each notebook's config cell as safe
  defaults; only the workspace name is centralised here.

## Foundation and job notebooks

### demo01 - Lake exploration

- **File:** `demos/demo01_lake_exploration.ipynb`
- **Purpose:** **Workshop:** F16 Advanced analytics (notebooks / ML) - Microsoft Sentinel data lake
- **Tables:** `SigninLogs`
- **Key libraries:** pandas, matplotlib
- **Visual:** -
- **Parameterised:** no
- **Writes table:** - (read-only / in-notebook viz)
- **Pool:** Small

### demo02 - Identity ML anomaly detection (hero lab)

- **File:** `demos/demo02_identity_anomaly_detection.ipynb`
- **Purpose:** A KQL rule uses a fixed threshold ("> 100 failures"). Here we do what KQL **cannot**: build a behavioural **feature vector per user** from history, then use an **Isolation Forest** to rank users behaving unlike themselves and unlike their peers - the model learns the baseline.
- **Tables:** `SigninLogs`, `AADNonInteractiveUserSignInLogs`
- **Key libraries:** scikit-learn
- **Visual:** -
- **Parameterised:** no
- **Writes table:** `IdentityAnomalies_SPRK`
- **Pool:** Medium

### demo03 - Network beacon & lateral-movement detection

- **File:** `demos/demo03_network_beacon_detection.ipynb`
- **Purpose:** Two analytics that are natural in Spark and awkward in KQL: - **Part A - Beaconing:** regular, low-volume outbound connections over long windows (a C2 signature). The tell is *regularity over time* - a statistical property, not a filter. - **Part B - Lateral movement:** unusual internal-to-internal fan-out (e.g. SMB/RDP).
- **Tables:** `DeviceNetworkEvents`
- **Key libraries:** pandas, matplotlib
- **Visual:** -
- **Parameterised:** no
- **Writes table:** `NetworkBeacons_SPRK`
- **Pool:** Medium

### demo04 - Scheduled enrichment job (parameterised)

- **File:** `demos/demo04_scheduled_job_enrichment.ipynb`
- **Purpose:** This notebook is designed to run **as a scheduled job**. It reads sign-ins over a lookback window, scores users by failed-sign-in pressure, and writes a compact **enrichment table** - satisfying the F16 Definition of Done: *"a notebook-based analytic runs on a schedule over lake data and produces a usable detection or enrichment output, with cost monitored."*
- **Tables:** `SigninLogs`, `AADNonInteractiveUserSignInLogs`
- **Key libraries:** pandas, matplotlib
- **Visual:** -
- **Parameterised:** yes (Parameters cell - can run as a job)
- **Writes table:** `SigninAnomalyEnrichment_SPRK`, `SigninAnomalyEnrichment_SPRK_CL`
- **Pool:** Medium

## Visual demos - fast, graph-heavy, "why notebooks beat KQL"

### demo05 - Sign-in activity heatmap (hour x weekday)

- **File:** `demos/demo05_signin_activity_heatmap.ipynb`
- **Purpose:** One picture of *when* your organisation signs in - and where the off-hours outliers are. KQL can bucket by hour, but it cannot **render a 2-D heatmap**; you would export to another tool. Here it's three lines of Spark and one Seaborn call.
- **Tables:** `SigninLogs`
- **Key libraries:** seaborn
- **Visual:** 2-D heatmap
- **Parameterised:** no
- **Writes table:** - (read-only / in-notebook viz)
- **Pool:** Small
- **Why a notebook, not KQL:** KQL renders tables, not heatmaps. Spotting the working-hours block and the lone 3 a.m. Saturday cell is instant visually, and near-impossible to eyeball in a KQL grid.

### demo06 - Peer-group anomaly detection (UEBA) with clustering

- **File:** `demos/demo06_ueba_peer_clustering.ipynb`
- **Purpose:** Group users by behaviour with **K-Means**, project to 2-D with **PCA**, and spotlight the accounts that sit apart from every peer group. Unsupervised clustering and dimensionality reduction simply do not exist in KQL.
- **Tables:** `SigninLogs`
- **Key libraries:** scikit-learn
- **Visual:** 2-D PCA cluster scatter
- **Parameterised:** no
- **Writes table:** - (read-only / in-notebook viz)
- **Pool:** Medium
- **Why a notebook, not KQL:** K-Means, StandardScaler and PCA are core data-science, not query operators. KQL can't cluster entities or reduce five features to a 2-D map - so it can't answer *'who behaves unlike their peers?'* the way this does.

### demo07 - Impossible travel (geodesic speed between sign-ins)

- **File:** `demos/demo07_impossible_travel.ipynb`
- **Purpose:** Compute the real **great-circle distance** and implied **travel speed** between each user's consecutive sign-ins with `geopy`, and flag anything faster than a jet. Row-to-row window maths plus true geodesic distance is exactly what KQL is bad at - here it's natural.
- **Tables:** `SigninLogs`
- **Key libraries:** geopy (falls back to a built-in haversine if the pool doesn't have it)
- **Visual:** speed bars + timeline
- **Parameterised:** no
- **Writes table:** - (read-only / in-notebook viz)
- **Pool:** Medium
- **Why a notebook, not KQL:** This needs `lag()` across ordered rows AND a geodesic (Haversine) distance between lat/long pairs, then a speed calc. In KQL that's contortion; with `geopy` + pandas it's a few readable lines - and you get a chart for free.

### demo08 - Sign-in volume forecast with anomaly band

- **File:** `demos/demo08_signin_volume_forecast.ipynb`
- **Purpose:** Fit a **Holt-Winters** model (trend + weekly seasonality) with `statsmodels`, forecast the next week, and shade a confidence band so today's spike is obviously in- or out-of-range. KQL has a fixed forecast function; here you own the model, the seasonality and the visual.
- **Tables:** `SigninLogs`
- **Key libraries:** statsmodels
- **Visual:** actual vs forecast
- **Parameterised:** no
- **Writes table:** - (read-only / in-notebook viz)
- **Pool:** Small
- **Why a notebook, not KQL:** Holt-Winters exponential smoothing with additive trend and 7-day seasonality is a statistical model, not a query. You can tune it, extract residuals, and plot a band - control KQL's single built-in forecast verb doesn't give you.

### demo09 - Lateral movement graph

- **File:** `demos/demo09_lateral_movement_graph.ipynb`
- **Purpose:** Turn remote logons into a **graph**, size nodes by **degree centrality**, and draw the device-to-device movement map. Highlighting hub devices that fan out across the estate is a graph problem - KQL has no graph construction, centrality, or rendering.
- **Tables:** `DeviceLogonEvents`
- **Key libraries:** networkx
- **Visual:** directed network graph
- **Parameterised:** no
- **Writes table:** - (read-only / in-notebook viz)
- **Pool:** Medium
- **Why a notebook, not KQL:** Building a directed graph, computing degree centrality, and laying it out visually are native to `networkx`. KQL can list edges as rows but can't traverse, score centrality, or draw the pivot map that makes lateral movement obvious.

### demo10 - Command-line entropy (obfuscation hunting)

- **File:** `demos/demo10_commandline_entropy.ipynb`
- **Purpose:** Encoded/obfuscated commands have high **Shannon entropy**. Compute it per command line and combine with rarity to surface the weird ones. Entropy is an information-theory calculation - there is no KQL function for it.
- **Tables:** `DeviceProcessEvents`
- **Key libraries:** pandas, matplotlib
- **Visual:** entropy histogram + bar
- **Parameterised:** no
- **Writes table:** - (read-only / in-notebook viz)
- **Pool:** Medium
- **Why a notebook, not KQL:** Shannon entropy is `-sum(p*log2 p)` over the character distribution - an information-theory metric with no KQL equivalent. Notebooks let you define arbitrary maths per row and rank on it.

### demo11 - Cross-signal correlation heatmap

- **File:** `demos/demo11_cross_signal_correlation.ipynb`
- **Purpose:** Join **three** telemetry sources into one per-device feature matrix, then show how the signals correlate. Multi-table feature assembly plus a correlation matrix and clustered heatmap is heavy going in KQL; here it's a couple of joins and one Seaborn call.
- **Tables:** `DeviceProcessEvents`, `DeviceNetworkEvents`, `DeviceLogonEvents`
- **Key libraries:** seaborn
- **Visual:** correlation clustermap
- **Parameterised:** no
- **Writes table:** - (read-only / in-notebook viz)
- **Pool:** Medium
- **Why a notebook, not KQL:** Assembling a per-entity feature matrix from three tables, correlating every pair, and clustering the result into a heatmap is a pandas/Seaborn one-liner. In KQL you'd hand-write each pairwise correlation and still have no clustered visual.

### demo12 - Failed-logon spike detection (rolling z-score)

- **File:** `demos/demo12_failed_logon_zscore.ipynb`
- **Purpose:** Build an hourly failed-sign-in series, compute a **rolling mean and standard deviation**, and flag hours whose **z-score** breaches 3 sigma. Proper statistical process control with a plotted band - richer and clearer than a static KQL threshold.
- **Tables:** `SigninLogs`
- **Key libraries:** pandas, matplotlib
- **Visual:** time series with control bands
- **Parameterised:** no
- **Writes table:** - (read-only / in-notebook viz)
- **Pool:** Small
- **Why a notebook, not KQL:** A rolling z-score adapts the threshold to the recent baseline instead of a fixed number, so it catches relative spikes and ignores steady noise. Expressing rolling windows, sigma bands and the plot is trivial in pandas/matplotlib and clumsy in KQL.

## Threat hunting demos

### demo13 - Retro-hunt: sweep IOCs across full lake history (HERO)

- **File:** `demos/demo13_retrohunt_ioc_sweep.ipynb`
- **Purpose:** **The data-lake hunting superpower.** A fresh threat report drops with a list of IOCs. In the analytics tier you can only look back ~90 days affordably. The **data lake holds up to 12 years** cheaply - so you sweep every hash, IP and domain across *all* of history in one pass and get first-seen / last-seen for each.
- **Tables:** `DeviceProcessEvents`, `DeviceNetworkEvents`, `DeviceFileEvents`
- **Key libraries:** pandas, matplotlib
- **Visual:** IOC activity gantt (first-seen -> last-seen)
- **Parameterised:** yes (Parameters cell - can run as a job)
- **Writes table:** - (read-only / in-notebook viz)
- **Pool:** Medium
- **Why a notebook, not KQL:** Retro-hunting a full IOC set across **years** of telemetry is the lake's signature move. The analytics tier is cost-bound to a short window; here you point one notebook at all history, get first/last-seen per indicator, and visualise the campaign timeline.

### demo14 - Stack counting (least-frequency-of-occurrence)

- **File:** `demos/demo14_stack_counting_lfo.ipynb`
- **Purpose:** The oldest trick in hunting: **stack** a field and read the **long tail**. Rare parent->child process relationships are where the evil hides. Here we stack `parent -> child` across the estate and surface the rarest launches.
- **Tables:** `DeviceProcessEvents`
- **Key libraries:** pandas, matplotlib
- **Visual:** long-tail frequency curve + rarest-pairs table
- **Parameterised:** no
- **Writes table:** - (read-only / in-notebook viz)
- **Pool:** Medium
- **Why a notebook, not KQL:** Stack counting is a *distribution* hunt: sort by rarity and read the tail. Pandas makes the whole distribution explorable and plottable in one shot; in KQL you'd `summarize count()` and squint at rows without the long-tail curve that guides the eye.

### demo15 - First-seen hunt: what's NEW versus a long baseline

- **File:** `demos/demo15_first_seen_hunt.ipynb`
- **Purpose:** Hypothesis: *attacker infrastructure and tooling appear for the first time.* Compare a long **baseline** window against a short **recent** window and surface domains/IPs that were **never seen before** - a hunt that leans directly on the lake's long retention.
- **Tables:** `DeviceNetworkEvents`
- **Key libraries:** pandas, matplotlib
- **Visual:** new-entity activity bar + first-appearance timeline
- **Parameterised:** no
- **Writes table:** - (read-only / in-notebook viz)
- **Pool:** Medium
- **Why a notebook, not KQL:** *'Never seen before'* is an anti-join between a long baseline and a recent window. The lake makes a 90-day (or multi-year) baseline affordable, and the left-anti join + novelty timeline is far cleaner here than nesting `not in` over huge KQL result sets.

### demo16 - Hypothesis hunt: living-off-the-land binary (LOLBin) abuse

- **File:** `demos/demo16_lolbin_hunt.ipynb`
- **Purpose:** Hypothesis: *adversaries abuse trusted Windows binaries to download and execute.* Hunt known LOLBins with suspicious argument patterns, score each execution, and rank.
- **Tables:** `DeviceProcessEvents`
- **Key libraries:** pandas, matplotlib
- **Visual:** LOLBin usage bars + suspicious-execution timeline
- **Parameterised:** no
- **Writes table:** - (read-only / in-notebook viz)
- **Pool:** Medium
- **Why a notebook, not KQL:** A hunt is a hypothesis plus scoring, not a static rule. Here we combine a curated LOLBin list with regex arg-scoring and rank the results - easy to iterate cell-by-cell as the hypothesis evolves, with the timeline updating alongside.

### demo17 - Entity investigation timeline (one notebook = the whole picture)

- **File:** `demos/demo17_entity_investigation_timeline.ipynb`
- **Purpose:** Pick a device (or user) and reconstruct a **unified timeline** across processes, network, logons and files. One swimlane view of everything that entity did - the pivot hunters do constantly, assembled from many tables at once.
- **Tables:** `DeviceProcessEvents`, `DeviceNetworkEvents`, `DeviceFileEvents`, `DeviceLogonEvents`
- **Key libraries:** pandas, matplotlib
- **Visual:** multi-source swimlane timeline
- **Parameterised:** yes (Parameters cell - can run as a job)
- **Writes table:** - (read-only / in-notebook viz)
- **Pool:** Medium
- **Why a notebook, not KQL:** Investigation is inherently multi-table. A notebook unions processes, network, logons and files into one swimlane and keeps the pivot interactive. KQL can `union`, but the single annotated visual timeline - and the ability to keep drilling in-place - is the notebook advantage.

### demo18 - MITRE ATT&CK coverage of the hunt library

- **File:** `demos/demo18_mitre_attack_coverage.ipynb`
- **Purpose:** Map every hunt notebook to the ATT&CK techniques it exercises and render a **coverage heatmap** across tactics. Great for a hunt-program review: where are we strong, where are the gaps? Optionally weighted by live finding counts.
- **Tables:** `DeviceProcessEvents`
- **Key libraries:** seaborn
- **Visual:** tactic x technique coverage heatmap
- **Parameterised:** no
- **Writes table:** - (read-only / in-notebook viz)
- **Pool:** Small
- **Why a notebook, not KQL:** Hunters live in ATT&CK. Building a coverage matrix from your hunt library and rendering it as a heatmap - then optionally weighting cells with live counts - is a pandas/Seaborn exercise. KQL has no way to turn your hunt catalogue into a coverage picture.

## Threat hunting running order

A hunt-team-facing guide to demoing these notebooks. The message is simple:

> **KQL answers a question. A notebook runs a hunt.** The lake keeps up to **12 years** of
> telemetry cheaply, and notebooks let you pivot, model, and visualise across all of it - the
> analytics tier can't hold that history affordably, and KQL can't cluster, graph, or compute
> entropy/geodesics.

Every notebook ends with a **"Why this is a notebook hunt, not a KQL query"** cell - use it as
the talk track.

### Suggested running order (hunt team, ~45-60 min)

Lead with the retro-hunt - it's the clearest "only the lake can do this" moment.

| Order | Notebook | Hunt hypothesis / question | KQL contrast | ATT&CK |
| --- | --- | --- | --- | --- |
| 1 (hero) | `demo13_retrohunt_ioc_sweep` | "A new report dropped - were these IOCs ever here?" | Analytics tier ~90d; lake sweeps **years** | T1071, T1204 |
| 2 | `demo14_stack_counting_lfo` | "Show me the rarest parent->child process launches" | Long-tail curve, not a row grid | T1059 |
| 3 | `demo15_first_seen_hunt` | "What infrastructure is brand-new vs a 90-day baseline?" | Left-anti join over long history | T1071 |
| 4 | `demo16_lolbin_hunt` | "Are trusted binaries being abused to download/exec?" | Hypothesis + scoring, iterated live | T1218, T1059 |
| 5 | `demo17_entity_investigation_timeline` | "Show me everything this host did, one view" | Multi-table swimlane, not `union` rows | T1057 |
| 6 | `demo18_mitre_attack_coverage` | "Where does our hunt library cover ATT&CK?" | Coverage heatmap from the catalogue | (meta) |

**Also strongly hunt-relevant** (from the visual set): `demo03` beaconing (C2 regularity),
`demo07` impossible travel (geodesic speed), `demo09` lateral-movement graph (centrality),
`demo10` command-line entropy (obfuscation).

### The 15-minute "wow" cut

If you only have 15 minutes with the hunt team:

1. **`demo13` retro-hunt** - sweep a fresh IOC set across full history (the lake's superpower).
2. **`demo14` stack counting** - the classic LFO hunt, with the long-tail curve.
3. **`demo09` lateral-movement graph** - a visual you simply cannot produce in KQL.

### Why notebooks change the hunt (say this)

- **Retro-hunting depth** - sweep IOCs / TTPs across **years**, not the analytics tier's short
  window. First-seen / last-seen per indicator in one pass.
- **Techniques KQL lacks** - clustering (UEBA), graph centrality (lateral movement), entropy
  (obfuscation), geodesic speed (impossible travel), forecasting/z-scores (volume anomalies).
- **The hunt is the artefact** - code + narrative + charts in one file. Re-run it next week,
  hand it to a teammate, or schedule it as a job so a manual hunt becomes a standing detection.
- **Pivot without re-querying** - pull the data once, then explore it cell by cell as the
  hypothesis evolves.

### From hunt -> standing detection

When a hunt proves out, promote it: write results to a custom table (`_SPRK` lake tier, or
`_SPRK_CL` analytics tier for KQL hunting) and schedule the notebook as a **job** (see
`demo04`). A one-off hunt becomes continuous coverage.

### Data prerequisites (confirm in Zava)

The hunting notebooks read: `DeviceProcessEvents`, `DeviceNetworkEvents`, `DeviceFileEvents`,
`DeviceLogonEvents`, `SigninLogs`. Run `data_provider.list_tables("<workspace>")` first and
swap table/column names if Zava's schema differs. `demo13` and `demo17` have **Parameters**
cells (IOC lists / entity name) - set them before you run.

Three SDK/schema gotchas that bite the demos:

- `list_tables()` returns **`TableInfo` objects**, not strings, and `TableInfo` defines no
  ordering - `sorted(tables)` raises `TypeError`. Sort on `t.name`. The
  [class reference](https://learn.microsoft.com/azure/sentinel/datalake/sentinel-provider-class-reference)
  still documents `list[str]`.
- Device tables in the Sentinel schema use **`TimeGenerated`**. The Defender advanced hunting
  column `Timestamp` does not exist here, so Microsoft's own beacon sample does not resolve
  against a Sentinel workspace.
- `save_as_table(df, name, ...)` with no database argument writes to the **`System tables`**
  database, not your workspace - that is the only lake-tier location supporting `overwrite`
  and `partitionBy`. Read it back with `read_table("<name>_SPRK")`, no workspace argument.
  Analytics-tier (`_SPRK_CL`) writes take the workspace as the third positional argument and
  are append-only.

### Facilitation notes

- Start each notebook's kernel first (3-6 min warm-up overlaps your setup talk).
- Keep windows small for live demos (defaults are 7-14 days); `demo13` intentionally runs over
  full history - narrate that that's the point, and keep the IOC list short so it's still fast.
- Pools: Small for `demo18`; Medium for the rest.
- Interactive querying supports roughly **8-10 concurrent users on a Large pool**. If a room
  is running notebooks at the same time as you, that ceiling is what you will hit first.

## Cost: the Advanced data insights meter

Notebook compute bills against the data lake **Advanced data insights** meter. The formula
is the part worth memorising:

```
compute hours = vCores in the selected pool x hours the session was active
```

Three things follow from that, and the middle one catches people out:

1. **The pool size is a direct multiplier.** Sessions and jobs run on pools of **12, 32 or
   80 vCores**, and the runtime picker offers Small, Medium and Large. Microsoft documents
   the vCore counts and the pool names in separate articles and never maps one to the other,
   so treat Small=12 / Medium=32 / Large=80 as inferred - confirm it from the vCore gauge in
   the notebook status bar, which reports the pool's actual total. Either way, Large costs
   roughly 6.7x Small for the same wall-clock time.
2. **The clock runs on session time, not execution time.** An idle session with a warm
   kernel bills exactly the same as one crunching a query. Talking over a live demo with a
   Medium session open is billable time.
3. **The same meter covers notebook jobs and custom graph node/edge building**, not just
   interactive sessions.

Worked examples, in compute hours (multiply by the per-compute-hour rate for your
agreement):

| Scenario | Pool | Session | Compute hours |
| --- | --- | --- | --- |
| `demo18` alone | Small (12) | 15 min | 3 |
| `demo06` with discussion | Medium (32) | 45 min | 24 |
| The 15-minute "wow" cut | Medium (32) | 30 min inc. warm-up | 16 |
| Full hunt running order | Medium (32) | 90 min | 48 |
| Same, left open over lunch | Medium (32) | 150 min | 80 |

That last row is the point. An hour of forgetting to disconnect costs more than the entire
demo that preceded it.

**Keeping the bill down**

- **Disconnect when you stop.** The service kills an interactive session after **20 minutes**
  of inactivity, and the VS Code extension has its own timeout defaulting to **30 minutes**
  (click the connection status in the status bar to change it). Neither helps if you keep
  the session warm by clicking about.
- **Right-size the pool.** Small is genuinely enough for `demo05`, `demo08`, `demo12` and
  `demo18`. Reach for Large only when a notebook is actually memory-bound.
- **Keep `LOOKBACK_DAYS` small.** It cuts the data lake query meter as well as the time the
  session stays busy.
- **Watch the vCore gauge** in the notebook status bar. It shows utilisation across your
  interactive and job workloads, so you can see whether a Medium pool is actually being
  used or just being paid for.

**Related meters a notebook can trigger**

| Meter | When |
| --- | --- |
| Advanced data insights | Notebook sessions, notebook jobs, custom graph build |
| Data lake query | Per GB of uncompressed data scanned by KQL |
| Data lake storage | Per GB-month, at a 6:1 compression assumption |
| Data lake ingestion / processing | Per GB, lake-tier-only tables |
| Graph | Custom graph build (49 vCores) and query (6 vCores, 1 min minimum) |

Microsoft does not publish the per-compute-hour rate in the product docs. Get it from the
[Microsoft Sentinel pricing page](https://azure.microsoft.com/pricing/details/microsoft-sentinel/)
or the [cost estimator](https://microsoft.com/en-us/security/pricing/microsoft-sentinel/cost-estimator),
and track actuals through
[Sentinel cost management in the Defender portal](https://learn.microsoft.com/azure/sentinel/billing-monitor-costs).

> The per-GB lake rates used by
> [`Export-SdlMigrationWorkbook.ps1`](../Tools/SDL-Migration-Workbook-Export.md#pricing)
> cover ingest, processing, storage and query. They do **not** model this meter, so a
> migration estimate will understate a workspace that runs notebooks.

Reference: [Data lake tier billing](https://learn.microsoft.com/azure/sentinel/billing#data-lake-tier).
