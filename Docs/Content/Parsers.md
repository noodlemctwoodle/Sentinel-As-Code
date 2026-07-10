# Parsers

KQL parsers (workspace saved functions) authored in YAML and deployed to Microsoft Sentinel as saved searches via the Log Analytics REST API. A parser is a reusable, named KQL function that normalises or unions one or more source tables into a single view, so that analytics rules, hunting queries, and summary rules can reference the function by name instead of repeating the same union/normalisation logic in every query.

Source files live under [`Content/Parsers/`](../../Content/Parsers).

## What a Parser Is

A parser deploys as a Log Analytics saved search that carries a `functionAlias`. Once deployed, the alias becomes a callable KQL function inside the workspace, so a rule can simply write `UnifiedSignInLogs` and Sentinel expands it to the underlying query at run time. This makes parsers the foundation layer of the content set: they are deployed **first** (stage 1 of `Deploy-CustomContent.ps1`) so that any rule, hunting query, or summary rule that depends on a function has it available before it is created.

| | Parsers | Hunting Queries |
|---|---|---|
| Deployment API | Log Analytics Saved Searches API | Log Analytics Saved Searches API |
| Resource shape | Saved search with a `functionAlias` (callable function) | Saved search categorised `Hunting Queries` (no alias) |
| Execution | Referenced by name from other KQL | Manual / on-demand by an analyst |
| Output | A reusable table/view when called | Query results for analyst review |
| Deploy order | Stage 1 (before everything else) | Stage 4 |
| Dependency role | **Provides** functions other content depends on | **Consumes** tables/functions |

Because the parser and hunting-query deployers both target the Saved Searches API, they share the same `$script:SavedSearchApiVersion`. The distinguishing property is `functionAlias`: a saved search that carries one is a callable function, one that does not is an ordinary saved query. For analytics rule schema see [Analytical Rules](Analytical-Rules.md); for hunting queries see [Hunting Queries](Hunting-Queries.md).

## Folder Structure

`Deploy-CustomParsers` walks `Content/Parsers/` recursively (`Get-ChildItem -Include *.yaml,*.yml -Recurse`), so the subfolder layout is purely organisational and has no bearing on how a parser is deployed. The convention in this repository is to group parsers by the primary log source or security domain they normalise.

The tree currently holds a single domain subfolder:

```
Content/Parsers/
  Security/
    UnifiedSignInLogs.yaml    # unions interactive + non-interactive sign-in logs
```

Place a new parser in whichever folder best matches the source it normalises (for example a `Network/` or `Identity/` folder), or create a new folder if none fits. The `functionAlias` must be globally unique across the whole tree regardless of folder, because Sentinel rejects duplicate workspace function names (the CI gate enforces this, see the note below).

## YAML Schema

Parsers are authored against the Toolkit's `sentinel-parser-schema.json`, which is the source of truth for field names, types, and which fields are required. The Sentinel as Code Toolkit scaffolds a parser from its `parser.template.yaml` and validates it live in the editor as you type (see [Templates](../Toolkit/Templates.md) and [Schemas and Validation](../Toolkit/Schemas-and-Validation.md)). The schema requires four fields (`id`, `name`, `functionAlias`, `query`) and defines five further optional fields (`description`, `category`, `functionParameters`, `version`, `tags`); additional properties are permitted. The template's canonical field order is:

`id`, `name`, `description`, `category`, `functionAlias`, `functionParameters`, `query`, `version`, `tags`

### Required Fields

The schema requires four fields (`id`, `name`, `functionAlias`, `query`), and `Deploy-CustomParsers` enforces the same set (`$requiredFields = @('id', 'name', 'functionAlias', 'query')`). A file missing any of them, or leaving any of them blank, is skipped with a warning and does not deploy.

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Stable unique identifier used as the saved search resource name (the `savedSearches/{id}` segment of the PUT URL). Must not change after initial deployment, the PUT is idempotent on this value. The example parser uses a plain slug (`UnifiedSignInLogs`); a GUID is equally valid. |
| `name` | string | Display name shown against the function in the workspace (sentence case). |
| `functionAlias` | string | The callable KQL function name the parser exposes. Other content references the parser by this alias. Must be a valid KQL identifier and unique across the parser tree (see CI note). |
| `query` | string | The KQL body of the function. Runs whenever the alias is called. |

