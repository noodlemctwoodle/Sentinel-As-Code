# PowerShell Module Requirements

A complete audit of every PowerShell module, external binary, **and Azure /
Entra ID / Graph permission** the Sentinel-As-Code scripts depend on, grouped
by what you are trying to do: **validate** the project (run the test suite / PR
gate) or **use** it (deploy content and run the tooling).

Derived from the `#Requires` statements, module manifests, `Install-Module`
calls, cmdlet usage, and role/permission grants across `Deploy/`, `Tools/`, and
`Modules/`. The code is the source of truth; if a script changes its
dependencies or permissions, update this doc in the same PR.

## Baseline runtime

- **PowerShell 7.2 or later** - required by every script and declared in the
  `Sentinel.Common` manifest (`PowerShellVersion = '7.2'`).

## Modules required to validate the project

These are all you need to run the Pester suite and the PR-validation gate via
[`Tools/Invoke-PRValidation.ps1`](../../Tools/Invoke-PRValidation.ps1). CI pins
exact versions in
[`.github/actions/setup-pwsh-modules/action.yml`](../../.github/actions/setup-pwsh-modules/action.yml).

| Module | Pinned version (CI) | Local minimum | Why |
| --- | --- | --- | --- |
| `Pester` | 5.7.1 | 5.0.0 | Runs every `Tests/*.Tests.ps1` suite |
| `powershell-yaml` | 0.4.12 | any | YAML schema tests, dependency-manifest gate, content parsing |
| `Az.Accounts` | 2.0.0+ | 2.0.0 | Hard dependency of `Sentinel.Common`, imported transitively by the module-unit tests |

All other Az / Microsoft.Graph cmdlets used by the deploy scripts are **mocked**
in the test suite (`Mock -ModuleName Sentinel.Common ...`), so they are not
needed to validate the project.

## Modules required to use the project

| Module | Required by | Declared via |
| --- | --- | --- |
| `Az.Accounts` | `Sentinel.Common` manifest; [`Deploy-CustomContent.ps1`](../../Deploy/content/Deploy-CustomContent.ps1), [`Deploy-SentinelContentHub.ps1`](../../Deploy/content/Deploy-SentinelContentHub.ps1), [`Deploy-DefenderDetections.ps1`](../../Deploy/content/Deploy-DefenderDetections.ps1), [`Export-SentinelWorkbooks.ps1`](../../Tools/Export-SentinelWorkbooks.ps1), [`Invoke-DCRWatchlistSync.ps1`](../../Tools/Invoke-DCRWatchlistSync.ps1), [`Test-SentinelRuleDrift.ps1`](../../Tools/Test-SentinelRuleDrift.ps1) | `#Requires` / manifest |
| `Az.Resources` | [`Deploy-CustomContent.ps1`](../../Deploy/content/Deploy-CustomContent.ps1) (playbook ARM deploy via `New`/`Test-AzResourceGroupDeployment`), [`Set-PlaybookPermissions.ps1`](../../Deploy/permissions/Set-PlaybookPermissions.ps1) (`Get-AzResource`, `*-AzRoleAssignment`), [`Setup-ServicePrincipal.ps1`](../../Deploy/setup/Setup-ServicePrincipal.ps1) | cmdlet usage / `Requires:` header |
| `Az.LogicApp` | Declared in [`Set-PlaybookPermissions.ps1`](../../Deploy/permissions/Set-PlaybookPermissions.ps1)'s `Requires:` header, but the script reads Logic App resources via `Get-AzResource` (`Az.Resources`) and assigns roles via `*-AzRoleAssignment`; no `Az.LogicApp` cmdlet is actually called, so the dependency is effectively unused today | `Requires:` header |
| `Az.KeyVault` | Playbook permissions / Key Vault references (per [Scripts](Scripts.md)) | docs |
| `Az.ManagedServiceIdentity` | Service-principal / managed-identity setup (per [Scripts](Scripts.md)) | docs |
| `Az.OperationalInsights` | [`Sentinel-Deploy.yml`](../../Pipelines/Sentinel-Deploy.yml) and the nightly workflow (`Get-AzOperationalInsightsWorkspace`); Documenter collector | cmdlet usage |
| `Microsoft.Graph.Applications` | [`Setup-ServicePrincipal.ps1`](../../Deploy/setup/Setup-ServicePrincipal.ps1) | `Install-Module` (auto) |
| `Microsoft.Graph.Identity.DirectoryManagement` | [`Setup-ServicePrincipal.ps1`](../../Deploy/setup/Setup-ServicePrincipal.ps1) | `Install-Module` (auto) |
| `powershell-yaml` | [`Deploy-CustomContent.ps1`](../../Deploy/content/Deploy-CustomContent.ps1), [`Deploy-DefenderDetections.ps1`](../../Deploy/content/Deploy-DefenderDetections.ps1), [`Import-CommunityRules.ps1`](../../Tools/Import-CommunityRules.ps1), [`Build-DependencyManifest.ps1`](../../Tools/Build-DependencyManifest.ps1), [`Test-SentinelRuleDrift.ps1`](../../Tools/Test-SentinelRuleDrift.ps1) | `Install-Module` (auto) |
| `Sentinel.Common` (local) | Every deploy script plus [`Build-DependencyManifest.ps1`](../../Tools/Build-DependencyManifest.ps1) | `Import-Module` from `Modules/` |

