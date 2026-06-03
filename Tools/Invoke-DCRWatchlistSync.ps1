#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Enumerates DCR associations via the ARM REST API and performs a full replace
    of the Sentinel CustomerResources watchlist.

.DESCRIPTION
    Authenticates via system-assigned managed identity, lists all Data Collection
    Rules in the subscription using Invoke-AzRestMethod, retrieves associations
    for each DCR, builds an in-memory CSV, then calls the Sentinel Watchlist REST
    API to delete and recreate the watchlist in a single operation.

    No Az.ResourceGraph dependency — uses the same ARM API pattern as
    Invoke-DCRAudit.ps1 (DCR api-version 2024-03-11, watchlist api-version 2025-09-01).

.PARAMETER SubscriptionId
    The subscription ID to enumerate DCRs from.

.PARAMETER WorkspaceResourceGroup
    Resource group containing the Sentinel Log Analytics workspace.

.PARAMETER WorkspaceName
    Log Analytics workspace name (Sentinel).

.PARAMETER WatchlistAlias
    Alias (unique identifier) for the Sentinel watchlist.

.PARAMETER WatchlistDisplayName
    Human-readable display name shown in Sentinel.

.PARAMETER SearchKey
    Column used as the watchlist search key. Defaults to ResourceId.

.NOTES
    Author:         noodlemctwoodle
    Version:        1.0.0
    Last Updated:   2026-03-23
    Repository:     Sentinel-As-Code
    Website:        https://sentinel.blog

    Required RBAC on managed identity:
      - Monitoring Reader on subscription (to list DCRs and associations via ARM)
      - Microsoft Sentinel Contributor on Sentinel resource group (watchlist write)

    API versions:
      - DCR / associations : 2024-03-11
      - Sentinel watchlist : 2025-09-01
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $SubscriptionId

  , [Parameter(Mandatory)]
    [string] $WorkspaceResourceGroup

  , [Parameter(Mandatory)]
    [string] $WorkspaceName

  , [Parameter(Mandatory)]
    [string] $WatchlistAlias

  , [Parameter()]
    [string] $WatchlistDisplayName = 'Customer DCR Resources'

  , [Parameter()]
    [string] $SearchKey = 'DCRName'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region ── Constants ────────────────────────────────────────────────────────────

$DCR_API_VERSION       = '2024-03-11'
$WATCHLIST_API_VERSION = '2025-09-01'
$ARM_BASE              = 'https://management.azure.com'

#endregion

#region ── Helper: Write-AuditLog ───────────────────────────────────────────────

function Write-AuditLog {
    [CmdletBinding()]
    param (
        [string] $Message
      , [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string] $Level = 'Info'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Output "[$ts] [$Level] $Message"
}

#endregion

#region ── Helper: Invoke-ArmRequest ────────────────────────────────────────────

function Invoke-ArmRequest {
    <#
    .SYNOPSIS
        Thin wrapper around Invoke-AzRestMethod with consistent error handling.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Uri

      , [string] $Method = 'GET'

      , [string] $Body
    )

    $params = @{
        Uri    = $Uri
        Method = $Method
    }
    if ($Body) { $params['Payload'] = $Body }

    $response = Invoke-AzRestMethod @params

    if ($response.StatusCode -notin 200, 201, 202, 204) {
        throw "ARM request failed [$Method $Uri] — HTTP $($response.StatusCode): $($response.Content)"
    }

    return $response
}

#endregion

#region ── Helper: Get-DCRList ──────────────────────────────────────────────────

function Get-DCRList {
    <#
    .SYNOPSIS
        Lists all DCRs in the subscription via the ARM REST API.
        Handles nextLink pagination automatically.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $SubscriptionId
    )

    $dcrs    = [System.Collections.Generic.List[object]]::new()
    $nextUri = "$ARM_BASE/subscriptions/$SubscriptionId/providers/Microsoft.Insights/dataCollectionRules?api-version=$DCR_API_VERSION"

    do {
        $response = Invoke-ArmRequest -Uri $nextUri
        $content  = $response.Content | ConvertFrom-Json

        foreach ($dcr in $content.value) { $dcrs.Add($dcr) }

        $nextUri = if ($content.PSObject.Properties['nextLink']) { $content.nextLink } else { $null }
    }
    while ($nextUri)

    return $dcrs
}

