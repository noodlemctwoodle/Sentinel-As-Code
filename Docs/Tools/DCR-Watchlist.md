# DCR Watchlist Sync

Automatically inventories all Data Collection Rule (DCR) associations in a subscription and syncs them to a Microsoft Sentinel watchlist. Designed for billing, audit, and operational visibility.

The Bicep stack lives under [`Infra/dcr-watchlist/`](../../Infra/dcr-watchlist); the runbook is [`Tools/Invoke-DCRWatchlistSync.ps1`](../../Tools/Invoke-DCRWatchlistSync.ps1) and the permissions helper [`Deploy/permissions/Set-RunbookPermissions.ps1`](../../Deploy/permissions/Set-RunbookPermissions.ps1).

Deployment is driven by CI from either side of the mirror: the GitHub Actions workflow [`.github/workflows/sentinel-dcr-inventory.yml`](../../.github/workflows/sentinel-dcr-inventory.yml) (the primary path for this repo) or the Azure DevOps pipeline [`Pipelines/Sentinel-DCR-Inventory.yml`](../../Pipelines/Sentinel-DCR-Inventory.yml). Both provision the same Automation Account and register the same runbook.

## What It Does

1. **Lists all DCRs** in the subscription via the ARM REST API (`Get-DCRList`, with `nextLink` pagination)
2. **Enumerates associations** for each DCR (`Get-DCRAssociations`) - the servers/resources sending data through it. The built-in `configurationAccessEndpoint` association is skipped, and each associated resource name, type, and resource group is derived from the association resource ID via regular-expression matching
3. **Groups by DCR** - one watchlist row per DCR (keyed by DCR name) with the associated resource names as a delimited list
4. **Upserts to a Sentinel watchlist** - creates the watchlist with data if it is missing (404), otherwise merges into existing items, and never deletes mid-billing-period
5. **Tracks billing history** - maintains `AllResourceNames` (cumulative union, case-insensitive), `RemovedResourceNames`, `PeakResourceCount`, and `FirstSeenUtc` so removed servers are still billable for the period they were active

**Billing-safe guards.** The runbook exits early (exit code 0) without touching the watchlist in two cases: when the subscription contains zero DCRs, and when no associations are found across any DCR. This prevents an empty enumeration (for example a transient ARM error) from wiping active billing history via an accidental empty replace.

> **Note on the script header.** The runbook's own `.SYNOPSIS`/`.DESCRIPTION` still describe a legacy "delete and recreate / full replace" model. That header is stale - the implemented body performs the billing-safe merge/upsert described above. Trust this document over the script comment block.

## Architecture

```
Azure Automation Account (PowerShell 7.2)
  ├── System-assigned managed identity
  ├── Invoke-DCRWatchlistSync.ps1 (runbook)
  └── Daily schedule (03:00 UTC)
         │
         ├── ARM API: List DCRs + associations
         │     GET /subscriptions/{sub}/providers/Microsoft.Insights/dataCollectionRules
         │     GET /subscriptions/{sub}/providers/Microsoft.Insights/dataCollectionRules/{dcr}/associations
         │
         └── Sentinel Watchlist API: Upsert items
               PUT /subscriptions/{sub}/.../watchlists/CustomerResources
               PUT /subscriptions/{sub}/.../watchlists/CustomerResources/watchlistItems/{id}
```

## Watchlist Schema

Each row represents a single DCR:

| Column | Description |
|---|---|
| `DCRName` | Data Collection Rule name (watchlist search key) |
| `DCRId` | Full ARM resource ID |
| `DCRResourceGroup` | Resource group containing the DCR |
| `SubscriptionId` | Subscription ID |
| `ActiveResourceCount` | Number of currently associated resources |
| `ActiveResourceNames` | Semicolon-delimited list of current resources |
| `AllResourceNames` | Cumulative list — every resource ever seen this billing period |
| `RemovedResourceNames` | Resources previously active but no longer associated |
| `ResourceTypes` | Distinct resource types (e.g., `Microsoft.Compute/virtualMachines`) |
| `PeakResourceCount` | High-water mark — maximum concurrent resources seen |
| `FirstSeenUtc` | When this DCR first appeared in the watchlist |
| `LastUpdatedUtc` | Last sync timestamp |
| `Status` | `Active` or `Inactive` (DCR no longer has associations) |

**Search key.** The watchlist search key is `DCRName`. There is one row per DCR, so `DCRName` is the only column that carries a stable per-row identifier. The runbook exposes this as the `-SearchKey` parameter, which defaults to `DCRName`, and both CI paths register the scheduled runbook with `SearchKey=DCRName` to match the row shape. (Do not set it to `ResourceId`: the grouped row objects have no `ResourceId` property, so under `Set-StrictMode -Version Latest` the sync would fault.)

**Alias vs display name.** The watchlist is addressed by its alias `CustomerResources` (no spaces, used in the ARM path and in `_GetWatchlist(...)` queries) and shown in the Sentinel portal under its display name `Customer DCR Resources`. Both are configurable (`watchlistAlias` / `watchlistDisplayName`).

