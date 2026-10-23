# iSOCDeployments migration map

Where each script and function that `iSOCDeployments` replaces goes, and
every change made to the code on the way in. The module is being built
beside the scripts for release 26.11.0: a row appears in the pull request
that ports the code, the old script keeps running the pipelines until the
cut-over removes it, and `Tests/iSOCDeployments/Migration-Map.Tests.ps1`
holds this file to the repository in both directions.

The parameter mapping for each command lands with the pull request that
adds the command.

## How to read it

- **Scripts** lists every script or module the release replaces and its
  status: `Planned` (nothing ported yet), `In progress` (some functions
  ported), `Ported` (every function has a row; the script is still in the
  repository until cut-over), `Removed` (cut-over has deleted it) or
  `Unmerged` (the code lives on a branch, not on `main`).
- **Functions** has one row per old function and new file. One old
  function can feed several new files (a deployer loop split into a
  reader, a validator and a request builder), and several old copies can
  land in one file (the duplicated helpers). Each destination file defines
  exactly one function, named after the file.
- **Edits** lists every change in behaviour, however small, by the ID the
  function rows use. A row with `-` copies the code unchanged apart from
  the names of the helpers it calls.

## Scripts

| Source | Replaced by | Status |
| --- | --- | --- |
| `Modules/Sentinel.Common` | the private core: logging, the REST client, `Connect-iSOCWorkspace` and the KQL helpers | In progress |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-iSOCContent` | In progress |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `Deploy-iSOCContent -ContentType DefenderDetection` | Planned |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Get-iSOCContentHubSolution`, `Install-iSOCContentHubSolution` | In progress |
| `Tools/Test-SentinelRuleDrift.ps1` | `Compare-iSOCContent`, `Export-iSOCDriftReport`, `Sync-iSOCContent` | In progress |
| `Tools/Export-SentinelWorkbooks.ps1` | `Export-iSOCContent -ContentType Workbook` | Planned |
| `847ef86:Tools/Export-Playbooks.ps1` | `Export-iSOCContent -ContentType Playbook` | Unmerged |
| `Tools/Build-DependencyManifest.ps1` | `Update-iSOCDependencyManifest`, `Test-iSOCDependencyManifest`, `Get-iSOCContentDependency` | Planned |
| `Tools/Import-CommunityRules.ps1` | `Import-iSOCCommunityRule` | Planned |
| `Deploy/permissions/Set-PlaybookPermissions.ps1` | `Grant-iSOCPlaybookPermission` | Planned |
| `Deploy/permissions/Set-RunbookPermissions.ps1` | `Grant-iSOCRunbookPermission`, `Revoke-iSOCRunbookPermission` | Planned |
| `Deploy/setup/Setup-ServicePrincipal.ps1` | `Initialize-iSOCServicePrincipal` | Planned |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-iSOCTableMigrationImpact`, `Export-iSOCTableMigrationReport` | Planned |
| `Tools/ClassicToDcr/Invoke-ClassicTableMigration.ps1` | `Invoke-iSOCClassicTableMigration` | Planned |
| `Tools/ClassicToDcr/Rehearsal/New-ClassicTableFixture.ps1` | `New-iSOCClassicTableFixture`, `Remove-iSOCClassicTableFixture` | Planned |
| `Tools/ClassicToDcr/Rehearsal/New-DependencyFixture.ps1` | `New-iSOCDependencyFixture`, `Remove-iSOCDependencyFixture` | Planned |
| `Tools/ClassicToDcr/Rehearsal/Test-DcrIngestion.ps1` | `Test-iSOCDcrIngestion` | Planned |
| `Tools/DcrFromSchema/New-DcrFromSchema.ps1` | `New-iSOCDcrFromSchema` | Planned |

Out of scope, and staying as they are: `Tools/Invoke-DCRWatchlistSync.ps1`
(an Automation runbook), `Tools/Invoke-PRValidation.ps1`,
`Tools/Test-PullRequestTemplate.ps1` and `Tools/Migrate-ForkLayout.ps1`.
`Deploy/setup/Setup-SharePointPublisher.ps1` and
`Tools/New-BlueprintDemoWorkspace.ps1` belong to the iSOC Blueprint, a
separate module, and are not part of this map.

## Functions

| Source | Function | Destination | Edits | Notes |
| --- | --- | --- | --- | --- |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Write-PipelineMessage` | `Modules/iSOCDeployments/Private/Core/Write-iSOCLog.ps1` | E1 | Same levels and local output |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Write-PipelineMessage` | `Modules/iSOCDeployments/Private/Core/Get-iSOCPipelineHost.ps1` | E1 | The host test, on its own |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Invoke-SentinelApi` | `Modules/iSOCDeployments/Private/Rest/Invoke-iSOCRestRequest.ps1` | E3 | Through Invoke-AzRestMethod |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Invoke-SentinelApi` | `Modules/iSOCDeployments/Private/Rest/Get-iSOCRestRetryDelay.ps1` | E3 | Retry-After, else doubling |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Invoke-SentinelApi` | `Modules/iSOCDeployments/Private/Rest/Get-iSOCRestErrorDetail.ps1` | E3 | The error body as one line |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Connect-AzureEnvironment` | `Modules/iSOCDeployments/Public/Connect-iSOCWorkspace.ps1` | E2, E6, E7 | Returns a read-only context instead of a hashtable |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Connect-AzureEnvironment` | `Modules/iSOCDeployments/Private/Core/New-iSOCContext.ps1` | E6 | The context object |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Connect-AzureEnvironment` | `Modules/iSOCDeployments/Private/Az/Get-iSOCAzContext.ps1` | - | Get-AzContext |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Connect-AzureEnvironment` | `Modules/iSOCDeployments/Private/Az/Set-iSOCAzContext.ps1` | - | Set-AzContext |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Remove-KqlComments` | `Modules/iSOCDeployments/Private/Kql/Remove-iSOCKqlComment.ps1` | - | |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Get-KqlWatchlistReferences` | `Modules/iSOCDeployments/Private/Kql/Get-iSOCKqlWatchlistReference.ps1` | - | |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Get-KqlExternalDataReferences` | `Modules/iSOCDeployments/Private/Kql/Get-iSOCKqlExternalDataReference.ps1` | - | |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Get-KqlBareIdentifiers` | `Modules/iSOCDeployments/Private/Kql/Get-iSOCKqlBareIdentifier.ps1` | - | |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Get-ContentKqlQuery` | `Modules/iSOCDeployments/Private/Kql/Get-iSOCContentKqlQuery.ps1` | E4 | |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Get-ContentDependencies` | `Modules/iSOCDeployments/Private/Kql/Get-iSOCContentFileDependency.ps1` | - | Get-iSOCContentDependency is kept for the public command |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomDetections` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Read-iSOCAnalyticsRuleRepo.ps1` | E4, E5 | Reading the files |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomDetections` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Test-iSOCAnalyticsRule.ps1` | - | The required-field checks |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomDetections` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCAnalyticsRuleRequest.ps1` | - | The request body |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomDetections` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCTriggerOperator.ps1` | - | The operator map |
| `Tools/Test-SentinelRuleDrift.ps1` | `Get-RepoAnalyticsRuleYamls` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Read-iSOCAnalyticsRuleRepo.ps1` | E4, E5 | Keyed by the item's Identity instead of a hashtable of ids |
| `Tools/Test-SentinelRuleDrift.ps1` | `Convert-TriggerOperator` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCTriggerOperator.ps1` | - | |
| `Tools/Test-SentinelRuleDrift.ps1` | `ConvertTo-NormalisedDuration` | `Modules/iSOCDeployments/Private/Drift/ConvertTo-iSOCCanonicalDuration.ps1` | - | |
| `Tools/Test-SentinelRuleDrift.ps1` | `ConvertTo-YamlScalarString` | `Modules/iSOCDeployments/Private/Yaml/ConvertTo-iSOCYamlScalar.ps1` | - | |
| `Tools/Test-SentinelRuleDrift.ps1` | `ConvertTo-IndentedSubtreeYaml` | `Modules/iSOCDeployments/Private/Yaml/ConvertTo-iSOCYamlSubtree.ps1` | E4 | |
| `Tools/Test-SentinelRuleDrift.ps1` | `ConvertTo-ReportPath` | `Modules/iSOCDeployments/Private/Core/ConvertTo-iSOCRepoRelativePath.ps1` | - | |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `ConvertTo-NormalisedDuration` | `Modules/iSOCDeployments/Private/Drift/ConvertTo-iSOCCanonicalDuration.ps1` | - | The second copy |

