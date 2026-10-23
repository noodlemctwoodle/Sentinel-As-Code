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
> comparers) and the content type registry with analytics rules read,
> validated and turned into requests. The deploy, export, compare and sync
> commands arrive as each area is ported; [MIGRATION.md](MIGRATION.md)
> tracks which.

```powershell
Import-Module ./Modules/iSOCDeployments
Connect-AzAccount
Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel

Get-iSOCContentType
Test-iSOCDeploymentPrerequisite
```

## Commands

| Command | What it does | Needs |
| --- | --- | --- |
| `Connect-iSOCWorkspace` | Points the module at one workspace through the current Az sign-in; the result is the context every other command uses | Az.Accounts, `Connect-AzAccount` |
| `Get-iSOCContext` | The workspace the module is connected to | Nothing |
| `Get-iSOCContentType` | The content types, in deploy order, with their folder, endpoint, capabilities and compared fields | Nothing |
| `Test-iSOCDeploymentPrerequisite` | What this machine is missing for each step | Nothing |

Every command has full help: `Get-Help Connect-iSOCWorkspace -Full`.

Still to come, each replacing the scripts named in [MIGRATION.md](MIGRATION.md):
`Deploy-iSOCContent`, `Deploy-iSOCWorkspace`, `Export-iSOCContent`,
`Compare-iSOCContent`, `Export-iSOCDriftReport`, `Sync-iSOCContent`, the
Content Hub, dependency manifest, permission, set-up, community import and
table migration commands.

## What it needs

Only what a step uses has to be installed, and the module installs
nothing:

| Step | Needs |
| --- | --- |
| Connect | Az.Accounts 2.0.0 or later, signed in with `Connect-AzAccount` (in a pipeline, the AzurePowerShell task or `azure/login`) |
| Read | powershell-yaml 0.4.12 or later, to read YAML content |

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
  Kql/           dependency discovery in KQL (from Sentinel.Common)
  Drift/         comparers and canonical forms
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
