# iSOCDeployments content types

Every content type the module knows, or will, and what it can do with
each so far. `Get-iSOCContentType` returns the registered ones with the
same details. Types deploy in the order shown: the workspace settings the
pipelines configure after the infrastructure stage, the order
`Deploy/content/Deploy-CustomContent.ps1` uses today, then the Defender
detections the pipelines deploy in a later stage.

## Registered

| Type | Repository folder | Endpoint | Identity | Deploy order | Missing dependency | Capabilities |
| --- | --- | --- | --- | --- | --- | --- |
| `WorkspaceSetting` | `Content/WorkspaceSettings` (JSON, any depth) | ARM, workspace, `settings` (2025-07-01-preview) | `name` (the setting's kind) | 5 | Deploy (not checked) | Deploy |
| `Parser` | `Content/Parsers` (YAML, any depth) | ARM, workspace, `savedSearches` (2025-07-01) | `id` | 10 | Deploy (not checked) | Deploy |
| `Watchlist` | `Content/Watchlists` (one folder each: `watchlist.json`, `data.csv`) | ARM, workspace, `watchlists` (2025-09-01) | `watchlistAlias` | 20 | Skip | Deploy |
| `AnalyticsRule` | `Content/AnalyticalRules` (YAML, any depth) | ARM, workspace, `alertRules` (2025-07-01-preview) | `id` | 30 | Deploy disabled | Deploy, Compare, Sync, Dependencies |
| `HuntingQuery` | `Content/HuntingQueries` (YAML, any depth) | ARM, workspace, `savedSearches` (2025-07-01) | `id` | 40 | Skip | Deploy, Dependencies |
| `Playbook` | `Content/Playbooks` (ARM templates, any depth) | ARM deployment through Az.Resources, playbook resource group | `PlaybookName` default, else the file name | 50 | Skip | Deploy, Export |
| `Workbook` | `Content/Workbooks` (one folder each: `workbook.json`, `metadata.json`) | ARM, resource group, `Microsoft.Insights/workbooks` (2022-04-01) | `workbookId`, else derived | 60 | Skip | Deploy, Export |
| `AutomationRule` | `Content/AutomationRules` (JSON, any depth) | ARM, workspace, `automationRules` (2025-09-01) | `automationRuleId` | 70 | Skip | Deploy |
| `SummaryRule` | `Content/SummaryRules` (JSON, any depth) | ARM, workspace, `summarylogs` (2025-07-01) | `name` | 80 | Skip | Deploy |
| `DefenderDetection` | `Content/DefenderCustomDetections` (YAML, any depth) | Microsoft Graph, tenant, `security/rules/detectionRules` (beta) | `displayName` | 90 | Deploy (not checked) | Deploy |

`Deploy` means `Deploy-iSOCContent` deploys the type
([Deploying content](Deploy.md)); `Compare` and `Sync` mean
`Compare-iSOCContent` finds its drift and `Sync-iSOCContent` writes it into
the repository ([Drift](Drift.md)); `Export` means `Export-iSOCContent`
writes the workspace's items into the repository ([Export](Export.md));
`Dependencies` means the type is in the
dependency manifest ([Dependency manifest](Dependency-Manifest.md)). After
watchlists are uploaded, deploy waits 30 seconds before the rules that
read them. Every type deploys in repository order, the items
`sentinel-deployment.config` prioritises first and Community items last,
except playbooks, which have an order of their own (MIGRATION.md edit
E15).

### WorkspaceSetting

- **Read**: every `*.json` file under `Content/WorkspaceSettings/`, one
  Microsoft Sentinel setting each: anomalies, EyesOn, Entity Analytics or
  UEBA.
- **Validate**: a kind Sentinel has and a name the same as it; properties,
  when present, an object; Entity Analytics with a list of
  `entityProviders` and UEBA with a list of `dataSources`.
- **Request**: the kind and the file's properties, as the Configure
  Sentinel Settings step of the deploy pipelines sends them.
- **Deploy**: the setting is read for its etag first, and a refusal for
  want of permission (UEBA and Entity Analytics need the Security
  Administrator directory role) skips it with a warning rather than failing
  the run (MIGRATION.md edit E43). Settings are never deleted.
  `Tests/iSOCDeployments/WorkspaceSetting.Tests.ps1` holds every file to
  the settings both pipelines send ([Workspace settings and
  onboarding](Workspace-Settings.md)).
- **Compared fields**: the kind, and the entity providers or data sources
  as sets, for when compare comes to the type.

### Parser

- **Read**: every `*.yaml` and `*.yml` file under `Content/Parsers/`; the
  function alias is `functionAlias`.
- **Validate**: `id`, `name`, `functionAlias` and `query` present and not
  blank.
- **Request**: the saved search `Deploy-CustomContent.ps1` sends, field for
  field: `etag: *` so an existing function is overwritten, category
  Sentinel Parsers unless the file sets one, version 2 (a function), and
  `functionParameters` when the file has them.
  `Tests/iSOCDeployments/Parser.Tests.ps1` holds every parser to the
  request the script builds.

### Watchlist

- **Read**: each folder directly under `Content/Watchlists/` is one
  watchlist; `watchlist.json` is parsed, and `data.csv` is read when the
  request is built.
- **Validate**: both files present, `watchlistAlias`, `displayName` and
  `itemsSearchKey` set, and the rows within the 3.5 MB inline upload limit
  (a larger watchlist is uploaded by hand in the portal).
- **Request**: the upload `Deploy-CustomContent.ps1` sends, rows inline as
  Text/Csv from a local file; an empty description and provider Custom when
  the file has neither (MIGRATION.md edit E9).
  `Tests/iSOCDeployments/Watchlist.Tests.ps1` holds every watchlist to the
  request the script builds.

### AnalyticsRule

- **Read**: every `*.yaml` and `*.yml` file under `Content/AnalyticalRules/`;
  a file under a `Community/` folder is a Community rule.
- **Validate**: `id`, `name`, `kind`, `severity` and `query` present and not
  blank; a Scheduled rule also needs `queryFrequency`, `queryPeriod`,
  `triggerOperator` and `triggerThreshold`.
- **Request**: the body `Deploy-CustomContent.ps1` sends, field for field:
  Community rules and rules with a missing dependency are sent disabled,
  suppression defaults to off for five hours, the trigger operator is
  mapped to the API spelling (`gt` to `GreaterThan`), techniques are split
  into parent techniques and sub-techniques, and entity mappings, custom
  details, alert details override, event grouping and incident
  configuration pass through. `Tests/iSOCDeployments/AnalyticsRule.Tests.ps1`
  holds every rule in the repository to the request the script builds.
- **Compared fields**: kind and display name (exactly), severity (any
  case), query (ignoring whitespace, not case), and for Scheduled rules
  frequency and period (as durations), trigger operator (any case) and
  threshold (as a number): the fields `Tools/Test-SentinelRuleDrift.ps1`
  compares, with the changes in MIGRATION.md edit E22.
- **Compare**: every rule in the workspace, read with the preview alert
  rules API, is classed as Microsoft-managed (Fusion, ML, threat
  intelligence and incident creation rules), governed by the repository
  file with its id, from a Content Hub template, or portal-only, and
  compared with its source ([Drift](Drift.md)).
- **Sync**: a portal edit is written into the rule's file in place, its
  patch version raised; a customised Content Hub rule and a portal-only
  rule are written to new files under
  `Content/AnalyticalRules/AbsorbedFromPortal/`.
  `Tests/iSOCDeployments/Drift.Tests.ps1` holds compare, sync and the
  report to what the drift script does.

### HuntingQuery

- **Read**: every `*.yaml` and `*.yml` file under `Content/HuntingQueries/`.
- **Validate**: `id`, `name` and `query` present and not blank.
- **Request**: the saved search `Deploy-CustomContent.ps1` sends, field for
  field: category Hunting Queries, and the description, tactics (joined),
  parent techniques, sub-techniques and the file's own tags as saved
  search tags. `Tests/iSOCDeployments/HuntingQuery.Tests.ps1` holds every
  query to the request the script builds.
- **Compared fields**: display name, query (whitespace-insensitive) and
  tags (as JSON).

### Playbook

- **Read**: every `*.json` file under `Content/Playbooks/`, leaving out
  parameter files (`*.parameters.json`) and anything in a folder named
  `Template`. A playbook is named `<folder>/<file>`, or `<file>` alone in
  `Content/Playbooks/` itself.
- **Validate**: the file parses and its `$schema` is an ARM deployment
  template.
- **Order**: the templates in `Module` folders first, each after the
  modules it calls (a `Microsoft.Logic/workflows/Module-<name>` reference),
  then the rest in repository order. Calls to modules the repository does
  not have are warned about, and modules that call each other in a cycle
  deploy after the other modules, with a warning.
- **Request**: a resource group deployment of the template to the
  playbook resource group, named `Playbook-<file>-<yyyyMMddHHmmss>`, with
  the `<file>.parameters.json` beside it when there is one. The template
  parameters the workspace can answer are filled in, and only those the
  template declares: `AutomationResourceGroup` and `PlaybookResourceGroup`,
  `SentinelResourceGroup` and `SentinelResourceGroupName`,
  `SentinelWorkspaceName` (and the common misspelling
  `SentinelWorkpaceName`), `SubscriptionId` and `WorkspaceId`. Under
  `-WhatIf` the template is validated against the resource group instead
  (MIGRATION.md edit E14). Az.Resources is needed only when there are
  playbooks to deploy. `Tests/iSOCDeployments/Playbook.Tests.ps1` holds
  every playbook to the deployment the script runs.
- **Export**: the Logic Apps in the playbook resource group, each written
  as a parameterised template to its trigger's folder, or over the
  template whose `PlaybookName` is its name with `-Force`
  ([Export](Export.md)).
  `Tests/iSOCDeployments/Export.Tests.ps1` holds it to the unmerged
  playbook exporter.

### Workbook

- **Read**: each folder directly under `Content/Workbooks/` is one
  workbook; `metadata.json` is parsed when there is one, and
  `workbook.json` is read when the request is built. Only `workbook.json`
  is recorded in the deployment state.
- **Validate**: `workbook.json` present (a folder without it is skipped)
  and `metadata.json`, when there is one, parses (a workbook whose
  metadata does not is failed).
- **Request**: a shared workbook in the workspace's resource group and
  region, sourced from the workspace. The display name, category and
  `workbookId` come from `metadata.json` when it sets them; otherwise the
  folder name spaced at its capitals (MIGRATION.md edit E16), `sentinel`,
  and a GUID made from the workspace and the folder name, so the workbook
  keeps its name across runs. A gallery template is sent as it is; an ARM
  template wrapping a workbook resource sends that resource's
  `serializedData`. `Tests/iSOCDeployments/Workbook.Tests.ps1` holds every
  workbook to the request the script builds.
- **Export**: the workspace's Sentinel workbooks, each written to a folder
  its display name makes, or over the folder with its `workbookId` (or
  the GUID deploy makes for one without) with `-Force`; Content Hub
  workbooks are left out unless asked for ([Export](Export.md)).
  `Tests/iSOCDeployments/Export.Tests.ps1` holds it to
  `Tools/Export-SentinelWorkbooks.ps1`.

### AutomationRule

- **Read**: every `*.json` file under `Content/AutomationRules/`.
- **Validate**: `automationRuleId`, `displayName`, `order` (0 counts),
  `triggeringLogic` and `actions` present.
- **Request**: the file's display name, order, triggering logic and
  actions as the rule's properties, as `Deploy-CustomContent.ps1` sends
  them. `Tests/iSOCDeployments/AutomationRule.Tests.ps1` holds every rule
  to the request the script builds.

### SummaryRule

- **Read**: every `*.json` file under `Content/SummaryRules/`.
- **Validate**: `name`, `query`, `binSize` and `destinationTable` present;
  `binSize` one of 20, 30, 60, 120, 180, 360, 720 or 1440 minutes; and the
  destination a custom table (`_CL`).
- **Request**: a User rule whose definition is the query, bin size and
  destination table, with `binDelay` and `binStartTime` when the file sets
  them, and the description and display name when it has them.
  `Tests/iSOCDeployments/SummaryRule.Tests.ps1` holds every rule to the
  request the script builds.

### DefenderDetection

- **Read**: every `*.yaml` and `*.yml` file under
  `Content/DefenderCustomDetections/`, named by its `displayName`. A file
  written with the Graph fields retired on 2026-10-01 (`isEnabled`,
  `schedule.period`, `category`, `mitreTechniques`, `impactedAssets`,
  `responseActions`, `scopeNames`) is translated to the current shape as
  it is read. A file that does not parse, holds no mapping, or names an
  impacted asset or response action the translation cannot place is
  failed.
- **Validate**: `displayName`, `queryCondition.queryText` and a
  `schedule.frequency` of PT1H, PT3H, PT12H or P1D; a known `status` when
  set; an alert template with a title, a known severity and at least one
  known tactic, with well-formed techniques that each belong to the
  tactic they sit under in MITRE ATT&CK 18.1 (the module's own map,
  `Resources/DefenderDetection/mitre-attack-tactics.json`; MIGRATION.md
  edit E46); known entity mapping
  collections and automated action members, each action entry with the
  columns it needs. Every problem is reported on one line.
- **Request**: the Graph detectionRule body: status enabled unless the
  file says otherwise, the severity in lower case, the canonical
  frequency, an empty `automatedActions` and a null `organizationalScope`
  unless the file sets them, so the file stays the source of truth.
- **Deploy**: the tenant's rules are read once per run (under `-WhatIf`
  too, MIGRATION.md edit E18). A rule the tenant has under the same
  display name, in any case, is updated in place with PATCH; a new one is
  created with POST and the file's `id`, and fails when the file has none.
  The service principal needs the `CustomDetection.ReadWrite.All` Graph
  application permission; Microsoft does not offer the API in US
  Government clouds. `Tests/iSOCDeployments/DefenderDetection.Tests.ps1`
  holds every detection to the request the script sends.

## Not content types

Export comes to the other registered types as each is ported. Content Hub
solutions are installed by their own
commands rather than as a content type, since an item there is a package,
not a file ([Content Hub solutions](Content-Hub.md)). Whether a workspace
and its Sentinel onboarding exist is read by `Get-iSOCWorkspaceOnboarding`,
which the infrastructure stage runs before Bicep
([Workspace settings and onboarding](Workspace-Settings.md)).

## Not representable

Some ISOC and Defender portal features have no API to deploy them through,
so the module cannot carry them: enhanced automation rules, generated
Python playbooks, integration profiles, tenant-level Defender workbooks,
case templates, the ISOC workspace create-and-connect flow, and UEBA's
Defender XDR source selection.
