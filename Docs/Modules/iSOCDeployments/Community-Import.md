# Community rule import

`Import-iSOCCommunityRule` brings a community repository's analytics
rules into `Content/AnalyticalRules/Community/<Source>/`, normalised to
the repository's conventions and deploying disabled, with a manifest
beside them and a README under `Docs/Content/Community/`. It will replace
`Tools/Import-CommunityRules.ps1` at the 26.11.0 cut-over; until then the
script is the importer, and [Community rules](../../Content/Community-Rules.md)
describes how the community folders are governed.

```powershell
Import-Module ./Modules/iSOCDeployments

# What importing David Alonso's rules would change, writing nothing.
Import-iSOCCommunityRule -WhatIf

# The YAML rules and the rules in the ARM templates, as the committed tree has them.
Import-iSOCCommunityRule -IncludeKqlConversion

# From a checkout already on disk, without cloning.
Import-iSOCCommunityRule -SourcePath ~/src/Dalonso-Security-Repo -IncludeKqlConversion
```

It needs no Azure sign-in: only powershell-yaml, and git when it clones
(`Test-iSOCDeploymentPrerequisite -Step Import`).

`Tests/iSOCDeployments/CommunityImport.Tests.ps1` builds a synthetic
upstream git repository in David Alonso's layout (a rule the repository
already has, two rules sharing an id across categories, one with an
in-house rule's id, rules that are not valid, files the import ignores,
and ARM templates with rules, without them and broken). It then clones
it over `file://` twice: with the script, run unchanged from a copy of
this repository, and with the module, on another copy. It requires the
same rules, ids, manifest entries and README rows.

## From the script

| `Import-CommunityRules.ps1` | `Import-iSOCCommunityRule` |
| --- | --- |
| `-OutputPath`, `-DocsPath`, `-SourceRepo`, `-SourceBranch`, `-IncludeKqlConversion` | The same |
| `-DryRun` | `-WhatIf` |
| (David Alonso's settings, fixed in the script) | `-Source Dalonso`, the default |
| (none) | `-SourcePath` to read a checkout instead of cloning, `-RepoPath` |

## Sources

A source is a definition `Get-iSOCCommunitySource` returns:

| Key | Meaning |
| --- | --- |
| `Name` | What `-Source` takes, and the folder under `Content/AnalyticalRules/Community/` |
| `Repository`, `Branch` | What is cloned |
| `Attribution` | The paragraph put before every rule's description |
| `Tags` | The tags every rule gets |
| `YamlFolders` | Source folder to category, for folders of YAML rules |
| `ArmFolders` | Source folder to category, for folders of ARM templates (`-IncludeKqlConversion`) |
| `Title`, `About`, `Licence` | The README's heading, attribution and licence sections |

`Dalonso` is the one source so far. Adding a contributor with an import is
adding a definition; [Community rules](../../Content/Community-Rules.md)
covers what else a new contributor needs.

## What a run does

1. Clones the source's branch at depth 1 into a temporary folder (or
   reads `-SourcePath`), and notes its commit.
2. Reads the `*.yaml` files directly in each YAML folder, and with
   `-IncludeKqlConversion` every `alertRules` resource in every
   `azuredeploy.json` under each ARM folder, in ordinal order of name. A
   folder the source does not have is warned about and passed over.
3. Normalises each rule: it must have `id`, `name`, `kind`, `severity` and
   `query`, or it is skipped with the reason; it is set disabled; the
   attribution becomes its description's first paragraph; its tags gain
   the source's; a short trigger operator (`gt`) is spelt as the API does
   (`GreaterThan`). An ARM rule's shorthand durations (`5m`, `1h`, `1d`)
   become ISO 8601, and one without an `alertRuleTemplateName` gets a
   stable id from the source and its path.
4. Settles every rule's id, since the deployer names each rule in the
   workspace by its id and two files with one id would overwrite each
   other. In ordinal order of path: a rule whose file already exists keeps
   that file's id; any other keeps its upstream id unless another rule
   file in the repository (in-house, another contributor's, or another
   rule of this import) has it, and then gets a version 5 GUID from the
   source repository and its path, the same on every run.
5. Writes each rule to `<category>/<file>` under the output folder, unless
   the file holds that text already.
6. Writes `import-manifest.json` beside the rules (the source repository,
   branch and commit, the date, and each rule's SHA-256), and the README
   (the source's attribution and licence, the deployment note, rule counts
   per category, and each rule's name, severity and own first line). When
   the commit and every rule are as the manifest records, both keep their
   date, so an import that finds nothing new changes no file.
7. Removes the temporary clone.

Nothing is deleted from the output folder: a rule the upstream dropped
stays until someone removes it. With `-WhatIf` the source is cloned and
read, nothing is written, and each rule says what would be done. Every
file is UTF-8 without a byte order mark, with LF line endings and one
final newline.

## The result

`Import-iSOCCommunityRule` returns an `iSOCDeployments.CommunityImportRun`:
`Source`, `SourceRepo`, `SourceBranch`, `SourceCommit`, `OutputPath`,
`DocsPath`, `Results`, `IdChanges` (each rule whose id is not its
upstream's, and why), the counts `Created`, `Updated`, `Unchanged`,
`Skipped` and `WhatIf`, `Manifest` and `Readme` (what was done to each),
`Duration` and `ExitCode`. Each result is an
`iSOCDeployments.CommunityRuleResult`:

| Property | Meaning |
| --- | --- |
| `Category`, `Name`, `Path` | The category, the rule's name (its file name when it was skipped) and its file under the output folder |
| `Outcome` | `Created`, `Updated`, `Unchanged`, `Skipped` or `WhatIf` |
| `Reason` | Why it was skipped; under `-WhatIf`, what it would do |
| `Id`, `UpstreamId` | The id written, and the source's when they differ |

`MIGRATION.md` edits E28 to E31 list every way the command differs from
the script: sources as definitions, the attribution paragraph, a
`-WhatIf` that tells new from updated, files ending in one newline so a
repeat import changes nothing, the README's description column, and
stable ids for ARM rules without a template name.
