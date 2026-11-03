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
| `Private/Az/` | The only files that call Az cmdlets, as thin wrappers the rest of the module mocks |
| `Private/Rest/` | The only files that call REST: `Invoke-iSOCRestRequest` and its helpers |
| `Private/Yaml/` | Loading powershell-yaml, reading files, writing scalars and nested blocks |
| `Private/Kql/` | Dependency discovery in KQL, copied from `Sentinel.Common` |
| `Private/Drift/` | The comparers and the canonical forms they rest on |
| `Private/ContentTypes/` | The registry, the shared YAML item reader, and one folder per content type with its definition and handlers |
| `Private/Manifest/` | The dependency manifest: inventory, discovery, comparison and serialisation ([Dependency manifest](Dependency-Manifest.md)) |

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
| `SecurityInsights` | 2025-09-01 | Watchlists, automation rules, metadata, Content Hub |
| `SecurityInsightsPreview` | 2025-07-01-preview | Alert rules; the preview keeps `subTechniques`, which GA drops |
| `OperationalInsights` | 2022-10-01 | Workspaces and tables |
| `SavedSearches` | 2025-07-01 | Parsers and hunting queries |
| `SummaryRules` | 2025-07-01 | Summary rules |
| `Workbooks` | 2022-04-01 | Workbooks |
| `Deployments` | 2024-11-01 | ARM template deployments |
| `ResourceGroups` | 2021-04-01 | Resource groups |
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
| `MissingDependency` | What a deploy does when an item's dependency is missing | `DeployDisabled`, `Skip`, `Deploy` |
| `Capabilities` | What the module can do with the type | `Deploy`, `Export`, `Compare`, `Sync`, `Dependencies` |
| `Prerequisites` | What reading or sending the type needs | Names from the requirement table |
| `Handlers` | The functions that do the type's work | See below |
| `Fields` | What a compare looks at | `@{ Name = 'properties.x'; Comparer = '...' }`, by place in the request body |

`Get-iSOCContentFile` lists a type's items in ordinal order of their
repository-relative path, so every machine walks the repository the same
way. `Get-iSOCResourcePath` joins the scope from the context, the
collection and an item's name.

## Handlers

Handlers are named functions, looked up when they are called through
`Invoke-iSOCContentTypeHandler`, so a test can mock any one of them by
name. Each lives in its type's folder in a file named after it.

| Handler | Takes | Returns |
| --- | --- | --- |
| `ReadRepo` | `-RepoPath`, `-ContentType` | One `iSOCDeployments.RepoItem` per item: `ContentType`, `Identity` (lower case), `Name`, `Path`, `RelativePath`, `Source` (`Custom` or `Community`), `Data`, `ParseError`, and anything the type needs besides (a watchlist adds `MetadataPath` and `CsvPath`). YAML types share `Read-iSOCYamlRepoItem` |
| `Validate` | `-Item` | The reasons the item cannot be sent; nothing when it can |
| `ToRequest` | `-Item`, and switches the type needs (`-Disabled` for rules) | An `iSOCDeployments.Request`: `ContentType`, `Identity`, `ResourceName`, `Body`. It reads nothing outside the item, except a watchlist's `data.csv`, and sends nothing |
| `GetQuery` | `-Item` | The KQL the item runs |
| `ReadWorkspace`, `Classify`, `Deploy`, `Order`, `ToComparable`, `GetTemplates`, `ToRepoFile`, `UpdateRepoFile`, `GetRepoPath` | | Arrive with deploy, export, compare and sync |

An unreadable item and an invalid one are told apart, because deploy
treats them as the scripts do: `ParseError` is set when the file is there
but does not parse (deploy fails the item), and `Validate` reports
everything else, such as a missing field or file (deploy skips the item).

A capability needs these handlers:

| Capability | Handlers |
| --- | --- |
| `Deploy` | `ReadRepo`, `Validate`, `ToRequest` |
| `Export` | `ReadWorkspace`, `ToRepoFile`, `GetRepoPath` |
| `Compare` | `ReadRepo`, `ReadWorkspace`, `ToRequest`, `ToComparable` |
| `Sync` | Compare's, and `UpdateRepoFile`, `ToRepoFile`, `GetRepoPath` |
| `Dependencies` | `ReadRepo`, `GetQuery` |

Compare works on what deploy would send: `ToRequest` builds the body from
the repository file, and `ToComparable` maps the workspace's copy into the
same shape, so a field is compared once, by its place in the body.

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
list. powershell-yaml is loaded the first time YAML is read
(`Import-iSOCYamlModule`), never installed.

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