#endregion

#region ── Helper: Get-DCRAssociations ──────────────────────────────────────────

function Get-DCRAssociations {
    <#
    .SYNOPSIS
        Retrieves associations for a specific DCR via its resource ID.
        Handles pagination and parses associated resource details.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $DataCollectionRuleId
    )

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $nextUri = "$ARM_BASE$($DataCollectionRuleId)/associations?api-version=$DCR_API_VERSION"

    do {
        $response = Invoke-AzRestMethod -Uri $nextUri -Method GET

        if ($response.StatusCode -ne 200) {
            Write-AuditLog "Failed to retrieve associations (HTTP $($response.StatusCode)) for: $DataCollectionRuleId" -Level Warning
            return $results
        }

        $content = $response.Content | ConvertFrom-Json

        if ($content.PSObject.Properties['value']) {
            foreach ($assoc in $content.value) {

                # Skip built-in endpoint associations
                if ($assoc.name -eq 'configurationAccessEndpoint') { continue }

                $resourceId    = $null
                $resourceName  = $null
                $resourceType  = $null
                $resourceGroup = $null

                if ($assoc.id -match '^(.+)/providers/Microsoft\.Insights/dataCollectionRuleAssociations/') {
                    $resourceId = $Matches[1]

                    if ($resourceId -match '/([^/]+)$')                        { $resourceName  = $Matches[1] }
                    if ($resourceId -match '/resourceGroups/([^/]+)/')         { $resourceGroup = $Matches[1] }
                    if ($resourceId -match '/providers/([^/]+/[^/]+)/[^/]+$') { $resourceType  = $Matches[1] }
                }

                $results.Add([PSCustomObject]@{
                    AssociationName = $assoc.name
                    ResourceId      = $resourceId
                    ResourceName    = $resourceName
                    ResourceType    = $resourceType
                    ResourceGroup   = $resourceGroup
                })
            }
        }

        $nextUri = if ($content.PSObject.Properties['nextLink']) { $content.nextLink } else { $null }
    }
    while ($nextUri)

    return $results
}

#endregion

#region ── Auth ─────────────────────────────────────────────────────────────────

Write-AuditLog 'Authenticating via managed identity...'
Connect-AzAccount -Identity | Out-Null
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
Write-AuditLog 'Authentication successful.' -Level Success

#endregion

#region ── Enumerate DCRs ───────────────────────────────────────────────────────

Write-AuditLog 'Listing DCRs via ARM API...'

$dcrs = @(Get-DCRList -SubscriptionId $SubscriptionId)

Write-AuditLog "Found $($dcrs.Count) DCR(s)." -Level Success

if ($dcrs.Count -eq 0) {
    Write-AuditLog 'No DCRs found in subscription. Watchlist will not be updated.' -Level Warning
    exit 0
}

#endregion

#region ── Enumerate Associations (per-DCR) ────────────────────────────────────

Write-AuditLog 'Retrieving associations for each DCR...'

$dcrRows    = [ordered]@{}  # keyed by DCR name
$now        = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$totalAssoc = 0

foreach ($dcr in $dcrs) {

    $dcrName = $dcr.name
    $dcrId   = $dcr.id
    $dcrRg   = if ($dcrId -match '/resourceGroups/([^/]+)/') { $Matches[1] } else { '' }

    Write-AuditLog "  Getting associations for: $dcrName"

    $associations = @(Get-DCRAssociations -DataCollectionRuleId $dcrId)

    if ($associations.Count -eq 0) {
        Write-AuditLog "    No associations — skipping."
        continue
    }

    $totalAssoc += $associations.Count
    Write-AuditLog "    $($associations.Count) association(s) found." -Level Success

    $dcrRows[$dcrName] = [PSCustomObject]@{
        DCRName          = $dcrName
        DCRId            = $dcrId
        DCRResourceGroup = $dcrRg
        SubscriptionId   = $SubscriptionId
        ResourceCount    = $associations.Count
        ResourceNames    = [System.Collections.Generic.List[string]]::new()
        ResourceTypes    = [System.Collections.Generic.List[string]]::new()
        LastUpdatedUtc   = $now
    }

    $row = $dcrRows[$dcrName]
    foreach ($assoc in $associations) {
        if ($assoc.ResourceName -and $assoc.ResourceName -notin $row.ResourceNames) {
            $row.ResourceNames.Add($assoc.ResourceName)
        }
        if ($assoc.ResourceType -and $assoc.ResourceType -notin $row.ResourceTypes) {
            $row.ResourceTypes.Add($assoc.ResourceType)
        }
    }
}

