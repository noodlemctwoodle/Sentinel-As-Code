# SparkNotebooks - Microsoft Sentinel data lake (Notebooks / ML)

Runnable Jupyter/PySpark notebooks for the Microsoft Sentinel **data lake** advanced
analytics capability (F16). They read lake-tier tables via the `MicrosoftSentinelProvider`
SDK, build ML anomaly detections, write enrichment back to custom tables, and run as
scheduled notebook jobs.

Run them in **VS Code** with the **Microsoft Sentinel** extension against a data-lake–onboarded
workspace. The kernel executes on a managed Spark pool - there is nothing to install locally
beyond VS Code + the extension.

## Documentation

- **[Spark Notebooks catalogue](../../Docs/Content/Spark-Notebooks.md)** - full catalogue of
  all 18 notebooks (purpose, tables, technique, visual, parameters, pool, and why-not-KQL for
  each), how to configure the workspace name with `apply_config.py`, plus the **threat-hunting
  running order** and ATT&CK mapping.

## Contents

**Foundation + job notebooks**

| Path | What it is |
| --- | --- |
| `demos/demo01_lake_exploration.ipynb` | Connect, list, read and shape lake tables |
| `demos/demo02_identity_anomaly_detection.ipynb` | ML anomaly detection over an identity baseline (Isolation Forest) + write-back |
| `demos/demo03_network_beacon_detection.ipynb` | C2 beacon + lateral-movement detection over `DeviceNetworkEvents` |
| `demos/demo04_scheduled_job_enrichment.ipynb` | Parameterised, schedulable enrichment job |

**Visual demos - fast, graph-heavy, "why notebooks beat KQL"**

Each is tuned to run quickly (aggregate in Spark, then a rich chart) and ends with a
*Why a notebook beats KQL here* note. They rely on the Synapse Spark 3.4 library set, which
cannot be extended (`%pip install` is unsupported on data lake pools) - run the demo01
preflight cell first to confirm what your pool actually has.

| Path | Technique | Visual | Pool |
| --- | --- | --- | --- |
| `demos/demo05_signin_activity_heatmap.ipynb` | Hour × weekday aggregation | Seaborn heatmap | Small |
| `demos/demo06_ueba_peer_clustering.ipynb` | K-Means + PCA (UEBA) | Cluster scatter, outliers starred | Medium |
| `demos/demo07_impossible_travel.ipynb` | `geopy` geodesic speed between sign-ins | Speed bars + timeline | Medium |
| `demos/demo08_signin_volume_forecast.ipynb` | Holt-Winters (`statsmodels`) | Actual vs forecast + band | Small |
| `demos/demo09_lateral_movement_graph.ipynb` | `networkx` degree centrality | Directed network graph | Medium |
| `demos/demo10_commandline_entropy.ipynb` | Shannon entropy + rarity | Entropy histogram + top-N bar | Medium |
| `demos/demo11_cross_signal_correlation.ipynb` | 3-table feature matrix | Correlation clustermap | Medium |
| `demos/demo12_failed_logon_zscore.ipynb` | Rolling z-score (3σ) | Time series + control band | Small |

**Threat hunting demos - hypothesis-driven, retro-hunt, ATT&CK**

For a hunt-team audience. Lead with retro-hunting (the lake keeps up to 12 years; the
analytics tier is cost-capped at ~90 days). See the **threat-hunting running order** section
in the [Spark Notebooks catalogue](../../Docs/Content/Spark-Notebooks.md) for hunt hypotheses,
KQL contrast and the 15-minute "wow" cut.

| Path | Hunt | Visual |
| --- | --- | --- |
| `demos/demo13_retrohunt_ioc_sweep.ipynb` | Sweep IOCs across **full history** (hero) | First/last-seen activity gantt |
| `demos/demo14_stack_counting_lfo.ipynb` | Least-frequency-of-occurrence stacking | Long-tail curve + rarest pairs |
| `demos/demo15_first_seen_hunt.ipynb` | New entities vs a long baseline | New-entity bars + first-seen timeline |
| `demos/demo16_lolbin_hunt.ipynb` | LOLBin abuse (hypothesis + scoring) | Usage bars + suspicious timeline |
| `demos/demo17_entity_investigation_timeline.ipynb` | Unified multi-table entity timeline | Swimlane timeline |
| `demos/demo18_mitre_attack_coverage.ipynb` | Hunt-library ATT&CK coverage | Tactic × technique heatmap |

