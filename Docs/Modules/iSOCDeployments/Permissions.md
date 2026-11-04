# Permissions: playbooks and the DCR runbook

Three commands assign the Azure RBAC roles the repository's managed
identities need. None of them runs in a pipeline: the deployment service
principal's User Access Administrator is conditioned and cannot assign the
Sentinel roles, so they are run by an identity with Owner or User Access
Administrator on the scopes concerned.

| Command | Replaces |
| --- | --- |
| `Grant-iSOCPlaybookPermission` | `Deploy/permissions/Set-PlaybookPermissions.ps1` |
| `Grant-iSOCRunbookPermission` | `Deploy/permissions/Set-RunbookPermissions.ps1` |
| `Revoke-iSOCRunbookPermission` | `Deploy/permissions/Set-RunbookPermissions.ps1 -Remove` |

They replace the scripts at the 26.11.0 cut-over. All three go through the
module's REST client, so they need Az.Accounts and a sign-in, and neither
Az.Resources nor the az CLI.

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

## From the scripts

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

`MIGRATION.md` edits E32 and E33 list how the commands differ from the
scripts. The role analysis and the already-assigned check are as
`Set-PlaybookPermissions.ps1` 1.0.2 has them: that release stopped a PUT
pattern giving Microsoft Sentinel Contributor to 44 of this repository's 90
playbooks, made the already-assigned check find assignments, and made the
script read safely under strict mode.
