# iSOCDeployments

A PowerShell module that deploys, exports, compares and syncs the security
operations content kept in a Sentinel-As-Code repository: analytics rules,
hunting queries, parsers, watchlists, workbooks, playbooks, automation and
summary rules, Content Hub solutions and Defender XDR custom detections.
Each verb is one command that takes `-ContentType`, working over a registry
of content types, so deploy and drift can never disagree about where a
type's files are or what an item is called. Today it works with Microsoft
Sentinel workspaces; the public commands avoid the product name.

> **Status: in development for release 26.11.0.** The module is being
> built beside the scripts it replaces under `Deploy/` and `Tools/`, which
> still run every pipeline. What is here today is the core (logging, the
> REST client, the workspace context, the YAML and KQL helpers, the
> comparers), the content type registry, `Deploy-iSOCContent` for every
> content type `Deploy-CustomContent.ps1` deploys and the Defender XDR
> custom detections `Deploy-DefenderDetections.ps1` does, the Content Hub
> commands, compare, sync and the drift report for analytics rules,
> export for workbooks and playbooks, community rule import, playbook and
> runbook permissions, the service principal setup, the classic table
> migration and its review, and the dependency manifest commands. Export, compare and sync for the other types arrive as each
> area is ported; [MIGRATION.md](MIGRATION.md) tracks which.

```powershell
Import-Module ./Modules/iSOCDeployments
Connect-AzAccount
Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel

Get-iSOCContentType
Deploy-iSOCContent -WhatIf
```

## Commands

| Command | What it does | Needs |
| --- | --- | --- |
| `Connect-iSOCWorkspace` | Points the module at one workspace through the current Az sign-in; the result is the context every other command uses | Az.Accounts, `Connect-AzAccount` |
| `Deploy-iSOCContent` | Deploys parsers, watchlists, analytics rules, hunting queries, playbooks, workbooks, automation rules and summary rules in dependency order, then Defender XDR custom detections through Microsoft Graph, with smart deployment and `-WhatIf` | Az.Accounts, powershell-yaml, a connected workspace; Az.Resources when there are playbooks; the `CustomDetection.ReadWrite.All` Graph permission when there are Defender detections |
| `Get-iSOCContentHubSolution` | Where Content Hub solutions stand: installed and available versions, and what installing them would do | Az.Accounts, a connected workspace |
| `Grant-iSOCPlaybookPermission` | Assigns each Sentinel-As-Code playbook's managed identity the RBAC roles its workflow needs, leaving those it has, with `-WhatIf` | Az.Accounts, a connected workspace, Owner or User Access Administrator on the scopes |
| `Grant-iSOCRunbookPermission`, `Revoke-iSOCRunbookPermission` | Assign or remove the DCR watchlist sync runbook's two roles, asking first | Az.Accounts, a connected workspace, Owner or User Access Administrator on the subscription |
| `Initialize-iSOCServicePrincipal` | Gives the deployment service principal Contributor, a conditioned User Access Administrator, Security Administrator and CustomDetection.ReadWrite.All, once, asking first | Az.Accounts; Microsoft.Graph.Authentication for the last two; Owner and Privileged Role Administrator |
| `Import-iSOCCommunityRule` | Imports a community repository's analytics rules (David Alonso's, so far) under `Content/AnalyticalRules/Community/`, normalised, disabled and with ids no other rule uses, with its manifest and README, with `-WhatIf` | powershell-yaml; git to clone |
| `Install-iSOCContentHubSolution` | Installs or updates Content Hub solutions, then deploys the analytics rules and workbooks they ship, protecting rules changed in the workspace, with `-WhatIf` | Az.Accounts, a connected workspace |
| `Compare-iSOCContent` | What was changed in the workspace and not in the repository: each analytics rule classed by its source of truth and compared with it field by field | Az.Accounts, powershell-yaml, a connected workspace |
| `Sync-iSOCContent` | Writes a compare's drift into the repository: portal edits into their files, customised Content Hub and portal-only rules into new ones, with `-WhatIf` | powershell-yaml |
| `Export-iSOCContent` | Writes the workspace's workbooks and playbooks into the repository, ready to deploy: new items to new files, items the repository has only with `-Force`, environment values made portable, with `-WhatIf` | Az.Accounts, a connected workspace |
| `Export-iSOCDriftReport` | Writes a compare's result as the JSON and Markdown drift report, when anything drifted | Nothing |
| `Get-iSOCContext` | The workspace the module is connected to | Nothing |
| `Get-iSOCTableMigrationImpact` | The classic custom log tables and what depends on each, directly or through parser functions, with their Content Hub solutions; read-only | Az.Accounts, a connected workspace |
| `Invoke-iSOCClassicTableMigration` | Migrates classic custom log tables to DCR-based ones and writes, and with `-Deploy` deploys, a data collection rule for each, asking before each migration | Az.Accounts, Az.OperationalInsights, Az.Resources with `-Deploy`, a connected workspace |
| `Export-iSOCTableMigrationReport` | Writes a table migration review as CSV, JSON and a self-contained HTML report | Nothing |
| `Get-iSOCContentType` | The content types, in deploy order, with their folder, endpoint, capabilities and compared fields | Nothing |
| `Get-iSOCContentDependency` | The tables, watchlists, functions and external data a content file's KQL reads | powershell-yaml |
| `Test-iSOCDependencyManifest` | Whether `dependencies.json` matches the content, with the differences | powershell-yaml |
| `Update-iSOCDependencyManifest` | Rewrites `dependencies.json` when it is out of date | powershell-yaml |
| `Test-iSOCDeploymentPrerequisite` | What this machine is missing for each step | Nothing |