**Config**

| Path | What it is |
| --- | --- |
| `.env.example` | Config template (committed) |
| `.env` | Your local config - **git-ignored**, holds the real workspace name |
| `apply_config.py` | Stamps the workspace name from `.env` into the notebooks |

## Configure the workspace name (single file, git-ignored)

The only tenant-specific value is the Log Analytics workspace onboarded to the data lake.
It lives in one git-ignored file (`.env`) and is stamped into the notebooks locally - because the cloud Spark kernel cannot read a local file at run time.

```bash
cp .env.example .env                     # first time only
# edit .env and set SENTINEL_WORKSPACE_NAME=<your workspace>
python3 apply_config.py apply            # inject the name before you run the notebooks
```

Get the exact workspace name by running `data_provider.list_databases()` in any notebook.

### Before you commit

Keep the real name out of git - the committed notebooks always carry the
`your-workspace-name` placeholder:

```bash
python3 apply_config.py reset            # restore placeholders
python3 apply_config.py check            # exits 1 if a real name is still present (CI/pre-commit)
```

`python3 apply_config.py status` shows the current state of each notebook.

> `.env` is already ignored by the repo-root `.gitignore` (`.env` / `.env.*` rules), matching
> the repo's existing `.env` / `.env.example` convention.

**Full config reference (all commands, pre-commit hook, troubleshooting): [Spark Notebooks - Configuration](../../Docs/Content/Spark-Notebooks.md#configuration-apply_configpy).**

## Prerequisites

- Workspace onboarded to the **Microsoft Sentinel data lake** (Defender portal).
- Role for read: **Security Reader** (or equivalent). For write/schedule (demo04):
  **Security Operator**. Analytics-tier custom tables need the data-lake managed identity
  (`msg-resources-<guid>`) to have **Log Analytics Contributor** on the workspace.
- VS Code + the **Microsoft Sentinel** extension.

## Custom-table suffixes

| Suffix | Tier | Notes |
| --- | --- | --- |
| `_SPRK` | Lake | Cheapest; `overwrite` + `append` |
| `_SPRK_CL` | Analytics | KQL-queryable; append-only from notebooks; higher storage cost |

## Notes

- Runtime: Python (PySpark) on Azure Synapse Spark 3.4 libraries + the Sentinel provider.
  Charts use matplotlib / seaborn / networkx; models use scikit-learn / statsmodels / scipy;
  geo uses geopy. **`%pip install` and custom libraries are not supported** on the data-lake
  pools, so if a library is absent the only option is to drop that notebook from the running
  order. **Run the preflight cell in demo01 (section 1b) once before a demo** to find out
  which. Demo 07 is the only notebook that degrades gracefully, falling back to a built-in
  haversine when `geopy` is missing.
- **Cost:** notebook compute bills against the **Advanced data insights** meter at
  `vCores x session hours`, and the clock runs on the whole session, not just cell
  execution. See [Spark Notebooks - cost](../../Docs/Content/Spark-Notebooks.md#cost-the-advanced-data-insights-meter).
- Tables used across the demos (confirm these exist in the Zava data lake, or swap for
  equivalents): `SigninLogs`, `AADNonInteractiveUserSignInLogs`, `DeviceProcessEvents`,
  `DeviceNetworkEvents`, `DeviceLogonEvents`. Run `data_provider.list_tables("<workspace>")`
  to see what's available - note it returns `TableInfo` objects, not strings, so read `.name`
  off each entry (the class reference still documents `list[str]`).
- Device tables in the Sentinel schema use **`TimeGenerated`**, not the Defender advanced
  hunting `Timestamp` column. Some Microsoft samples use `Timestamp` and will not resolve here.
- For a live demo, keep `LOOKBACK_DAYS` small (each notebook defaults to 7–14 days; demo08
  uses 60 daily points) and start on a **Small/Medium** pool - first Spark session takes
  3–6 minutes, subsequent runs are fast.
- Facilitation guides (agenda, labs, slides, cost governance, cheat sheet) are maintained
  separately as workshop material.
- Docs: https://learn.microsoft.com/azure/sentinel/datalake/notebooks