The stricter CI schema gate (`Tests/Test-ParserYaml.Tests.ps1`) additionally requires `description` and `category` to be present and non-empty, so in practice every parser merged to `main` carries all six fields. See the CI note under Optional Fields.

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | Plain-English explanation of what the parser normalises and why. **Enforced as required by CI**, even though `Deploy-CustomParsers` treats it as optional. Not written into the saved-search body by the deployer. |
| `category` | string | Grouping category stored on the saved search. Defaults to `"Sentinel Parsers"` when omitted. The example parser sets `category: Security`. **Enforced as non-empty by CI.** |
| `functionParameters` | string | A parameter signature string (for example `table:string, lookback:timespan`) that makes the function parameterised. When present and non-empty it is written to `properties.functionParameters`; when absent the function takes no parameters. |
| `version` | string | Semantic version of the parser (for example `1.0.0`); bump it when the output schema of the function changes. Authoring metadata only, see the deploy-time note below. |
| `tags` | array of strings | Free-form string tags for organisation and discovery. Authoring metadata only, see the deploy-time note below. |

> **Deploy-time note:** `Deploy-CustomParsers` does not read the YAML `version` or `tags` fields. The `version` it writes into the saved-search body (`"version": 2`) is a fixed saved-search function-schema version, unrelated to the parser's own `version` field, and `tags` are not carried onto the deployed saved search at all. Both fields are authoring metadata: they are retained in source control and understood by the Toolkit, but they do not change the deployed resource.

> **CI note:** `Tests/Test-ParserYaml.Tests.ps1` validates every YAML under `Content/Parsers/` on each PR. It asserts that all six of `id`, `name`, `description`, `category`, `functionAlias`, `query` are present and non-empty, that `functionAlias` matches the KQL identifier pattern `^[A-Za-z_][A-Za-z0-9_]*$` (letter or underscore start, then word characters only), and that every `functionAlias` is unique across the whole parser tree. This is deliberate two-layer validation: `Deploy-CustomParsers` is lenient (it only hard-requires the four deploy-critical fields), while the CI gate is strict so that a typo in an alias, which would silently break every rule that depends on it, is caught before merge.

### API Mapping

The pipeline converts each YAML file to a PUT request against the Log Analytics Saved Searches API. The api-version comes from the `$script:SavedSearchApiVersion` variable in `Deploy/content/Deploy-CustomContent.ps1` (currently `2025-07-01`, the same version used for hunting queries), so it is defined in one place rather than hard-coded per call:

```
PUT /subscriptions/{sub}/resourceGroups/{rg}/providers/
    Microsoft.OperationalInsights/workspaces/{workspace}/
    savedSearches/{id}?api-version=2025-07-01
```

The request body is built by `Deploy-CustomParsers`. `etag` is set to `"*"` (unconditional upsert) and the `properties` object is assembled as:

```json
{
  "etag": "*",
  "properties": {
    "category": "Security",
    "displayName": "<name>",
    "query": "<query>",
    "functionAlias": "<functionAlias>",
    "version": 2
  }
}
```

`version` is fixed at `2` (the saved-search function schema version). `functionParameters` is added to `properties` only when the YAML declares a non-empty `functionParameters` value. `category` falls back to `"Sentinel Parsers"` when the YAML omits it. The body is serialised with `ConvertTo-Json -Depth 10`.

## Example YAML

The one parser shipped today, [`Content/Parsers/Security/UnifiedSignInLogs.yaml`](../../Content/Parsers/Security/UnifiedSignInLogs.yaml), unions the interactive and non-interactive sign-in tables into a single normalised view:

