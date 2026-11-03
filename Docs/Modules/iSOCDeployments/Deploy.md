# Deploying content with Deploy-iSOCContent

`Deploy-iSOCContent` deploys the repository's content to the workspace
`Connect-iSOCWorkspace` connected. It will replace
`Deploy/content/Deploy-CustomContent.ps1` at the 26.11.0 cut-over; until
then the pipelines run the script. It deploys everything the script does:
parsers, watchlists, analytics rules, hunting queries, playbooks,
workbooks, automation rules and summary rules.

```powershell
Import-Module ./Modules/iSOCDeployments
Connect-AzAccount
Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel

# See what would deploy, changing nothing.
Deploy-iSOCContent -WhatIf

# Deploy everything the module can deploy.
$run = Deploy-iSOCContent
$run.Results | Where-Object Outcome -ne Deployed

# A pipeline step: what changed, Community rules held back.
$run = Deploy-iSOCContent -SmartDeployment -Exclude 'Content/AnalyticalRules/Community/*'
exit $run.ExitCode
```

`Tests/iSOCDeployments/DeployParity.Tests.ps1` runs the script's steps and
`Deploy-iSOCContent` over this repository against the same stand-in
workspace, and requires the same requests, bodies, playbook deployments and
outcome counts.

## From the script

| Script | Command |
| --- | --- |
| `-ResourceGroup`, `-Workspace`, `-SubscriptionId`, `-PlaybookResourceGroup` | `Connect-iSOCWorkspace` first (or `-Context`) |
| `-Region`, `-IsGov` | Not needed: read from the workspace and the Az sign-in |
| `-BasePath` | `-RepoPath` |
| `-SkipParsers`, `-SkipWatchlists`, `-SkipDetections`, `-SkipHuntingQueries` | `-ExcludeContentType Parser`, `Watchlist`, `AnalyticsRule`, `HuntingQuery` |
| `-SkipPlaybooks`, `-SkipWorkbooks`, `-SkipAutomationRules`, `-SkipSummaryRules` | `-ExcludeContentType Playbook`, `Workbook`, `AutomationRule`, `SummaryRule` |
| `-SkipCommunityDetections` | `-Exclude 'Content/AnalyticalRules/Community/*'` |
| `-SmartDeployment` | `-SmartDeployment` |
| `-WhatIf` | `-WhatIf`, and `-Confirm` |
| exit code 1 on a failure | the result's `ExitCode` |

`-ContentType` limits a run to some types, by name or wildcard;
`Get-iSOCContentType` lists them.

## What a run does

1. Reads every content type's files, and when there are playbooks to
   deploy checks that Az.Resources is installed, so a missing module stops
   the run before anything deploys.
2. Reads `sentinel-deployment.config` (at the repository root, or
   `Deploy/content/` until cut-over): `prioritizedcontentfiles` deploy first
   within their type, `excludecontentfiles` never deploy.
3. With `-SmartDeployment`, asks git which files the commit changed
   (against the target branch for an Azure DevOps pull request build).
   When it cannot tell, everything deploys.
4. Reads `deployment-state.json`, the record of what deployed successfully,
   so smart deployment can retry what did not.
5. Reads `dependencies.json` and, when it lists anything, the workspace's
   tables, watchlists and functions. When the state records more than ten
   rules deployed but the workspace has none, the workspace was rebuilt and
   the state is reset.
6. Deploys each content type in order (parsers, watchlists, analytics
   rules, hunting queries, playbooks, workbooks, automation rules, summary
   rules), custom items before Community ones, and playbook modules before
   the playbooks that call them. For each item: excluded or unchanged
   items are left alone; an invalid one is skipped and one that does not
   parse fails; a missing dependency sends an analytics rule disabled and
   skips anything else; then the item is sent. Community rules always go
   disabled, and a rule whose query the service will not validate yet (a
   watchlist column not indexed yet, say) is sent again disabled.
   Playbooks deploy as ARM templates to the playbook resource group;
   everything else is a REST request.
7. After watchlists are uploaded, waits 30 seconds for Sentinel to index
   them before the rules that read them.
8. Saves `deployment-state.json` after each type, and reports a summary.

A failed item does not stop the run. With `-WhatIf` every step reads as
usual, nothing is sent, each playbook template is validated against the
playbook resource group instead of deployed, the state file is not written
and there is no wait.

## The result

`Deploy-iSOCContent` returns an `iSOCDeployments.DeployRun`: `Deployed`,
`Skipped`, `Failed` and `WhatIf` counts, `Duration`, `ExitCode` (1 when
anything failed) and `Results`, one `iSOCDeployments.ItemResult` per item:

| Property | Meaning |
| --- | --- |
| `ContentType`, `Name`, `Identity`, `RelativePath` | The item |
| `Outcome` | `Deployed`, `DeployedDisabled` (a missing dependency, a Community rule, or a query the service would not validate yet), `WhatIf`, `Unchanged` (smart deployment), `Skipped` or `Failed` |
| `Reason` | Why, when the outcome is not a plain Deployed |
| `Missing` | The missing dependencies, as `table:`, `watchlist:` or `function:` names |

`MIGRATION.md` edits E9 and E11 to E16 list every way the module differs
from the script: fields the script failed on under strict mode, what
`-WhatIf` touches, how exclusions and oversized watchlists are reported,
two fixes to the pre-flight checks, playbook validation under `-WhatIf`
(which never worked in the script), a fixed deploy order, and workbook
names.
