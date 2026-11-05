# iSOCDeployments architecture

How the module is put together, for anyone changing it or adding a content
type. The rules here are enforced by the suites under
`Tests/iSOCDeployments/`; where a suite holds a rule, it is named.

## Contents

- [Layout](#layout)
- [The workspace context](#the-workspace-context)
- [The REST client](#the-rest-client)
- [API versions](#api-versions)
- [Content types](#content-types)
- [Handlers](#handlers)
- [Comparers](#comparers)
- [Logging](#logging)
- [Prerequisites](#prerequisites)
- [Adding a content type](#adding-a-content-type)

## Layout

| Folder | Holds |
| --- | --- |
| `Public/` | One exported command per file. The manifest's `FunctionsToExport` is the list of these files (`Module.Tests.ps1`). |
| `Private/Core/` | Logging, the API table, the context, repository paths, property access and the requirement table |
| `Private/Az/` | The only files that call Az cmdlets, as thin wrappers the rest of the module mocks: the Az context, the resource group deployments playbooks and data collection rules need, and Log Analytics queries |
| `Private/Rest/` | The only files that call REST: `Invoke-iSOCRestRequest` and its helpers |
| `Private/Yaml/` | Loading powershell-yaml, reading files, writing scalars and nested blocks |
| `Private/Kql/` | Dependency discovery in KQL, copied from `Sentinel.Common`, and the code-only reading the parser chains use: comments and strings out, quoted names made bare, names that cannot be a local function removed |
| `Private/Community/` | Community rule import: the sources, the checkout, reading and normalising rules, settling ids, the manifest hash and the README ([Community rule import](Community-Import.md)) |
| `Private/Permissions/` | Role assignments over REST (reading, finding one that applies at a scope or above, creating under a stable name, deleting), the playbook role analysis and the runbook's roles ([Permissions](Permissions.md)) |
| `Private/Graph/` | The only files that run Microsoft Graph SDK commands: a sign-in with the delegated scopes the service principal setup needs, and requests through it (`Module.Tests.ps1`) |
| `Private/Git/` | The only file that runs git: `Invoke-iSOCGit` (`Module.Tests.ps1`) |
| `Private/Http/` | The only file that calls endpoints outside ARM and Graph, which take other credentials: the Data Collector API (signed with the workspace key), the Entra token endpoint and the Logs Ingestion API; `Invoke-iSOCHttpRequest` logs nothing of the request (`Module.Tests.ps1`) |
| `Private/Export/` | Reading, comparing and saving an item's files, the export result and summary, and making exported content portable: ARM expressions for a workspace's own values, and the plain-text secret scan ([Export](Export.md)) |
| `Private/Drift/` | The comparers and the canonical forms they rest on, and the drift run: comparing a body field by field, the drift item, writing a repository file, the report and its Markdown ([Drift](Drift.md)) |
| `Private/ContentTypes/` | The registry, the shared YAML and JSON item readers, and one folder per content type with its definition and handlers |
| `Private/Manifest/` | The dependency manifest: inventory, discovery, comparison and serialisation ([Dependency manifest](Dependency-Manifest.md)) |
| `Private/Deploy/` | The deploy engine: the run, configuration, smart deployment, order, the dependency graph and pre-flight reads, the per-item steps and the summary ([Deploying content](Deploy.md)) |
| `Private/State/` | `deployment-state.json`: reading, recording and saving |
| `Private/Orchestration/` | The stages `Deploy-iSOCWorkspace` runs, what gates each, and running one through its command ([Deploying a workspace](Deploy-Workspace.md)) |
| `Private/Onboarding/` | The onboarding decision `Get-iSOCWorkspaceOnboarding` makes from what a workspace has ([Workspace settings and onboarding](Workspace-Settings.md)) |
| `Private/ContentHub/` | Content Hub: the onboarding wait, the catalogue and solution status, solution deployment, the rule and workbook steps and the run summary ([Content Hub solutions](Content-Hub.md)) |
| `Private/MigrationKits/ClassicToDcr/` | The classic table migration and its review: the table inventory and row counts, the migrate operation, the stream, transform and rule template, the rule deployment and ingestion role, the content read, the parser alias index and chains, the impact per table, the Content Hub mapping and the report writers ([Classic table migration](Table-Migration.md)) |
| `Private/MigrationKits/Rehearsal/` | The rehearsal aids: the Data Collector signature, fixture records and posts, the workspace key, the stream and its records, the token request, the settings and `.env` reader, the ingestion role check, the ingestion stream and the arrival check |
| `Resources/ClassicToDcr/` | The solution mapping and the HTML report template the review ships with (not code, so outside the one-function-per-file rule) |

Every `.ps1` file defines exactly one function named after the file and
nothing else, so the loader can dot-source everything in any order. No file
calls `exit` or installs a module, and no file carries `#Requires
-Modules`: the module imports with nothing beyond PowerShell 7.2 and checks
each step's needs when it runs.

The module runs in strict mode, which shapes two habits. A value that may
be one item or several is wrapped in `@()` before `.Count`, and `$null`
filtered out first where a helper can return nothing (`@($null)` counts
as one). And `ForEach-Object` always takes a script block: its
member-name form (`ForEach-Object Name`) honours ShouldProcess, so under
`-WhatIf` it returns nothing. `Module.Tests.ps1` fails on the member-name
form.

## The workspace context

`Connect-iSOCWorkspace -ResourceGroup -WorkspaceName [-SubscriptionId]
[-PlaybookResourceGroup]` reads the workspace through the current Az
sign-in and returns an `iSOCDeployments.Context`:

| Property | From |
| --- | --- |
| `TenantId`, `SubscriptionId`, `Account` | The Az sign-in |
| `ResourceGroup`, `WorkspaceName`, `PlaybookResourceGroup` | The parameters (`PlaybookResourceGroup` defaults to `ResourceGroup`) |
| `WorkspaceResourceId` | The ARM path of the workspace, no host |
| `WorkspaceId`, `Region` | The workspace itself (its customer id and location) |
| `Environment`, `IsGov`, `ArmUrl`, `GraphUrl` | The sign-in's Az environment |

Every property is a getter with no setter, so no command can change the
context for the next one, and the context holds no token. The last context
connected is the only state the module keeps; commands take `-Context` and
fall back to it.

## The REST client

`Invoke-iSOCRestRequest -Method -Path [-ApiVersion] [-Api Arm|Graph]
[-Body] [-Context] [-AllowNotFound] [-ReadOnly] [-Raw]` carries every
request (`Rest.Tests.ps1`):

- Requests go through `Invoke-AzRestMethod`, signed by the current Az
  sign-in in whichever cloud it is in. ARM paths start at
  `/subscriptions`; Graph paths start after the version segment and
  `-ApiVersion` is that segment.
- A GET that returns `{ "value": [...] }` is followed through `nextLink` or
  `@odata.nextLink`, and the items of every page are returned.
- 408, 429, 500, 502, 503, 504 and connection failures are retried up to
  five times, waiting as long as `Retry-After` says, else 5, 10, 20 and 40
  seconds.
- A failure throws an `HttpRequestException` carrying the status code. The
  message names the status, the method, the last two segments of the path
  and the service's own reason, never the subscription or the host.
- Bodies are serialised once, at depth 100.
- `-WhatIf` turns into two rules. Reads always run, because the client
  passes `-WhatIf:$false` to `Invoke-AzRestMethod`, which would otherwise
  skip them. A write that reaches the client while `WhatIfPreference` is
  set throws, because the command that sent it skipped `ShouldProcess`; a
  POST that only reads is marked `-ReadOnly`.

## API versions

`Get-iSOCApiVersion` holds every version in one table:

| Name | Version | Used for |
| --- | --- | --- |
| `SecurityInsights` | 2025-09-01 | Watchlists, automation rules, metadata, Content Hub, the onboarding state |
| `SecurityInsightsPreview` | 2025-07-01-preview | Alert rules, where the preview keeps `subTechniques`, which GA drops; and workspace settings (UEBA, Entity Analytics, anomalies, EyesOn), which only preview versions have |
| `OperationsManagement` | 2015-11-01-preview | The SecurityInsights solution, the older of the two resources that onboard Sentinel, for `Get-iSOCWorkspaceOnboarding` |
| `OperationalInsights` | 2022-10-01 | Workspaces and tables |
| `TablePlans` | 2025-07-01 | Log Analytics tables `New-iSOCDcrFromSchema` writes and reads; earlier versions know no Auxiliary plan |
| `SavedSearches` | 2025-07-01 | Parsers and hunting queries |
| `SummaryRules` | 2025-07-01 | Summary rules |
| `Workbooks` | 2022-04-01 | Workbooks |
| `Deployments` | 2024-11-01 | ARM template deployments |
| `ResourceGroups` | 2021-04-01 | Resource groups |
| `LogicApps` | 2019-05-01 | Logic App workflows: where playbooks live, for compare, export and permissions (they deploy as templates) |
| `Authorization` | 2022-04-01 | Role assignments |
| `Automation` | 2023-11-01 | Automation Accounts, for the runbook's identity |
| `DataCollectionRules` | 2023-03-11 | Data collection rules: read by the table migration review for their transforms, and authored by the classic table migration and `New-iSOCDcrFromSchema`; 2023-03-11 is the first version with `endpoints`, so a Direct rule gets its own logs ingestion endpoint |
| `SharedKeys` | 2020-08-01 | A workspace's `sharedKeys` action, for signing the classic table fixture's Data Collector posts |
| `GraphSecurity` | beta | Defender XDR custom detections (a Graph version segment) |

## Content types

Each content type is a definition returned by
`Private/ContentTypes/<Type>/Get-iSOC<Type>Definition.ps1` and listed in
`Get-iSOCContentTypeRegistry`. Deploy, export, compare, sync and the
dependency manifest all walk the registry. `Test-iSOCContentTypeDefinition`
checks every definition each time the registry is built, and the registry
refuses to build when one is wrong (`ContentTypes.Tests.ps1`).

| Key | Meaning | Values |
| --- | --- | --- |
| `Name` | What `-ContentType` takes | One PascalCase word, the folder name |
| `DisplayName` | Used in logs and reports | Text |
| `RepoFolder` | Where the files live | A forward-slash path under `Content/` |
| `Layout` | One item per file, or per folder | `File`, `Folder` |
| `Format` | How the files are written | `Yaml`, `Json` |
| `FilePattern` | Which files are items | Wildcards, such as `*.yaml` |
| `Recurse` | Whether subfolders are read | `$true`, `$false` |
| `Endpoint` | Where items are sent | `Arm`, `Graph` |
| `Scope` | What the collection hangs off | `Workspace`, `ResourceGroup`, `PlaybookResourceGroup`, `Tenant` |
| `CollectionPath` | The collection under the scope | A path starting with `/` |
| `ApiVersion` | The API table entry | A name from the table above |
| `IdentityKey` | What names an item | The key in the file |
| `DeployOrder` | When the type deploys | A whole number; types deploy in ascending order |
| `SettleSeconds` | How long deploy waits after the type when it sent anything | A whole number of seconds; 30 for watchlists, for Sentinel to index their columns |
| `MissingDependency` | What a deploy does when an item's dependency is missing | `DeployDisabled`, `Skip`, `Deploy` |
| `Capabilities` | What the module can do with the type | `Deploy`, `Export`, `Compare`, `Sync`, `Dependencies` |
| `Prerequisites` | What reading or sending the type needs | Names from the requirement table |
| `Handlers` | The functions that do the type's work | See below |
| `Fields` | What a compare looks at | `@{ Name = 'properties.x'; Comparer = '...' }`, by dotted place in the request body (`queryCondition.queryText` for a Graph type), with `Kind = '...'` when the field is compared only for items of that kind (a Scheduled rule's schedule) |

`Get-iSOCContentFile` lists a type's items in ordinal order of their
repository-relative path, so every machine walks the repository the same
way. `Get-iSOCResourcePath` joins the scope from the context, the
collection and an item's name; a `Tenant` scope adds nothing, so a Graph
type's path starts at its collection (`/security/rules/detectionRules`).
`Get-iSOCContentTypeNoun` gives a display name as it reads inside a
sentence, lower-casing its first letter unless a capitalised word follows
(`analytics rules`, but `Defender XDR custom detections`).

## Handlers

Handlers are named functions, looked up when they are called through
`Invoke-iSOCContentTypeHandler`, so a test can mock any one of them by
name. Each lives in its type's folder in a file named after it. A caller
offers what it has (the context, the run, the item) and each handler is
passed only the parameters it declares, so the tables below list what a
handler may take.

| Handler | Takes | Returns |
| --- | --- | --- |
| `ReadRepo` | `-RepoPath`, `-ContentType` | One `iSOCDeployments.RepoItem` per item: `ContentType`, `Identity` (lower case), `Name`, `Path`, `RelativePath`, `Source` (`Custom` or `Community`), `Data`, `ParseError`, and anything the type needs besides (a watchlist adds `MetadataPath` and `CsvPath`, a playbook its `Category` and `ParametersPath`, a Defender detection the translated `Rule` and the `LegacyFields` it was translated from). An item made of more than one file lists them in `Files`, which smart deployment and the state file use; otherwise `Path` is the one file. YAML types share `Read-iSOCYamlRepoItem`, and JSON types `Read-iSOCJsonRepoItem` |
| `Validate` | `-Item` | The reasons the item cannot be sent; nothing when it can. Deploy reports the first; a type with several problems to report at once joins them onto one line (Defender detections) |
| `ToRequest` | `-Item`, `-Context` when the body needs the workspace (a workbook's region, a playbook's resource groups), and switches the type needs (`-Disabled` for rules) | An `iSOCDeployments.Request`: `ContentType`, `Identity`, `ResourceName`, `Body`. It reads nothing outside the item and the context, except a watchlist's `data.csv` and a workbook's template, and sends nothing. A playbook's `Body` is the deployment's parameters rather than a REST body |
| `GetQuery` | `-Item` | The KQL the item runs |
| `Deploy` | `-Run`, `-ContentType`, `-Item`, and `-Disabled` when the type deploys disabled | Optional: sends the item itself, checking ShouldProcess, and returns Outcome and Reason. Without one, deploy sends the ToRequest body as it is. Analytics rules have one, to resend a rule disabled after a KQL error; playbooks, which deploy through Az.Resources and validate under `-WhatIf`; and Defender detections, which Graph updates with PATCH at an existing rule's id or creates with POST, after reading the tenant's rules once per run into the run's `Cache` |
| `Order` | `-Item` | Optional: the items in the order they must deploy. Without one, deploy takes repository order, prioritised items first and Community items last (`Get-iSOCDeployOrder`). Playbooks have one, to deploy modules before the playbooks that call them |
| `ReadWorkspace` | `-Context`, `-ContentType` | The type's items in the workspace, every page, as the API returns them, each in full: an item the list leaves part of is read on its own, and one that then cannot be read carries the error in `ReadError` |
| `Classify` | `-Run`, `-ContentType`, `-WorkspaceItem` | Where a workspace item's source of truth is, for compare and export: `Source` (`Custom`, `ContentHub`, `Orphan`, `Managed`), `State` when nothing more is needed (`Managed`, `Skipped`, `PortalOnly`, or `Failed` when the item could not be read), `Reason`, `Expected` (the body to compare with, in `ToRequest`'s shape), `SourceRef`, `SourcePath` and `Solution`. What it reads for every item (the repository's items, the templates) it reads once per run into the run's `Cache` |
| `ToComparable` | `-WorkspaceItem` | The workspace's copy in the shape `ToRequest` builds, without the fields the service manages |
| `UpdateRepoFile` | `-Path`, `-Modification` | Writes the workspace's values for the changed fields into the item's file, leaving the rest as it was; `$true` when the file changed |
| `ToRepoFile` | `-WorkspaceItem`, `-Provenance`, `-SolutionName`, `-Context`, `-RelativePath`, `-Existing` (what the item's files in the repository hold now), `-Author`, `-Warning` (a list to add warnings to) | The item's file text, or for a type with one item per folder its files' text by name |
| `GetRepoPath` | `-WorkspaceItem`, `-Provenance`, `-SolutionName`, `-Context` | Where a new item's file or folder goes, relative to the repository |
| `GetTemplates` | | Arrives with export |

An unreadable item and an invalid one are told apart, because deploy
treats them as the scripts do: `ParseError` is set when the file is there
but does not parse (deploy fails the item), and `Validate` reports
everything else, such as a missing field or file (deploy skips the item).

A capability needs these handlers:

| Capability | Handlers |
| --- | --- |
| `Deploy` | `ReadRepo`, `Validate`, `ToRequest` |
| `Export` | `ReadRepo`, `ReadWorkspace`, `Classify`, `ToRepoFile`, `GetRepoPath` |
| `Compare` | `ReadRepo`, `ReadWorkspace`, `Classify`, `ToRequest`, `ToComparable` |
| `Sync` | Compare's, and `UpdateRepoFile`, `ToRepoFile`, `GetRepoPath` |
| `Dependencies` | `ReadRepo`, `GetQuery` |

Compare works on what deploy would send: `ToRequest` builds the body from
the repository file, and `ToComparable` maps the workspace's copy into the
same shape, so a field is compared once, by its place in the body.
`Compare-iSOCContentBody` walks the type's `Fields` in order, skips one
whose `Kind` is not the workspace item's and one the source leaves unset,
and returns each difference with both values as they are.
[Drift](Drift.md) describes the commands built on it.

## Comparers

`Compare-iSOCFieldValue -Comparer -Expected -Actual` (`Comparers.Tests.ps1`):

| Comparer | Equal when |
| --- | --- |
| `Exact` | The text is the same, case-sensitive |
| `CaseInsensitive` | The text is the same, ignoring case |
| `Whitespace` | The text is the same once runs of whitespace are one space and the ends trimmed, case-sensitive (KQL is) |
| `Number` | The numbers are the same (5 and 5.0) |
| `Duration` | The ISO 8601 durations are the same (PT24H and P1D) |
| `Set` | The members are the same in any order, duplicates ignored |
| `OrderedList` | The members are the same in the same order |
| `Json` | The structure is the same with keys in any order |
| `Ignore` | Always |

A missing value, empty text, an empty list and an empty mapping all mean
"not set" and are equal to each other.

## Logging

`Write-iSOCLog -Message -Level Info|Warning|Error|Section|Success|Debug`
writes Azure DevOps logging commands (`##[warning]`, `##[error]`,
`##[section]`) under Azure DevOps, GitHub Actions workflow commands
(`::warning::`, `::error::`) under GitHub Actions, and coloured text on a
local console. It is the only place the module writes to the console
(`Module.Tests.ps1`).

## Prerequisites

`Get-iSOCRequirement` lists what each step needs; `Assert-iSOCPrerequisite
-Step` stops a command before it starts when something is missing, naming
it and how to install it; `Test-iSOCDeploymentPrerequisite` reports the
list. A requirement is PowerShell itself, a module, or a command on the
PATH (git, for the Import step, whose version is read from `--version`).
powershell-yaml is loaded the first time YAML is read
(`Import-iSOCYamlModule`), never installed. A content type's own
`Prerequisites` are checked by name (`Assert-iSOCPrerequisite -Name`)
only when there is something of that type to deploy: `Deploy-iSOCContent`
reads every type's files first, so a missing Az.Resources stops a run
with playbooks before anything deploys, and a repository without
playbooks never needs it.

## Adding a content type

1. Add a folder `Private/ContentTypes/<Type>/` with
   `Get-iSOC<Type>Definition.ps1` and one file per handler.
2. Add `<Type>` to the list in `Get-iSOCContentTypeRegistry`.
3. Add any new API version to `Get-iSOCApiVersion` and any new
   prerequisite to `Get-iSOCRequirement`.
4. Add `Tests/iSOCDeployments/<Type>.Tests.ps1` with fixtures under
   `Tests/iSOCDeployments/Fixtures/repo/Content/`, and, while the old
   script exists, a parity block that runs it beside the handlers over
   every real file.
5. Add rows to `MIGRATION.md` for every old function the type absorbs,
   and a row to [Content-Types.md](Content-Types.md).

`ContentTypes.Tests.ps1` fails until the folder, the registry entry and
the handlers agree.
