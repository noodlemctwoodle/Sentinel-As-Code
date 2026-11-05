# Deploying a workspace with Deploy-iSOCWorkspace

`Deploy-iSOCWorkspace` runs the deploy pipelines' stages that come after
the infrastructure, in order, as one command. It replaces the stage
sequence of `Pipelines/Sentinel-Deploy.yml` and
`.github/workflows/sentinel-deploy.yml`: their stage conditions, the
dependency manifest guard, and the inline PowerShell that built each
script's parameters. The pipelines run their own stages by default; the
Azure DevOps deploy pipeline runs the command one stage at a time with
`engine` `module` ([The pipeline switch](Pipeline-Switch.md)).

```powershell
Import-Module ./Modules/iSOCDeployments
Connect-AzAccount
Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel -PlaybookResourceGroup rg-playbooks

# See what every stage would deploy, changing nothing.
Deploy-iSOCWorkspace -Solution 'Microsoft Entra ID', 'Azure Activity' -DisableRules -WhatIf

# The pipelines' defaults.
$run = Deploy-iSOCWorkspace -Solution $solutions -DisableRules -SmartDeployment -Exclude 'Content/AnalyticalRules/Community/*'
exit $run.ExitCode
```

## The stages

| Stage | Command | Gated by |
| --- | --- | --- |
| `WorkspaceSettings` | `Deploy-iSOCContent -ContentType WorkspaceSetting` | Nothing |
| `ContentHub` | `Install-iSOCContentHubSolution` | Nothing (the pipeline's infrastructure stage) |
| `CustomContent` | `Test-iSOCDependencyManifest`, then `Deploy-iSOCContent` for every other type | `ContentHub` |
| `DefenderDetections` | `Deploy-iSOCContent -ContentType DefenderDetection` | `CustomContent` |

A stage does not run when the stage that gates it failed. A stage that was
left out, or did not run itself, holds back nothing. So a failed Content
Hub stage holds back custom content, while the Defender detections still
deploy. This is what the GitHub workflow's job conditions and the Azure
DevOps stage conditions say, and
`Tests/iSOCDeployments/DeployWorkspace.Tests.ps1` reads those conditions
from the YAML and holds the command to them. The one difference: Azure
DevOps ran custom content after a failed Content Hub stage when its
infrastructure stage was off. The module holds it back on both platforms.

Workspace settings run first and gate nothing. The pipelines configured
them in the infrastructure stage and only warned when one failed
([Workspace settings and onboarding](Workspace-Settings.md)).

Custom content deploys only when `dependencies.json` matches the content,
as the pipelines' guard step required. A missing or stale manifest fails
the stage with the fix: run `Update-iSOCDependencyManifest`, commit, and
deploy again.

A stage whose command fails an item fails. One whose command throws fails
too, with the error as its reason, and the run goes on to the stages it
does not gate. Each stage's command logs its own run, and the command
closes with a line per stage.

Registering the resource providers, deploying `Infra/sentinel/main.bicep`,
the wait for the workspace, installing powershell-yaml and saving
`deployment-state.json` as a pipeline artifact stay pipeline steps.
`Get-iSOCWorkspaceOnboarding` says whether Bicep must run.

## Parameters

| Parameter | Stage | What it does |
| --- | --- | --- |
| `-Stage`, `-ExcludeStage` | All | Which stages run; all four unless named |
| `-Solution` | ContentHub | The solutions to install or update; needed when the stage runs |
| `-Severity` | ContentHub | The rule severities to deploy from templates; all four by default |
| `-DisableRules` | ContentHub | Create the rules disabled |
| `-OverwriteCustomisedRules` | ContentHub | Update rules changed in the workspace; they are protected without it |
| `-ForceSolutionUpdate`, `-ForceContentDeployment` | ContentHub | Deploy solutions, and their rules and workbooks, that are already current |
| `-ExcludeSolutionContentType` | ContentHub | What the solutions' deployment leaves out: `Solution`, `AnalyticsRule`, `Workbook`, `AutomationRule`, `HuntingQuery` |
| `-ExcludeContentType` | CustomContent | Content types to leave out |
| `-Exclude` | Every deploying stage | Repository paths to leave out, such as the Community rules |
| `-SmartDeployment` | Every deploying stage | Only what changed, and what last failed |
| `-WhatIf`, `-Confirm` | All | Passed to every stage's command |
| `-Context`, `-RepoPath` | All | The workspace and the repository |

## The result

An `iSOCDeployments.WorkspaceDeployRun`:

| Property | What it holds |
| --- | --- |
| `Stages` | One `iSOCDeployments.StageResult` per stage: `Stage`, `Outcome` (`Succeeded`, `Failed`, `Excluded` or `NotRun`), `Reason`, `ExitCode` and `Run`, the stage command's own result |
| `Failed` | How many stages failed |
| `Duration` | How long the run took |
| `ExitCode` | 1 when a stage failed, else 0 |

## From the pipelines

| Azure DevOps parameter | GitHub input | `Deploy-iSOCWorkspace` |
| --- | --- | --- |
| `deployContentHub`, `deployCustomContent`, `deployDefenderDetections` | `deploy_content_hub`, `deploy_custom_content`, `deploy_defender_detections` | `-ExcludeStage ContentHub`, `CustomContent`, `DefenderDetections` when off |
| `solutions`, `severitiesToInclude` | `solutions`, `severities_to_include` | `-Solution`, `-Severity` |
| `disableRules` | `disable_rules` | `-DisableRules` |
| `protectCustomisedRules` | `protect_customised_rules` | `-OverwriteCustomisedRules` when off |
| `skipAnalyticsRules`, `skipWorkbooks`, `skipAutomationRules`, `skipHuntingQueries` | `skip_analytics_rules`, `skip_workbooks`, `skip_automation_rules`, `skip_hunting_queries` | `-ExcludeSolutionContentType AnalyticsRule`, `Workbook`, `AutomationRule`, `HuntingQuery` |
| `forceSolutionUpdate`, `forceContentDeployment` | `force_solution_update`, `force_content_deployment` | `-ForceSolutionUpdate`, `-ForceContentDeployment` |
| `skipCustomParsers`, `skipCustomDetections`, `skipCustomWatchlists`, `skipCustomPlaybooks`, `skipCustomWorkbooks`, `skipCustomHuntingQueries`, `skipCustomAutomationRules`, `skipCustomSummaryRules` | `skip_custom_content_types`: `parsers`, `detections`, `watchlists`, `playbooks`, `workbooks`, `hunting-queries`, `automation-rules`, `summary-rules` | `-ExcludeContentType Parser`, `AnalyticsRule`, `Watchlist`, `Playbook`, `Workbook`, `HuntingQuery`, `AutomationRule`, `SummaryRule` |
| `skipCommunityDetections` | `skip_custom_content_types`: `community-detections` | `-Exclude 'Content/AnalyticalRules/Community/*'` |
| `smartDeployment` | `smart_deployment` | `-SmartDeployment` |
| `whatIf` | `what_if` | `-WhatIf` |
| `deployInfrastructure`, `dailyQuota`, `retentionInDays`, `totalRetentionInDays` | `deploy_infrastructure`, `daily_quota`, `retention_in_days`, `total_retention_in_days` | Stay with the pipeline's Bicep stage |

The suite runs each pipeline's Content Hub, custom content and Defender
steps unchanged, filled in from the pipeline's own defaults and three other
cases (a scheduled GitHub run with no inputs among them), against stand-in
scripts that record what they are given. The command, called as the
pipeline would call it, must give the module's commands the same.
`MIGRATION.md` edit E44 lists how it differs from the pipelines.