```yaml
id: UnifiedSignInLogs
name: Unified Sign-In Logs
description: |
  Unions interactive and non-interactive sign-in logs into a single normalised view.
  Handles type inconsistencies between SigninLogs and AADNonInteractiveUserSignInLogs
  by normalising dynamic/string column variants and removing duplicated columns.
category: Security
functionAlias: UnifiedSignInLogs
query: |
  union isfuzzy=true SigninLogs, AADNonInteractiveUserSignInLogs
  // Rename all columns named _dynamic to normalize the column names
  | extend ConditionalAccessPolicies = iff(isempty( ConditionalAccessPolicies_dynamic ), todynamic(ConditionalAccessPolicies_string), ConditionalAccessPolicies_dynamic)
  | extend Status = iff(isempty( Status_dynamic ), todynamic(Status_string), Status_dynamic)
  | extend MfaDetail = iff(isempty( MfaDetail_dynamic ), todynamic(MfaDetail_string), MfaDetail_dynamic)
  | extend DeviceDetail = iff(isempty( DeviceDetail_dynamic ), todynamic(DeviceDetail_string), DeviceDetail_dynamic)
  | extend LocationDetails = iff(isempty( LocationDetails_dynamic ), todynamic(LocationDetails_string), LocationDetails_dynamic)
  | extend TokenProtection = iff(isempty(TokenProtectionStatusDetails_dynamic),todynamic(TokenProtectionStatusDetails_string),TokenProtectionStatusDetails_dynamic)
  // Remove duplicated columns
  | project-away *_dynamic, *_string
```

### Example with Parameters

To expose a parameterised function, declare `functionParameters` alongside the query. The signature is passed straight through to the saved search:

```yaml
id: "b1c2d3e4-f5a6-7890-bcde-1234567890ab"
name: "Recent Failed Sign-Ins"
description: "Returns failed sign-ins within a caller-supplied lookback window."
category: Security
functionAlias: RecentFailedSignIns
functionParameters: "lookback:timespan"
query: |
  UnifiedSignInLogs
  | where TimeGenerated > ago(lookback)
  | where ResultType != 0
```

Once deployed this can be called as `RecentFailedSignIns(24h)`. Note that this example also references the `UnifiedSignInLogs` parser, so it depends on that parser deploying first, which the stage-1 ordering guarantees.

## Using a Parser in KQL

After a parser deploys, its `functionAlias` is a first-class function in the workspace. Any content type that embeds KQL can call it by name:

```kusto
// In an analytics rule, hunting query, or summary rule:
UnifiedSignInLogs
| where ResultType == 0
| summarize SignIns = count() by UserPrincipalName, bin(TimeGenerated, 1h)
```

When a rule or hunting query references a parser alias, `Build-DependencyManifest.ps1` records that reference as a `functions` dependency in `dependencies.json` (see Dependency Manifest below). This is what guarantees the parser is deployed before its consumers.

## Deployment Behaviour

Parsers are **stage 1** of the eight-stage `Deploy-CustomContent.ps1` run (**Parsers**, Watchlists, Detections, Hunting Queries, Playbooks, Workbooks, Automation Rules, Summary Rules), reported as `Step 5/12: KQL Parsers & Functions` in the wider deploy log. They deploy first precisely so that every downstream content type can resolve its function dependencies against a workspace where the parsers already exist.

- **File ordering (`Get-PrioritizedFiles`).** The discovered YAML files are ordered by any `prioritizedcontentfiles` list in the deployment config before processing, so a parser that others depend on can be pushed to the front of stage 1 if needed.
- **Smart deployment / deployment state (`Test-ShouldDeployFile`).** When smart deployment is enabled, a parser whose content is unchanged since the last successful run (tracked in the deployment-state file) is skipped with an "Unchanged ... (smart deployment)" message. Smart deployment is an opt-in `-SmartDeployment` switch that **defaults to off**; with it off, every parser is (re)deployed on each run. On a successful PUT the file's state is recorded via `Set-DeploymentItemState`; a failed PUT is recorded as `failed`.
- **No dependency pre-flight.** Unlike the consuming content types (detections, hunting queries, summary rules), `Deploy-CustomParsers` does **not** run `Test-ContentDependencies`. Parsers are the providers of function dependencies, not consumers of them, so there is nothing to gate on. The only per-file check before PUT is the required-field validation described in the schema section.
- **`-SkipParsers` switch.** Passing `-SkipParsers` to `Deploy-CustomContent.ps1` skips stage 1 wholesale (the run log shows `Parsers: SKIP` and `Skipped (SkipParsers flag set).`), leaving existing workspace functions untouched. Use this only when you are certain the target workspace already has every function the rest of the run depends on, otherwise consumers with unmet function dependencies will be skipped or deployed disabled.

