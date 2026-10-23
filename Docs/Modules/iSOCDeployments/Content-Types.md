# iSOCDeployments content types

Every content type the module knows, or will, and what it can do with
each so far. `Get-iSOCContentType` returns the registered ones with the
same details. Types deploy in the order shown, the order
`Deploy/content/Deploy-CustomContent.ps1` uses today.

## Registered

| Type | Repository folder | Endpoint | Identity | Deploy order | Capabilities |
| --- | --- | --- | --- | --- | --- |
| `AnalyticsRule` | `Content/AnalyticalRules` (YAML, any depth) | ARM, workspace, `alertRules` (2025-07-01-preview) | `id` | 30 | Dependencies |

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

## Planned

| Type | Repository folder | Replaces |
| --- | --- | --- |
| `Parser` | `Content/Parsers` | `Deploy-CustomParsers` |
| `Watchlist` | `Content/Watchlists` | `Deploy-CustomWatchlists` |
| `HuntingQuery` | `Content/HuntingQueries` | `Deploy-CustomHuntingQueries` |
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
