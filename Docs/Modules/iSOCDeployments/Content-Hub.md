# Content Hub solutions

`Install-iSOCContentHubSolution` installs Content Hub solutions in the
workspace `Connect-iSOCWorkspace` connected, and deploys the analytics
rules and workbooks they ship. `Get-iSOCContentHubSolution` says where
solutions stand without changing anything. Together they will replace
`Deploy/content/Deploy-SentinelContentHub.ps1` at the 26.11.0 cut-over;
until then the pipelines run the script.

Solutions are packages from Microsoft's catalogue rather than files in
this repository, so they are not a content type: `Deploy-iSOCContent`
does not deploy them, and they have their own commands.

```powershell
Import-Module ./Modules/iSOCDeployments
Connect-AzAccount
Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel

# Where two solutions stand.
Get-iSOCContentHubSolution -Name 'Azure Activity', 'Microsoft Entra ID'

# What installing them would do, changing nothing.
Install-iSOCContentHubSolution -Name 'Azure Activity', 'Microsoft Entra ID' -WhatIf

# A pipeline step: the pipeline's comma-separated list, rules disabled.
$run = Install-iSOCContentHubSolution -Name $solutions -Severity High, Medium -DisableRules
exit $run.ExitCode
```

`Tests/iSOCDeployments/ContentHub.Tests.ps1` runs the script's functions
and the module against the same stand-in Content Hub (a synthetic
catalogue with solutions to install, update, leave alone and not find, and
rule and workbook templates for every case the code handles) in six
scenarios, and requires the same writes and outcome counts.

## From the script

| `Deploy-SentinelContentHub.ps1` | Command |
| --- | --- |
| `-SubscriptionId`, `-ResourceGroup`, `-Workspace` | `Connect-iSOCWorkspace` first (or `-Context`) |
| `-Region`, `-IsGov` | Not needed: read from the workspace and the Az sign-in |
| `-Solutions` | `-Name` |
| `-SeveritiesToInclude` | `-Severity` |
| `-DisableRules`, `-ForceSolutionUpdate`, `-ForceContentDeployment` | The same |
| `-SkipSolutionDeployment` | `-ExcludeContentType Solution` |
| `-SkipAnalyticsRules`, `-SkipWorkbooks`, `-SkipAutomationRules`, `-SkipHuntingQueries` | `-ExcludeContentType AnalyticsRule`, `Workbook`, `AutomationRule`, `HuntingQuery` |
| `-ProtectCustomisedRules $false` | `-OverwriteCustomisedRules` (protection is on unless it is given) |
| `-WhatIf` | `-WhatIf`, and `-Confirm` |
| exit code 1 on a failure | the result's `ExitCode` |

## What a run does

1. Waits up to three minutes for the workspace's Sentinel onboarding to
   read (a workspace the infrastructure stage has just onboarded can take
   that long), then reads the catalogue and the installed packages.
2. Works out where each solution stands: not in the catalogue (it fails),
   not installed, behind the catalogue, or current. A package the
   workspace lists but the catalogue does not report installed (left by a
   workspace that was deleted and recreated) is reinstalled. Logs a table
   of the solutions.
3. Installs or updates each solution as an incremental ARM deployment of
   its package, with the postDeployment metadata that makes deployments
   fail taken out. A package over ARM's 4 MB request limit is not sent; a
   solution with no package is registered only.
4. When a solution was installed or updated, waits a minute for its
   templates to appear.
5. For each analytics rule template of the solutions: skips one with no
   rule in it, one marked `[Deprecated]` and one of a severity not asked
   for; leaves a current rule alone (writing only its solution metadata);
   protects a rule changed in the workspace, or one with the template's
   name but no link to it; and otherwise creates or updates the rule with
   the preview alert rules API, which keeps sub-techniques, then links it
   to its solution. A refusal the workspace can fix (a missing table or
   column, say) skips the rule with a warning; anything else fails it.
6. For each workbook template: leaves a saved workbook at the template's
   version alone, and otherwise saves the workbook to the workspace's
   resource group (an update keeps its name) and links it to its
   solution.
7. Counts the automation rules and hunting queries the solutions ship:
   they arrive with the solution package.
8. Logs a summary and returns the result.

A rule or workbook of a solution installed or updated in the run is always
processed, and `-ForceContentDeployment` processes them all. `-DisableRules`
sends every rule disabled and disables enabled rules that are otherwise
current.

With `-WhatIf` every step reads as usual and nothing is written, the
metadata of unchanged rules included, and there is no wait.

On a Microsoft ISOC workspace (the Defender portal's SIEM packaging),
Content Hub is documented to install only a solution's data connectors
during the preview; each item's outcome says what happened rather than the
run assuming a full install.

## The result

`Install-iSOCContentHubSolution` returns an `iSOCDeployments.ContentHubRun`:
`Solutions`, `Results`, the counts `Deployed`, `Updated`, `Unchanged`,
`Protected`, `Skipped` (deprecated templates included), `Failed` and
`WhatIf`, `MetadataLinked` and `MetadataFailed`, `AutomationRuleTemplates`
and `HuntingQueryTemplates`, `Duration` and `ExitCode` (1 when anything
failed). Each result is an `iSOCDeployments.ContentHubResult`:

| Property | Meaning |
| --- | --- |
| `ContentType` | `Solution`, `AnalyticsRule` or `Workbook` |
| `Name`, `Identity`, `Solution` | The display name, the template's contentId (a solution's catalogue name) and the solution it comes from |
| `Outcome` | `Deployed`, `Updated`, `Unchanged`, `Protected`, `Deprecated`, `WhatIf`, `Skipped` or `Failed` |
| `Reason` | Why, when the outcome is not a plain one; under `-WhatIf`, what it would do |

`Get-iSOCContentHubSolution` returns an `iSOCDeployments.ContentHubSolution`
per solution: `Name`, `Status` (`NotFound`, `NotInstalled`,
`UpdateAvailable` or `Installed`), `InstalledVersion`, `AvailableVersion`,
`Action` (`Install`, `Update`, `None` or `ForceUpdate`), `ContentId` and
`CatalogueName`. Without `-Name` it lists the whole catalogue.

`MIGRATION.md` edits E19 to E21 list every way the commands differ from
the script: item outcomes, a `-WhatIf` that writes nothing, the wait only
after an install, how refused rules are classified, every page of the
catalogue and template lists read, and the one function not ported.