`-WhatIf` performs a dry run that logs the intended deploy (`[WhatIf] Would deploy parser: ...`) without calling the API.

## Dependency Manifest

`Tools/Build-DependencyManifest.ps1` treats parsers as the repository's source of in-repo **functions**. During a manifest build it walks `Content/Parsers/**/*.yaml`, reads each `functionAlias`, and populates a `knownFunctionsLookup` map of alias to parser file path. When it then scans analytics rules, hunting queries, and summary rules, any bare identifier that matches a known parser alias is recorded under `functions` in that content item's `dependencies.json` entry. The manifest builder logs the count as `Functions  (Parsers/):` during the build.

At deploy time this closes the loop. When `Test-ContentDependencies` checks a consuming rule, a declared function dependency is considered satisfied if the alias is present **either** in the target workspace **or** in the list of internal parsers about to be deployed (`$script:InternalParsers`, built during the pre-flight from the same `Content/Parsers/` tree). Because parsers deploy at stage 1, an alias provided by a repo parser is always available by the time its consumers reach their stages. Microsoft ASIM functions are matched separately by regex and are assumed to exist in the workspace.

## Prerequisites

The identity used by the pipeline (service principal or managed identity) requires one of the following roles on the Log Analytics workspace:

- **Contributor** (resource group or workspace scope)
- **Microsoft Sentinel Contributor** (workspace scope)

The `Microsoft.OperationalInsights/workspaces/savedSearches/write` permission is what the deployment needs specifically. Sentinel Contributor grants this alongside all other Sentinel-scoped permissions.

## Adding Parsers

### From Scratch

1. Author and validate the KQL in the Sentinel **Logs** blade, confirming it returns the shape you want across all the tables it unions.
2. Choose a `functionAlias` that is a valid KQL identifier and not already used by another parser (the CI gate rejects duplicates).
3. Create a YAML file following the schema above and place it under `Content/Parsers/` in a folder that matches the source or domain. The [Sentinel as Code Toolkit](../Toolkit/Templates.md) can scaffold this file for you (its **Create Parser** command) with the canonical field order already in place.
4. Populate all six fields the CI gate checks (`id`, `name`, `description`, `category`, `functionAlias`, `query`) so PR validation passes.
5. If any analytics rule, hunting query, or summary rule references the new alias, regenerate the dependency manifest (see [Analytical Rules](Analytical-Rules.md)) so the `functions` dependency is recorded.
6. Open a pull request; the pipeline will deploy the parser at stage 1 on merge to `main`.

### Exporting an Existing Function from the Sentinel Portal

1. Navigate to **Microsoft Sentinel > Logs** and open **Functions**.
2. Locate the saved function you want to source-control and open it to view its KQL and alias.
3. Create a new YAML file using the schema above, pasting the function body into `query` and the existing alias into `functionAlias`.
4. Set a stable `id` (reuse the portal's saved-search name if you want to overwrite it in place, or a fresh slug/GUID to deploy alongside it).
5. Commit the file so the function is source-controlled and deployed idempotently going forward.

## Authoring with GitHub Copilot

There is no dedicated parser instructions file. When editing files under `Content/Parsers/**`, Copilot automatically loads the cross-cutting
[`.github/instructions/kql-queries.instructions.md`](../../.github/instructions/kql-queries.instructions.md),
whose `applyTo` glob includes `Content/Parsers/**/*.yaml`.

Copilot tooling useful for parsers:

- Agent `Sentinel-As-Code: KQL Engineer`, optimise the function body
- Agent `Sentinel-As-Code: Rule Author`, author a parser and the rules that consume it end-to-end

See [GitHub Copilot setup](../GitHub/GitHub-Copilot.md) for the full layout.