For general watchlist authoring conventions, see [Watchlists](../Content/Watchlists.md).

## Billing Logic

The watchlist is designed for billing where **removed servers must still be billed for the time they were active**:

- **Resources are only ever added** to `AllResourceNames`, never removed
- `RemovedResourceNames` tracks servers that were previously active but are no longer associated
- `PeakResourceCount` captures the high-water mark for peak-based billing models
- `FirstSeenUtc` is preserved from the first sync — never overwritten
- Inactive DCRs (all associations removed) are marked `Status = Inactive`, not deleted
- Daily snapshots at 03:00 UTC provide day-level granularity for proration

### Billing Query (KQL)

Join the watchlist with the `Usage` table to calculate actual ingestion per DCR:

```kql
let BillingPeriodStart = startofmonth(now());
_GetWatchlist('CustomerResources')
| where Status == "Active"
| mv-expand ResourceName = split(AllResourceNames, "; ")
| extend ResourceName = tostring(ResourceName)
| join kind=inner (
    Usage
    | where TimeGenerated > BillingPeriodStart
    | where IsBillable == true
    | summarize IngestedGB = sum(Quantity) / 1024.0
        by DataType, Computer = SourceSystem
) on $left.ResourceName == $right.Computer
| summarize TotalGB = round(sum(IngestedGB), 2),
    ServerCount = dcount(ResourceName)
    by DCRName
| sort by TotalGB desc
```

## Prerequisites

