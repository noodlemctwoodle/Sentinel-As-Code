# Sentinel Common Module

The shared `Modules/Sentinel.Common` PowerShell module: the single source of
truth for the logging, REST, Azure-context, and KQL-dependency helpers that the
deployer scripts and tooling reuse. This doc enumerates its public API, explains
the key functions in depth, and covers the manifest discipline that keeps its
version, release notes, and tests in lockstep.

## What it is and why it exists

Before extraction, the same `Write-PipelineMessage` logger and near-identical
`Invoke-SentinelApi` / `Connect-AzureEnvironment` helpers were copy-pasted (and
had quietly diverged) across four scripts:
[`Deploy-CustomContent.ps1`](../../Deploy/content/Deploy-CustomContent.ps1),
[`Deploy-SentinelContentHub.ps1`](../../Deploy/content/Deploy-SentinelContentHub.ps1),
[`Deploy-DefenderDetections.ps1`](../../Deploy/content/Deploy-DefenderDetections.ps1),
and [`Test-SentinelRuleDrift.ps1`](../../Tools/Test-SentinelRuleDrift.ps1).
`Sentinel.Common` collapses those copies onto one implementation, picking the
most defensive version of each helper as the canonical one.

The module is consumed by importing the manifest, not the raw `.psm1`. Every
consumer imports it relative to its own location, for example:

```powershell
Import-Module (Join-Path $PSScriptRoot '../../Modules/Sentinel.Common/Sentinel.Common.psd1') -Force -ErrorAction Stop
```

Current consumers are the three content deployers above,
[`Export-SentinelWorkbooks.ps1`](../../Tools/Export-SentinelWorkbooks.ps1),
[`Test-SentinelRuleDrift.ps1`](../../Tools/Test-SentinelRuleDrift.ps1), and
[`Build-DependencyManifest.ps1`](../../Tools/Build-DependencyManifest.ps1).

## Manifest at a glance

Defined in
[`Sentinel.Common.psd1`](../../Modules/Sentinel.Common/Sentinel.Common.psd1):

| Field | Value |
| --- | --- |
| `ModuleVersion` | `1.1.1` (SemVer, independent of the repository CalVer) |
| `RootModule` | `Sentinel.Common.psm1` |
| `PowerShellVersion` | `7.2` |
| `RequiredModules` | `Az.Accounts` (>= 2.0.0) |
| Licence | Apache License 2.0 |

The module's SemVer is deliberately decoupled from the repository's CalVer
(`YY.0M`) release scheme; see [Versioning](../Releases/Versioning.md#module-semver)
for how the two relate.

## Exported functions

Nine functions are exported. The manifest's `FunctionsToExport` list and the
`.psm1`'s `Export-ModuleMember -Function` list are kept identical (both are
updated when a function is added).

| Function | Purpose |
| --- | --- |
| `Write-PipelineMessage` | ADO / GitHub / local-friendly logging abstraction with a fixed set of severity levels |
| `Invoke-SentinelApi` | REST wrapper with retry-on-transient-failure and defensive error-body recovery |
| `Connect-AzureEnvironment` | Az context bootstrap; returns a hashtable of derived deployment state |
| `Remove-KqlComments` | Strip KQL line and block comments before regex extraction |
| `Get-KqlWatchlistReferences` | Extract watchlist aliases referenced via `_GetWatchlist('alias')` |
| `Get-KqlExternalDataReferences` | Extract URLs referenced by an `externaldata(...)` operator |
| `Get-KqlBareIdentifiers` | Heuristically extract table / function identifiers at data-source positions |
| `Get-ContentKqlQuery` | Read a content file and return its embedded KQL text |
| `Get-ContentDependencies` | Orchestrate the extractors for one content file and classify the results |

The last six form the KQL dependency-discovery layer added in `1.1.0`; they are
what [`Build-DependencyManifest.ps1`](../../Tools/Build-DependencyManifest.ps1)
uses to derive `dependencies.json` from content rather than hand-maintaining it
(see [Dependency Manifest](../Tools/Dependency-Manifest.md)).

## Logging: `Write-PipelineMessage`

The logging abstraction so callers do not have to care whether the script is
running in Azure DevOps, in a GitHub Actions runner, or on a developer laptop.