Write-AuditLog "Total: $totalAssoc association(s) across $($dcrRows.Count) DCR(s)."

if ($dcrRows.Count -eq 0) {
    Write-AuditLog 'No associations found across any DCR. Watchlist will not be updated to avoid accidental empty replace.' -Level Warning
    exit 0
}

# Log summary per DCR
foreach ($row in $dcrRows.Values) {
    Write-AuditLog "  $($row.DCRName): $($row.ResourceCount) resource(s)" -Level Success
}

#endregion

#region ── Watchlist Schema ─────────────────────────────────────────────────────

$columns = @(
    'DCRName'
  , 'DCRId'
  , 'DCRResourceGroup'
  , 'SubscriptionId'
  , 'ActiveResourceCount'
  , 'ActiveResourceNames'
  , 'AllResourceNames'
  , 'RemovedResourceNames'
  , 'ResourceTypes'
  , 'PeakResourceCount'
  , 'FirstSeenUtc'
  , 'LastUpdatedUtc'
  , 'Status'
)

#endregion

#region ── Sentinel Watchlist Upsert ───────────────────────────────────────────

$watchlistBase = "$ARM_BASE/subscriptions/$SubscriptionId" +
                 "/resourceGroups/$WorkspaceResourceGroup" +
                 "/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName" +
                 "/providers/Microsoft.SecurityInsights/watchlists/$WatchlistAlias"
$watchlistUri  = "$watchlistBase`?api-version=$WATCHLIST_API_VERSION"
$itemsBaseUri  = "$watchlistBase/watchlistItems"

# ── Helper: Build CSV row from DCR data ───────────────────────────────────────

function ConvertTo-WatchlistCsvRow {
    param ([PSCustomObject] $Row, [string[]] $Columns)

    $values = foreach ($col in $Columns) {
        $val = switch ($col) {
            'ActiveResourceNames'  { ($Row.ResourceNames | Sort-Object) -join '; ' }
            'AllResourceNames'     { ($Row.ResourceNames | Sort-Object) -join '; ' }
            'ResourceTypes'        { ($Row.ResourceTypes | Sort-Object) -join '; ' }
            'ActiveResourceCount'  { [string]$Row.ResourceCount }
            'PeakResourceCount'    { [string]$Row.ResourceCount }
            'RemovedResourceNames' { '' }
            'FirstSeenUtc'         { $now }
            'LastUpdatedUtc'       { $now }
            'Status'               { 'Active' }
            default                { [string]$Row.$col }
        }
        if ($val -match '[,;"\r\n]') { '"' + $val.Replace('"', '""') + '"' }
        else                         { $val }
    }
    return ($values -join ',')
}

# ── Step 1: Create watchlist if it doesn't exist ─────────────────────────────

Write-AuditLog 'Checking for existing watchlist...'

$checkResponse   = Invoke-AzRestMethod -Uri $watchlistUri -Method GET
$watchlistExists = $checkResponse.StatusCode -eq 200

