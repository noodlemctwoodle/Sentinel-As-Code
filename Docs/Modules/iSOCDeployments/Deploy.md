# Deploying content with Deploy-iSOCContent

`Deploy-iSOCContent` deploys the repository's content to the workspace
`Connect-iSOCWorkspace` connected. It will replace
`Deploy/content/Deploy-CustomContent.ps1` and
`Deploy/content/Deploy-DefenderDetections.ps1` at the 26.11.0 cut-over;
until then the pipelines run the scripts. It deploys everything they do:
parsers, watchlists, analytics rules, hunting queries, playbooks,
workbooks, automation rules and summary rules to the workspace, and
Defender XDR custom detections to the tenant through Microsoft Graph.

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

# The Defender stage on its own: which detections would be updated and
# which created.
Deploy-iSOCContent -ContentType DefenderDetection -WhatIf
```

`Tests/iSOCDeployments/DeployParity.Tests.ps1` runs both scripts' steps
and `Deploy-iSOCContent` over this repository against the same stand-in
workspace and tenant, and requires the same requests, bodies, playbook
deployments and outcome counts.

## From the scripts

| `Deploy-CustomContent.ps1` | Command |
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

| `Deploy-DefenderDetections.ps1` | Command |
| --- | --- |
| (the script on its own) | `-ContentType DefenderDetection`; leave detections out of another run with `-ExcludeContentType DefenderDetection` |
| `-BasePath` | `-RepoPath` |
| `-IsGov` | Not needed: the Graph host comes from the Az sign-in |
| `-WhatIf` | `-WhatIf`, and `-Confirm` |
| exit code 1 on a failure | the result's `ExitCode` |

`-ContentType` limits a run to some types, by name or wildcard;
`Get-iSOCContentType` lists them. Defender detections need a connected
workspace too, as every run does, and the service principal needs the
`CustomDetection.ReadWrite.All` Graph application permission.

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
   rules, Defender XDR custom detections), custom items before Community
   ones, and playbook modules before
   the playbooks that call them. For each item: excluded or unchanged
   items are left alone; an invalid one is skipped and one that does not
   parse fails; a missing dependency sends an analytics rule disabled and
   skips anything else; then the item is sent. Community rules always go
   disabled, and a rule whose query the service will not validate yet (a
   watchlist column not indexed yet, say) is sent again disabled.
   Playbooks deploy as ARM templates to the playbook resource group.
   Defender detections are read from the tenant first: a detection whose
   display name the tenant has is updated in place, and a new one is
   created with the `id` its file gives it (one without an `id` fails).
   Everything else is a REST request to the workspace.
7. After watchlists are uploaded, waits 30 seconds for Sentinel to index
   them before the rules that read them.
8. Saves `deployment-state.json` after each type, and reports a summary.

A failed item does not stop the run. With `-WhatIf` every step reads as
usual, nothing is sent, each playbook template is validated against the
playbook resource group instead of deployed, the tenant's Defender
detections are still read so the run says which it would update and which
create, the state file is not written and there is no wait.

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

`MIGRATION.md` edits E9 and E11 to E18 list every way the module differs
from the scripts: fields the script failed on under strict mode, what
`-WhatIf` touches, how exclusions and oversized watchlists are reported,
two fixes to the pre-flight checks, playbook validation under `-WhatIf`
(which never worked in the script), a fixed deploy order, workbook names,
the deployment controls Defender detections now share with the rest of the
content, and the tenant read a Defender dry run now makes.