## Edits

| ID | What changed | Why |
| --- | --- | --- |
| E1 | `Write-iSOCLog` writes GitHub Actions workflow commands (`::warning::`, `::error::`) for warnings and errors, and recognises Azure DevOps by `TF_BUILD` as well as `BUILD_BUILDID`. | On GitHub, `Write-PipelineMessage` wrote warnings and errors as plain text, so they were not annotated on the run. |
| E2 | `Connect-iSOCWorkspace` never signs in. It needs an Az sign-in made first (`Connect-AzAccount`, the AzurePowerShell task or `azure/login`) and says so when there is none; `Connect-AzureEnvironment` called `Connect-AzAccount` itself. | A sign-in prompt from inside a module, or a pipeline step, hangs or fails without saying why; the instruction is clearer. |
| E3 | Requests go through `Invoke-AzRestMethod`, so no bearer token is fetched or held. Failures are retried on 408, 429, 500, 502, 503, 504 and connection errors, up to five attempts, waiting as long as `Retry-After` says or else 5, 10, 20 and 40 seconds; `Invoke-SentinelApi` made three attempts five and ten seconds apart and ignored `Retry-After`. Collections are followed through `nextLink` and `@odata.nextLink`. Errors read `HTTP <status> from <METHOD> <last two path segments>: <code>: <message>`, with the service's detail messages, instead of `API call failed: HTTP <status> - <body>`. A write that reaches the client under `-WhatIf` throws. | One client for ARM and Graph that works in every cloud, keeps tokens out of variables, follows paging, waits as long as the service asks, and keeps subscription ids out of error text. The `-WhatIf` check makes a missed `ShouldProcess` fail a test instead of changing a workspace. |
| E4 | powershell-yaml is loaded when YAML is first read, and never installed; it must be 0.4.12 or later, and when it is missing the error names the install command. `Get-iSOCContentKqlQuery` loads it before it parses, where `Get-ContentKqlQuery` relied on the caller having loaded it and returned nothing when it had not. | A module should not install software into the session that imports it, and the pipelines pin 0.4.12. |
| E5 | A rule is a Community rule when `Community/` appears in its repository-relative path; the scripts matched the full path. | A clone that sits inside a folder called Community no longer marks every rule as Community. |
| E6 | `Connect-iSOCWorkspace` takes no `-Region` or `-IsGov`: the region is read from the workspace and the cloud, with its ARM and Graph hosts, from the Az sign-in. A workspace that cannot be found stops the command; `Connect-AzureEnvironment` warned and carried on with no workspace id. The context is read-only. | The values the pipelines passed could disagree with the workspace, and every later step needs the workspace to exist. |
| E7 | Nothing `Connect-iSOCWorkspace` logs names the subscription id or the workspace id. `Connect-AzureEnvironment` printed both. | Pipeline logs of a public repository are public. |
