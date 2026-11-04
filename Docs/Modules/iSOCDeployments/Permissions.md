# Permissions: the service principal, playbooks and the DCR runbook

Four commands give identities the permissions the repository needs. None
of them runs in a pipeline. `Initialize-iSOCServicePrincipal` sets up the
deployment service principal the pipelines run as, once. The other three
assign the roles the playbooks' and the DCR runbook's managed identities
need: the deployment service principal's User Access Administrator is
conditioned and cannot assign the Sentinel roles, so they are run by an
identity with Owner or User Access Administrator on the scopes concerned.

| Command | Replaces |
| --- | --- |
| `Initialize-iSOCServicePrincipal` | `Deploy/setup/Setup-ServicePrincipal.ps1` |
| `Grant-iSOCPlaybookPermission` | `Deploy/permissions/Set-PlaybookPermissions.ps1` |
| `Grant-iSOCRunbookPermission` | `Deploy/permissions/Set-RunbookPermissions.ps1` |
| `Revoke-iSOCRunbookPermission` | `Deploy/permissions/Set-RunbookPermissions.ps1 -Remove` |

They replace the scripts at the 26.11.0 cut-over. They go through the
module's REST client, so they need Az.Accounts and a sign-in, and neither
Az.Resources nor the az CLI; the service principal's directory role and
Graph permission also need Microsoft.Graph.Authentication
(`Test-iSOCDeploymentPrerequisite -Step Setup`).

```powershell
Import-Module ./Modules/iSOCDeployments
Connect-AzAccount
Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel -PlaybookResourceGroup rg-automation

# The roles each playbook would be given, assigning none.
Grant-iSOCPlaybookPermission -KeyVaultName kv-sentinel -WhatIf

# Assign them.
Grant-iSOCPlaybookPermission -KeyVaultName kv-sentinel

# The DCR watchlist sync runbook: asks before each change.
Grant-iSOCRunbookPermission -AutomationAccountName aa-dcr-watchlist-sync -AutomationResourceGroup rg-dcr-watchlist-sync
```

`Tests/iSOCDeployments/Permissions.Tests.ps1` runs both scripts unchanged
in a child pwsh, with the Az cmdlets and az stood in for over a stand-in
tenant, and runs the commands against the same tenant. The tenant has
playbooks needing each kind of role, an untagged one, one without an
identity, one needing nothing, ones already holding their role at the
resource group or from the subscription, one refused, and one that wins a
race (a conflict). The suite requires the same role assignments
attempted, created and removed, and the same counts.

## The deployment service principal

```powershell
Connect-AzAccount
Initialize-iSOCServicePrincipal -ServicePrincipalAppId $appId -WhatIf
Initialize-iSOCServicePrincipal -ServicePrincipalAppId $appId
```

Run it once, as someone with Owner on the subscription and at least
Privileged Role Administrator in Entra ID; no workspace is needed, as it
runs before the pipelines create one. It gives the service principal:

| Grant | Scope | For |
| --- | --- | --- |
| Contributor | Subscription | Resource groups, the workspace, Bicep and content |
| User Access Administrator, conditioned (ABAC) to assign and remove only Microsoft Sentinel Responder, Microsoft Sentinel Reader, Log Analytics Reader, Logic App Contributor and Managed Identity Operator | Subscription | The playbook identities' role assignments during ARM deployment |
| Security Administrator (`-SkipEntraRole` leaves it out) | Directory | UEBA and Entity Analytics settings |
| CustomDetection.ReadWrite.All, with admin consent (`-SkipGraphPermission` leaves it out) | Microsoft Graph | Defender XDR custom detections |

A grant the service principal already has is left alone. The Azure roles
go through the Az sign-in. The directory role and the Graph permission
need a Microsoft Graph SDK sign-in with RoleManagement.ReadWrite.Directory,
AppRoleAssignment.ReadWrite.All and Application.Read.All, to the Az
sign-in's tenant: the Az sign-in's own Graph token does not carry those
scopes. One sign-in is opened, with every scope the chosen steps need,
unless the current one already has them. Each grant asks for confirmation
unless `-Confirm:$false` is given; a failed grant is reported and the run
goes on, with `ExitCode` 1.

`Tests/iSOCDeployments/Setup.Tests.ps1` runs
`Deploy/setup/Setup-ServicePrincipal.ps1` unchanged in a child pwsh, its
Az, Graph SDK and `Read-Host` commands stood in for, beside the command
against the same stand-in tenant, and requires the same role assignments,
directory role assignment and app role assignment.

## From the scripts

| `Setup-ServicePrincipal.ps1` | `Initialize-iSOCServicePrincipal` |
| --- | --- |
| `-SubscriptionId` | The same; it defaults to the Az sign-in's |
| `-ServicePrincipalAppId`, `-SkipEntraRole`, `-SkipGraphPermission` | The same |
| The `Y/N` consent prompt | The confirmation prompt; `-Confirm:$false` to skip it, `-WhatIf` to preview |

