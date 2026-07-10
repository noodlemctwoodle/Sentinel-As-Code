# Sentinel-As-Code - Build and Test Guide

**Running and validating without a local PowerShell install**

| **Prepared for** | Any organisation adopting Sentinel-As-Code |
|------------------|---------------------------------------------------|
| **Version**      | 1.0 |
| **Applies to**   | The Sentinel-As-Code repository |

---

## Contents

- [Sentinel-As-Code - Build and Test Guide](#sentinel-as-code---build-and-test-guide)
  - [Contents](#contents)
  - [Executive summary](#executive-summary)
  - [1 Purpose and audience](#1-purpose-and-audience)
    - [1.1 The constraint](#11-the-constraint)
    - [1.2 What this guide gives you](#12-what-this-guide-gives-you)
  - [2 What you are building and testing](#2-what-you-are-building-and-testing)
  - [3 Requirements](#3-requirements)
    - [3.1 Baseline runtime](#31-baseline-runtime)
    - [3.2 Modules required to validate the project](#32-modules-required-to-validate-the-project)
    - [3.3 Modules required to use (deploy) the project](#33-modules-required-to-use-deploy-the-project)
    - [3.4 Sentinel Documenter modules](#34-sentinel-documenter-modules)
    - [3.5 External (non-module) dependencies](#35-external-non-module-dependencies)
    - [3.6 Permissions](#36-permissions)
      - [3.6.1 Pipeline service principal (deploy + content)](#361-pipeline-service-principal-deploy--content)
      - [3.6.2 Playbook managed identities](#362-playbook-managed-identities)
      - [3.6.3 DCR Watchlist Sync automation account](#363-dcr-watchlist-sync-automation-account)
      - [3.6.4 Defender XDR export tool](#364-defender-xdr-export-tool)
      - [3.6.5 Resource providers](#365-resource-providers)
  - [4 Choosing a no-local-install execution method](#4-choosing-a-no-local-install-execution-method)
    - [4.1 Recommendation](#41-recommendation)
  - [5 Recommended primary: Windows 365 Cloud PC](#5-recommended-primary-windows-365-cloud-pc)
    - [5.1 What IT installs on the Cloud PC image](#51-what-it-installs-on-the-cloud-pc-image)
    - [5.2 Provision and connect](#52-provision-and-connect)
    - [5.3 Get the code and run the tests](#53-get-the-code-and-run-the-tests)
    - [5.4 Deploy interactively (optional)](#54-deploy-interactively-optional)
    - [5.5 Other managed-desktop variants](#55-other-managed-desktop-variants)
  - [6 Alternative: Azure Cloud Shell](#6-alternative-azure-cloud-shell)
    - [6.1 One-time setup](#61-one-time-setup)
    - [6.2 Get the code and validation modules](#62-get-the-code-and-validation-modules)
    - [6.3 Run the tests](#63-run-the-tests)
    - [6.4 Deploy interactively (optional)](#64-deploy-interactively-optional)
  - [7 Alternative: GitHub Codespaces / dev container](#7-alternative-github-codespaces--dev-container)
    - [7.1 When to use it](#71-when-to-use-it)
    - [7.2 Setup outline](#72-setup-outline)
  - [8 Alternative: CI/CD only (no interactive PowerShell)](#8-alternative-cicd-only-no-interactive-powershell)
    - [8.1 How validation runs](#81-how-validation-runs)
    - [8.2 How deployment runs](#82-how-deployment-runs)
  - [9 Alternative: container image](#9-alternative-container-image)
    - [9.1 Setup outline](#91-setup-outline)
  - [10 Quick reference: install commands](#10-quick-reference-install-commands)
    - [10.1 Minimum to validate (run the test suite)](#101-minimum-to-validate-run-the-test-suite)
    - [10.2 Full runtime (deploy content + run the tooling)](#102-full-runtime-deploy-content--run-the-tooling)
    - [10.3 Only for the standalone SDL workbook export](#103-only-for-the-standalone-sdl-workbook-export)
    - [10.4 Run the validation gate](#104-run-the-validation-gate)
  - [11 Microsoft Learn references](#11-microsoft-learn-references)
    - [11.1 Runtime, modules and testing](#111-runtime-modules-and-testing)
    - [11.2 Local developer tooling](#112-local-developer-tooling)
    - [11.3 Execution environments](#113-execution-environments)
    - [11.4 Permissions, roles and identity](#114-permissions-roles-and-identity)
    - [11.5 API schemas and resource definitions](#115-api-schemas-and-resource-definitions)

---

## Executive summary

Your organisation needs to build, test and deploy the Sentinel-As-Code
solution, which requires full end-to-end testing of every configuration item
locally in PowerShell before it is promoted. Because PowerShell 7, the Az
modules and related tooling often cannot be installed on managed end-user
devices, this guide sets out sanctioned methods that provide that same local
PowerShell testing in a controlled Azure or cloud-hosted environment.

The work divides into two activities. **End-to-end testing** runs the full
Pester test suite, the PR-validation gate and a deployment dry-run that
exercises every analytics rule, playbook, workbook and automation rule. It must
be carried out locally in PowerShell 7 against a test workspace so that all
configuration is validated before promotion. **Deployment** authenticates to
Azure and is normally carried out by the CI/CD pipeline rather than by a person,
so it does not depend on any individual workstation.

The recommended primary method is **a Windows 365 Cloud PC**: a persistent,
Intune-managed desktop on which IT installs PowerShell 7, the required modules
and the full developer toolchain once. It gives engineers a governed environment
in which to run the complete end-to-end tests locally in PowerShell, with
nothing installed on their own device. Four alternatives are documented - Azure
Cloud Shell, GitHub Codespaces, CI/CD-only and a container image - so each team
can adopt the approach that best fits its security posture. All requirements in
this guide are derived from the repository's own scripts, module manifests and
CI configuration, which remains the single source of truth.

**At a glance**

- Constraint: no local install of PowerShell, the Az modules or related tooling
  on managed devices.
- Test (validate): full end-to-end testing of every configuration item, run
  locally in PowerShell 7 - the Pester suite, the PR-validation gate and a
  deployment dry-run against a test workspace.
- Use (deploy): PowerShell 7.2 or later, the Az and Microsoft.Graph modules and
  the right Azure permissions; normally pipeline-driven.
- Recommended method: a Windows 365 Cloud PC with all tools pre-installed,
  giving a governed place to run the local PowerShell end-to-end tests; Azure
  Cloud Shell, GitHub Codespaces, CI/CD-only and a container image are
  alternatives.
- Baseline runtime: PowerShell 7.2 or later; Windows PowerShell 5.1 is not
  supported.

## 1 Purpose and audience

This guide explains everything your organisation needs to build, run and test
the Sentinel-As-Code solution, and gives a practical method to do so **without
installing PowerShell, the Az modules, or any other tooling on a local
workstation**.

It is written for the platform, security and DevOps engineers who will own the
Sentinel-As-Code pipeline. It assumes familiarity with Azure and Microsoft
Sentinel, but not with the specifics of this repository.

### 1.1 The constraint

Local installation of PowerShell 7, the Az PowerShell modules and supporting
binaries is often not permitted on managed end-user devices. Rather than treat
this as a blocker, this guide positions a set of **sanctioned,
zero-local-install execution methods** that run the same tooling in a controlled
Azure or cloud-hosted context.

### 1.2 What this guide gives you

- The complete list of **requirements** - runtime, PowerShell modules, external
  binaries and permissions - split by what you need to **validate (test)** the
  project versus **use (deploy)** it.
- A comparison of **smart execution options** that need nothing installed
  locally, with a recommended primary and several fallbacks.
- **Step-by-step run and test instructions** for the recommended method and the
  main alternatives.

> **Source of truth.** Requirements in this document are derived from the
> repository's own scripts, module manifests and CI configuration. If a script
> changes its dependencies, the repository documentation is updated in the same
> change - treat the repository as authoritative.

## 2 What you are building and testing

Sentinel-As-Code is a CI/CD solution that deploys Microsoft Sentinel and
Defender XDR content from a Git repository. It provisions infrastructure (Bicep)
and deploys Content Hub solutions, custom analytical rules, hunting queries,
watchlists, playbooks, workbooks, parsers, automation rules, summary rules and
Defender XDR custom detections.

There are two distinct activities, and they have very different requirements:

| Activity | What it means | Where it runs |
| --- | --- | --- |
| **Validate (test)** | Run the Pester test suite and the PR-validation gate to prove content and scripts are correct, before anything touches a live tenant. | Any host with PowerShell 7 - no Azure access required for the core suite. |
| **Use (deploy)** | Authenticate to Azure and deploy infrastructure and content to a real Sentinel workspace and Defender XDR tenant. | A host with PowerShell 7, the Az/Graph modules, and the right Azure permissions. |

The good news for a no-local-install scenario: **validation needs almost
nothing**, and **deployment is normally done by the pipeline, not by a person**.
The execution methods in Section 4 cover both cases.

## 3 Requirements

### 3.1 Baseline runtime

- **PowerShell 7.2 or later** - required by every script and declared in the
  `Sentinel.Common` module manifest (`PowerShellVersion = '7.2'`). Windows
  PowerShell 5.1 is not supported.

### 3.2 Modules required to validate the project

This is all you need to run the Pester suite and the PR-validation gate via
`Tools/Invoke-PRValidation.ps1`. CI pins exact versions; the local minimums are
looser.

| Module | Pinned (CI) | Local minimum | Why |
| --- | --- | --- | --- |
| [Pester](https://learn.microsoft.com/powershell/scripting/dev-cross-plat/testing-with-pester) | 5.7.1 | 5.0.0 | Runs every `Tests/*.Tests.ps1` suite |
| [powershell-yaml](https://www.powershellgallery.com/packages/powershell-yaml) | 0.4.12 | any | YAML schema tests, dependency-manifest gate, content parsing |
| [Az.Accounts](https://learn.microsoft.com/powershell/module/az.accounts/) | 2.0.0+ | 2.0.0 | Hard dependency of `Sentinel.Common`, imported transitively by the module-unit tests |

> **Why so little?** All other Az and Microsoft.Graph cmdlets used by the deploy
> scripts are mocked in the test suite, so they are not needed to validate the
> project. This is what makes browser-based validation in Cloud Shell practical.

### 3.3 Modules required to use (deploy) the project

| Module | Required by | Declared via |
| --- | --- | --- |
| [Az.Accounts](https://learn.microsoft.com/powershell/module/az.accounts/) | `Sentinel.Common` manifest; the `Deploy-*` content scripts; `Export-DefenderDetections`; `Export-SentinelWorkbooks`; `Invoke-DCRWatchlistSync` | `#Requires` / manifest |
| [Az.Resources](https://learn.microsoft.com/powershell/module/az.resources/) | `Deploy-CustomContent` (playbook ARM deploy); `Set-PlaybookPermissions`; `Setup-ServicePrincipal` | cmdlet usage / header |
| [Az.LogicApp](https://learn.microsoft.com/powershell/module/az.logicapp/) | `Set-PlaybookPermissions` | `Requires:` header |
| [Az.KeyVault](https://learn.microsoft.com/powershell/module/az.keyvault/) | Playbook permissions / Key Vault references | docs |
| [Az.ManagedServiceIdentity](https://learn.microsoft.com/powershell/module/az.managedserviceidentity/) | Service-principal / managed-identity setup | docs |
| [Az.OperationalInsights](https://learn.microsoft.com/powershell/module/az.operationalinsights/) | Deploy pipeline and nightly workflow; Documenter collector | cmdlet usage |
| [Microsoft.Graph.Applications](https://learn.microsoft.com/powershell/module/microsoft.graph.applications/) | `Setup-ServicePrincipal` | `Install-Module` (auto) |
| [Microsoft.Graph.Identity.DirectoryManagement](https://learn.microsoft.com/powershell/module/microsoft.graph.identity.directorymanagement/) | `Setup-ServicePrincipal` | `Install-Module` (auto) |
| [powershell-yaml](https://www.powershellgallery.com/packages/powershell-yaml) | `Deploy-CustomContent`; `Deploy-DefenderDetections`; `Export-DefenderDetections`; `Import-CommunityRules`; `Build-DependencyManifest` | `Install-Module` (auto) |
| `Sentinel.Common` (local) | Every deploy script plus `Build-DependencyManifest` | `Import-Module` from `Modules/` |

Scripts marked **(auto)** install the module on first run if it is missing.
Pre-installing avoids interactive prompts in non-interactive contexts such as
pipelines.

### 3.4 Sentinel Documenter modules

The read-only Documenter pins its own module set. The collector imports the Az
modules; the renderer only needs `powershell-yaml`.

| Module | Pinned version | Module | Pinned version |
| --- | --- | --- | --- |
| [Az.Accounts](https://learn.microsoft.com/powershell/module/az.accounts/) | 3.0.4 | [Az.Resources](https://learn.microsoft.com/powershell/module/az.resources/) | 7.4.0 |
| [Az.SecurityInsights](https://learn.microsoft.com/powershell/module/az.securityinsights/) | 3.1.2 | [Az.LogicApp](https://learn.microsoft.com/powershell/module/az.logicapp/) | 1.7.0 |
| [Az.OperationalInsights](https://learn.microsoft.com/powershell/module/az.operationalinsights/) | 3.2.0 | [powershell-yaml](https://www.powershellgallery.com/packages/powershell-yaml) | 0.4.12 |
| [Az.Monitor](https://learn.microsoft.com/powershell/module/az.monitor/) | 5.2.1 | | |

### 3.5 External (non-module) dependencies

These are only needed for specific optional tools, not for the core
validate-or-deploy path. Note that some are **not present in Azure Cloud Shell**
(see Section 6).

| Dependency | Required by |
| --- | --- |
| [git](https://learn.microsoft.com/devops/develop/git/what-is-git) (2.x+ on PATH) | `Import-CommunityRules`; `Migrate-ForkLayout` (and cloning the repo) |
| [pandoc](https://pandoc.org/) (on PATH) | `Convert-MarkdownToWord`; `Convert-FolderToWordReport` |
| Node.js + [@mermaid-js/mermaid-cli](https://github.com/mermaid-js/mermaid-cli) | `Convert-MermaidToImage` (Documenter diagrams) |
| [Azure CLI + Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) (`az bicep build`) | PR-validation bicep-build job |
| [ImportExcel](https://www.powershellgallery.com/packages/ImportExcel) (module) | Standalone SDL migration workbook export only |

### 3.6 Permissions

Modules get you the cmdlets; you still need the right Azure RBAC roles, Entra ID
directory roles and Microsoft Graph application permissions for the scripts to
do anything against a live tenant. None of this is needed to **validate** the
project - only to **deploy**.

Authoritative references: [Azure built-in roles](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles),
[Microsoft Sentinel roles and permissions](https://learn.microsoft.com/azure/sentinel/roles),
[Azure RBAC conditions (ABAC)](https://learn.microsoft.com/azure/role-based-access-control/conditions-overview)
and the [Microsoft Graph permissions reference](https://learn.microsoft.com/graph/permissions-reference).
Each role and permission below links to its Microsoft Learn page.

#### 3.6.1 Pipeline service principal (deploy + content)

Granted once by `Setup-ServicePrincipal.ps1`, run by a user who holds **Owner**
on the subscription **and** at least **Privileged Role Administrator** in Entra
ID. After it runs once, the pipeline is autonomous.

| Permission | Type | Scope | Purpose |
| --- | --- | --- | --- |
| [Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles) | Azure RBAC | Subscription | Resource group, workspace, Bicep, content, summary rules. Implies Reader. |
| [User Access Administrator](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles) (ABAC-conditioned) | Azure RBAC | Subscription | Playbook managed-identity role assignments, restricted by ABAC to five named roles. |
| [Security Administrator](https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference#security-administrator) | Entra ID role | Tenant | UEBA and Entity Analytics settings. Optional (`-SkipEntraRole`). |
| [CustomDetection.ReadWrite.All](https://learn.microsoft.com/graph/permissions-reference) | Graph app permission | Tenant | Defender XDR custom detection rules. Optional (`-SkipGraphPermission`); needs admin consent. |

#### 3.6.2 Playbook managed identities

Assigned by `Set-PlaybookPermissions.ps1` as a post-deployment step, run by a
separate identity holding User Access Administrator or Owner (the pipeline's
ABAC-conditioned role cannot assign Sentinel-tier roles). Roles are derived per
playbook from its connectors and HTTP actions.

| Role | Scope | Triggered by |
| --- | --- | --- |
| [Microsoft Sentinel Responder](https://learn.microsoft.com/azure/sentinel/roles) | Sentinel RG | `azuresentinel` / `microsoftsentinel` connector |
| [Microsoft Sentinel Contributor](https://learn.microsoft.com/azure/sentinel/roles) | Sentinel RG | Playbook modifies incidents/watchlists, or HTTP PUT to `management.azure.com` |
| [Key Vault Secrets User](https://learn.microsoft.com/azure/key-vault/general/rbac-guide) | Key Vault | `keyvault` connector |
| [Log Analytics Reader](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles) | Sentinel RG | `azuremonitorlogs` connector or `api.loganalytics.io` HTTP action |

#### 3.6.3 DCR Watchlist Sync automation account

Assigned by `Set-RunbookPermissions.ps1`, run once by a user with Owner or User
Access Administrator on the subscription (the pipeline SPN lacks
`roleAssignments/write`).

| Role | Scope | Purpose |
| --- | --- | --- |
| [Monitoring Reader](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles) | Subscription | List DCRs and their associations via ARM |
| [Microsoft Sentinel Contributor](https://learn.microsoft.com/azure/sentinel/roles) | Sentinel RG | Create and update the Sentinel watchlist |

#### 3.6.4 Defender XDR export tool

- `Export-DefenderDetections.ps1` reads from the [Microsoft Graph Security API](https://learn.microsoft.com/graph/api/resources/security-detectionrule?view=graph-rest-beta)
  and needs either [CustomDetection.Read.All](https://learn.microsoft.com/graph/permissions-reference)
  or [CustomDetection.ReadWrite.All](https://learn.microsoft.com/graph/permissions-reference)
  (Microsoft Graph application permission, with admin consent).

#### 3.6.5 Resource providers

- [Microsoft.OperationsManagement](https://learn.microsoft.com/azure/templates/microsoft.operationsmanagement/solutions)
  and [Microsoft.SecurityInsights](https://learn.microsoft.com/azure/templates/microsoft.securityinsights)
  are registered automatically by the pipeline during infrastructure deployment -
  no manual provider registration is required.

## 4 Choosing a no-local-install execution method

Every option below runs PowerShell 7 and the required modules **somewhere other
than the user's managed device**. They differ in where the compute lives, how
much setup they need, and what they are best suited for. None require any
software to be installed on the user's machine beyond a web browser (or, for
managed workstations, the standard remote-desktop client your organisation
already uses).

| Option | How it runs | Best suited for | Key trade-offs |
| --- | --- | --- | --- |
| **Windows 365 Cloud PC** (recommended) | A persistent, per-user cloud desktop managed through Intune, with PowerShell 7, the modules and developer tooling in the image. | The recommended default: a governed, persistent desktop with everything pre-installed. | Per-user licensing and run-cost; managed by IT like any endpoint. |
| **Azure Cloud Shell** | Browser-based shell in the Azure Portal, pre-loaded with PowerShell 7 and Az. | Validation, ad-hoc deploys, quick onboarding - zero setup. | Ephemeral; pandoc / Node not present; idle timeout. |
| **GitHub Codespaces / dev container** | Cloud dev container opened in the browser or VS Code, tooling baked into the image. | Active development and full local-like testing. | Needs a devcontainer definition; consumes Codespaces quota. |
| **CI/CD only** (GitHub Actions / Azure DevOps) | Hosted runners execute every stage; no human runs PowerShell at all. | Production deployment and gated validation. | Not interactive; slower feedback loop for experiments. |
| **Container image** (Docker / MCR PowerShell base) | A pre-built image with PowerShell, Az and the repo dependencies, run on any container host. | Reproducible, portable execution and self-hosted runners. | Requires a container host and image maintenance. |

### 4.1 Recommendation

Lead with **a Windows 365 Cloud PC** as the primary method: IT installs
PowerShell 7, the modules and the full developer toolchain once on the image, so
engineers get a governed, persistent desktop with nothing to install on their
own device. Use **Azure Cloud Shell** as a lightweight browser alternative for
quick validation, **CI/CD** as the path to production so people rarely deploy by
hand, **Codespaces** for engineers doing heavy development, and a **container
image** where a fully self-hosted environment is required.

## 5 Recommended primary: Windows 365 Cloud PC

A Windows 365 Cloud PC is a persistent, per-user cloud desktop managed through
Microsoft Intune. IT builds the image once with PowerShell 7, the validate and
deploy modules and the full developer toolchain, then assigns a Cloud PC to each
engineer. Users connect from a browser or the Windows App, so the machine and
everything on it stays in Azure and nothing is installed on the user's own
device. For most organisations this is the recommended default: it is governed
like any other managed endpoint, supports Conditional Access and Defender for
Endpoint, and gives engineers a consistent environment where the project is
ready to build, test and deploy.

### 5.1 What IT installs on the Cloud PC image

Because the Cloud PC is IT-built and governed, installation happens once on the
image, not on the user's device. Alongside the runtime and modules from Section
3, bake in the standard Windows developer toolchain so engineers can author,
clone and run the project directly on the Cloud PC. On the image, install:

- [PowerShell 7.2 or later](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows) -
  the baseline runtime for every script (see 3.1). Windows PowerShell 5.1 is not
  sufficient; install PowerShell 7 side-by-side as `pwsh`.
- [Git for Windows](https://git-scm.com/download/win) - provides git 2.x on PATH
  (required to clone the repository and by `Import-CommunityRules` and
  `Migrate-ForkLayout`), plus Git Bash and Git Credential Manager for
  authentication.
- **The Az and Microsoft.Graph modules from Section 3** - the validate and
  deploy modules (Pester, powershell-yaml, and the Az and Sentinel modules),
  installed for all users so engineers never need a per-session `Install-Module`
  step.
- **The external binaries from Section 3.5** - git, plus pandoc and Node.js
  where the Sentinel Documenter Word export and mermaid diagrams are required, so
  the full validation and documentation flow runs on the host.
- [Visual Studio Code](https://code.visualstudio.com/) - the recommended editor
  for authoring rules, scripts, Bicep and pipeline changes, and the desktop
  client for the dev container / Codespaces flow in Section 7. Add the
  [Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/visual-studio-code)
  and PowerShell extensions; it also runs the repository's shipped
  [GitHub Copilot customisations](https://code.visualstudio.com/docs/copilot/customization/overview)
  (path-scoped instructions, custom agents and reusable prompts under
  `.github/`).

### 5.2 Provision and connect

IT assigns a Cloud PC from the Windows 365 experience in Intune and applies the
same Conditional Access, compliance and update policies as any managed device.
Engineers sign in at `windows365.microsoft.com` or through the Windows App on
Windows, macOS, iOS or the web. The connection is brokered, so there is no
inbound RDP to the user's device and nothing is installed locally. Because the
Cloud PC is persistent, clones, modules and settings are retained between
sessions.

### 5.3 Get the code and run the tests

Open a terminal or Visual Studio Code on the Cloud PC, clone the repository and
run the validation gate. The modules and binaries are already present from the
image, so there is no setup step:

```powershell
# Clone the repository (git is pre-installed on the image)
git clone https://github.com/noodlemctwoodle/Sentinel-As-Code.git
Set-Location Sentinel-As-Code

# Modules are already installed - run the full PR-validation gate
./Tools/Invoke-PRValidation.ps1 -RepoPath .
```

### 5.4 Deploy interactively (optional)

Unlike Cloud Shell, a Cloud PC is not automatically signed in to Azure, so
authenticate once with the account that holds the permissions from Section 3.6,
select the subscription, and preview every change with `-WhatIf` before applying
it:

```powershell
# Sign in and select the subscription
Connect-AzAccount
Set-AzContext -Subscription '<subscription-id>'

# Example: deploy custom content (see Docs/Deploy for parameters)
./Deploy/content/Deploy-CustomContent.ps1 -WhatIf
```

> **Use `-WhatIf` first.** Always preview changes with a `-WhatIf` pass before
> applying them, then route production deployments through the CI/CD pipeline
> (Section 8) rather than deploying by hand.

### 5.5 Other managed-desktop variants

A Windows 365 Cloud PC is the recommended flavour because it is per-user,
persistent and managed through Intune. Where an organisation already operates a
different managed-desktop estate, the same image and commands apply to the
alternatives below:

| Workstation option | What it is | Good fit when |
| --- | --- | --- |
| **Azure VM (jump box)** | A locked-down Windows or Linux VM with PowerShell 7 and the modules pre-installed, reached over Bastion or RDP. | You want a single shared, auditable admin host. |
| **Azure Virtual Desktop (AVD)** | A pooled or personal virtual desktop delivered from Azure, with the tooling in the image. | Several engineers need a consistent managed desktop. |
| **Windows 365 Cloud PC** | A persistent, per-user Cloud PC managed through Intune. | You prefer a per-user device managed like any other endpoint. |
| **Remote Desktop Services (RDS)** | Session-host based remote desktops or published apps on Windows Server. | You already operate an RDS estate and want to extend it. |

## 6 Alternative: Azure Cloud Shell

Azure Cloud Shell is a browser-based shell, launched from the Azure Portal or
`shell.azure.com`, that already includes PowerShell 7, the Az modules, git and
the Azure CLI. Nothing is installed on the user's device. It is a fast,
zero-setup way to validate the project or run an interactive deployment when a
full Cloud PC is not needed.

### 6.1 One-time setup

1. Sign in to the Azure Portal and select the **Cloud Shell** icon in the top
   toolbar (or browse to `shell.azure.com`).
2. Choose **PowerShell** (not Bash) when prompted. If this is the first launch,
   accept the prompt to create the backing storage account for your Cloud Shell
   profile.
3. Confirm the environment:

```powershell
$PSVersionTable.PSVersion   # expect 7.x
Get-Module Az.Accounts -ListAvailable | Select-Object -First 1
```

### 6.2 Get the code and validation modules

```powershell
# Clone the repository (git is pre-installed)
git clone https://github.com/noodlemctwoodle/Sentinel-As-Code.git
Set-Location Sentinel-As-Code

# Install the three modules needed to validate
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module powershell-yaml -RequiredVersion 0.4.12 -Scope CurrentUser -Force

# Az.Accounts is already present in Cloud Shell
```

### 6.3 Run the tests

1. Run the full PR-validation entry point:

   ```powershell
   ./Tools/Invoke-PRValidation.ps1 -RepoPath .
   ```

2. Or run a single suite while iterating:

   ```powershell
   Invoke-Pester -Path Tests/Test-AnalyticalRuleYaml.Tests.ps1
   ```

> **Cloud Shell limitations.** Cloud Shell does not include pandoc or the
> Node-based mermaid-cli, so the Word-conversion and diagram-rendering helpers
> will not run there. The core Pester suite and YAML/schema gates - which is what
> validation means here - run cleanly. For the bicep-build gate, the Azure CLI
> and Bicep are pre-installed.

### 6.4 Deploy interactively (optional)

Cloud Shell is already authenticated as your portal identity, so for an
interactive deploy you only need the relevant Azure permissions from Section
3.6:

```powershell
# Confirm context / select subscription
Get-AzContext
Set-AzContext -Subscription '<subscription-id>'

# Example: deploy custom content (see Docs/Deploy for parameters)
./Deploy/content/Deploy-CustomContent.ps1 -WhatIf
```

> **Use `-WhatIf` first.** Always run a `-WhatIf` pass before a live deployment
> to preview changes. Production deployments should normally go through the
> pipeline (Section 8), not interactive Cloud Shell.

## 7 Alternative: GitHub Codespaces / dev container

A Codespace is a cloud-hosted development container, opened in the browser or in
desktop VS Code, with all tooling baked into the image. It gives a full
local-like experience - including pandoc and Node - without installing anything
on the user's device.

### 7.1 When to use it

- Engineers actively authoring rules, scripts or pipeline changes who want
  editor, terminal and tests in one place.
- Scenarios that need the optional tooling (Documenter Word export, mermaid
  diagrams) that Cloud Shell lacks.

### 7.2 Setup outline

1. Add a devcontainer definition to the repository
   (`.devcontainer/devcontainer.json`) based on the Microsoft PowerShell image,
   installing Pester, powershell-yaml and the Az/Graph modules during the
   post-create step.
2. Add the optional binaries (pandoc, Node + `@mermaid-js/mermaid-cli`, Azure
   CLI + Bicep) as devcontainer features or post-create commands.
3. Open the repository in a Codespace from GitHub (Code → Codespaces → Create),
   then run the same validation commands as Section 5.3 inside the integrated
   terminal.

> **Governance.** Codespaces run under your GitHub organisation's policies and
> billing. Confirm Codespaces is enabled for the organisation and that the
> repository is permitted before relying on this method.

## 8 Alternative: CI/CD only (no interactive PowerShell)

In normal operation, **no person needs to run PowerShell at all**. The
repository ships equivalent pipelines for both GitHub Actions and Azure DevOps;
the hosted runners install the pinned modules and execute every stage. This is
the recommended path to production.

### 8.1 How validation runs

- Every pull request triggers a five-job gate: validate (Pester suites),
  bicep-build, arm-validate, kql-validate and dependency-manifest.
- The runner installs the pinned modules via the `setup-pwsh-modules` composite
  action, so the result is reproducible and independent of any developer's
  machine.
- A failing gate blocks merge - engineers get pass/fail feedback in the PR
  without ever opening a shell.

### 8.2 How deployment runs

- Authentication uses OIDC federated credentials - there are no stored secrets
  and no interactive sign-in.
- The deploy pipeline provisions infrastructure (Bicep) and deploys content
  using the service principal permissions from Section 3.6.
- This means the entire build-test-deploy lifecycle can be operated with only a
  browser and Git access - the strongest fit for a no-local-install policy.

> **Recommended pairing.** Use a Cloud PC or Cloud Shell for interactive work
> and the CI/CD pipeline for anything that reaches a shared or production
> workspace. Together they cover the full lifecycle with nothing installed
> locally.

## 9 Alternative: container image

A container image bundles PowerShell, the Az and Graph modules, and the
repository's external dependencies into a single reproducible artifact. It runs
on any container host - a developer's container runtime, an Azure Container
Instance, or a self-hosted pipeline runner - and guarantees everyone uses an
identical toolset.

### 9.1 Setup outline

1. Base the image on the official Microsoft PowerShell image
   (`mcr.microsoft.com/powershell`).
2. In the Dockerfile, install the pinned modules (Pester 5.7.1, powershell-yaml
   0.4.12, the Az and Microsoft.Graph modules) and the external binaries (git,
   pandoc, Node + mermaid-cli, Azure CLI + Bicep) as needed.
3. Run the container and execute the same validation and deploy commands as
   Section 5. For unattended use, drive it from a self-hosted Actions or Azure
   DevOps runner.

> **Best fit.** Use a container image when you need bit-for-bit reproducibility
> or a self-hosted runner, and you already operate a container host. Otherwise
> the managed services in Sections 5 to 8 need less maintenance.

## 10 Quick reference: install commands

The same commands work in any of the methods above. Run them once per
environment (or bake them into the image / devcontainer).

### 10.1 Minimum to validate (run the test suite)

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module powershell-yaml -RequiredVersion 0.4.12 -Scope CurrentUser -Force
Install-Module Az.Accounts -MinimumVersion 2.0.0 -Scope CurrentUser -Force
```

### 10.2 Full runtime (deploy content + run the tooling)

```powershell
Install-Module Az.Resources, Az.KeyVault, Az.ManagedServiceIdentity, `
  Az.LogicApp, Az.OperationalInsights, Az.SecurityInsights, Az.Monitor `
  -Scope CurrentUser -Force

Install-Module Microsoft.Graph.Applications, `
  Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser -Force
```

### 10.3 Only for the standalone SDL workbook export

```powershell
Install-Module ImportExcel -Scope CurrentUser -Force
```

### 10.4 Run the validation gate

```powershell
./Tools/Invoke-PRValidation.ps1 -RepoPath .
```

For deployment parameters, pipeline configuration and content-authoring
conventions, refer to the repository documentation under `Docs/` (start with
`Docs/README.md`), which remains the authoritative reference.

## 11 Microsoft Learn references

Every requirement in this guide links to its Microsoft Learn page inline
(PowerShell Gallery is used for the two community modules that are not on
Learn). The list below groups the authoritative pages by topic for quick access,
including the API schemas the tooling depends on.

### 11.1 Runtime, modules and testing

- [Install PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) -
  the baseline runtime for every script.
- [Az PowerShell overview](https://learn.microsoft.com/powershell/azure/) and
  [Microsoft Graph PowerShell overview](https://learn.microsoft.com/powershell/microsoftgraph/) -
  module families used by the deploy scripts.
- [Install-Module (PowerShellGet)](https://learn.microsoft.com/powershell/module/powershellget/install-module) -
  how modules are installed in each environment.
- [Testing PowerShell with Pester](https://learn.microsoft.com/powershell/scripting/dev-cross-plat/testing-with-pester) -
  the framework behind the `Tests/` suite.

### 11.2 Local developer tooling

- [Install PowerShell on Windows](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows) -
  installs the PowerShell 7 runtime on the Cloud PC image (Section 5.1).
- [Git for Windows](https://git-scm.com/download/win) - git on PATH for cloning
  and the community-import tooling.
- [Visual Studio Code](https://code.visualstudio.com/) and the
  [Copilot customisations](https://code.visualstudio.com/docs/copilot/customization/overview) -
  editor for authoring and running the project on the managed workstation.

### 11.3 Execution environments

- [Azure Virtual Desktop](https://learn.microsoft.com/azure/virtual-desktop/overview)
  and [Windows 365](https://learn.microsoft.com/windows-365/) - the recommended
  Cloud PC method (Section 5).
- [Azure Cloud Shell overview](https://learn.microsoft.com/azure/cloud-shell/overview) -
  a lightweight browser alternative (Section 6).
- [Develop in a container with VS Code](https://code.visualstudio.com/docs/devcontainers/containers)
  and [GitHub Codespaces](https://docs.github.com/codespaces) - the dev-container
  option (Section 7).
- [GitHub Actions](https://docs.github.com/actions) and
  [Azure Pipelines](https://learn.microsoft.com/azure/devops/pipelines/) - the
  CI/CD path to production (Section 8).
- [PowerShell in a container](https://learn.microsoft.com/powershell/scripting/install/powershell-in-docker) -
  the container-image option (Section 9).

### 11.4 Permissions, roles and identity

- [Azure built-in roles](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles) -
  Contributor, User Access Administrator, Monitoring Reader, Log Analytics
  Reader.
- [Microsoft Sentinel roles and permissions](https://learn.microsoft.com/azure/sentinel/roles) -
  Microsoft Sentinel Responder and Contributor.
- [Azure RBAC conditions (ABAC)](https://learn.microsoft.com/azure/role-based-access-control/conditions-overview) -
  how the pipeline's User Access Administrator role is constrained.
- [Microsoft Entra built-in roles](https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference) -
  Security Administrator and Privileged Role Administrator.
- [Microsoft Graph permissions reference](https://learn.microsoft.com/graph/permissions-reference) -
  CustomDetection.Read.All / ReadWrite.All.
- [Key Vault RBAC guide](https://learn.microsoft.com/azure/key-vault/general/rbac-guide)
  and [workload identity federation (OIDC)](https://learn.microsoft.com/entra/workload-id/workload-identity-federation) -
  secret access and pipeline authentication.

### 11.5 API schemas and resource definitions

- [ARM template reference](https://learn.microsoft.com/azure/templates/) - the
  schema index for every Azure resource type.
- [Microsoft.SecurityInsights ARM types](https://learn.microsoft.com/azure/templates/microsoft.securityinsights)
  and [Microsoft.OperationalInsights/workspaces](https://learn.microsoft.com/azure/templates/microsoft.operationalinsights/workspaces) -
  the Sentinel and workspace resources the Bicep deploys.
- [Microsoft.Insights/dataCollectionRules ARM type](https://learn.microsoft.com/azure/templates/microsoft.insights/datacollectionrules) -
  the DCR schema used by the watchlist sync.
- [Bicep language reference](https://learn.microsoft.com/azure/azure-resource-manager/bicep/) -
  the infrastructure-as-code dialect in `Infra/`.
- [Microsoft Sentinel REST API](https://learn.microsoft.com/rest/api/securityinsights/)
  and [Azure Monitor Log Analytics REST API](https://learn.microsoft.com/rest/api/loganalytics/) -
  the management and query APIs behind the deploy scripts.
- [Microsoft Graph security detectionRule API](https://learn.microsoft.com/graph/api/resources/security-detectionrule?view=graph-rest-beta) -
  the Defender XDR custom-detection schema used by the export and deploy tooling.
