# Export: workspace content into the repository

`Export-iSOCContent` writes content from the workspace that
`Connect-iSOCWorkspace` connected into the repository, in the shape
`Deploy-iSOCContent` deploys, so a round trip (export, commit, deploy)
lands on the same resources. It will replace
`Tools/Export-SentinelWorkbooks.ps1` and the playbook exporter that was
never merged (`847ef86:Tools/Export-Playbooks.ps1`) at the 26.11.0
cut-over.

Workbooks and playbooks are the content types it exports so far. The
others gain Export as they are ported
([Content types](Content-Types.md)).

```powershell
Import-Module ./Modules/iSOCDeployments
Connect-AzAccount
Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel -PlaybookResourceGroup rg-automation

# What exporting everything would write, writing nothing.
Export-iSOCContent -WhatIf

# The workbooks the repository does not have yet.
Export-iSOCContent -ContentType Workbook

# One playbook, over its template in the repository.
Export-iSOCContent -ContentType Playbook -Name 'Module-AddSentinelComment' -Force

# Playbooks for review outside the repository, and those with plain-text secrets.
$run = Export-iSOCContent -ContentType Playbook -Path ./export
$run.Results | Where-Object Warnings | Format-List Name, Warnings
```

`Tests/iSOCDeployments/Export.Tests.ps1` runs each script, unchanged, in
a child pwsh against a stand-in workspace, and runs the module against the
same one. The stand-in holds every workbook in this repository as deploy
sends it, new and Content Hub workbooks, ones with no content or broken
content, and Logic Apps with every kind of trigger, two connections to
one API, a module call and plain-text keys. The suite requires the same
files and counts, with the repository's own workbooks and playbooks
written over and without. The playbook exporter is read from a
byte-for-byte copy at `Tests/iSOCDeployments/Fixtures/legacy/`, because
its commit is on no remote.

## From the scripts

| `Export-SentinelWorkbooks.ps1` | `Export-iSOCContent` |
| --- | --- |
| `-SubscriptionId`, `-ResourceGroup`, `-Workspace` | `Connect-iSOCWorkspace` first (or `-Context`), then `-ContentType Workbook` |
| `-Region`, `-IsGov` | Not needed: read from the workspace and the Az sign-in |
| `-BasePath` | `-RepoPath`, or `-Path` to write somewhere else |
| `-Filter` (a regular expression) | `-Name` (wildcards) |
| `-OnlyMissing` | The default; `-Force` writes over workbooks the repository has |
| `-IncludeContentHub`, `-WhatIf` | The same |
| exit code 1 on a failure | The result's `ExitCode` |

| `Export-Playbooks.ps1` (847ef86) | `Export-iSOCContent` |
| --- | --- |
| `-SubscriptionId`, `-ResourceGroup`, `-Workspace`, `-PlaybookResourceGroup` | `Connect-iSOCWorkspace -PlaybookResourceGroup` first, then `-ContentType Playbook` |
| `-Region`, `-IsGov` | Not needed |
| `-OutputPath` (the `Content/Playbooks` folder) | `-Path` (the folder `Content/Playbooks/` is written under) |
| `-NameFilter` | `-Name` |
| `-Author`, `-Force`, `-WhatIf` | The same |
| exit code 1 on a failure | The result's `ExitCode` |

## What a run does

For each content type that can be exported, every item in the workspace
is read and classed by its source, the same way `Compare-iSOCContent`
classes it:

1. An item `-Name` does not match is skipped.
2. An item the repository already has is found by its identity, wherever
   its file is: a workbook by its `workbookId`, or by the GUID deploy
   makes for a folder without one, and a Logic App by its template's
   `PlaybookName`. Without `-Force` it is skipped; with it, it is written
   over in its own file or folder. A Logic App two templates name (five
   pairs in this repository share a `PlaybookName`) is skipped as
   ambiguous.
3. A workbook a Content Hub solution installed is skipped unless
   `-IncludeContentHub` is given: it belongs to its solution, whose
   updates would then conflict with the repository.
4. An item that could not be read fails. An item with nothing to write
   is skipped: a workbook with no content, or content that is not JSON,
   or a Logic App with no workflow definition.
5. An item only the workspace has goes to a new file or folder:
   `Content/Workbooks/<Name>/` for a workbook, its display name (less the
   ` - <workspace>` suffix Microsoft adds) made one PascalCase word, and
   `Content/Playbooks/<Trigger>/<Name>.bicep` for a playbook (`.json`
   with `-Format Json`), its trigger's category folder and its name
   without a leading category prefix. A playbook the repository already
   has keeps its own file's format. A path
   another item already holds, or one an earlier item of the run was
   written to, is never written over.
6. The files are written, unless they would not change.

Nothing is deleted, and nothing in the workspace changes. With `-WhatIf`
everything is read and nothing written, and each item says whether it
would be created or updated. With `-Path` the files go under that folder
at their repository-relative paths, and the repository still decides
which items it already has.

## What is written

A workbook is two files:

- `workbook.json`: the gallery template, pretty-printed, with the
  workspace's resource id replaced by the placeholder the repository's
  workbooks use
  (`/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/your-resource-group/providers/microsoft.operationalinsights/workspaces/your-workspace`);
- `metadata.json`: `displayName`, `description`, `category`, `sourceId`
  (the folder name) and `workbookId` (the workbook's GUID, so a redeploy
  updates the same workbook), in that order. The workspace's values are
  merged with the folder's own `metadata.json`: a curated description or
  category is kept over the workspace's empty or default one, a display
  name that differs only in case keeps the folder's capitalisation, and
  any other key the folder's file has is kept.

A playbook is one parameterised template, written as Bicep by the
module's own writer (no Bicep CLI is needed to export), or as ARM JSON
with `-Format Json`. Both describe the same deployment:

- the `PlaybookName` parameter defaults to the Logic App's live name, so
  a redeploy updates the same workflow;
- the subscription, the playbook and workspace resource groups, the
  workspace name and its id become ARM expressions and the parameters
  deploy fills in (`AutomationResourceGroup`,
  `SentinelResourceGroupName`, `SentinelWorkpaceName`, `WorkspaceId`),
  each declared when an expression references it, and
  `AutomationResourceGroup` and `SentinelWorkpaceName` always for a
  Sentinel-triggered playbook, as the existing templates have;
- each API connection becomes a `Microsoft.Web/connections` resource
  named after the playbook. A connection that uses the workflow's managed
  identity keeps it; an OAuth or API key connection needs authorising
  once after deployment;
- the workflow keeps its live state, has the `Source: Sentinel-As-Code`
  tag `Set-PlaybookPermissions.ps1` looks for, and a metadata block
  (title, description, the date, entities, tags, support, author);
- a template that would differ from the repository's only in that date
  is left as it is;
- in Bicep, the connections are referred to by their symbolic names
  (`MicrosoftSentinelConnection.id`), ARM `concat()` becomes string
  interpolation, and where Bicep's own type data is wrong or missing for
  these resource types (Logic Apps `2017-07-01`; `kind` and
  `parameterValueType` on API connections) a `#disable-next-line` for that
  warning sits on the line before, so the file builds clean.

The export does not remove secrets. A value that looks like one held in
plain text (an API key header, an authentication secret, a key in a URI)
is warned about and listed in the item's `Warnings`, so it can be moved
to Key Vault before the template is committed. Every file is UTF-8
without a byte order mark, with LF line endings.

## Converting JSON playbooks to Bicep

`Convert-iSOCPlaybook` rewrites the repository's JSON playbooks as Bicep, for
a repository (or fork) that still has them. For each JSON playbook the
deploy reads, it writes the template as Bicep into a temporary copy of its
folder (with the repository's `bicepconfig.json`), compiles every candidate
in one run of the Bicep CLI, and compares each compiled template with the
JSON it came from. Only when they deploy the same thing is `<Name>.bicep`
written beside the JSON and the JSON removed; a parameters file beside it
stays. A playbook the writer cannot write, that does not compile or that
would deploy something else is left as JSON and reported with why, and
one that already has a `.bicep` beside it is skipped. `-WhatIf` runs every
check and changes nothing; `-Name` limits it to playbooks whose
`Category/File` or file name matches.

```powershell
Import-Module ./Modules/iSOCDeployments/iSOCDeployments.psd1
Convert-iSOCPlaybook -WhatIf
Convert-iSOCPlaybook
```

It returns an `iSOCDeployments.ConvertRun`: `Results` (one per JSON
playbook, in repository order: `Name`, `Path`, `Bicep`, `Outcome`
(`Converted`, `WhatIf`, `Skipped` or `Failed`), `Reason`, `Warnings`), the
counts, `Duration` and `ExitCode` (1 when anything failed). It needs the
Bicep CLI on the PATH.

## The result

`Export-iSOCContent` returns an `iSOCDeployments.ExportRun`:
`ContentTypes`, `Path` (the folder written under), `Results`, the counts
`Created`, `Updated`, `Unchanged`, `Skipped`, `Failed` and `WhatIf`,
`Warnings` (how many items carry warnings), `Duration` and `ExitCode` (1
when anything failed). Each result is an `iSOCDeployments.ExportResult`:

| Property | Meaning |
| --- | --- |
| `ContentType`, `Name`, `Identity` | The content type, the display name (a Logic App's name) and the workspace's name for it (a workbook's GUID) |
| `Source` | `Custom` (the repository has it), `ContentHub` or `Orphan` |
| `Outcome` | `Created`, `Updated`, `Unchanged`, `Skipped`, `Failed` or `WhatIf` |
| `Reason` | Why, when the outcome is not a plain one; under `-WhatIf`, what it would do |
| `Path` | The file or folder, relative to the folder written under |
| `Warnings` | What to act on before committing |

`MIGRATION.md` edits E25 to E27 and E48 list every way the command
differs from the scripts: items found by identity rather than by path,
`-OnlyMissing` as the default, ambiguous playbooks skipped, paths never
written over, every page read, a failed read failing, the metadata key
order and depth, the playbook date kept, and playbooks written as Bicep.