Scripts marked **(auto)** install the module on first run if it is missing.
Pre-installing avoids interactive prompts in non-interactive contexts.

[`Invoke-DCRWatchlistSync.ps1`](../../Tools/Invoke-DCRWatchlistSync.ps1) deliberately
avoids `Az.ResourceGraph` - it lists DCRs and their associations by calling
`Invoke-AzRestMethod` directly against the ARM REST API, so `Az.Accounts` (for
the authenticated context) is the only module it needs.

## Sentinel Documenter

The read-only Documenter (`Tools/Documenter/`) pins its own module set in
[`Documenter.psd1`](../../Tools/Documenter/Documenter.psd1). The collector
imports the Az modules; the renderer only needs `powershell-yaml`.

| Module | Pinned version |
| --- | --- |
| `Az.Accounts` | 3.0.4 |
| `Az.SecurityInsights` | 3.1.2 |
| `Az.OperationalInsights` | 3.2.0 |
| `Az.Monitor` | 5.2.1 |
| `Az.Resources` | 7.4.0 |
| `Az.LogicApp` | 1.7.0 |
| `powershell-yaml` | 0.4.12 |

## Companion workbook export

[`Content/Workbooks/SentinelDataLake/Export-SdlMigrationWorkbook.ps1`](../../Content/Workbooks/SentinelDataLake/Export-SdlMigrationWorkbook.ps1)
is a standalone helper (not part of the deploy path) that needs:
`Az.Accounts`, `Az.OperationalInsights`, and `ImportExcel`.

## External (non-module) dependencies

| Dependency | Required by |
| --- | --- |
| `git` (2.x+ on PATH) | [`Import-CommunityRules.ps1`](../../Tools/Import-CommunityRules.ps1), [`Migrate-ForkLayout.ps1`](../../Tools/Migrate-ForkLayout.ps1) |
| `pandoc` (on PATH) | [`Convert-MarkdownToWord.ps1`](../../Tools/Documenter/Report/Convert-MarkdownToWord.ps1), [`Convert-FolderToWordReport.ps1`](../../Tools/Documenter/Report/Convert-FolderToWordReport.ps1) |
| Node.js + `@mermaid-js/mermaid-cli` | [`Convert-MermaidToImage.ps1`](../../Tools/Documenter/Convert-MermaidToImage.ps1) |
| Azure CLI + Bicep (`az bicep build`) | PR-validation `bicep-build` job |
| Azure CLI (`az`) | [`Set-RunbookPermissions.ps1`](../../Deploy/permissions/Set-RunbookPermissions.ps1) (`az automation account show`, `az role assignment create` / `delete` / `list`) |

## Quick install

```powershell
# Minimum to validate (run the test suite locally)
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module powershell-yaml -RequiredVersion 0.4.12 -Scope CurrentUser -Force
Install-Module Az.Accounts -MinimumVersion 2.0.0 -Scope CurrentUser -Force

# Full runtime (deploy content + run the tooling)
Install-Module Az.Resources, Az.KeyVault, Az.ManagedServiceIdentity, `
    Az.LogicApp, Az.OperationalInsights, Az.SecurityInsights, Az.Monitor `
    -Scope CurrentUser -Force
Install-Module Microsoft.Graph.Applications, `
    Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser -Force