if ($watchlistExists) {
    Write-AuditLog 'Existing watchlist found.'
}
elseif ($checkResponse.StatusCode -eq 404) {
    Write-AuditLog 'Watchlist does not exist — creating with data...'

    # Build full CSV with all current DCR rows
    $csvLines = [System.Collections.Generic.List[string]]::new()
    $csvLines.Add($columns -join ',')

    foreach ($row in $dcrRows.Values) {
        $csvLines.Add((ConvertTo-WatchlistCsvRow -Row $row -Columns $columns))
    }

    $csvPayload = $csvLines -join "`n"

    $createBody = [ordered]@{
        properties = [ordered]@{
            displayName         = $WatchlistDisplayName
            source              = 'Local file'
            provider            = 'Microsoft'
            itemsSearchKey      = $SearchKey
            rawContent          = $csvPayload
            contentType         = 'Text/Csv'
            numberOfLinesToSkip = 0
        }
    } | ConvertTo-Json -Depth 5

    Invoke-ArmRequest -Uri $watchlistUri -Method PUT -Body $createBody | Out-Null
    Write-AuditLog "Watchlist created with $($dcrRows.Count) DCR(s), $totalAssoc association(s)." -Level Success

    Start-Sleep -Seconds 3
}
else {
    throw "Unexpected response checking watchlist — HTTP $($checkResponse.StatusCode): $($checkResponse.Content)"
}

# ── Step 2: List existing watchlist items (preserve billing history) ──────────

Write-AuditLog 'Listing existing watchlist items...'

$existingItems = [ordered]@{}  # keyed by SearchKey value (DCRName) → full item data
$nextUri       = "$itemsBaseUri`?api-version=$WATCHLIST_API_VERSION"

do {
    $response = Invoke-AzRestMethod -Uri $nextUri -Method GET

    if ($response.StatusCode -ne 200) {
        Write-AuditLog "Failed listing watchlist items — HTTP $($response.StatusCode)" -Level Warning
        break
    }

    $content = $response.Content | ConvertFrom-Json

    foreach ($item in $content.value) {
        $keyValue = $item.properties.itemsKeyValue
        $existingItems[$keyValue] = @{
            ItemId         = $item.properties.watchlistItemId
            EntityMapping  = $item.properties.entityMapping
        }
    }

    $nextUri = if ($content.PSObject.Properties['nextLink']) { $content.nextLink } else { $null }
}
while ($nextUri)

Write-AuditLog "Found $($existingItems.Count) existing item(s) in watchlist."

# ── Step 3: Merge and upsert — never lose billing history ────────────────────

Write-AuditLog 'Merging watchlist items (billing-safe)...'

$created   = 0
$updated   = 0
$deactived = 0
$newKeys   = [System.Collections.Generic.HashSet[string]]::new()

foreach ($row in $dcrRows.Values) {

    $keyValue       = $row.$SearchKey
    [void]$newKeys.Add($keyValue)
    $activeNames    = [System.Collections.Generic.List[string]]($row.ResourceNames | Sort-Object)
    $activeTypes    = [System.Collections.Generic.List[string]]($row.ResourceTypes | Sort-Object)
    $activeNamesStr = $activeNames -join '; '
    $activeTypesStr = $activeTypes -join '; '

    if ($existingItems.Contains($keyValue)) {
        # ── UPDATE: merge new resources into historical list ──────────
        $existing    = $existingItems[$keyValue]
        $itemId      = $existing.ItemId
        $entityMap   = $existing.EntityMapping

        # Parse existing AllResourceNames (cumulative history)
        $previousAll = @()
        if ($entityMap.PSObject.Properties['AllResourceNames'] -and $entityMap.AllResourceNames) {
            $previousAll = @($entityMap.AllResourceNames -split ';\s*' | Where-Object { $_ })
        }

        # Union: all previously seen + all currently active
        $allNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($n in $previousAll) { [void]$allNames.Add($n) }
        foreach ($n in $activeNames) { [void]$allNames.Add($n) }
        $allNamesStr = ($allNames | Sort-Object) -join '; '

        # Removed = in AllResourceNames but NOT in current active
        $removedNames = $allNames | Where-Object { $_ -notin $activeNames } | Sort-Object
        $removedStr   = $removedNames -join '; '

        # Preserve FirstSeenUtc from existing row
        $firstSeen = if ($entityMap.PSObject.Properties['FirstSeenUtc'] -and $entityMap.FirstSeenUtc) {
            $entityMap.FirstSeenUtc
        } else { $now }

        # Peak = max of previous peak and current count
        $previousPeak = 0
        if ($entityMap.PSObject.Properties['PeakResourceCount'] -and $entityMap.PeakResourceCount) {
            $previousPeak = [int]$entityMap.PeakResourceCount
        }
        $peak = [Math]::Max($previousPeak, $row.ResourceCount)

        $updated++
    }
    else {
        # ── CREATE: brand new DCR ─────────────────────────────────────
        $itemId       = [guid]::NewGuid().ToString()
        $allNamesStr  = $activeNamesStr
        $removedStr   = ''
        $firstSeen    = $now
        $peak         = $row.ResourceCount

        $created++
    }

    $itemProps = [ordered]@{
        DCRName              = $row.DCRName
        DCRId                = $row.DCRId
        DCRResourceGroup     = $row.DCRResourceGroup
        SubscriptionId       = $row.SubscriptionId
        ActiveResourceCount  = [string]$row.ResourceCount
        ActiveResourceNames  = $activeNamesStr
        AllResourceNames     = $allNamesStr
        RemovedResourceNames = $removedStr
        ResourceTypes        = $activeTypesStr
        PeakResourceCount    = [string]$peak
        FirstSeenUtc         = $firstSeen
        LastUpdatedUtc       = $now
        Status               = 'Active'
    }

    $itemBody = [ordered]@{
        properties = [ordered]@{
            itemsKeyValue = $keyValue
            entityMapping = $itemProps
        }
    } | ConvertTo-Json -Depth 5

    $itemUri = "$itemsBaseUri/$itemId`?api-version=$WATCHLIST_API_VERSION"
    Invoke-ArmRequest -Uri $itemUri -Method PUT -Body $itemBody | Out-Null
}

