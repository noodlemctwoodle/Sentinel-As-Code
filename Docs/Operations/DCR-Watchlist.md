# DCR Watchlist Sync

Automatically inventories all Data Collection Rule (DCR) associations in a subscription and syncs them to a Microsoft Sentinel watchlist. Designed for billing, audit, and operational visibility.

Source files live under [`Automation/DCR-Watchlist/`](../../Automation/DCR-Watchlist/).

## What It Does

1. **Lists all DCRs** in the subscription via the ARM REST API
2. **Enumerates associations** for each DCR (the servers/resources sending data through it)
3. **Groups by DCR** — one watchlist row per DCR with the associated resource names as a delimited list
4. **Upserts to a Sentinel watchlist** — creates new entries, merges into existing ones, never deletes mid-billing-period
5. **Tracks billing history** — maintains `AllResourceNames` (cumulative), `RemovedResourceNames`, `PeakResourceCount`, and `FirstSeenUtc` so removed servers are still billable for the period they were active

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
| **Azure DevOps** | Service connection with **Contributor** on the subscription |
| **Variable group** | `sentinel-deployment` with `sentinelResourceGroup` and `sentinelWorkspaceName` (shared with the main deploy pipeline — see [Pipelines](../Deployment/Pipelines.md)) |
| **Manual RBAC** | One-time post-deployment (see below) |

## Deployment

### 1. Run the Pipeline

The pipeline is at [`Pipelines/DCR-Watchlist-Deploy.yml`](../../Pipelines/DCR-Watchlist-Deploy.yml) and triggers on changes to `Automation/DCR-Watchlist/**`.

It has two stages:

| Stage | What it does |
|---|---|
| **Deploy Infrastructure** | Deploys the Automation Account, schedule, and empty runbook via Bicep |
| **Update Runbook** | Imports and publishes `Invoke-DCRWatchlistSync.ps1`, links the job schedule |

Pipeline parameters:

| Parameter | Default | Description |
|---|---|---|
| `deployInfrastructure` | `true` | Deploy Bicep template |
| `updateRunbook` | `false` | Update runbook only (skip Bicep) |
| `automationResourceGroup` | `rg-dcr-watchlist-sync` | Resource group for the Automation Account |
| `automationAccountName` | `aa-dcr-watchlist-sync` | Automation Account name |
| `watchlistAlias` | `CustomerResources` | Sentinel watchlist alias |
| `scheduleFrequencyHours` | `24` | Run every 24h (daily) or 168h (weekly) |
| `location` | `uksouth` | Azure region |
| `whatIf` | `false` | Preview changes without applying |

### 2. Apply RBAC (One-Time, Manual)

The pipeline service principal does not have `roleAssignments/write`. After the first deployment, run [`Automation/DCR-Watchlist/scripts/Set-RunbookPermissions.ps1`](../../Automation/DCR-Watchlist/scripts/Set-RunbookPermissions.ps1):

```powershell
./Automation/DCR-Watchlist/scripts/Set-RunbookPermissions.ps1 -SubscriptionId '<your-subscription-id>'
```

This assigns:

| Role | Scope | Purpose |
|---|---|---|
| **Monitoring Reader** | Subscription | List DCRs and associations via ARM |
| **Microsoft Sentinel Contributor** | Sentinel resource group | Create/update the watchlist |

To remove the permissions:

```powershell
./Automation/DCR-Watchlist/scripts/Set-RunbookPermissions.ps1 -SubscriptionId '<your-subscription-id>' -Remove
```

### 3. Verify

After the first scheduled run (or a manual trigger from the Azure Portal):

1. Open **Microsoft Sentinel** > **Watchlist**
2. Find `CustomerResources`
3. Verify DCR rows with `ActiveResourceNames` populated

## File Structure

```
Automation/DCR-Watchlist/
├── main.bicep                         # Subscription-scoped Bicep orchestrator
├── modules/
│   └── automationAccount.bicep        # Automation Account, schedule, runbook shell
└── scripts/
    ├── Invoke-DCRWatchlistSync.ps1    # Runbook — DCR enumeration and watchlist sync
    └── Set-RunbookPermissions.ps1     # Post-deployment RBAC assignment script

Pipelines/
└── DCR-Watchlist-Deploy.yml           # Azure DevOps pipeline
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
