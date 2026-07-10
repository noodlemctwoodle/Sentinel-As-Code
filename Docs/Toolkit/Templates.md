# Templates

## Overview

The Sentinel as Code Toolkit ships eight bundled starter templates, one for each content type the Sentinel-As-Code pipeline deploys. When you scaffold a new piece of content the toolkit copies the matching template into your repository, replaces its placeholder tokens, and writes it to the folder the pipeline expects.

Every template is authored as **commented YAML**, so each field is documented inline as you edit it. The scaffolders write the commented YAML template and ask where to save it. Most content deploys as YAML, but three content types (Summary Rule, Automation Rule, and Watchlist) are stored as JSON in the repository. Those are authored as YAML too, then converted with the explicit **Convert Content YAML to JSON** command, which writes the `.json` file beside the YAML. See [YAML on disk versus JSON on disk](#yaml-on-disk-versus-json-on-disk) below.

The toolkit **authors and validates** content. It does **not** deploy. Deployment is the job of the Sentinel-As-Code pipeline. A template is a correct starting point for the pipeline's on-disk contract, not a deployment step.

Each content type has a dedicated schema and authoring guide. The templates are the fastest way to produce a file that matches those schemas:

| Template | Authoring guide |
| --- | --- |
| Standard Rule, NRT Rule | [Analytical Rules](../Content/Analytical-Rules.md) |
| Custom Detection | [Defender Custom Detections](../Content/Defender-Custom-Detections.md) |
| Hunting Query | [Hunting Queries](../Content/Hunting-Queries.md) |
| Parser | [Parsers](../Content/Parsers.md) |
| Summary Rule | [Summary Rules](../Content/Summary-Rules.md) |
| Automation Rule | [Automation Rules](../Content/Automation-Rules.md) |
| Watchlist | [Watchlists](../Content/Watchlists.md) |

---

## The bundled templates

There are eight templates. Each scaffolds one content type, targets a fixed folder under `Content/`, and is authored as commented YAML. The scaffolder asks where to save it.

| Template | Content type and repository folder | Authored as | Deployed as |
| --- | --- | --- | --- |
| Standard Rule | Scheduled analytics rule, [`Content/AnalyticalRules/`](../../Content/AnalyticalRules) | YAML | YAML |
| NRT Rule | Near-Real-Time analytics rule, [`Content/AnalyticalRules/`](../../Content/AnalyticalRules) | YAML | YAML |
| Custom Detection | Defender XDR detection, [`Content/DefenderCustomDetections/`](../../Content/DefenderCustomDetections) | YAML | YAML |
| Hunting Query | Hunting query, [`Content/HuntingQueries/`](../../Content/HuntingQueries) | YAML | YAML |
| Parser | KQL parser / saved function, [`Content/Parsers/`](../../Content/Parsers) | YAML | YAML |
| Summary Rule | Summary rule, [`Content/SummaryRules/`](../../Content/SummaryRules) | YAML | **JSON** (via Convert Content YAML to JSON) |
| Automation Rule | Automation rule, [`Content/AutomationRules/`](../../Content/AutomationRules) | YAML | **JSON** (via Convert Content YAML to JSON) |
| Watchlist | Watchlist metadata, `Content/Watchlists/<alias>/watchlist.yaml` | YAML | **JSON** (`watchlist.json`, via Convert Content YAML to JSON) |

### What each template scaffolds

- **Standard Rule** - a general-purpose scheduled analytics rule. It includes the scheduling fields (`queryFrequency`, `queryPeriod`, `triggerOperator`, `triggerThreshold`), plus optional entity mappings, alert-details override, custom details, event grouping, and incident configuration. `kind: Scheduled`.
- **NRT Rule** - a Near-Real-Time analytics rule. It deliberately omits the scheduling fields, because Sentinel manages the cadence (roughly once a minute). Use it for time-critical signals. `kind: NRT`.
- **Custom Detection** - a Defender XDR custom detection. It runs an Advanced Hunting KQL query and, on a match, raises an alert and optionally runs response actions. The template documents the full response-actions catalogue (device, file, user, and email actions); keep only the actions whose `identifier` maps to a column your query projects.
- **Hunting Query** - a Sentinel hunting query with no schedule, threshold, or trigger. It returns rows directly to the analyst, so the query must be self-contained and scope its own time range. It uses the `techniques` field (not `relevantTechniques`, which belongs to analytics rules).
- **Parser** - a reusable KQL function, invoked from other queries by its `functionAlias`. Parsers typically normalise a raw source into a stable, documented column set.
- **Summary Rule** - a scheduled KQL aggregation that writes results to a custom `_CL` table. It has a `binSize` (allowed values 20, 30, 60, 120, 180, 360, 720, 1440 minutes) and a `destinationTable` ending in `_CL`. The query must not carry an explicit time filter, because each run is implicitly scoped to one bin window.
- **Automation Rule** - a rule that fires when incidents or alerts are created or updated, matches optional conditions, then runs an ordered list of actions. The template shows all three action types (`ModifyProperties`, `RunPlaybook`, `AddIncidentTask`) for reference; keep at least one.
- **Watchlist** - the metadata for a reference table (high-value assets, allow-lists, VIP users) used to enrich detections. The template is metadata only; the row data lives beside it as `data.csv` or `data.tsv` in the same folder. The **Create Watchlist from CSV** command generates both files for you.

---

## YAML on disk versus JSON on disk

This is the most important rule to understand about the templates.

The Sentinel-As-Code pipeline stores **analytics rules, hunting queries, parsers, and Defender detections as YAML** on disk. For these, the toolkit writes the commented YAML template straight to the target folder with no conversion.

Three content types must be **JSON on disk** for the pipeline to read them:

- **Summary Rule** goes to `Content/SummaryRules/<name>.json`
- **Automation Rule** goes to `Content/AutomationRules/<name>.json`
- **Watchlist** goes to `Content/Watchlists/<alias>/watchlist.json` (plus its `data.csv` or `data.tsv`)

For these three, the template is still authored as commented YAML, purely so the fields can be documented inline. There is no automatic conversion on scaffold. You author the YAML (guided by its inline comments), then run **Convert Content YAML to JSON** on the file, which writes the `.json` beside it. You commit the generated JSON, not the YAML. The comments do not survive the conversion, which is expected, because JSON has no comment syntax.

Every other template (Standard Rule, NRT Rule, Custom Detection, Hunting Query, and Parser) is written as YAML and deploys as YAML, so no conversion is needed.

This split is also reflected in the toolkit's schema binding: the Summary Rule, Automation Rule, and Watchlist schemas validate `*.json` files under their folders, while the analytics-rule, hunting-query, parser, and Defender schemas validate `*.yaml` / `*.yml` files.

---

## Placeholder tokens

Templates carry `{{GUID}}` placeholder tokens where a fresh, stable identifier is required. When you scaffold a template the toolkit replaces each `{{GUID}}` with a newly generated GUID:

- Standard Rule and NRT Rule set the rule resource name via `id: {{GUID}}`.
- Hunting Query sets its saved-search resource name via `id: {{GUID}}`.
- Automation Rule sets `automationRuleId: {{GUID}}`.

Do not change a generated `id` or `automationRuleId` after the first deployment; it is the stable resource name in Sentinel.

Note that the analytics-rule templates also contain `{{ColumnName}}`-style tokens inside `alertDetailsOverride` (for example `{{UserPrincipalName}}`, `{{RiskScore}}`). Those are **Sentinel runtime tokens**, not scaffold placeholders. Sentinel substitutes them per matching row when the alert fires, so they are meant to stay in the file (edited to reference your own query columns), not replaced at scaffold time.

---

## Templates are always skipped by validation

Scaffolding templates are the `*.template.yaml` files bundled with the extension. Because they contain `{{PLACEHOLDER}}` tokens (such as `id: {{GUID}}`) they are not deployable content, so the toolkit skips them during validation automatically. They never surface diagnostics in the Problems panel, regardless of your `sentinelAsCode.validation.excludePatterns` setting. Once you scaffold a real file from a template and the placeholders are resolved, that file validates normally.