# ── Step 4: Mark removed DCRs as inactive (never delete for billing) ─────────

foreach ($existingKey in $existingItems.Keys) {
    if (-not $newKeys.Contains($existingKey)) {
        $existing  = $existingItems[$existingKey]
        $itemId    = $existing.ItemId
        $entityMap = $existing.EntityMapping

        # Preserve all historical data, just mark inactive
        $prevAll = ''
        if ($entityMap.PSObject.Properties['AllResourceNames'] -and $entityMap.AllResourceNames) {
            $prevAll = $entityMap.AllResourceNames
        }

        $itemProps = [ordered]@{
            DCRName              = $existingKey
            DCRId                = if ($entityMap.PSObject.Properties['DCRId'])            { $entityMap.DCRId }            else { '' }
            DCRResourceGroup     = if ($entityMap.PSObject.Properties['DCRResourceGroup']) { $entityMap.DCRResourceGroup } else { '' }
            SubscriptionId       = $SubscriptionId
            ActiveResourceCount  = '0'
            ActiveResourceNames  = ''
            AllResourceNames     = $prevAll
            RemovedResourceNames = $prevAll
            ResourceTypes        = if ($entityMap.PSObject.Properties['ResourceTypes'])    { $entityMap.ResourceTypes }    else { '' }
            PeakResourceCount    = if ($entityMap.PSObject.Properties['PeakResourceCount']){ $entityMap.PeakResourceCount }else { '0' }
            FirstSeenUtc         = if ($entityMap.PSObject.Properties['FirstSeenUtc'])     { $entityMap.FirstSeenUtc }     else { $now }
            LastUpdatedUtc       = $now
            Status               = 'Inactive'
        }

        $itemBody = [ordered]@{
            properties = [ordered]@{
                itemsKeyValue = $existingKey
                entityMapping = $itemProps
            }
        } | ConvertTo-Json -Depth 5

        $itemUri = "$itemsBaseUri/$itemId`?api-version=$WATCHLIST_API_VERSION"
        Invoke-ArmRequest -Uri $itemUri -Method PUT -Body $itemBody | Out-Null

        Write-AuditLog "  Marked inactive (billing retained): $existingKey" -Level Warning
        $deactived++
    }
}

Write-AuditLog "Watchlist '$WatchlistAlias' sync complete — $created created, $updated updated, $deactived deactivated ($totalAssoc active association(s) across $($dcrRows.Count) DCR(s))." -Level Success

#endregion
