# iSOCDeployments migration map

Where each script and function that `iSOCDeployments` replaces goes, and
every change made to the code on the way in. The module is being built
beside the scripts for release 26.11.0: a row appears in the pull request
that ports the code, the old script keeps running the pipelines until the
cut-over removes it, and `Tests/iSOCDeployments/Migration-Map.Tests.ps1`
holds this file to the repository in both directions.

The [Parameters](#parameters) table maps each ported script's parameters
to the command's.

## How to read it

- **Scripts** lists every script or module the release replaces and its
  status: `Planned` (nothing ported yet), `In progress` (some functions
  ported), `Ported` (every function has a row; the script is still in the
  repository until cut-over), `Removed` (cut-over has deleted it) or
  `Unmerged` (the code lives on a branch, not on `main`). An unmerged
  source is named by its commit; once it is ported, a byte-for-byte copy
  under `Tests/iSOCDeployments/Fixtures/legacy/` stands in for it, so the
  parity tests and this map can read it where the commit is not
  fetched.
- **Functions** has one row per old function and new file. One old
  function can feed several new files (a deployer loop split into a
  reader, a validator and a request builder), and several old copies can
  land in one file (the duplicated helpers). `(script)` stands for a
  script's top-level code, outside any function. Each destination file
  defines exactly one function, named after the file; `(not ported)`
  marks a function left behind, with the edit that says why.
- **Edits** lists every change in behaviour, however small, by the ID the
  function rows use. A row with `-` copies the code unchanged apart from
  the names of the helpers it calls.

## Scripts

| Source | Replaced by | Status |
| --- | --- | --- |
| `Modules/Sentinel.Common` | the private core: logging, the REST client, `Connect-iSOCWorkspace` and the KQL helpers | In progress |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-iSOCContent` | Ported |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `Deploy-iSOCContent -ContentType DefenderDetection` | Ported |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Get-iSOCContentHubSolution`, `Install-iSOCContentHubSolution` | Ported |
| `Tools/Test-SentinelRuleDrift.ps1` | `Compare-iSOCContent`, `Export-iSOCDriftReport`, `Sync-iSOCContent` | Ported |
| `Tools/Export-SentinelWorkbooks.ps1` | `Export-iSOCContent -ContentType Workbook` | Ported |
| `847ef86:Tools/Export-Playbooks.ps1` | `Export-iSOCContent -ContentType Playbook` | Ported |
| `Tools/Build-DependencyManifest.ps1` | `Update-iSOCDependencyManifest`, `Test-iSOCDependencyManifest`, `Get-iSOCContentDependency` | Ported |
| `Tools/Import-CommunityRules.ps1` | `Import-iSOCCommunityRule` | Ported |
| `Deploy/permissions/Set-PlaybookPermissions.ps1` | `Grant-iSOCPlaybookPermission` | Ported |
| `Deploy/permissions/Set-RunbookPermissions.ps1` | `Grant-iSOCRunbookPermission`, `Revoke-iSOCRunbookPermission` | Ported |
| `Deploy/setup/Setup-ServicePrincipal.ps1` | `Initialize-iSOCServicePrincipal` | Ported |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-iSOCTableMigrationImpact`, `Export-iSOCTableMigrationReport` | Ported |
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
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Connect-AzureEnvironment` | `Modules/iSOCDeployments/Private/Core/Get-iSOCAzSession.ps1` | E6 | The tenant, subscription and cloud hosts, shared with Initialize-iSOCServicePrincipal |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Connect-AzureEnvironment` | `Modules/iSOCDeployments/Private/Az/Set-iSOCAzContext.ps1` | - | Set-AzContext |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Remove-KqlComments` | `Modules/iSOCDeployments/Private/Kql/Remove-iSOCKqlComment.ps1` | - | |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Get-KqlWatchlistReferences` | `Modules/iSOCDeployments/Private/Kql/Get-iSOCKqlWatchlistReference.ps1` | - | |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Get-KqlExternalDataReferences` | `Modules/iSOCDeployments/Private/Kql/Get-iSOCKqlExternalDataReference.ps1` | - | |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Get-KqlBareIdentifiers` | `Modules/iSOCDeployments/Private/Kql/Get-iSOCKqlBareIdentifier.ps1` | - | |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Get-ContentKqlQuery` | `Modules/iSOCDeployments/Private/Kql/Get-iSOCContentKqlQuery.ps1` | E4 | |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Get-ContentDependencies` | `Modules/iSOCDeployments/Private/Kql/Get-iSOCQueryDependency.ps1` | - | The classification; reading the query is each type's GetQuery handler, or Get-iSOCContentKqlQuery for any file |
| `Modules/Sentinel.Common/Sentinel.Common.psm1` | `Get-ContentDependencies` | `Modules/iSOCDeployments/Public/Get-iSOCContentDependency.ps1` | - | For a file, with the known functions read from the repository's parsers |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomDetections` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Read-iSOCAnalyticsRuleRepo.ps1` | E4, E5 | Reading the files |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomDetections` | `Modules/iSOCDeployments/Private/ContentTypes/Read-iSOCYamlRepoItem.ps1` | E4, E5 | The YAML reader rules, hunting queries and parsers share |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomDetections` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Test-iSOCAnalyticsRule.ps1` | - | The required-field checks |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomDetections` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCAnalyticsRuleRequest.ps1` | - | The request body |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomDetections` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCTriggerOperator.ps1` | - | The operator map |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomParsers` | `Modules/iSOCDeployments/Private/ContentTypes/Parser/Read-iSOCParserRepo.ps1` | E4 | Reading the files |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomParsers` | `Modules/iSOCDeployments/Private/ContentTypes/Parser/Test-iSOCParser.ps1` | - | The required-field check |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomParsers` | `Modules/iSOCDeployments/Private/ContentTypes/Parser/ConvertTo-iSOCParserRequest.ps1` | - | The request body |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomWatchlists` | `Modules/iSOCDeployments/Private/ContentTypes/Watchlist/Read-iSOCWatchlistRepo.ps1` | - | One item per folder |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomWatchlists` | `Modules/iSOCDeployments/Private/ContentTypes/Watchlist/Test-iSOCWatchlist.ps1` | - | The file, field and size checks |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomWatchlists` | `Modules/iSOCDeployments/Private/ContentTypes/Watchlist/ConvertTo-iSOCWatchlistRequest.ps1` | E9 | The upload, rows inline |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomHuntingQueries` | `Modules/iSOCDeployments/Private/ContentTypes/HuntingQuery/Read-iSOCHuntingQueryRepo.ps1` | E4 | Reading the files |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomHuntingQueries` | `Modules/iSOCDeployments/Private/ContentTypes/HuntingQuery/Test-iSOCHuntingQuery.ps1` | - | The required-field check |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomHuntingQueries` | `Modules/iSOCDeployments/Private/ContentTypes/HuntingQuery/ConvertTo-iSOCHuntingQueryRequest.ps1` | - | The request body and its tags |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomPlaybooks` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Read-iSOCPlaybookRepo.ps1` | - | Which files are templates, and their names |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomPlaybooks` | `Modules/iSOCDeployments/Private/ContentTypes/Read-iSOCJsonRepoItem.ps1` | - | The JSON reader playbooks, automation rules and summary rules share |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomPlaybooks` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Test-iSOCPlaybook.ps1` | E9 | The ARM template check |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomPlaybooks` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/ConvertTo-iSOCPlaybookRequest.ps1` | - | The deployment parameters, and the ones filled in from the workspace |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomPlaybooks` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookOrder.ps1` | E15 | Modules first, in the order they call each other |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomPlaybooks` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Invoke-iSOCPlaybookDeploy.ps1` | E7, E14 | The deployment, or the validation under `-WhatIf` |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomPlaybooks` | `Modules/iSOCDeployments/Private/Az/New-iSOCAzResourceGroupDeployment.ps1` | - | New-AzResourceGroupDeployment |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomPlaybooks` | `Modules/iSOCDeployments/Private/Az/Test-iSOCAzResourceGroupDeployment.ps1` | E14 | Test-AzResourceGroupDeployment, without the deployment name |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomWorkbooks` | `Modules/iSOCDeployments/Private/ContentTypes/Workbook/Read-iSOCWorkbookRepo.ps1` | E16 | One item per folder, with its metadata |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomWorkbooks` | `Modules/iSOCDeployments/Private/ContentTypes/Workbook/Test-iSOCWorkbook.ps1` | E16 | The template check, and the metadata parse error |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomWorkbooks` | `Modules/iSOCDeployments/Private/ContentTypes/Workbook/ConvertTo-iSOCWorkbookRequest.ps1` | E16 | The request body, the derived workbookId and the ARM unwrapping |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomAutomationRules` | `Modules/iSOCDeployments/Private/ContentTypes/AutomationRule/Read-iSOCAutomationRuleRepo.ps1` | - | Reading the files |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomAutomationRules` | `Modules/iSOCDeployments/Private/ContentTypes/AutomationRule/Test-iSOCAutomationRule.ps1` | E9 | The required-field check |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomAutomationRules` | `Modules/iSOCDeployments/Private/ContentTypes/AutomationRule/ConvertTo-iSOCAutomationRuleRequest.ps1` | - | The request body |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomSummaryRules` | `Modules/iSOCDeployments/Private/ContentTypes/SummaryRule/Read-iSOCSummaryRuleRepo.ps1` | - | Reading the files |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomSummaryRules` | `Modules/iSOCDeployments/Private/ContentTypes/SummaryRule/Test-iSOCSummaryRule.ps1` | E9 | The field, bin size and table checks |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomSummaryRules` | `Modules/iSOCDeployments/Private/ContentTypes/SummaryRule/ConvertTo-iSOCSummaryRuleRequest.ps1` | E9 | The request body and its optional fields |
| `Deploy/content/Deploy-CustomContent.ps1` | `Initialize-SmartDeployment` | `Modules/iSOCDeployments/Private/Deploy/Get-iSOCDeploymentConfig.ps1` | E11 | Reading sentinel-deployment.config |
| `Deploy/content/Deploy-CustomContent.ps1` | `Initialize-SmartDeployment` | `Modules/iSOCDeployments/Private/Deploy/Get-iSOCChangedFile.ps1` | - | The git diff |
| `Deploy/content/Deploy-CustomContent.ps1` | `Test-ShouldDeployFile` | `Modules/iSOCDeployments/Private/Deploy/Test-iSOCShouldDeployItem.ps1` | E12 | Per item, with the reason |
| `Deploy/content/Deploy-CustomContent.ps1` | `Test-ShouldDeployFile` | `Modules/iSOCDeployments/Private/Deploy/Get-iSOCItemFile.ps1` | - | The files behind an item (a watchlist's two) |
| `Deploy/content/Deploy-CustomContent.ps1` | `Get-PrioritizedFiles` | `Modules/iSOCDeployments/Private/Deploy/Get-iSOCDeployOrder.ps1` | E15 | With the custom-before-Community order from Deploy-CustomDetections |
| `Deploy/content/Deploy-CustomContent.ps1` | `Initialize-DeploymentState` | `Modules/iSOCDeployments/Private/State/Read-iSOCDeploymentState.ps1` | E12 | |
| `Deploy/content/Deploy-CustomContent.ps1` | `Save-DeploymentState` | `Modules/iSOCDeployments/Private/State/Save-iSOCDeploymentState.ps1` | E12 | |
| `Deploy/content/Deploy-CustomContent.ps1` | `Set-DeploymentItemState` | `Modules/iSOCDeployments/Private/State/Set-iSOCDeploymentItemState.ps1` | - | |
| `Deploy/content/Deploy-CustomContent.ps1` | `Test-WasDeployedSuccessfully` | `Modules/iSOCDeployments/Private/State/Test-iSOCDeployedSuccessfully.ps1` | - | |
| `Deploy/content/Deploy-CustomContent.ps1` | `Initialize-DependencyGraph` | `Modules/iSOCDeployments/Private/Deploy/Read-iSOCDependencyGraph.ps1` | - | |
| `Deploy/content/Deploy-CustomContent.ps1` | `Invoke-PreFlightChecks` | `Modules/iSOCDeployments/Private/Deploy/Get-iSOCWorkspaceInventory.ps1` | E13 | |
| `Deploy/content/Deploy-CustomContent.ps1` | `Test-ContentDependencies` | `Modules/iSOCDeployments/Private/Deploy/Test-iSOCItemDependency.ps1` | E13 | |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomParsers` | `Modules/iSOCDeployments/Private/Deploy/Invoke-iSOCItemDeploy.ps1` | E12 | The per-item steps, shared by every type |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomWatchlists` | `Modules/iSOCDeployments/Private/Deploy/Invoke-iSOCItemDeploy.ps1` | E12 | The per-item steps, shared by every type |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomDetections` | `Modules/iSOCDeployments/Private/Deploy/Invoke-iSOCItemDeploy.ps1` | E12 | The per-item steps, shared by every type |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomHuntingQueries` | `Modules/iSOCDeployments/Private/Deploy/Invoke-iSOCItemDeploy.ps1` | E12 | The per-item steps, shared by every type |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomPlaybooks` | `Modules/iSOCDeployments/Private/Deploy/Invoke-iSOCItemDeploy.ps1` | E12 | The per-item steps, shared by every type |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomWorkbooks` | `Modules/iSOCDeployments/Private/Deploy/Invoke-iSOCItemDeploy.ps1` | E12 | The per-item steps, shared by every type |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomAutomationRules` | `Modules/iSOCDeployments/Private/Deploy/Invoke-iSOCItemDeploy.ps1` | E12 | The per-item steps, shared by every type |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomSummaryRules` | `Modules/iSOCDeployments/Private/Deploy/Invoke-iSOCItemDeploy.ps1` | E12 | The per-item steps, shared by every type |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomDetections` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Invoke-iSOCAnalyticsRuleDeploy.ps1` | - | The send, and the resend disabled after a KQL error |
| `Deploy/content/Deploy-CustomContent.ps1` | `Deploy-CustomParsers` | `Modules/iSOCDeployments/Private/Deploy/Send-iSOCContentRequest.ps1` | - | The PUT every type shares |
| `Deploy/content/Deploy-CustomContent.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Private/Core/Assert-iSOCPrerequisite.ps1` | E14 | A type's own prerequisites, checked only when it has items to deploy |
| `Deploy/content/Deploy-CustomContent.ps1` | `Write-DeploymentSummary` | `Modules/iSOCDeployments/Private/Deploy/Write-iSOCDeploySummary.ps1` | E12 | |
| `Deploy/content/Deploy-CustomContent.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Public/Deploy-iSOCContent.ps1` | E12 | The step sequence, as a loop over the content types |
| `Deploy/content/Deploy-CustomContent.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Deploy/New-iSOCDeployRun.ps1` | - | The script-scope state, now one object per call |
| `Deploy/content/Deploy-CustomContent.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Deploy/New-iSOCItemResult.ps1` | E12 | The counters, now one result per item |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `Invoke-GraphApi` | `Modules/iSOCDeployments/Private/Rest/Invoke-iSOCRestRequest.ps1` | E3 | With `-Api Graph` |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `Connect-GraphEnvironment` | `Modules/iSOCDeployments/Public/Connect-iSOCWorkspace.ps1` | E2, E6 | The Graph host comes from the Az sign-in; no token is fetched (E3) |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `Connect-GraphEnvironment` | `Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/Get-iSOCDefenderDetectionRuleId.ps1` | - | The US Government warning, logged when the rules are first read |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `Get-ExistingDetectionRules` | `Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/Get-iSOCDefenderDetectionRuleId.ps1` | E18 | Read once per run, under `-WhatIf` too, keyed by display name |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `Get-DetectionContract` | `Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/Get-iSOCDefenderDetectionContract.ps1` | - | Built on each call rather than kept in script scope |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `ConvertTo-DetectionColumnName` | `Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/ConvertTo-iSOCDefenderDetectionColumn.ps1` | - |  |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `ConvertTo-DetectionFrequency` | `Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/ConvertTo-iSOCDefenderDetectionFrequency.ps1` | - |  |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `ConvertTo-DetectionTactic` | `Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/ConvertTo-iSOCDefenderDetectionTactic.ps1` | - |  |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `ConvertTo-DetectionEntityMapping` | `Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/ConvertTo-iSOCDefenderDetectionEntityMapping.ps1` | - |  |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `ConvertTo-DetectionAutomatedAction` | `Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/ConvertTo-iSOCDefenderDetectionAutomatedAction.ps1` | - |  |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `ConvertFrom-LegacyDetectionRule` | `Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/ConvertFrom-iSOCLegacyDefenderDetection.ps1` | - |  |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `Test-DetectionRule` | `Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/Test-iSOCDefenderDetection.ps1` | - | Every problem on one line, as the deployer logged them |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `Get-DetectionMappedColumn` | `Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/Get-iSOCDefenderDetectionMappedColumn.ps1` | - |  |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `ConvertTo-GraphDetectionBody` | `Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/ConvertTo-iSOCDefenderDetectionRequest.ps1` | - | The request body, with the id when creating |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `Deploy-DefenderDetections` | `Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/Read-iSOCDefenderDetectionRepo.ps1` | E4, E17 | Reading the files, translated from the retired fields once |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `Deploy-DefenderDetections` | `Modules/iSOCDeployments/Private/ContentTypes/Read-iSOCYamlRepoItem.ps1` | E4, E5 | The YAML reader the YAML types share |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `Deploy-DefenderDetections` | `Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/Invoke-iSOCDefenderDetectionDeploy.ps1` | E17, E18 | Update by display name, or create with the file's id |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `Deploy-DefenderDetections` | `Modules/iSOCDeployments/Private/Deploy/Invoke-iSOCItemDeploy.ps1` | E15, E17 | The per-item steps, shared by every type |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `Write-DeploymentSummary` | `Modules/iSOCDeployments/Private/Deploy/Write-iSOCDeploySummary.ps1` | E12 |  |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Public/Deploy-iSOCContent.ps1` | E12, E17 | `-ContentType DefenderDetection` |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `(script)` | `Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/Get-iSOCDefenderDetectionDefinition.ps1` | - | The endpoint; the Graph version is `GraphSecurity` in `Get-iSOCApiVersion` |
| `Tools/Build-DependencyManifest.ps1` | `Build-Manifest` | `Modules/iSOCDeployments/Private/Manifest/New-iSOCDependencyManifest.ps1` | E8 | Walks the content types with the Dependencies capability |
| `Tools/Build-DependencyManifest.ps1` | `ConvertTo-OrderedManifestJson` | `Modules/iSOCDeployments/Private/Manifest/ConvertTo-iSOCManifestJson.ps1` | - | |
| `Tools/Build-DependencyManifest.ps1` | `Compare-Manifest` | `Modules/iSOCDeployments/Private/Manifest/Compare-iSOCDependencyManifest.ps1` | - | |
| `Tools/Build-DependencyManifest.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Manifest/Get-iSOCDependencyInventory.ps1` | E8 | The parser and watchlist inventory |
| `Tools/Build-DependencyManifest.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Manifest/Get-iSOCDependencyManifestState.ps1` | E10 | Discover, read and compare, shared by both commands |
| `Tools/Build-DependencyManifest.ps1` | `(script)` | `Modules/iSOCDeployments/Public/Test-iSOCDependencyManifest.ps1` | E10 | `-Mode Verify` |
| `Tools/Build-DependencyManifest.ps1` | `(script)` | `Modules/iSOCDeployments/Public/Update-iSOCDependencyManifest.ps1` | E10 | `-Mode Generate` and `-Mode Update` |
| `Tools/Build-DependencyManifest.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Core/Write-iSOCTextFile.ps1` | E10 | Writing the file |
| `Tools/Test-SentinelRuleDrift.ps1` | `Get-RepoAnalyticsRuleYamls` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Read-iSOCAnalyticsRuleRepo.ps1` | E4, E5 | Keyed by the item's Identity instead of a hashtable of ids |
| `Tools/Test-SentinelRuleDrift.ps1` | `Convert-TriggerOperator` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCTriggerOperator.ps1` | - | |
| `Tools/Test-SentinelRuleDrift.ps1` | `ConvertTo-NormalisedDuration` | `Modules/iSOCDeployments/Private/Drift/ConvertTo-iSOCCanonicalDuration.ps1` | - | |
| `Tools/Test-SentinelRuleDrift.ps1` | `ConvertTo-YamlScalarString` | `Modules/iSOCDeployments/Private/Yaml/ConvertTo-iSOCYamlScalar.ps1` | - | |
| `Tools/Test-SentinelRuleDrift.ps1` | `ConvertTo-IndentedSubtreeYaml` | `Modules/iSOCDeployments/Private/Yaml/ConvertTo-iSOCYamlSubtree.ps1` | E4 | |
| `Tools/Test-SentinelRuleDrift.ps1` | `ConvertTo-ReportPath` | `Modules/iSOCDeployments/Private/Core/ConvertTo-iSOCRepoRelativePath.ps1` | - | |
| `Tools/Test-SentinelRuleDrift.ps1` | `Get-ExistingAnalyticsRules` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Read-iSOCAnalyticsRuleWorkspace.ps1` | E3 | The ReadWorkspace handler |
| `Tools/Test-SentinelRuleDrift.ps1` | `Get-ContentHubAnalyticsRuleTemplates` | `Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubTemplate.ps1` | - | The template read Content Hub deployment uses |
| `Tools/Test-SentinelRuleDrift.ps1` | `Get-ContentHubSolutionLookup` | `Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubSolutionName.ps1` | - |  |
| `Tools/Test-SentinelRuleDrift.ps1` | `ConvertTo-ShortTriggerOperator` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCShortTriggerOperator.ps1` | - |  |
| `Tools/Test-SentinelRuleDrift.ps1` | `Convert-Severity` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCRuleSeverity.ps1` | - |  |
| `Tools/Test-SentinelRuleDrift.ps1` | `Convert-QueryWhitespace` | `Modules/iSOCDeployments/Private/Drift/Compare-iSOCFieldValue.ps1` | E22 | The Whitespace comparer |
| `Tools/Test-SentinelRuleDrift.ps1` | `ConvertTo-NormalisedYamlRule` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCAnalyticsRuleRequest.ps1` | E22 | A repository rule is compared as deploy sends it |
| `Tools/Test-SentinelRuleDrift.ps1` | `ConvertTo-NormalisedTemplateRule` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Get-iSOCAnalyticsRuleTemplateBody.ps1` | - | The same choice of resource |
| `Tools/Test-SentinelRuleDrift.ps1` | `ConvertTo-NormalisedDeployedRule` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCAnalyticsRuleComparable.ps1` | E22 | The ToComparable handler |
| `Tools/Test-SentinelRuleDrift.ps1` | `Update-RuleYamlFile` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Update-iSOCAnalyticsRuleYaml.ps1` | E22 | The UpdateRepoFile handler |
| `Tools/Test-SentinelRuleDrift.ps1` | `New-AbsorbedRuleYaml` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCAnalyticsRuleYaml.ps1` | - | The ToRepoFile handler |
| `Tools/Test-SentinelRuleDrift.ps1` | `ConvertTo-FileSlug` | `Modules/iSOCDeployments/Private/Core/ConvertTo-iSOCFileSlug.ps1` | - |  |
| `Tools/Test-SentinelRuleDrift.ps1` | `Save-AbsorbedRule` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Get-iSOCAnalyticsRuleRepoPath.ps1` | - | The GetRepoPath handler |
| `Tools/Test-SentinelRuleDrift.ps1` | `Save-AbsorbedRule` | `Modules/iSOCDeployments/Private/Drift/Save-iSOCRepoFile.ps1` | E24 | The write, only when the content changes |
| `Tools/Test-SentinelRuleDrift.ps1` | `Compare-SentinelRule` | `Modules/iSOCDeployments/Private/Drift/Compare-iSOCContentBody.ps1` | E22 | Field by field, with the content type's comparers |
| `Tools/Test-SentinelRuleDrift.ps1` | `Resolve-RuleSource` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Get-iSOCAnalyticsRuleSource.ps1` | E23 | The Classify handler |
| `Tools/Test-SentinelRuleDrift.ps1` | `Get-LineDiff` | `Modules/iSOCDeployments/Private/Drift/Get-iSOCLineDiff.ps1` | - |  |
| `Tools/Test-SentinelRuleDrift.ps1` | `Test-IsMultiLine` | `Modules/iSOCDeployments/Private/Drift/Test-iSOCMultiLineValue.ps1` | - |  |
| `Tools/Test-SentinelRuleDrift.ps1` | `Format-FieldBlock` | `Modules/iSOCDeployments/Private/Drift/Format-iSOCDriftFieldBlock.ps1` | - |  |
| `Tools/Test-SentinelRuleDrift.ps1` | `Write-DriftSummary` | `Modules/iSOCDeployments/Private/Drift/Write-iSOCDriftSummary.ps1` | - |  |
| `Tools/Test-SentinelRuleDrift.ps1` | `Write-DriftReport` | `Modules/iSOCDeployments/Private/Drift/ConvertTo-iSOCDriftMarkdown.ps1` | E24 | The Markdown |
| `Tools/Test-SentinelRuleDrift.ps1` | `Write-DriftReport` | `Modules/iSOCDeployments/Public/Export-iSOCDriftReport.ps1` | E24 | The files |
| `Tools/Test-SentinelRuleDrift.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Public/Compare-iSOCContent.ps1` | E2, E6, E23, E24 | Detection |
| `Tools/Test-SentinelRuleDrift.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Public/Sync-iSOCContent.ps1` | E24 | Absorption |
| `Tools/Test-SentinelRuleDrift.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Private/Drift/ConvertTo-iSOCDriftReport.ps1` | E24 | The report's shape |
| `Tools/Test-SentinelRuleDrift.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Get-iSOCAnalyticsRuleSource.ps1` | E23 | The managed, severity, deprecated and solution filters |
| `Tools/Test-SentinelRuleDrift.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Private/Drift/New-iSOCDriftRun.ps1` | - | The script-scope state, now one object per call |
| `Tools/Test-SentinelRuleDrift.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Private/Drift/New-iSOCDriftItem.ps1` | E24 | One item per workspace rule instead of the drifted and orphan lists |
| `Tools/Test-SentinelRuleDrift.ps1` | `(script)` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Get-iSOCAnalyticsRuleSource.ps1` | - | The Microsoft-managed rule kinds |
| `Tools/Export-SentinelWorkbooks.ps1` | `Remove-WorkspaceArmId` | `Modules/iSOCDeployments/Private/ContentTypes/Workbook/ConvertTo-iSOCPortableWorkbookJson.ps1` | - |  |
| `Tools/Export-SentinelWorkbooks.ps1` | `Remove-WorkspaceSuffix` | `Modules/iSOCDeployments/Private/ContentTypes/Workbook/Get-iSOCWorkbookDisplayName.ps1` | - |  |
| `Tools/Export-SentinelWorkbooks.ps1` | `ConvertTo-FolderName` | `Modules/iSOCDeployments/Private/ContentTypes/Workbook/ConvertTo-iSOCWorkbookFolderName.ps1` | - |  |
| `Tools/Export-SentinelWorkbooks.ps1` | `Format-WorkbookJson` | `Modules/iSOCDeployments/Private/ContentTypes/Workbook/ConvertTo-iSOCWorkbookFile.ps1` | E26 | To depth 100 |
| `Tools/Export-SentinelWorkbooks.ps1` | `Merge-WorkbookMetadata` | `Modules/iSOCDeployments/Private/ContentTypes/Workbook/Merge-iSOCWorkbookMetadata.ps1` | E26 |  |
| `Tools/Export-SentinelWorkbooks.ps1` | `Get-MetaValue` | `Modules/iSOCDeployments/Private/Core/Get-iSOCPropertyEntry.ps1` | E26 | A one-item list stays a list |
| `Tools/Export-SentinelWorkbooks.ps1` | `Write-WorkbookFolder` | `Modules/iSOCDeployments/Private/Export/Save-iSOCRepoItem.ps1` | E25, E26 | Each file written only when it changes |
| `Tools/Export-SentinelWorkbooks.ps1` | `(script)` | `Modules/iSOCDeployments/Public/Export-iSOCContent.ps1` | E2, E6, E25 |  |
| `Tools/Export-SentinelWorkbooks.ps1` | `(script)` | `Modules/iSOCDeployments/Private/ContentTypes/Workbook/Read-iSOCWorkbookWorkspace.ps1` | E25 | Every page |
| `Tools/Export-SentinelWorkbooks.ps1` | `(script)` | `Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubWorkbookLookup.ps1` | - | The Content Hub exclusion set |
| `Tools/Export-SentinelWorkbooks.ps1` | `(script)` | `Modules/iSOCDeployments/Private/ContentTypes/Workbook/Get-iSOCWorkbookSource.ps1` | E25 | The Content Hub, filter and content checks |
| `Tools/Export-SentinelWorkbooks.ps1` | `(script)` | `Modules/iSOCDeployments/Private/ContentTypes/Workbook/Get-iSOCWorkbookRepoPath.ps1` | - |  |
| `Tools/Export-SentinelWorkbooks.ps1` | `(script)` | `Modules/iSOCDeployments/Private/ContentTypes/Workbook/ConvertTo-iSOCWorkbookFile.ps1` | E26 | The two files |
| `Tools/Export-SentinelWorkbooks.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Export/Write-iSOCExportSummary.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Get-SafeProperty` | `Modules/iSOCDeployments/Private/Core/Get-iSOCPropertyValue.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Get-PropertyNames` | `Modules/iSOCDeployments/Private/Core/Get-iSOCPropertyEntry.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Get-TriggerCategory` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookCategory.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Get-PlaybookFileName` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookFileName.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Get-WorkflowEntities` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookEntity.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Get-WorkflowDescription` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookDescription.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Get-ApiConnectorDisplayName` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCApiConnectorDisplayName.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Get-ConnectionMap` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookConnectionMap.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Get-ManagedApiIdExpression` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCManagedApiIdExpression.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Build-ConnectionVariables` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookConnectionVariable.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Build-ConnectionResources` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookConnectionResource.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Build-ConnectionParameters` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookConnectionParameter.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Get-PortableContext` | `Modules/iSOCDeployments/Private/Export/Get-iSOCPortableContext.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `ConvertTo-ArmStringValue` | `Modules/iSOCDeployments/Private/Export/ConvertTo-iSOCArmStringValue.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `ConvertTo-PortableValue` | `Modules/iSOCDeployments/Private/Export/ConvertTo-iSOCPortableValue.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Find-PlaintextSecret` | `Modules/iSOCDeployments/Private/Export/Find-iSOCPlaintextSecret.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Find-PlaintextSecretInNode` | `Modules/iSOCDeployments/Private/Export/Find-iSOCPlaintextSecret.ps1` | - | The walk, one function with the search |
| `847ef86:Tools/Export-Playbooks.ps1` | `Build-ArmTemplate` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/ConvertTo-iSOCPlaybookTemplate.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Invoke-PlaybookExport` | `Modules/iSOCDeployments/Public/Export-iSOCContent.ps1` | E2, E6, E25 |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Invoke-PlaybookExport` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Read-iSOCPlaybookWorkspace.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Invoke-PlaybookExport` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookSource.ps1` | E25 | The existing-file and definition checks |
| `847ef86:Tools/Export-Playbooks.ps1` | `Invoke-PlaybookExport` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookRepoPath.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `Invoke-PlaybookExport` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/ConvertTo-iSOCPlaybookFile.ps1` | E27 | The secret warnings and the template text |
| `847ef86:Tools/Export-Playbooks.ps1` | `Invoke-PlaybookExport` | `Modules/iSOCDeployments/Private/Export/Write-iSOCExportSummary.ps1` | - |  |
| `847ef86:Tools/Export-Playbooks.ps1` | `(script)` | `Modules/iSOCDeployments/Public/Export-iSOCContent.ps1` | - | The parameters |
| `Tools/Import-CommunityRules.ps1` | `Write-Status` | `Modules/iSOCDeployments/Private/Core/Write-iSOCLog.ps1` | - |  |
| `Tools/Import-CommunityRules.ps1` | `Initialize-YamlModule` | `Modules/iSOCDeployments/Private/Yaml/Import-iSOCYamlModule.ps1` | E4 |  |
| `Tools/Import-CommunityRules.ps1` | `Get-FileHash256` | (not ported) | E31 |  |
| `Tools/Import-CommunityRules.ps1` | `Get-ContentHash256` | `Modules/iSOCDeployments/Private/Community/Get-iSOCTextHash.ps1` | - |  |
| `Tools/Import-CommunityRules.ps1` | `Format-TriggerOperator` | `Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCTriggerOperator.ps1` | E28 | The one map |
| `Tools/Import-CommunityRules.ps1` | `Merge-Tags` | `Modules/iSOCDeployments/Private/Community/Merge-iSOCCommunityTag.ps1` | - |  |
| `Tools/Import-CommunityRules.ps1` | `ConvertTo-Iso8601Duration` | `Modules/iSOCDeployments/Private/Community/ConvertTo-iSOCIsoDuration.ps1` | - |  |
| `Tools/Import-CommunityRules.ps1` | `Build-RuleYaml` | `Modules/iSOCDeployments/Private/Community/ConvertTo-iSOCCommunityRuleYaml.ps1` | E28 |  |
| `Tools/Import-CommunityRules.ps1` | `Import-YamlFile` | `Modules/iSOCDeployments/Private/Community/Read-iSOCCommunityYamlRule.ps1` | E28 |  |
| `Tools/Import-CommunityRules.ps1` | `ConvertFrom-ArmAlertRule` | `Modules/iSOCDeployments/Private/Community/ConvertFrom-iSOCArmAlertRule.ps1` | E31 |  |
| `Tools/Import-CommunityRules.ps1` | `Get-ArmRulesFromFolder` | `Modules/iSOCDeployments/Private/Community/Read-iSOCCommunityArmRule.ps1` | E28, E31 |  |
| `Tools/Import-CommunityRules.ps1` | `Write-OutputFile` | `Modules/iSOCDeployments/Private/Core/Write-iSOCTextFile.ps1` | E29 |  |
| `Tools/Import-CommunityRules.ps1` | `Get-RuleFileId` | `Modules/iSOCDeployments/Private/Community/Get-iSOCRuleFileId.ps1` | - |  |
| `Tools/Import-CommunityRules.ps1` | `Get-ReservedRuleId` | `Modules/iSOCDeployments/Private/Community/Get-iSOCReservedRuleId.ps1` | - |  |
| `Tools/Import-CommunityRules.ps1` | `New-CommunityRuleId` | `Modules/iSOCDeployments/Private/Community/New-iSOCCommunityRuleId.ps1` | - |  |
| `Tools/Import-CommunityRules.ps1` | `Resolve-CommunityRuleId` | `Modules/iSOCDeployments/Private/Community/Resolve-iSOCCommunityRuleId.ps1` | - |  |
| `Tools/Import-CommunityRules.ps1` | `Build-Readme` | `Modules/iSOCDeployments/Private/Community/ConvertTo-iSOCCommunityReadme.ps1` | E30 |  |
| `Tools/Import-CommunityRules.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Public/Import-iSOCCommunityRule.ps1` | E28, E29 |  |
| `Tools/Import-CommunityRules.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Private/Community/Get-iSOCCommunityCheckout.ps1` | E28 | The clone, or -SourcePath |
| `Tools/Import-CommunityRules.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Private/Git/Invoke-iSOCGit.ps1` | - | Every git call |
| `Tools/Import-CommunityRules.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Private/Community/Read-iSOCCommunityRuleSet.ps1` | E28 | The collection loops |
| `Tools/Import-CommunityRules.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Private/Community/New-iSOCCommunityResult.ps1` | E28 | One result per rule |
| `Tools/Import-CommunityRules.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Private/Community/Write-iSOCCommunityImportSummary.ps1` | - |  |
| `Tools/Import-CommunityRules.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Community/Get-iSOCCommunitySource.ps1` | E28 | The constants: attribution, tags, folder maps, README text |
| `Deploy/permissions/Set-PlaybookPermissions.ps1` | `Get-PlaybookRequiredRoles` | `Modules/iSOCDeployments/Private/Permissions/Get-iSOCPlaybookRequiredRole.ps1` | - | As the script has it from 1.0.2 |
| `Deploy/permissions/Set-PlaybookPermissions.ps1` | `Resolve-Scope` | `Modules/iSOCDeployments/Private/Permissions/Resolve-iSOCRoleScope.ps1` | - |  |
| `Deploy/permissions/Set-PlaybookPermissions.ps1` | `(script)` | `Modules/iSOCDeployments/Public/Grant-iSOCPlaybookPermission.ps1` | E2, E32 |  |
| `Deploy/permissions/Set-PlaybookPermissions.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Permissions/Get-iSOCRoleDefinitionId.ps1` | - | $RoleDefinitions |
| `Deploy/permissions/Set-PlaybookPermissions.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Permissions/Get-iSOCRoleAssignment.ps1` | E32 | Get-AzRoleAssignment |
| `Deploy/permissions/Set-PlaybookPermissions.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Permissions/Find-iSOCRoleAssignment.ps1` | - | The already-assigned check, as the script has it from 1.0.2 |
| `Deploy/permissions/Set-PlaybookPermissions.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Permissions/New-iSOCRoleAssignment.ps1` | E32 | New-AzRoleAssignment |
| `Deploy/permissions/Set-PlaybookPermissions.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Permissions/Get-iSOCManagedIdentityPrincipal.ps1` | - | The identity checks |
| `Deploy/permissions/Set-PlaybookPermissions.ps1` | `(script)` | `Modules/iSOCDeployments/Private/ContentTypes/Playbook/Read-iSOCPlaybookWorkspace.ps1` | E32 | Get-AzResource |
| `Deploy/permissions/Set-PlaybookPermissions.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Permissions/New-iSOCPermissionResult.ps1` | E32 | One result per role |
| `Deploy/permissions/Set-PlaybookPermissions.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Permissions/New-iSOCPermissionRun.ps1` | E32 | The summary |
| `Deploy/permissions/Set-RunbookPermissions.ps1` | `(script)` | `Modules/iSOCDeployments/Public/Grant-iSOCRunbookPermission.ps1` | E2, E33 | Without -Remove |
| `Deploy/permissions/Set-RunbookPermissions.ps1` | `(script)` | `Modules/iSOCDeployments/Public/Revoke-iSOCRunbookPermission.ps1` | E33 | With -Remove |
| `Deploy/permissions/Set-RunbookPermissions.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Permissions/Get-iSOCRunbookRole.ps1` | - | $roles |
| `Deploy/permissions/Set-RunbookPermissions.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Permissions/Get-iSOCAutomationPrincipal.ps1` | E33 | az automation account show |
| `Deploy/permissions/Set-RunbookPermissions.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Permissions/Remove-iSOCRoleAssignment.ps1` | E33 | az role assignment delete |
| `Deploy/permissions/Set-RunbookPermissions.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Core/ConvertTo-iSOCNameBasedGuid.ps1` | E32 | The assignment names |
| `Deploy/setup/Setup-ServicePrincipal.ps1` | `(script)` | `Modules/iSOCDeployments/Public/Initialize-iSOCServicePrincipal.ps1` | E2, E34 |  |
| `Deploy/setup/Setup-ServicePrincipal.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Permissions/Get-iSOCServicePrincipalSetup.ps1` | - | The role ids, the ABAC condition and the summary |
| `Deploy/setup/Setup-ServicePrincipal.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Core/Get-iSOCAzSession.ps1` | - | Get-AzContext and Set-AzContext |
| `Deploy/setup/Setup-ServicePrincipal.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Permissions/Find-iSOCRoleAssignment.ps1` | - | Get-AzRoleAssignment |
| `Deploy/setup/Setup-ServicePrincipal.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Permissions/New-iSOCRoleAssignment.ps1` | E34 | New-AzRoleAssignment, with the condition |
| `Deploy/setup/Setup-ServicePrincipal.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Graph/Connect-iSOCGraphSession.ps1` | E34 | Connect-MgGraph |
| `Deploy/setup/Setup-ServicePrincipal.ps1` | `(script)` | `Modules/iSOCDeployments/Private/Graph/Invoke-iSOCGraphRequest.ps1` | E34 | The Get-Mg and New-Mg cmdlets |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `ConvertTo-NormalisedDuration` | `Modules/iSOCDeployments/Private/Drift/ConvertTo-iSOCCanonicalDuration.ps1` | - | The second copy |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Compare-SemanticVersion` | `Modules/iSOCDeployments/Private/ContentHub/Compare-iSOCSemanticVersion.ps1` | - |  |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `ConvertTo-ArmTemplate` | `(not ported)` | E21 | Nothing called it |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Get-ContentHubSolutions` | `Modules/iSOCDeployments/Private/ContentHub/Wait-iSOCWorkspaceOnboarding.ps1` | - | The onboarding wait |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Get-ContentHubSolutions` | `Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubCatalogue.ps1` | E20 | The catalogue and the installed packages |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Get-SolutionStatus` | `Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubSolutionStatus.ps1` | - |  |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `ConvertTo-SolutionDeploymentJson` | `Modules/iSOCDeployments/Private/ContentHub/ConvertTo-iSOCSolutionDeploymentJson.ps1` | - |  |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Deploy-Solution` | `Modules/iSOCDeployments/Private/ContentHub/Invoke-iSOCContentHubSolutionDeploy.ps1` | E19 | An outcome instead of true or false |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Get-ExistingAnalyticsRules` | `Modules/iSOCDeployments/Private/ContentHub/Invoke-iSOCContentHubRuleDeploy.ps1` | E3 | One paged read through the REST client |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Test-RuleIsCustomised` | `Modules/iSOCDeployments/Private/ContentHub/Test-iSOCContentHubRuleCustomised.ps1` | - |  |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Write-RuleMetadata` | `Modules/iSOCDeployments/Private/ContentHub/Set-iSOCContentHubRuleMetadata.ps1` | E7, E19 | Nothing written under `-WhatIf` |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Deploy-AnalyticsRules` | `Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubTemplate.ps1` | - | The template read |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Deploy-AnalyticsRules` | `Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubSolutionLookup.ps1` | - | The solution lookups |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Deploy-AnalyticsRules` | `Modules/iSOCDeployments/Private/ContentHub/Read-iSOCContentHubRuleTemplate.ps1` | - | The rule in a template |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Deploy-AnalyticsRules` | `Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubRuleAction.ps1` | - | Create, update, unchanged or protected |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Deploy-AnalyticsRules` | `Modules/iSOCDeployments/Private/ContentHub/ConvertTo-iSOCContentHubRuleRequest.ps1` | - | The rule body, without changing the template |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Deploy-AnalyticsRules` | `Modules/iSOCDeployments/Private/ContentHub/Invoke-iSOCContentHubRuleDeploy.ps1` | E19 | The loop, the send, the NRT recreation and the error classes |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Deploy-AnalyticsRules` | `Modules/iSOCDeployments/Private/ContentHub/New-iSOCContentHubResult.ps1` | E19 | The counters, now one result per item |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Deploy-Workbooks` | `Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubTemplate.ps1` | - | The template read |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Deploy-Workbooks` | `Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubSolutionLookup.ps1` | - | The solution lookup |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Deploy-Workbooks` | `Modules/iSOCDeployments/Private/ContentHub/ConvertTo-iSOCContentHubWorkbookRequest.ps1` | - | The workbook and metadata bodies |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Deploy-Workbooks` | `Modules/iSOCDeployments/Private/ContentHub/Invoke-iSOCContentHubWorkbookDeploy.ps1` | E19 | The loop and the saves |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Get-AutomationRuleStatus` | `Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubTemplateCount.ps1` | E20 | One count for both kinds |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Get-AutomationRuleStatus` | `Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubTemplate.ps1` | E20 | The template read |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Get-HuntingQueryStatus` | `Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubTemplateCount.ps1` | E20 | One count for both kinds |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Get-HuntingQueryStatus` | `Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubTemplate.ps1` | E20 | The template read |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Get-SolutionUpdateReport` | `Modules/iSOCDeployments/Private/ContentHub/Write-iSOCContentHubSolutionReport.ps1` | - |  |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Public/Install-iSOCContentHubSolution.ps1` | E2, E6, E19 | The phases |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Public/Get-iSOCContentHubSolution.ps1` | - | The solution assessment, as a command of its own |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `Invoke-Main` | `Modules/iSOCDeployments/Private/ContentHub/Write-iSOCContentHubSummary.ps1` | E19 | The summary and the exit code |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Write-Console` | `Modules/iSOCDeployments/Private/Core/Write-iSOCLog.ps1` | E35 | The one place it wrote |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Write-Step` | `Modules/iSOCDeployments/Private/Core/Write-iSOCLog.ps1` | E35 | Level Section |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Write-Info` | `Modules/iSOCDeployments/Private/Core/Write-iSOCLog.ps1` | E35 |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Write-Ok` | `Modules/iSOCDeployments/Private/Core/Write-iSOCLog.ps1` | E35 | Level Success |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Write-Warn2` | `Modules/iSOCDeployments/Private/Core/Write-iSOCLog.ps1` | E35 | Level Warning |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Write-Err` | `Modules/iSOCDeployments/Private/Core/Write-iSOCLog.ps1` | E35 | A failure throws instead |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Read-Required` | `Modules/iSOCDeployments/Private/Core/Resolve-iSOCContext.ps1` | E35 | The workspace comes from the context; nothing prompts |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Initialize-AzContext` | `Modules/iSOCDeployments/Private/Core/Resolve-iSOCContext.ps1` | E2, E6, E7 | Connect-iSOCWorkspace first |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-ArmToken` | `Modules/iSOCDeployments/Private/Rest/Invoke-iSOCRestRequest.ps1` | E3 | No token is held |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Invoke-ArmRequest` | `Modules/iSOCDeployments/Private/Rest/Invoke-iSOCRestRequest.ps1` | E3, E35 | GET with paging |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-WorkspaceTableInventory` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCWorkspaceTableInventory.ps1` | E35 |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-ClassicCustomLogTable` | `(not ported)` | E36 | Nothing in the run called it |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-WorkspaceContent` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Read-iSOCTableMigrationContent.ps1` | E35 | Workbooks with their content, as 0.2.2 |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Test-KqlReferencesTable` | `Modules/iSOCDeployments/Private/Kql/Test-iSOCKqlTableReference.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-MatchedTable` | `(not ported)` | E36 | Nothing in the run called it |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-WorkbookQueryText` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCWorkbookQueryText.ps1` | - | A local list instead of a script variable |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-ReservedAliasName` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCReservedAliasName.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-FunctionAliasSafety` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCFunctionAliasSafety.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Test-SafeFunctionAlias` | `(not ported)` | E36 | Nothing in the run called it |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Expand-KqlQuotedIdentifier` | `Modules/iSOCDeployments/Private/Kql/Expand-iSOCKqlQuotedIdentifier.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-KqlCodeText` | `Modules/iSOCDeployments/Private/Kql/Get-iSOCKqlCodeText.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `ConvertTo-KqlNameSearchText` | `Modules/iSOCDeployments/Private/Kql/ConvertTo-iSOCKqlNameSearchText.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-KqlLetBoundName` | `Modules/iSOCDeployments/Private/Kql/Get-iSOCKqlLetBoundName.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-KqlIdentifierSet` | `(not ported)` | E36 | Nothing in the run called it |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-KqlReferenceIdentifierSet` | `Modules/iSOCDeployments/Private/Kql/Get-iSOCKqlReferenceIdentifierSet.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-PlaybookKqlText` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCPlaybookKqlText.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-ParserAliasIndex` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCParserAliasIndex.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Resolve-IndirectTableImpact` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Resolve-iSOCIndirectTableImpact.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-TableImpactAnalysis` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCTableImpactAnalysis.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-ContentHubPackage` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Read-iSOCContentHubPackage.ps1` | E35 |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-SolutionMapping` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCSolutionMapping.ps1` | E35 | The module's own copy |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Resolve-ConnectorKind` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Resolve-iSOCConnectorKind.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-SolutionMatchForTable` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCSolutionMatch.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Get-ConnectorClassification` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCConnectorClassification.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Export-ReportCsv` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Write-iSOCTableMigrationCsv.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Export-ReportJson` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Write-iSOCTableMigrationJson.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `ConvertTo-JsStringLiteral` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/ConvertTo-iSOCJsStringLiteral.ps1` | - |  |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `Export-ReportHtml` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Write-iSOCTableMigrationHtml.ps1` | E35 | The module's own template |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `(script)` | `Modules/iSOCDeployments/Public/Get-iSOCTableMigrationImpact.ps1` | E2, E6, E7, E35 | Steps 1 to 3 |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `(script)` | `Modules/iSOCDeployments/Public/Export-iSOCTableMigrationReport.ps1` | E35 | The export |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `(script)` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Write-iSOCTableMigrationFinding.ps1` | E35 | What step 2 found |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `(script)` | `Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/New-iSOCTableMigrationReview.ps1` | E35 | The review it returned |

## Edits

| ID | What changed | Why |
| --- | --- | --- |
| E1 | `Write-iSOCLog` writes GitHub Actions workflow commands (`::warning::`, `::error::`) for warnings and errors, and recognises Azure DevOps by `TF_BUILD` as well as `BUILD_BUILDID`. | On GitHub, `Write-PipelineMessage` wrote warnings and errors as plain text, so they were not annotated on the run. |
| E2 | `Connect-iSOCWorkspace` never signs in. It needs an Az sign-in made first (`Connect-AzAccount`, the AzurePowerShell task or `azure/login`) and says so when there is none; `Connect-AzureEnvironment` called `Connect-AzAccount` itself. Nor does it call `Update-AzConfig`, which `Connect-AzureEnvironment` and the Defender script's `Connect-GraphEnvironment` ran to hide Az breaking-change warnings. | A sign-in prompt from inside a module, or a pipeline step, hangs or fails without saying why; the instruction is clearer. `Update-AzConfig` writes the user's Az configuration file, which a module should not change to quiet its own output. |
| E3 | Requests go through `Invoke-AzRestMethod`, so no bearer token is fetched or held. Failures are retried on 408, 429, 500, 502, 503, 504 and connection errors, up to five attempts, waiting as long as `Retry-After` says or else 5, 10, 20 and 40 seconds; `Invoke-SentinelApi` made three attempts five and ten seconds apart and ignored `Retry-After`. Collections are followed through `nextLink` and `@odata.nextLink`. Errors read `HTTP <status> from <METHOD> <last two path segments>: <code>: <message>`, with the service's detail messages, instead of `API call failed: HTTP <status> - <body>`. A write that reaches the client under `-WhatIf` throws. | One client for ARM and Graph that works in every cloud, keeps tokens out of variables, follows paging, waits as long as the service asks, and keeps subscription ids out of error text. The `-WhatIf` check makes a missed `ShouldProcess` fail a test instead of changing a workspace. |
| E4 | powershell-yaml is loaded when YAML is first read, and never installed; it must be 0.4.12 or later, and when it is missing the error names the install command. `Get-iSOCContentKqlQuery` loads it before it parses, where `Get-ContentKqlQuery` relied on the caller having loaded it and returned nothing when it had not. | A module should not install software into the session that imports it, and the pipelines pin 0.4.12. |
| E5 | A rule is a Community rule when `Community/` appears in its repository-relative path; the scripts matched the full path. | A clone that sits inside a folder called Community no longer marks every rule as Community. |
| E6 | `Connect-iSOCWorkspace` takes no `-Region` or `-IsGov`: the region is read from the workspace and the cloud, with its ARM and Graph hosts, from the Az sign-in. A workspace that cannot be found stops the command; `Connect-AzureEnvironment` warned and carried on with no workspace id. The context is read-only. | The values the pipelines passed could disagree with the workspace, and every later step needs the workspace to exist. |
| E7 | Nothing `Connect-iSOCWorkspace` logs names the subscription id or the workspace id. `Connect-AzureEnvironment` printed both. | Pipeline logs of a public repository are public. |
| E8 | The dependency manifest reads its content through the content type registry: every type with the Dependencies capability (analytics rules and hunting queries, as before), parsers for the function inventory and watchlists for the watchlist inventory. So `.yml` files count as well as `.yaml`, and the watchlists are the folders deploy reads, directly under `Content/Watchlists/`, where the script searched for `watchlist.json` at any depth; the repository has neither a `.yml` file nor a nested watchlist today, so the manifest is the same. The playbook inventory the script built and never used, and its log line, are gone. | The manifest and deploy must agree about what content there is. |
| E9 | A field the deployer read without checking for it no longer fails the item under strict mode, where the script threw reading the missing property and counted the item failed. A `watchlist.json` without a `description` or `provider` is uploaded with the defaults the code meant (an empty description, provider Custom). An automation rule or summary rule missing a required field, and a playbook file with no `$schema`, are skipped with the message the script meant to log. A summary rule without a `displayName` is sent without one, and a playbook template without `parameters` has none filled in. Every file in the repository has these fields, so nothing deployed from it changes. | The defaults and messages were the intent; failing an item over a field the code already checked for was not. |
| E10 | `-Mode Generate` and `-Mode Update` become `Update-iSOCDependencyManifest`, which writes only when an entry differs or the file is missing, always as UTF-8 without a byte order mark, with LF line endings and one final newline, entries in invariant-culture, case-insensitive path order (the order the script's sort produced). `-Mode Verify` becomes `Test-iSOCDependencyManifest`, which returns HasDrift instead of exiting 1. Missing watchlists are one warning line each, naming what reads them. The file's description still names the script until cut-over, so both write the same bytes meanwhile. | A module command never exits; the pipeline step decides what drift means. A write that changes nothing, or rewrites line endings on Windows, would make noise in PRs. |
| E11 | `sentinel-deployment.config` is read from the repository root first, then from `Deploy/content/`, where the script read it from beside itself. | The file moves to the root at cut-over, when `Deploy/` goes; `Migrate-ForkLayout.ps1` moves a fork's. |
| E12 | Deploy changes in how it reports and what `-WhatIf` touches, not in what it sends. Under `-WhatIf` nothing is written: no request, as before, and no `deployment-state.json`, which the script saved (and created) under its `-WhatIf` switch too; items count as Would deploy, not Deployed. The state a build artifact left in `deployment-state/` is read where it is instead of copied to the root first. An item that `sentinel-deployment.config` excludes is reported as excluded, where the script logged it as unchanged. A watchlist over the 3.5 MB inline limit is skipped without being recorded as deployed, so a smart deployment reports it each run until it is uploaded by hand; the script recorded it as deployed. Messages name an item's repository-relative path, not only its file name. The script's switches map to parameters as the [Parameters](#parameters) table shows, and the run returns a result with `ExitCode` instead of exiting 1. | One engine for every content type, a dry run that is really dry, and a log that says why each item did or did not deploy. |
| E13 | Two faults in the pre-flight checks are fixed. The stale-state check counted state entries starting `AnalyticalRules/`, which none has had since content moved under `Content/`, so a rebuilt workspace never reset the state; it now counts `Content/AnalyticalRules/`. And when the workspace's watchlists or functions could not be listed, the script said those checks would be skipped but then reported every such dependency missing; a list that cannot be read now skips the checks that need it, as the message says. | Both were bugs: the first left smart deployment skipping rules a rebuilt workspace no longer had, and the second deployed rules disabled, or skipped hunting queries, over a failed list request. |

| E14 | Playbooks: under `-WhatIf` a template is validated with `Test-AzResourceGroupDeployment` and no deployment name. The script passed its `-Name` to the validation too, which that cmdlet has no parameter for, so every template's validation failed with "A parameter cannot be found that matches parameter name 'Name'" and nothing was validated (`Tests/iSOCDeployments/Playbook.Tests.ps1` shows it for every template in the repository). Errors the validation returns, rather than throws, are reported as a failed validation too. Az.Resources is checked for before anything deploys, and only when there are playbooks to deploy; the script needed it on every run. The parameters filled in from the workspace are logged by name, not value (as E7). | A dry run that validated nothing was reported as a validation failure for every playbook; and a fork without playbooks should not need a module it never calls. |
| E15 | Every content type deploys in ordinal repository-path order, with the items `sentinel-deployment.config` prioritises first and Community items last. The script ordered parsers, rules and hunting queries that way and took watchlists, workbooks, automation rules and summary rules, and `Deploy-DefenderDetections.ps1` its detections, in the order the file system listed them. Playbooks keep their own order: modules first, each after the modules it calls, then the rest in repository order; the script began its sort from a hashtable, so modules that do not call each other came out in no fixed order, and here they keep repository order. The missing-module warnings follow the same order. | The same repository deploys in the same order on every machine and every run, so two runs' logs can be compared. |
| E16 | Workbooks: when `metadata.json` has no `displayName`, the folder name is split only where a capital follows a small letter (`ArmWrapped` becomes `Arm Wrapped`); the script's `-replace` ignored case and split between every pair of letters (`A rm Wr ap pe d`). A `metadata.json` that does not parse fails the workbook before its dependencies are checked, where the script checked them first. Every workbook in the repository sets a `displayName`, so nothing deployed from it changes; a fork's workbook without one keeps its workbookId and is renamed in place. | The split was meant to space out a PascalCase folder name. |
| E17 | Defender XDR custom detections deploy through the engine every content type shares, so `sentinel-deployment.config` exclusions and priorities, `-Exclude`, `-SmartDeployment` and `deployment-state.json` now apply to them; `Deploy-DefenderDetections.ps1` sent every file on every run and recorded nothing. They need a connected workspace (`Connect-iSOCWorkspace`), where the script needed only an Az sign-in, and the Graph host comes from the sign-in's environment instead of `-IsGov`. A file that does not parse, holds no YAML mapping, or uses retired fields the converters cannot place fails, as before, with a message saying which; a file that fails validation is skipped with every problem on one line, as before. The warning about retired fields is logged as the rule is sent, after validation, where the script logged it before validating, so a file that fails validation is reported by its problems alone. Messages name the repository-relative path, not only the file name. | One engine and one set of controls for every content type: a fork can hold detections back, or deploy only what changed, as it can rules. |
| E18 | Under `-WhatIf` the tenant's custom detection rules are read, so the dry run says which rules it would update and which it would create, and reports a new rule whose file has no `id` as one a real run would fail (outcome WhatIf, with that reason). The script read nothing under its `-WhatIf` switch and counted every rule as created. The rules are still read once per run. | A dry run should read what a real run reads (E12), and whether a rule is updated or created is the decision most worth seeing before a real run. |
| E19 | Content Hub runs report one result per solution and template, with its reason (`Deployed`, `Updated`, `Unchanged`, `Protected`, `Deprecated`, `WhatIf`, `Skipped` or `Failed`), where the script kept counters per kind; the automation rules and hunting queries the solutions ship, which the script's summary counted as deployed, are reported as available. Under `-WhatIf` nothing is written: the script wrote the solution metadata of every unchanged analytics rule even under its `-WhatIf` switch, and counted what it would deploy as deployed. The one-minute wait for templates to propagate happens only after a solution was installed or updated in the run; the script waited before every rule pass, dry runs and runs that installed nothing included. The Azure DevOps variables `SentinelDeploymentFailed` and `SentinelCustomisedRulesSkipped`, which no pipeline reads, are no longer set, and the run returns `ExitCode` instead of exiting 1. A refused rule is classified on its status and the service's message: the REST client's error also names the rule's path, and a new rule's GUID can contain 400, which would read as a bad request. A failed metadata write logs its body at debug level and not its URL (as E7). A rule whose PUT answer has no id is linked by its ARM path, where the script built a URL with the host and a slash before it. Workbooks are saved through the REST client, so any 2xx answer counts as saved, not only 200 and 201. The rule body no longer changes the template it is built from. The script's parameters map as the [Parameters](#parameters) table shows. | Item outcomes are what a run on a Microsoft ISOC workspace needs, where Content Hub installs only a solution's data connectors in the preview; a dry run should write nothing; and a minute's wait that changes nothing is a minute of every pipeline run. |
| E20 | The Content Hub catalogue, the installed packages, and the automation rule and hunting query templates are read through every page; the script read the first page of each, and followed `nextLink` only for analytics rule and workbook templates and for analytics rules. A solution on a later page of the catalogue was reported not found, and the template counts could be short. | One REST client that always pages (E3). |
| E21 | `ConvertTo-ArmTemplate` is not ported: nothing in `Deploy-SentinelContentHub.ps1` called it. | Dead code. |
| E22 | Drift compares what deploy would send. A repository rule is compared as `ConvertTo-iSOCAnalyticsRuleRequest` builds it, a Content Hub rule as its template's rule resource, and the workspace rule as the API returns it, field by field with the comparers the analytics rule type names: the query ignores whitespace but not case, and the display name is compared exactly, where the script compared both ignoring case; kind is compared too; the schedule and trigger are compared for Scheduled rules only, as the script did for NRT rules. A repository rule file that does not validate is skipped, where the script compared whatever fields it had. The differences carry each side's values as they are, not the normalised forms the script compared: a query edited in the portal is written into the YAML with its line breaks, where the script wrote it as one whitespace-collapsed line, and the report shows both queries in full with a line diff. The YAML rewrite replaces values literally (a `$` in a query is kept) and keeps a CRLF file's line endings, where the script's name and severity patterns took the line's carriage return with them. | Deploy, compare and sync then agree on what a rule is; a change of case in KQL is a real change; and absorbing a portal edit should not destroy the query's layout. |
| E23 | The repository's rules and the Content Hub templates are always read, and a source left out with `-ExcludeSource` has its rules reported as Skipped. The script read no rule files under `-SkipCustom` and no templates under `-SkipContentHub`, so those rules were classed as orphans and, without `-ReportOnly`, exported again as new orphan YAML files: under `-SkipCustom`, every rule in the repository (`Tests/iSOCDeployments/Drift.Tests.ps1` shows both). | Leaving a source out should leave its rules alone, not duplicate them. |
| E24 | Detecting, absorbing and reporting are three commands. `Compare-iSOCContent` returns the result: one item per workspace rule with its state (InSync, PortalEdit, ContentHubCustomised, PortalOnly, Managed or Skipped) and the reason. `Sync-iSOCContent` absorbs it, which the script did unless `-ReportOnly`; `Export-iSOCDriftReport` writes the same `reports/sentinel-drift-<UTC>.json` and `.md` files, and only when something drifted, as before. The report names each rule by its name and leaves out the full resource id the script wrote as `ruleId`, which holds the subscription id. The Markdown says what was done: the script headed its Custom section auto-synced even under `-ReportOnly`, and its Content Hub and orphan sections report-only even when it had written those rules into the repository. `-FailOnDrift` becomes the result's `HasDrift`, and nothing exits. An absorbed file is left alone only when its content is the same in case too. | Each step can run on its own (a report that changes no file, a sync checked with `-WhatIf`), and the report the bot commits should say what its pull request holds and carry no tenant detail. |
| E25 | Workbooks and playbooks are exported by one command, `Export-iSOCContent`, over the content type registry. An item the repository already has is found by its identity (a workbook's workbookId, or the GUID deploy makes for a folder without one; a Logic App's PlaybookName), wherever its file is, and left alone unless `-Force` is given, when it is written over in its own file or folder. The scripts knew an item only by the path its display name or trigger made: the workbook script wrote over that folder unless `-OnlyMissing`, and the playbook script left that file unless `-Force`, so a workbook whose name makes another folder name (Detection Engineering Dashboard lives in `DetectionEngineering`) was written to a second folder that deploys the same workbook, even under `-OnlyMissing`. A Logic App two templates name (five pairs in this repository) is skipped as ambiguous, where the playbook script with `-Force` wrote over the one its trigger chose. A new item's path that another item already holds, or that an earlier item of the run was written to, is never written over. A file whose content would not change is left alone and reported Unchanged. Every page of the workbook list is read; the workbook script read the first. A workbook the list returns empty that then cannot be read on its own fails, where the workbook script skipped it. `-Filter` (a regular expression) and `-NameFilter` become `-Name` (wildcards); `-BasePath` and `-OutputPath` become `-Path`, under which files go to their repository-relative paths; `-WhatIf` says of each item whether it would be created or updated. Each item has an outcome, the run an `ExitCode`, and nothing exits. Nothing logged names the subscription: the workbook script logged the list URL. | The repository says which items it already has, as it does for deploy and drift; an export should never make two files deploy one item, or replace another item's file. |
| E26 | A workbook's `metadata.json` keys are written in the order displayName, description, category, sourceId, workbookId, then the folder's own keys as they were: the script passed the ordered metadata through a `[hashtable]` parameter, so its keys came out in hash order (the committed `Content/Workbooks/MicrosoftSentinelCostGbpV2/metadata.json` starts with sourceId), and a one-item list among the folder's own keys became a single value. The template is written to depth 100; the script wrote to depth 32, so a deeper workbook lost its innermost levels. Both files have LF line endings on every platform. The script's help described a backup of the old `workbook.json`, which it never made; none is made. | An export that changes nothing changes no file, and a deep workbook survives the round trip. |
| E27 | A playbook template that would differ from the repository's only in its `metadata.lastUpdateTime` is left as it is: the script stamped every template it wrote with the day's date, so exporting again with `-Force` always changed the file. Each plain-text secret is in the item's `Warnings` as well as the log. | A repeat export leaves the working tree clean, and the secrets can be listed from the result. |
| E28 | Community rules are imported by `Import-iSOCCommunityRule`. What the script fixed for David Alonso's repository (the repository and branch, the attribution, the tags, the folder maps and the README text) is a source definition, `Dalonso`, so another contributor is another definition rather than a copy of the script. The attribution is its own paragraph before the description, as the committed rules have it: the script's here-string dropped the blank line after it, so its imports ran the attribution into the description. `-SourcePath` imports from a checkout on disk without cloning; git is a checked prerequisite (`Test-iSOCDeploymentPrerequisite -Step Import`), and powershell-yaml is never installed (E4). `-DryRun` becomes `-WhatIf`, which says of each rule whether it would be created or updated or is unchanged, where the dry run counted every rule as new. The ids an import must avoid are read from `-RepoPath`'s rules, where the script used the folder it was run from. Source files are read in ordinal order of name. A long trigger operator in another case is written in the API's case, through the one map the module keeps. Each rule has a result (Created, Updated, Unchanged, Skipped with the reason, WhatIf) and the run an `ExitCode`. | One importer for every contributor, a preview that tells the truth, and the same output on every platform. |
| E29 | Every file ends with one newline. The script wrote each rule, the manifest and the README with `Set-Content` after text that already ended in one, so rules and the README ended with a blank line, and its unchanged check compared the file (with that line) against the new text (without it), so a re-import reported every rule Updated and rewrote it. Here a rule whose file holds its text is reported Unchanged and not written, and the manifest's hash is of the file written. The manifest and the README keep their `importDate` when the source commit and every rule's hash are as the manifest records, so an import that finds nothing new changes no file. | A scheduled or repeated import leaves the working tree clean unless the upstream changed. |
| E30 | The README's description column shows each rule's own first line. The script took the first line of the description, which is the attribution every community rule starts with, so every row of the committed `Docs/Content/Community/Dalonso.md` reads the same. The README names `Import-iSOCCommunityRule` as the way to re-import. | The table should say what each rule does. |
| E31 | An ARM rule with no `alertRuleTemplateName` is given a version 5 GUID from the source repository, its category and its file name, the same on every run; the script gave it a new random GUID each time, so a first import never repeated. `Get-FileHash256` is not ported: nothing called it. | Stable ids, as the deployer needs; and no dead code. |
| E32 | Playbook permissions are granted by `Grant-iSOCPlaybookPermission` through the REST client rather than Az.Resources (`Get-AzResource`, `Get-AzRoleAssignment`, `New-AzRoleAssignment`); the script also required Az.LogicApp, which it never used. The subscription, the resource groups and the workspace come from the context, and the subscription id is not logged. `-WhatIf` is the common parameter, and `-Name` limits the run to Logic Apps by wildcard. Each assignment is created with the principal type ServicePrincipal, so Azure does not look the identity up first, and is named by a GUID made from its scope, principal and role, so sending it twice changes nothing. Each role of each playbook has a result (Assigned, Unchanged, Skipped with the reason, Failed or WhatIf), and the run an `ExitCode`; nothing exits. The role analysis and the already-assigned check are as `Set-PlaybookPermissions.ps1` 1.0.2 has them: that release fixed a PUT pattern that gave Microsoft Sentinel Contributor to 44 of the 90 playbooks here, a check that never found an assignment, and reads strict mode refused (CHANGELOG). | One REST client for every write, least privilege, and a run that says what it did to each playbook. |
| E33 | Runbook permissions are two commands, `Grant-iSOCRunbookPermission` and `Revoke-iSOCRunbookPermission` (the script's `-Remove`), through the REST client rather than the az CLI, which is no longer needed. The subscription and the Sentinel resource group come from the context. The script's consent prompt (`Read-Host`) is ShouldProcess with ConfirmImpact High: each change asks for confirmation unless `-Confirm:$false` is given, and `-WhatIf` changes nothing. A role the identity already has at the scope or above is left alone and reported Unchanged, where the script asked az to create it again. A failed assignment or removal is Failed and sets `ExitCode`, where the script only warned on a failed create and never checked a delete. Removing deletes only an assignment at the role's own scope, not one inherited from above. The identity's assignments afterwards are in the result's `Assignments`, where the script printed az's table. The script's help said Microsoft Sentinel Contributor was assigned at subscription scope and that the account and resource group had defaults; it assigned at the Sentinel resource group, and both were mandatory. | Changes that can be previewed and confirmed the PowerShell way, and a result that says what failed. |
| E34 | The deployment service principal is set up by `Initialize-iSOCServicePrincipal`. The Azure roles go through the REST client, and the service principal is found through Graph with the Az sign-in, so Az.Resources is not needed; nor is a workspace, and the subscription defaults to the Az sign-in's. The directory role and the Graph permission go through one Microsoft Graph SDK sign-in, to the Az sign-in's tenant and cloud, asked for with every scope the chosen steps need (RoleManagement.ReadWrite.Directory, AppRoleAssignment.ReadWrite.All, Application.Read.All) and kept only when it holds them all. The script signed in once with the first Graph step's scopes and reused that sign-in for the second, so unless the user had consented AppRoleAssignment.ReadWrite.All to the Graph SDK before, granting CustomDetection.ReadWrite.All failed; and it signed in to whichever tenant the browser chose. Only Microsoft.Graph.Authentication is needed, checked as the Setup step's prerequisite and never installed, where the script installed Microsoft.Graph.Identity.Governance and Microsoft.Graph.Applications. The app role is granted through the Microsoft Graph service principal's `appRoleAssignedTo`, as Graph's documentation recommends. The consent prompt (`Read-Host`) is ShouldProcess with ConfirmImpact High: each grant asks unless `-Confirm:$false` is given, and `-WhatIf` grants nothing. A failed Azure role is Failed and the run carries on, where the script stopped; any failure sets `ExitCode` 1, where the script ended with exit code 0 and a message. Each grant has a result. | One sign-in that can do what it is asked, nothing installed, and a run that says when it failed. |
| E35 | The review is two commands: `Get-iSOCTableMigrationImpact` assesses and returns an `iSOCDeployments.TableMigrationReview`, and `Export-iSOCTableMigrationReport` writes its five files; the script did both and returned the review with `OutputPath`. The workspace comes from the context rather than `-SubscriptionId`, `-ResourceGroupName` and `-WorkspaceName` or a prompt for each, so nothing prompts and `-NonInteractive` goes. Requests go through the REST client at the module's api-versions: tables 2022-10-01, alert rules 2025-07-01-preview, saved searches 2025-07-01, workbooks 2022-04-01 and Content Hub packages 2025-09-01, where the script used 2023-09-01, 2024-03-01, 2020-08-01, 2023-06-01 and 2024-03-01; data collection rules (2022-06-01) and Logic Apps are as before. A list that comes back empty is empty, where the script counted the response itself as one nameless item, which showed in the content counts it logged and in the share the fan-out warning is taken of. `solutionMatches` in report.json is a list for one table too, where the script wrote that table's match as an object. The output folder is made only when there is something to write: a workspace with no classic tables writes nothing, where the script made the folder first. `-WhatIf` writes nothing. Progress goes through `Write-iSOCLog`, without box drawing or symbols. The solution mapping and the HTML template are the module's own, under `Resources/ClassicToDcr/`: the mapping is the script's file, held identical by a test until the weekly refresh writes the module's at cut-over; the template is the script's but for the commands it offers, `Connect-iSOCWorkspace` then `Invoke-iSOCClassicTableMigration -ListOnly` or `-Deploy` in place of the script run from `Tools/ClassicToDcr`, its version badge (the module's) and its footer. | Assessing and reporting are separate, so a review can be filtered or kept without files; the module's context, REST client, logging and `-WhatIf` apply; a review of one table has the shape of any other; the report hands over to the module's migration command. |
| E36 | `Get-ClassicCustomLogTable`, `Get-MatchedTable`, `Test-SafeFunctionAlias` and `Get-KqlIdentifierSet` are not ported: the script's run never called them, only its unit tests did. | Dead code. |

## Parameters

| Source | Parameter | Replaced by |
| --- | --- | --- |
| `Deploy/content/Deploy-CustomContent.ps1` | `-SubscriptionId`, `-ResourceGroup`, `-Workspace`, `-PlaybookResourceGroup` | `Connect-iSOCWorkspace -SubscriptionId -ResourceGroup -WorkspaceName -PlaybookResourceGroup`, then `Deploy-iSOCContent` (or `-Context`) |
| `Deploy/content/Deploy-CustomContent.ps1` | `-Region`, `-IsGov` | Read from the workspace and the Az sign-in by `Connect-iSOCWorkspace` |
| `Deploy/content/Deploy-CustomContent.ps1` | `-BasePath` | `-RepoPath` (defaults to the repository the current folder is in) |
| `Deploy/content/Deploy-CustomContent.ps1` | `-SkipParsers`, `-SkipWatchlists`, `-SkipDetections`, `-SkipHuntingQueries` | `-ExcludeContentType Parser`, `Watchlist`, `AnalyticsRule`, `HuntingQuery` |
| `Deploy/content/Deploy-CustomContent.ps1` | `-SkipPlaybooks`, `-SkipWorkbooks`, `-SkipAutomationRules`, `-SkipSummaryRules` | `-ExcludeContentType Playbook`, `Workbook`, `AutomationRule`, `SummaryRule` |
| `Deploy/content/Deploy-CustomContent.ps1` | `-SkipCommunityDetections` | `-Exclude 'Content/AnalyticalRules/Community/*'` |
| `Deploy/content/Deploy-CustomContent.ps1` | `-SmartDeployment` | `-SmartDeployment` |
| `Deploy/content/Deploy-CustomContent.ps1` | `-WhatIf` (a switch of its own) | `-WhatIf` (the common parameter, with `-Confirm`) |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `-BasePath` | `-RepoPath` (defaults to the repository the current folder is in) |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `-IsGov` | Read from the Az sign-in by `Connect-iSOCWorkspace` |
| `Deploy/content/Deploy-DefenderDetections.ps1` | `-WhatIf` (a switch of its own) | `-WhatIf` (the common parameter, with `-Confirm`) |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `-SubscriptionId`, `-ResourceGroup`, `-Workspace` | `Connect-iSOCWorkspace -SubscriptionId -ResourceGroup -WorkspaceName`, then `Install-iSOCContentHubSolution` (or `-Context`) |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `-Region`, `-IsGov` | Read from the workspace and the Az sign-in by `Connect-iSOCWorkspace` |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `-Solutions` | `-Name` |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `-SeveritiesToInclude` | `-Severity` |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `-DisableRules`, `-ForceSolutionUpdate`, `-ForceContentDeployment` | `-DisableRules`, `-ForceSolutionUpdate`, `-ForceContentDeployment` |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `-SkipSolutionDeployment` | `-ExcludeContentType Solution` |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `-SkipAnalyticsRules`, `-SkipWorkbooks`, `-SkipAutomationRules`, `-SkipHuntingQueries` | `-ExcludeContentType AnalyticsRule`, `Workbook`, `AutomationRule`, `HuntingQuery` |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `-ProtectCustomisedRules` (a bool, on by default) | `-OverwriteCustomisedRules` (a switch: protection stays on unless it is given) |
| `Deploy/content/Deploy-SentinelContentHub.ps1` | `-WhatIf` (a switch of its own) | `-WhatIf` (the common parameter, with `-Confirm`) |
| `Tools/Test-SentinelRuleDrift.ps1` | `-SubscriptionId`, `-ResourceGroup`, `-Workspace` | `Connect-iSOCWorkspace -SubscriptionId -ResourceGroup -WorkspaceName`, then `Compare-iSOCContent` (or `-Context`) |
| `Tools/Test-SentinelRuleDrift.ps1` | `-Region`, `-IsGov` | Read from the workspace and the Az sign-in by `Connect-iSOCWorkspace` |
| `Tools/Test-SentinelRuleDrift.ps1` | `-Solutions` | `Compare-iSOCContent -Solution` |
| `Tools/Test-SentinelRuleDrift.ps1` | `-SeveritiesToInclude` | `Compare-iSOCContent -Severity` |
| `Tools/Test-SentinelRuleDrift.ps1` | `-RepoPath` | `Compare-iSOCContent -RepoPath` |
| `Tools/Test-SentinelRuleDrift.ps1` | `-SkipContentHub`, `-SkipCustom`, `-SkipOrphans` | `Compare-iSOCContent -ExcludeSource ContentHub`, `Custom`, `Orphan` |
| `Tools/Test-SentinelRuleDrift.ps1` | `-ReportOnly` | Leave out `Sync-iSOCContent` |
| `Tools/Test-SentinelRuleDrift.ps1` | `-FailOnDrift` | The result's `HasDrift`: `exit [int]$drift.HasDrift` |
| `Tools/Test-SentinelRuleDrift.ps1` | `-WhatIf` (a switch of its own) | `-WhatIf` on `Sync-iSOCContent` and `Export-iSOCDriftReport` |
| `Tools/Export-SentinelWorkbooks.ps1` | `-SubscriptionId`, `-ResourceGroup`, `-Workspace` | `Connect-iSOCWorkspace -SubscriptionId -ResourceGroup -WorkspaceName`, then `Export-iSOCContent -ContentType Workbook` (or `-Context`) |
| `Tools/Export-SentinelWorkbooks.ps1` | `-Region`, `-IsGov` | Read from the workspace and the Az sign-in by `Connect-iSOCWorkspace` |
| `Tools/Export-SentinelWorkbooks.ps1` | `-BasePath` | `-RepoPath`, or `-Path` to write somewhere else |
| `Tools/Export-SentinelWorkbooks.ps1` | `-Filter` (a regular expression) | `-Name` (wildcards) |
| `Tools/Export-SentinelWorkbooks.ps1` | `-OnlyMissing` | The default; `-Force` writes over workbooks the repository has |
| `Tools/Export-SentinelWorkbooks.ps1` | `-IncludeContentHub` | `-IncludeContentHub` |
| `Tools/Export-SentinelWorkbooks.ps1` | `-WhatIf` | `-WhatIf` |
| `847ef86:Tools/Export-Playbooks.ps1` | `-SubscriptionId`, `-ResourceGroup`, `-Workspace`, `-PlaybookResourceGroup` | `Connect-iSOCWorkspace -SubscriptionId -ResourceGroup -WorkspaceName -PlaybookResourceGroup`, then `Export-iSOCContent -ContentType Playbook` |
| `847ef86:Tools/Export-Playbooks.ps1` | `-Region`, `-IsGov` | Read from the workspace and the Az sign-in by `Connect-iSOCWorkspace` |
| `847ef86:Tools/Export-Playbooks.ps1` | `-OutputPath` (the `Content/Playbooks` folder) | `-Path` (the folder `Content/Playbooks/` is written under) |
| `847ef86:Tools/Export-Playbooks.ps1` | `-NameFilter` | `-Name` |
| `847ef86:Tools/Export-Playbooks.ps1` | `-Author`, `-Force` | The same |
| `847ef86:Tools/Export-Playbooks.ps1` | `-WhatIf` | `-WhatIf` |
| `Tools/Import-CommunityRules.ps1` | `-OutputPath`, `-DocsPath`, `-SourceRepo`, `-SourceBranch`, `-IncludeKqlConversion` | The same |
| `Tools/Import-CommunityRules.ps1` | `-DryRun` | `-WhatIf` |
| `Tools/Import-CommunityRules.ps1` | (the David Alonso settings, fixed in the script) | `-Source Dalonso`, the default |
| `Tools/Import-CommunityRules.ps1` | (none) | `-SourcePath`, a checkout to read instead of cloning; `-RepoPath` |
| `Deploy/permissions/Set-PlaybookPermissions.ps1` | `-SubscriptionId`, `-PlaybookResourceGroup`, `-SentinelResourceGroup`, `-SentinelWorkspaceName` | `Connect-iSOCWorkspace -SubscriptionId -ResourceGroup -WorkspaceName -PlaybookResourceGroup`, then `Grant-iSOCPlaybookPermission` (or `-Context`) |
| `Deploy/permissions/Set-PlaybookPermissions.ps1` | `-KeyVaultName` | The same |
| `Deploy/permissions/Set-PlaybookPermissions.ps1` | `-WhatIf` (a switch of its own) | `-WhatIf` (the common parameter, with `-Confirm`) |
| `Deploy/permissions/Set-PlaybookPermissions.ps1` | (none) | `-Name`, Logic Apps by wildcard |
| `Deploy/permissions/Set-RunbookPermissions.ps1` | `-SubscriptionId`, `-SentinelResourceGroup` | `Connect-iSOCWorkspace -SubscriptionId -ResourceGroup`, then `Grant-iSOCRunbookPermission` (or `-Context`) |
| `Deploy/permissions/Set-RunbookPermissions.ps1` | `-AutomationAccountName`, `-AutomationResourceGroup` | The same |
| `Deploy/permissions/Set-RunbookPermissions.ps1` | `-Remove` | `Revoke-iSOCRunbookPermission` |
| `Deploy/permissions/Set-RunbookPermissions.ps1` | (the Read-Host consent prompt) | The confirmation prompt; `-Confirm:$false`, `-WhatIf` |
| `Deploy/setup/Setup-ServicePrincipal.ps1` | `-SubscriptionId` | The same; it defaults to the Az sign-in's |
| `Deploy/setup/Setup-ServicePrincipal.ps1` | `-ServicePrincipalAppId`, `-SkipEntraRole`, `-SkipGraphPermission` | The same |
| `Deploy/setup/Setup-ServicePrincipal.ps1` | (the Read-Host consent prompt) | The confirmation prompt; `-Confirm:$false`, `-WhatIf` |
| `Tools/Build-DependencyManifest.ps1` | `-Mode Verify` | `Test-iSOCDependencyManifest` |
| `Tools/Build-DependencyManifest.ps1` | `-Mode Generate`, `-Mode Update` | `Update-iSOCDependencyManifest` |
| `Tools/Build-DependencyManifest.ps1` | `-RepoPath`, `-ManifestPath` | `-RepoPath`, `-ManifestPath` |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `-SubscriptionId`, `-ResourceGroupName`, `-WorkspaceName` | `Connect-iSOCWorkspace -SubscriptionId -ResourceGroup -WorkspaceName` first (or `-Context`) |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `-MaxParserChainDepth` | `Get-iSOCTableMigrationImpact -MaxParserChainDepth` |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `-OutputPath` | `Export-iSOCTableMigrationReport -Path` |
| `Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1` | `-NonInteractive` | Not needed: nothing prompts |