```powershell
Write-PipelineMessage "Deploying analytics rules" -Level Section
Write-PipelineMessage "Rule created" -Level Success
Write-PipelineMessage "Throttled, retrying" -Level Warning
```

- `-Message` is mandatory but accepts an empty string (`[AllowEmptyString()]`).
- `-Level` is one of `Info`, `Warning`, `Error`, `Section`, `Success`, `Debug`
  (default `Info`).
- ADO detection is driven by the presence of the `$env:BUILD_BUILDID`
  environment variable. When running under ADO, `Warning` / `Error` / `Section`
  emit the corresponding `##[warning]` / `##[error]` / `##[section]` logging
  commands so the Azure Pipelines UI renders them natively. Off ADO (GitHub or
  local) the same levels fall back to `Write-Warning`, `Write-Error
  -ErrorAction Continue`, and a cyan `Write-Host`, respectively.
- `Debug` always routes through `Write-Verbose`, so it only surfaces when the
  caller opts in with `-Verbose`.

## REST: `Invoke-SentinelApi`

A thin wrapper over `Invoke-WebRequest` that adds retry and defensive
error-body recovery. It is the canonical version taken from the old
`Deploy-SentinelContentHub.ps1` copy because it had the most complete
error-handling path.

```powershell
$result = Invoke-SentinelApi -Uri $uri -Method Get -Headers $authHeader
```

| Parameter | Notes |
| --- | --- |
| `-Uri` | Mandatory |
| `-Method` | Mandatory (`Get`, `Put`, `Delete`, etc.) |
| `-Headers` | Mandatory hashtable (typically the auth header from `Connect-AzureEnvironment`) |
| `-Body` | Optional; sent only when non-empty |
| `-MaxRetries` | Default `3` |
| `-RetryDelaySeconds` | Default `5` (multiplied by the attempt number for a simple linear backoff) |

Behaviour worth knowing:

- **Content type** is fixed to `application/json`, and requests use
  `-UseBasicParsing`. On success the function returns the response `Content`
  already piped through `ConvertFrom-Json`, so callers get an object, not a
  raw string.
- **Transient retry.** On HTTP `429`, `500`, `502`, `503`, or `504` (and while
  attempts remain) it sleeps `RetryDelaySeconds * attempt` seconds and retries,
  logging a warning via `Write-PipelineMessage` each time. Any other status
  code fails immediately.
- **Defensive error-body recovery.** On failure it reads the response body via
  a `StreamReader` so non-JSON 4xx / 5xx bodies are still captured, falling
  back to `ErrorDetails.Message` when the stream is unavailable. Property access
  is done through the `PSObject.Properties` reflection API so that under
  `Set-StrictMode -Version Latest` a plain `[Exception]` (which has no
  `Response` property) returns `$null` rather than throwing. On terminal
  failure it throws `API call failed: HTTP <code> - <body>`.

## Azure context: `Connect-AzureEnvironment`

Bootstraps the Az PowerShell context and returns a hashtable of derived state.
This is the canonical version taken from the old `Deploy-CustomContent.ps1`
copy (playbook-RG validation plus workspace-ID retrieval plus token fallback).

```powershell
$ctx = Connect-AzureEnvironment -ResourceGroup $ResourceGroup `
                                -Workspace $Workspace `
                                -Region $Region `
                                -SubscriptionId $script:SubscriptionId `
                                -IsGov:$IsGov `
                                -PlaybookResourceGroup $PlaybookResourceGroup
$script:BaseUri     = $ctx.BaseUri
$script:WorkspaceId = $ctx.WorkspaceId
$script:AuthHeader  = $ctx.AuthHeader
```

| Parameter | Required | Notes |
| --- | --- | --- |
| `-ResourceGroup` | Yes | Sentinel workspace resource group |
| `-Workspace` | Yes | Log Analytics / Sentinel workspace name |
| `-Region` | Yes | Logged for context |
| `-SubscriptionId` | No | If supplied, sets the context to it; otherwise the current context's subscription is used |
| `-IsGov` | No | Switch; branches to the Azure US Government cloud |
| `-PlaybookResourceGroup` | No | Separate RG for playbooks; defaults to `-ResourceGroup` |
| `-WorkspaceApiVersion` | No | Default `2022-10-01`, used for the workspace-ID lookup |

Key behaviours:

- **Return-a-hashtable, not mutate-script-scope.** The pre-extraction copies
  mutated the caller's `$script:` variables directly. That pattern does not
  survive a module boundary, because inside a module `$script:` refers to the
  module's own scope, not the caller's. The function therefore takes explicit
  parameters and returns a hashtable with keys `SubscriptionId`, `ServerUrl`,
  `BaseUri`, `WorkspaceResourceId`, `WorkspaceId`, `PlaybookRG`, and
  `AuthHeader`, which the caller assigns to its own script scope.
- **Government-cloud branching.** With `-IsGov`, login uses
  `-Environment AzureUSGovernment` and the ARM server URL becomes
  `https://management.usgovcloudapi.net` instead of
  `https://management.azure.com`; the derived `BaseUri` and
  `WorkspaceResourceId` follow.