Every command has full help: `Get-Help Connect-iSOCWorkspace -Full`.

Still to come, each replacing the scripts named in [MIGRATION.md](MIGRATION.md):
`Deploy-iSOCWorkspace`, the migration rehearsal aids and `New-iSOCDcrFromSchema`.

## What it needs

Only what a step uses has to be installed, and the module installs
nothing:

| Step | Needs |
| --- | --- |
| Connect | Az.Accounts 2.0.0 or later, signed in with `Connect-AzAccount` (in a pipeline, the AzurePowerShell task or `azure/login`) |
| Read | powershell-yaml 0.4.12 or later, to read YAML content |
| Deploy | Az.Resources 6.0.0 or later, only when there are playbooks to deploy: they deploy as ARM templates through it |
| Import | git 2.0 or later on the PATH, to clone a community rule source |
| Setup | Microsoft.Graph.Authentication 2.0.0 or later, for the service principal's directory role and Graph permission |
| Migrate | Az.OperationalInsights 3.0.0 or later, for the row counts and volume the classic table migration reads |

The cloud is the sign-in's: the ARM and Graph hosts come from its
environment, so US Government needs no switch. Nothing the module logs
names the subscription or the workspace id.

## How it is laid out

```text
iSOCDeployments.psd1 / .psm1   manifest and loader (Private/** then Public/*)
Public/                        one exported command per file
Private/
  Core/          logging, API versions, context, repository paths, requirements
  Az/            the only files that call Az cmdlets
  Rest/          the only files that call REST (Invoke-AzRestMethod)
  Yaml/          loading powershell-yaml, reading and writing YAML
  Kql/           dependency discovery in KQL (from Sentinel.Common), and the
                 code-only reading the parser chains use
  Drift/         comparers, canonical forms, the drift run and its report
  Export/        an item's files, export results, portable values, the secret scan
  Community/     community rule import
  Git/           the only file that runs git
  Permissions/   role assignments, playbook and runbook roles, service principal setup
  Graph/         the only files that run Graph SDK commands
  Manifest/      the dependency manifest
  Deploy/        the deploy engine
  State/         deployment-state.json
  ContentHub/    Content Hub solutions
  MigrationKits/ the classic table migration and its review
  ContentTypes/  the registry, and one folder per content type with its
                 definition and handlers
```

Every file defines exactly one function, named after the file. The rules
the code keeps to (no `exit`, no installs, Az and REST only in their
folders, console output only through the logger) are enforced by
`Tests/iSOCDeployments/Module.Tests.ps1`.

[Docs/Modules/iSOCDeployments/Architecture.md](../../Docs/Modules/iSOCDeployments/Architecture.md)
describes the context, the REST client, the content type definition and
its handlers, the comparers and how to add a content type.
[Content-Types.md](../../Docs/Modules/iSOCDeployments/Content-Types.md)
lists each type and what the module can do with it so far.

## The iSOC Blueprint is a separate module

The iSOC Blueprint, the other module in this repository, documents and
assesses a workspace and only ever reads; this module changes workspaces
and the repository. The two share no
files, helpers or imports, and are versioned and released on their own.
Neither loads the other.

## Testing

```powershell
Invoke-Pester -Path Tests/iSOCDeployments
```

The suites run offline. Beside the unit tests, the parity tests run the
old scripts' functions next to the module's over every file in `Content/`
and require the same result; they go when the old scripts do.