# Only for the standalone SDL workbook export
Install-Module ImportExcel -Scope CurrentUser -Force
```

## Permissions

Modules get you the cmdlets; you still need the right Azure RBAC roles, Entra
ID directory roles, and Microsoft Graph application permissions for the
scripts to do anything against a live tenant. The pipeline service principal
is bootstrapped once by
[`Setup-ServicePrincipal.ps1`](../../Deploy/setup/Setup-ServicePrincipal.ps1);
two managed-identity grants are applied separately because the pipeline SPN
deliberately cannot assign Sentinel-tier roles.

### Pipeline service principal (deploy + content)

Granted by [`Setup-ServicePrincipal.ps1`](../../Deploy/setup/Setup-ServicePrincipal.ps1)
(run once by a user who holds **Owner** on the subscription **and** at least
**Privileged Role Administrator** in Entra ID).

| Permission | Type | Scope | Purpose |
| --- | --- | --- | --- |
| `Contributor` | Azure RBAC | Subscription | Resource group, workspace, Bicep, content, summary rules. Implies `Reader` (which ADO needs to save a workload-identity service connection). |
| `User Access Administrator` (ABAC-conditioned) | Azure RBAC | Subscription | Playbook managed-identity role assignments. The ABAC condition restricts it to assigning only: Microsoft Sentinel Responder, Microsoft Sentinel Reader, Log Analytics Reader, Logic App Contributor, Managed Identity Operator. |
| `Security Administrator` | Entra ID directory role | Tenant | UEBA and Entity Analytics settings. Optional (`-SkipEntraRole`); can be enabled manually in the portal instead. |
| `CustomDetection.ReadWrite.All` | Microsoft Graph application permission | Tenant | Defender XDR custom detection rules (deploy stage 5). Optional (`-SkipGraphPermission`); requires **admin consent**. |

The person running the bootstrap script needs **Owner** (subscription) plus
**Privileged Role Administrator** (Entra ID). After it runs once, the pipeline
is autonomous.

### Playbook managed identities

Assigned by
[`Set-PlaybookPermissions.ps1`](../../Deploy/permissions/Set-PlaybookPermissions.ps1)
as a post-deployment step. The deploy SPN's ABAC-conditioned UAA does **not**
permit Sentinel-tier role assignments, so this runs as an **ad-hoc step by a
separate identity holding User Access Administrator or Owner** on the playbook
resource group (and the Sentinel RG, if different). Roles are derived per
playbook from its connectors and HTTP actions:

| Role | Scope | Triggered by |
| --- | --- | --- |
| `Microsoft Sentinel Responder` | Sentinel RG | `azuresentinel` / `microsoftsentinel` connector |
| `Microsoft Sentinel Contributor` | Sentinel RG | Playbook modifies incidents/watchlists, or HTTP PUT to `management.azure.com` (upgrade from Responder) |
| `Key Vault Secrets User` | Key Vault | `keyvault` connector |
| `Log Analytics Reader` | Sentinel RG | `azuremonitorlogs` connector or `api.loganalytics.io` HTTP action |

Graph and Defender HTTP actions (`graph.microsoft.com`,
`api.securitycenter.microsoft.com`) are handled via app-registration
permissions, not RBAC.

### DCR Watchlist Sync automation account

Assigned by
[`Set-RunbookPermissions.ps1`](../../Deploy/permissions/Set-RunbookPermissions.ps1)
(run once by a user with **Owner** or **User Access Administrator** on the
subscription). The pipeline SPN lacks `Microsoft.Authorization/roleAssignments/write`,
so this is a manual step:

| Role | Scope | Purpose |
| --- | --- | --- |
| `Monitoring Reader` | Subscription | List DCRs and their associations via ARM |
| `Microsoft Sentinel Contributor` | Sentinel RG | Create and update the Sentinel watchlist |

### Resource providers

`Microsoft.OperationsManagement` and `Microsoft.SecurityInsights` are
registered automatically by the pipeline during infrastructure deployment, so
no manual provider registration is required.
