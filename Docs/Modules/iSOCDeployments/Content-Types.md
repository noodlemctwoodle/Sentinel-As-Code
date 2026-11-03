# iSOCDeployments content types

Every content type the module knows, or will, and what it can do with
each so far. `Get-iSOCContentType` returns the registered ones with the
same details. Types deploy in the order shown, the order
`Deploy/content/Deploy-CustomContent.ps1` uses today.

## Registered

| Type | Repository folder | Endpoint | Identity | Deploy order | Missing dependency | Capabilities |
| --- | --- | --- | --- | --- | --- | --- |
| `Parser` | `Content/Parsers` (YAML, any depth) | ARM, workspace, `savedSearches` (2025-07-01) | `id` | 10 | Deploy (not checked) | - |
| `Watchlist` | `Content/Watchlists` (one folder each: `watchlist.json`, `data.csv`) | ARM, workspace, `watchlists` (2025-09-01) | `watchlistAlias` | 20 | Skip | - |
| `AnalyticsRule` | `Content/AnalyticalRules` (YAML, any depth) | ARM, workspace, `alertRules` (2025-07-01-preview) | `id` | 30 | Deploy disabled | Dependencies |
| `HuntingQuery` | `Content/HuntingQueries` (YAML, any depth) | ARM, workspace, `savedSearches` (2025-07-01) | `id` | 40 | Skip | Dependencies |

Every registered type can already be read, validated and turned into the
request deploy sends; `Deploy` joins the capabilities when the deploy
engine lands. `Dependencies` means the type is in the dependency manifest
([Dependency manifest](Dependency-Manifest.md)).

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
- **Compared fields**: kind, display name, severity (any case), query
  (whitespace-insensitive), frequency and period (as durations), trigger
  operator (any case) and threshold (as a number), the fields the drift
  script compares today.

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

## Planned

| Type | Repository folder | Replaces |
| --- | --- | --- |
| `Playbook` | `Content/Playbooks` | `Deploy-CustomPlaybooks`, the playbook exporter |
| `Workbook` | `Content/Workbooks` | `Deploy-CustomWorkbooks`, `Tools/Export-SentinelWorkbooks.ps1` |
| `AutomationRule` | `Content/AutomationRules` | `Deploy-CustomAutomationRules` |
| `SummaryRule` | `Content/SummaryRules` | `Deploy-CustomSummaryRules` |
| `DefenderDetection` | `Content/DefenderCustomDetections` | `Deploy/content/Deploy-DefenderDetections.ps1` |
| `WorkspaceSetting` | (pipeline parameters) | The UEBA, Entity Analytics and onboarding steps in the deploy pipelines |

Content Hub solutions are installed by their own commands rather than as a
content type, since an item there is a package, not a file.

## Not representable

Some ISOC and Defender portal features have no API to deploy them through,
so the module cannot carry them: enhanced automation rules, generated
Python playbooks, integration profiles, tenant-level Defender workbooks,
case templates, the ISOC workspace create-and-connect flow, and UEBA's
Defender XDR source selection.