| `Set-PlaybookPermissions.ps1` | `Grant-iSOCPlaybookPermission` |
| --- | --- |
| `-SubscriptionId`, `-PlaybookResourceGroup`, `-SentinelResourceGroup`, `-SentinelWorkspaceName` | `Connect-iSOCWorkspace -SubscriptionId -ResourceGroup -WorkspaceName -PlaybookResourceGroup` first (or `-Context`) |
| `-KeyVaultName` | The same |
| `-WhatIf` (a switch of its own) | `-WhatIf`, and `-Confirm` |
| (none) | `-Name`, Logic Apps by wildcard |
| exit code 1 on a failure | The result's `ExitCode` |

| `Set-RunbookPermissions.ps1` | `Grant-` / `Revoke-iSOCRunbookPermission` |
| --- | --- |
| `-SubscriptionId`, `-SentinelResourceGroup` | `Connect-iSOCWorkspace -SubscriptionId -ResourceGroup` first (or `-Context`) |
| `-AutomationAccountName`, `-AutomationResourceGroup` | The same |
| `-Remove` | `Revoke-iSOCRunbookPermission` |
| The `Y/N` consent prompt | The confirmation prompt; `-Confirm:$false` to skip it, `-WhatIf` to preview |

## Playbooks

Every Logic App in the playbook resource group tagged
`Source: Sentinel-As-Code` is read, and its workflow says which roles it
needs:

| Found in the workflow | Role | Scope |
| --- | --- | --- |
| The `azuresentinel` or `microsoftsentinel` connector | Microsoft Sentinel Responder | Sentinel resource group |
| A change to Sentinel: an `/Incidents` or `/Watchlists` path, an `Update_incident` action, or a `"method": "put"` request | Microsoft Sentinel Contributor, instead of Responder | Sentinel resource group |
| The `keyvault` connector | Key Vault Secrets User | The vault named by `-KeyVaultName`, in the Sentinel resource group |
| The `azuremonitorlogs` or `azureloganalyticsdatacollector` connector, or an HTTP action to `api.loganalytics.io` with the managed identity | Log Analytics Reader | Sentinel resource group |
| An HTTP action to `management.azure.com` with the managed identity | Microsoft Sentinel Contributor | Sentinel resource group |

HTTP actions to Microsoft Graph or the Defender API get no RBAC role:
their permissions come through the app registration. The identity is the
Logic App's system-assigned one, else its first user-assigned one. A role
it already has at the scope, or inherited from above (the subscription,
or the resource group for the vault), is left alone. A Key Vault role
without `-KeyVaultName` is skipped with the reason. Nothing is removed.

## The runbook

The DCR watchlist sync runbook needs Monitoring Reader on the subscription,
to list data collection rules and their associations, and Microsoft
Sentinel Contributor on the Sentinel resource group only, to write the
watchlist. `Grant-iSOCRunbookPermission` reads the Automation Account's
system-assigned identity, lists the two roles and why, and assigns each
the identity does not already have at that scope or above, asking first:
these are subscription-wide permissions, to review against your
organisation's least-privilege and compliance policies and to audit
regularly. Afterwards the identity's assignments in the subscription are in
the result. `Revoke-iSOCRunbookPermission` deletes each role's assignment at
exactly its scope, and leaves one inherited from above, which it did not
make.

## The result

Each command returns an `iSOCDeployments.PermissionRun`: `Results`, the
counts `Assigned`, `Removed`, `Unchanged`, `Skipped`, `Failed` and
`WhatIf`, `Duration`, `ExitCode` (1 when anything failed) and, from
`Grant-iSOCRunbookPermission`, `Assignments`. Each result is an
`iSOCDeployments.PermissionResult`:

| Property | Meaning |
| --- | --- |
| `Name` | The playbook or Automation Account |
| `PrincipalId` | Its managed identity's principal |
| `Role`, `Scope` | The role and where it applies; no role for a playbook given none |
| `Outcome` | `Assigned`, `Removed`, `Unchanged`, `Skipped`, `Failed` or `WhatIf` |
| `Reason` | Why, when the outcome is not a plain one |

Assignments are created with the principal type ServicePrincipal and named
by a GUID made from the scope, principal and role, so creating one twice
changes nothing; one that already exists under another name is reported
Unchanged.

`MIGRATION.md` edits E32 to E34 list how the commands differ from the
scripts. The role analysis and the already-assigned check are as
`Set-PlaybookPermissions.ps1` 1.0.2 has them: that release stopped a PUT
pattern giving Microsoft Sentinel Contributor to 44 of this repository's 90
playbooks, made the already-assigned check find assignments, and made the
script read safely under strict mode.