- **Token acquisition with fallback.** It calls `Get-AzAccessToken` first
  (handling both the `SecureString` and plain-string token shapes), and if that
  cmdlet is restricted it falls back to acquiring a token from the profile
  client (`RMProfileClient.AcquireAccessToken`). The resulting bearer token is
  assembled into the returned `AuthHeader`.
- **Playbook RG validation.** When `-PlaybookResourceGroup` differs from
  `-ResourceGroup`, the function verifies the RG exists and throws a clear
  remediation message (create it via Bicep or the portal) if it does not.
- **Workspace ID lookup is non-fatal.** It calls `Invoke-SentinelApi` to fetch
  the workspace `customerId` (the GUID needed for playbook parameter
  injection); on failure it warns and returns `WorkspaceId = $null` rather than
  aborting the deploy.

## KQL dependency-discovery helpers

These six functions let the dependency-manifest tooling read a content file,
pull the KQL out of it, and discover what tables, functions, watchlists, and
external-data URLs the query depends on. They are regex-based approximations,
not a full KQL parser, but they cover every real-world rule pattern in the repo
(the fixtures live in
[`Tests/Test-SentinelCommon.Tests.ps1`](../../Tests/Test-SentinelCommon.Tests.ps1)).

### `Remove-KqlComments`

Strips `/* ... */` block comments and `// ...` line comments so a commented-out
`_GetWatchlist` or `externaldata` call cannot produce a false positive. The
line-comment regex uses a negative lookbehind `(?<!:)` so that the `//` in a URL
such as `https://foo.com` is not mistaken for a comment marker.

### `Get-KqlWatchlistReferences`

Returns the distinct, sorted list of watchlist aliases referenced via
`_GetWatchlist('alias')` or `_GetWatchlist("alias")`. Returns `@()` when there
are none. Comments are stripped first.

### `Get-KqlExternalDataReferences`

Returns the distinct, sorted list of URLs referenced inside an
`externaldata(...) [ ... ]` operator's bracket list. The bracket list can carry
several URLs and every one is captured.

### `Get-KqlBareIdentifiers`

The heart of the discovery layer. It extracts bare identifiers that sit where a
data source is expected, then aggressively filters out everything that is not a
real external reference. Identifiers are collected from several syntactic
positions:

1. The first identifier of each `;`-delimited statement (a table directly, or
   the right-hand side of a `let X = ...` binding).
2. After a `union` keyword (skipping `key=value` modifiers such as
   `kind=outer`).
3. The first identifier inside a `join` / `lookup` subquery.
4. The first identifier inside a `materialize()` / `view()` / `toscalar()`
   subquery.
5. Table names passed as string arguments to KQL's `table()` function,
   including the lambda-wrapper pattern
   `let f = (t: string) { table(t) }; f("SigninLogs")` and direct
   `table('X')` / `table("X")` literals.

Positions 4 and 5 are the two data-source-position patterns added in `1.1.1`;
without them four legitimate rules had no manifest entry. Before further
parsing, string literals are blanked out so identifiers and `;` characters
inside strings (for example `"Other clients; POP"`) are not mistaken for tokens
or statement separators. Candidates are then dropped if they are KQL
keywords / operators, function-call sites (any `name(` in the query), the
left-hand side of a `let` binding, a lambda parameter, or a single-character
name. The result is the distinct, sorted list of surviving identifiers.

### `Get-ContentKqlQuery`

Reads one content file and returns its embedded KQL string, or `$null` if the
file matches no known shape. It understands:

- YAML analytical rules, hunting queries, and parsers (`query:` field).
- Defender custom detections (`queryCondition.queryText`).
- JSON summary rules (`query` property).

Parse errors are swallowed and return `$null`; the per-file content-schema
Pester tests own schema validation.

### `Get-ContentDependencies`

The orchestrator. For a single content file it calls `Get-ContentKqlQuery`,
then runs the watchlist, external-data, and bare-identifier extractors, and
classifies every bare identifier:

- Identifiers in the caller-supplied `-KnownFunctions` hashtable (built from the
  repo's `Parsers/` folder) go into the **functions** bucket, because they must
  deploy before any rule that references them.
- Identifiers matching `-ExternalFunctionPattern` (default
  `'^(_?ASim|_Im_|im)\w+$'`, the Microsoft ASIM naming convention) also go into
  **functions**, listed for visibility even though they are external.
- Everything else at a data-source position goes into **tables** (the default),
  including custom-log `_CL` tables. Tables are data-plane and not deployable
  from the repo, so no hard-coded table catalogue is needed.

It returns a hashtable shaped like a `dependencies.json` entry, with keys
`tables`, `watchlists`, `functions`, and `externalData` (empty arrays for
absent buckets). There is deliberately no `unclassified` bucket: because the
bare-identifier extractor already filters let-bound names, lambda parameters,
keywords, and string literals, every remaining identifier is a genuine
data-source reference.

## Manifest discipline (version + release notes + Pester in lockstep)

Because the module is a shared dependency, its manifest is versioned carefully.
The `powershell-scripts` path-scoped Copilot instructions codify the routine for
adding a function; the same discipline applies to any behavioural change:

1. Add or change the function under the appropriate section of
   [`Sentinel.Common.psm1`](../../Modules/Sentinel.Common/Sentinel.Common.psm1).
2. Keep the `Export-ModuleMember -Function ...` list at the bottom of the
   `.psm1` and the `FunctionsToExport` list in the `.psd1` identical.
3. Bump `ModuleVersion` in the `.psd1` under SemVer rules: patch for a bug fix,
   minor for a new function, major for a breaking change. This is independent
   of whichever CalVer repository release it ships with.
4. Update `ReleaseNotes` in `PrivateData.PSData` to record what changed. The
   existing notes read as a running changelog (`1.0.0` initial extraction,
   `1.1.0` KQL discovery helpers, `1.1.1` the two extra `Get-KqlBareIdentifiers`
   patterns plus four new unit tests).
5. Add or extend Pester coverage in
   [`Tests/Test-SentinelCommon.Tests.ps1`](../../Tests/Test-SentinelCommon.Tests.ps1).
   Every public function gets a unit test; the module is one of the 22 Pester
   suites the PR-validation gate runs.

Version, release notes, and tests move together in the same change: a bump with
no release-note entry, or a new function with no test, is treated as an
incomplete change.

## Testing the module

`Sentinel.Common` is tested as a real imported module rather than via the
AST-extraction pattern the script tests use, because its functions live in a
`.psm1`. The suite imports the manifest with `-Force` and mocks Az cmdlets with
`Mock -ModuleName Sentinel.Common ...` so no live tenant is needed. It covers
the ADO / local branching in `Write-PipelineMessage`, the failure and
retry handling in `Invoke-SentinelApi`, the returned-state contract and
government-cloud branching of `Connect-AzureEnvironment`, and the KQL extractors
(including the `materialize()` and `table('X')` patterns). See
[Pester Tests](../Tests/Pester-Tests.md) for the mocking conventions and the full suite
inventory.

## Related documentation

- [PowerShell Module Requirements](../Deploy/PowerShell-Module-Requirements.md) - the
  runtime and permission dependencies, including `Az.Accounts` as the module's
  one hard requirement.
- [Dependency Manifest](../Tools/Dependency-Manifest.md) - how
  `Build-DependencyManifest.ps1` consumes the KQL discovery helpers.
- [Versioning](../Releases/Versioning.md) - how the module's SemVer relates to
  the repository CalVer.
- [GitHub Copilot](../GitHub/GitHub-Copilot.md) - the `powershell-engineer` and
  `dependencies-engineer` agents own this module and its extractors.
</content>
</invoke>