| Requirement | Details |
|---|---|
| **Azure subscription** | Target subscription containing DCRs |
| **Sentinel workspace** | Log Analytics workspace with Sentinel enabled |
| **GitHub (OIDC)** | An Entra app federated for OIDC with **Contributor** on the subscription. Secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`. Variables: `SENTINEL_RESOURCE_GROUP`, `SENTINEL_WORKSPACE_NAME` |
| **Azure DevOps** | Service connection `sc-sentinel-as-code` with **Contributor** on the subscription |
| **Variable group (ADO)** | `sentinel-deployment` with `azureSubscriptionId`, `sentinelResourceGroup`, and `sentinelWorkspaceName` (shared with the main deploy pipeline, see [Pipelines](../Pipelines/README.md)) |
| **Manual RBAC** | One-time post-deployment (see below) |

## Deployment

### 1. Run the Deployment (CI)

Two equivalent CI definitions provision the same infrastructure and register the same runbook. Use whichever matches your platform.

#### GitHub Actions (primary)

The workflow is at [`.github/workflows/sentinel-dcr-inventory.yml`](../../.github/workflows/sentinel-dcr-inventory.yml). It triggers on:

- **push to `main`** touching `Infra/dcr-watchlist/**`, `Tools/Invoke-DCRWatchlistSync.ps1`, `Deploy/permissions/Set-RunbookPermissions.ps1`, or the workflow file itself (push runs resolve every input to its default); and
- **`workflow_dispatch`** (manual), which exposes the input parameters below.

It authenticates with the composite `azure-login-oidc` action using the `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` secrets, and reads `SENTINEL_RESOURCE_GROUP` and `SENTINEL_WORKSPACE_NAME` from repository variables.

#### Azure DevOps (mirror)

The pipeline is at [`Pipelines/Sentinel-DCR-Inventory.yml`](../../Pipelines/Sentinel-DCR-Inventory.yml) and triggers on changes to `Infra/dcr-watchlist/**`, `Tools/Invoke-DCRWatchlistSync.ps1`, or `Deploy/permissions/Set-RunbookPermissions.ps1`. It authenticates with the `sc-sentinel-as-code` service connection and reads `azureSubscriptionId`, `sentinelResourceGroup`, and `sentinelWorkspaceName` from the `sentinel-deployment` variable group.

#### Stages (both CI systems)

| Stage | What it does |
|---|---|
| **Deploy Infrastructure** | Deploys the Automation Account, schedule, and empty runbook via Bicep (`az deployment sub create` against `main.bicep`) |
| **Update Runbook** | Imports and publishes `Invoke-DCRWatchlistSync.ps1`, then registers the job schedule with runbook parameters if it is not already linked |

The Update Runbook stage runs after Deploy Infrastructure (even if that stage was skipped), so the runbook body can be updated independently. When linking the schedule it passes the runbook parameters, including `SearchKey=DCRName` (see [Search key](#watchlist-schema) above).

#### Parameters (identical across both definitions)

| Parameter | Default | Description |
|---|---|---|
| `deployInfrastructure` | `true` | Deploy Bicep template |
| `updateRunbook` | `false` | Update runbook only (skip Bicep) |
| `automationResourceGroup` | `rg-dcr-watchlist-sync` | Resource group for the Automation Account |
| `automationAccountName` | `aa-dcr-watchlist-sync` | Automation Account name |
| `watchlistAlias` | `CustomerResources` | Sentinel watchlist alias (no spaces) |
| `watchlistDisplayName` | `Customer DCR Resources` | Human-readable name shown in the Sentinel portal |
| `scheduleFrequencyHours` | `24` | Run every 24h (daily) or 168h (weekly) |
| `location` | `uksouth` | Azure region |
| `whatIf` | `false` | Preview changes without applying |

### 2. Apply RBAC (One-Time, Manual)

The CI service principal does not have `roleAssignments/write`. After the first deployment, run [`Deploy/permissions/Set-RunbookPermissions.ps1`](../../Deploy/permissions/Set-RunbookPermissions.ps1) as a user with **Owner** or **User Access Administrator** on the subscription. All four parameters are mandatory:

```powershell
./Deploy/permissions/Set-RunbookPermissions.ps1 `
    -SubscriptionId '<your-subscription-id>' `
    -AutomationAccountName 'aa-dcr-watchlist-sync' `
    -AutomationResourceGroup 'rg-dcr-watchlist-sync' `
    -SentinelResourceGroup '<sentinel-resource-group>'
```

The script resolves the Automation Account's managed-identity principal ID, prints a permission summary and disclaimer, then prompts interactively (`Y/N`) before making any change. It supports `-WhatIf` (via `SupportsShouldProcess`) to preview the assignments without applying them.

This assigns:

| Role | Scope | Purpose |
|---|---|---|
| **Monitoring Reader** | Subscription | List DCRs and associations via ARM |
| **Microsoft Sentinel Contributor** | Sentinel resource group | Create/update the watchlist |

To remove the permissions, pass the same four parameters plus `-Remove`:

```powershell
./Deploy/permissions/Set-RunbookPermissions.ps1 `
    -SubscriptionId '<your-subscription-id>' `
    -AutomationAccountName 'aa-dcr-watchlist-sync' `
    -AutomationResourceGroup 'rg-dcr-watchlist-sync' `
    -SentinelResourceGroup '<sentinel-resource-group>' `
    -Remove
```

### 3. Verify

After the first scheduled run (or a manual trigger from the Azure Portal):

1. Open **Microsoft Sentinel** > **Watchlist**
2. Find `CustomerResources`
3. Verify DCR rows with `ActiveResourceNames` populated

## File Structure

```
Infra/dcr-watchlist/
├── main.bicep                         # Subscription-scoped Bicep orchestrator
└── modules/
    └── automationAccount.bicep        # Automation Account, schedule, runbook shell

Tools/Invoke-DCRWatchlistSync.ps1      # Runbook — DCR enumeration and watchlist sync
Deploy/permissions/Set-RunbookPermissions.ps1      # Post-deployment RBAC assignment script

.github/workflows/sentinel-dcr-inventory.yml       # GitHub Actions workflow (primary CI path)
Pipelines/Sentinel-DCR-Inventory.yml               # Azure DevOps pipeline (mirror)
```

## API Versions

| API | Version | Documentation |
|---|---|---|
| Data Collection Rules | `2024-03-11` | [DCR REST API](https://learn.microsoft.com/en-us/rest/api/monitor/data-collection-rules) |
| DCR Associations | `2024-03-11` | [DCR Associations REST API](https://learn.microsoft.com/en-us/rest/api/monitor/data-collection-rule-associations) |
| Sentinel Watchlists | `2025-09-01` | [Watchlist REST API](https://learn.microsoft.com/en-us/rest/api/securityinsights/watchlists) |
| Sentinel Watchlist Items | `2025-09-01` | [Watchlist Items REST API](https://learn.microsoft.com/en-us/rest/api/securityinsights/watchlist-items) |
| Automation Account (Bicep) | `2024-10-23` | [Automation ARM Reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.automation/automationaccounts) |
| Resource Groups (Bicep) | `2024-03-01` | [Resources ARM Reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.resources/resourcegroups) |

## Cost

| Component | Cost |
|---|---|
| Azure Automation | **Free** — 500 free minutes/month, runbook uses ~3 min/day (~90 min/month) |
| ARM API calls | **Free** — management plane calls have no cost |
| Sentinel Watchlist | **Free** — watchlist items do not count toward ingestion billing |
| Managed Identity | **Free** — no licence cost |

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `The runbook does not have a published version` | Runbook exists as draft only | Pipeline Stage 2 publishes it — ensure both stages run |
| `Update runbook with definition of different runbook kind` | Existing runbook was PS 5.1, new is PS 7.2 | Delete the runbook manually then re-deploy: `az automation runbook delete --automation-account-name aa-dcr-watchlist-sync --resource-group rg-dcr-watchlist-sync --name Invoke-DCRWatchlistSync --yes` |
| `Schedule start time must be at least 5 minutes after` | Schedule start is in the past | Pipeline computes tomorrow 03:00 UTC automatically — re-run |
| `Authorization failed for roleAssignments` | Pipeline SPN lacks `roleAssignments/write` | Expected — run `Set-RunbookPermissions.ps1` manually instead |
| `GetTokenAsync method not implemented` | Az.Accounts too new for Automation sandbox | Az.Accounts is pinned to 3.0.5 in the Bicep module |
| `No associations found across any DCR` | DCRs exist but have no resource associations | Verify agents are installed and DCR associations are configured in the portal |
