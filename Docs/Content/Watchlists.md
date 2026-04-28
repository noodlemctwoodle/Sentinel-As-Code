# Watchlists

Custom watchlists for enriching analytics rules and hunting queries. Each watchlist is a subfolder under [`Watchlists/`](../../Watchlists/) containing a JSON metadata file and a CSV data file.

## Folder Structure

```
Watchlists/
  HighValueAssets/
    watchlist.json          # Metadata definition
    data.csv                # Watchlist data
  TrustedIPRanges/
    watchlist.json
    data.csv
```

## Metadata Schema (watchlist.json)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `watchlistAlias` | string | Yes | Unique alias used in KQL queries (e.g., `_GetWatchlist('HighValueAssets')`) |
| `displayName` | string | Yes | Human-readable name shown in the Sentinel UI |
| `description` | string | Yes | Description of the watchlist's purpose |
| `provider` | string | Yes | Set to `Custom` for custom watchlists |
| `itemsSearchKey` | string | Yes | Column name used as the primary key (must match a CSV header exactly) |

### Example

```json
{
  "watchlistAlias": "HighValueAssets",
  "displayName": "High Value Assets",
  "description": "Critical servers requiring elevated monitoring.",
  "provider": "Custom",
  "itemsSearchKey": "Hostname"
}
```

## Data File (data.csv)

Standard CSV format. The first row must be the header row, and one column must match `itemsSearchKey` from the metadata.

```csv
Hostname,IPAddress,Owner,Criticality
DC01,10.0.0.10,Platform Team,Critical
SQL-PROD-01,10.0.1.50,DBA Team,High
```

## Using Watchlists in KQL

```kql
let HVA = _GetWatchlist('HighValueAssets');
SigninLogs
| join kind=inner HVA on $left.Computer == $right.Hostname
| where Criticality == "Critical"
```

## Notes

- Redeploying a watchlist with the same alias replaces all existing items (idempotent)
- Maximum CSV size for inline upload is approximately 3.5 MB
- TSV format is also supported — rename the file to `data.tsv`
- The `itemsSearchKey` value is case-sensitive and must exactly match a CSV column header
- Deployment is handled by [`Scripts/Deploy-CustomContent.ps1`](../../Scripts/Deploy-CustomContent.ps1) — see [Scripts.md](../Deployment/Scripts.md#deploy-customcontentps1)
- For a watchlist that's auto-populated by an Azure Automation runbook (DCR inventory), see [DCR Watchlist](../Operations/DCR-Watchlist.md)
