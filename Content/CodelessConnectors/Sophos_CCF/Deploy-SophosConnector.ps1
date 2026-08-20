#
# Sentinel-As-Code/Content/CodelessConnectors/Sophos_CCF/Deploy-SophosConnector.ps1
#
# Created by noodlemctwoodle on 20/08/2026.
#

<#
.SYNOPSIS
    Deploys the Sophos Central CCF (Codeless Connector Framework) package to a Microsoft Sentinel workspace.

.DESCRIPTION
    Deploys, in order:
      1. Custom tables            (Sophos_Table.json)
      2. Data Collection Rule     (Sophos_DCR.json, kind = Direct)
      3. Connector definition     (Sophos_ConnectorDefinition.json)
      4. Data connector pollers   (Sophos_PollingConfig.json)  [optional]

    Template placeholders ({{location}}, {{workspaceResourceId}}, {{dataCollectionEndpoint}},
    {{dataCollectionRuleImmutableId}}) are resolved automatically at deploy time.

    The poller step (4) is only run when -ClientId and -ClientSecret are supplied. Otherwise the
    connector appears in Sentinel and you complete the connection from the UI (Data connectors >
    Sophos Central > Connect). The client secret is held only as a SecureString and, when the
    pollers are deployed, is passed to the Azure CLI as an in-memory argument. It is never
    written to disk and never printed.

.PARAMETER SubscriptionId
    Target Azure subscription ID.

.PARAMETER ResourceGroup
    Resource group that contains the Log Analytics / Sentinel workspace.

.PARAMETER WorkspaceName
    Name of the Log Analytics workspace onboarded to Microsoft Sentinel.

.PARAMETER Location
    Azure region (e.g. eastus, uksouth). Defaults to the workspace's region if omitted.

.PARAMETER ClientId
    (Optional) Sophos Central API Client ID. Supply with -ClientSecret to also deploy the pollers.

.PARAMETER ClientSecret
    (Optional) Sophos Central API Client Secret (SecureString).

.EXAMPLE
    ./Deploy-SophosConnector.ps1 -SubscriptionId <sub> -ResourceGroup rg-sentinel -WorkspaceName ws-sentinel

.EXAMPLE
    ./Deploy-SophosConnector.ps1 -SubscriptionId <sub> -ResourceGroup rg-sentinel -WorkspaceName ws-sentinel `
        -ClientId <id> -ClientSecret (Read-Host -AsSecureString "Sophos Client Secret")

.NOTES
    Requires: Azure CLI (az) logged in with rights to create tables, DCRs, and Sentinel resources.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $WorkspaceName,
    [Parameter()]          [string] $Location,
    [Parameter()]          [string] $ClientId,
    [Parameter()]          [securestring] $ClientSecret
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- API versions --------------------------------------------------------------
# Pinned to the versions the repository standardises on, see the $apiVersions map in
# Tools/Documenter/Export-SentinelInventory.ps1. dataConnectorDefinitions and the
# RestApiPoller connector kind are preview-only resource types, so both use the
# repository's SentinelPreview pin rather than the Sentinel GA pin.
$apiTables    = '2023-09-01'         # Tables
$apiDcr       = '2023-03-11'         # DataCollection
$apiConnDef   = '2024-10-01-preview' # SentinelPreview
$apiConnector = '2024-10-01-preview' # SentinelPreview
$apiWorkspace = '2025-02-01'         # OperationalInsights

# --- Paths ---------------------------------------------------------------------
$root            = $PSScriptRoot
$tableFile       = Join-Path $root 'Sophos_Table.json'
$dcrFile         = Join-Path $root 'Sophos_DCR.json'
$connDefFile     = Join-Path $root 'Sophos_ConnectorDefinition.json'
$pollingFile     = Join-Path $root 'Sophos_PollingConfig.json'

foreach ($f in @($tableFile, $dcrFile, $connDefFile, $pollingFile)) {
    if (-not (Test-Path $f)) { throw "Required file not found: $f" }
}

# --- Helpers -------------------------------------------------------------------
function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    [OK] $Message" -ForegroundColor Green }

function Invoke-AzRestPut {
    # The body is passed as an in-memory argument rather than via a temporary file. The
    # poller bodies carry the Sophos client secret, and a temp file would place that secret
    # on disk with default ACLs for the lifetime of the call. PowerShell passes native
    # arguments without shell re-parsing, so the JSON needs no escaping here.
    param([string]$Url, [string]$BodyJson)

    $result = az rest --method put --url $Url --headers 'Content-Type=application/json' --body $BodyJson 2>&1
    if ($LASTEXITCODE -ne 0) {
        # $result can echo the request body, which may contain the client secret, so report
        # the failing URL and status only.
        throw "PUT $Url failed with exit code $LASTEXITCODE."
    }
    if ([string]::IsNullOrWhiteSpace([string]$result)) { return $null }
    return ($result | ConvertFrom-Json -Depth 100)
}

function Invoke-AzRestGet {
    param([string]$Url)
    $result = az rest --method get --url $Url 2>&1
    if ($LASTEXITCODE -ne 0) { throw "GET $Url failed:`n$result" }
    return ($result | ConvertFrom-Json -Depth 100)
}

# --- 0. Context ----------------------------------------------------------------
Write-Step "Verifying Azure CLI session"
$account = az account show 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $account) { throw "Not logged in. Run 'az login' first." }
az account set --subscription $SubscriptionId | Out-Null
Write-Ok "Subscription set to $SubscriptionId"

$workspaceResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"

Write-Step "Resolving workspace"
$ws = Invoke-AzRestGet -Url "https://management.azure.com$workspaceResourceId`?api-version=$apiWorkspace"
if (-not $Location) { $Location = $ws.location }
Write-Ok "Workspace '$WorkspaceName' in '$Location'"

# --- 1. Custom tables ----------------------------------------------------------
Write-Step "Deploying custom tables"
$tables = Get-Content $tableFile -Raw | ConvertFrom-Json -Depth 100
foreach ($table in $tables) {
    $tableName = $table.name
    $body = @{ properties = @{ schema = $table.properties.schema } } | ConvertTo-Json -Depth 100
    $url  = "https://management.azure.com$workspaceResourceId/tables/$tableName`?api-version=$apiTables"
    Invoke-AzRestPut -Url $url -BodyJson $body | Out-Null
    Write-Ok "Table $tableName"
}

# --- 2. Data Collection Rule ---------------------------------------------------
Write-Step "Deploying Data Collection Rule"
$dcrRaw = Get-Content $dcrFile -Raw
$dcrRaw = $dcrRaw.Replace('{{location}}', $Location).Replace('{{workspaceResourceId}}', $workspaceResourceId)
$dcr    = $dcrRaw | ConvertFrom-Json -Depth 100

$dcrName = $dcr.name
$dcrBody = @{
    location   = $Location
    kind       = $dcr.kind
    properties = $dcr.properties
}
if ($dcr.PSObject.Properties.Name -contains 'tags' -and $dcr.tags) { $dcrBody.tags = $dcr.tags }
$dcrBody = $dcrBody | ConvertTo-Json -Depth 100

$dcrResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/dataCollectionRules/$dcrName"
$dcrResult = Invoke-AzRestPut -Url "https://management.azure.com$dcrResourceId`?api-version=$apiDcr" -BodyJson $dcrBody

$dcrImmutableId = $dcrResult.properties.immutableId
$dcrEndpoint    = $null
if ($dcrResult.properties.PSObject.Properties.Name -contains 'endpoints') {
    $dcrEndpoint = $dcrResult.properties.endpoints.logsIngestion
}
if (-not $dcrImmutableId) {
    # Re-read to be safe (some API versions omit immutableId on PUT response)
    $dcrResult = Invoke-AzRestGet -Url "https://management.azure.com$dcrResourceId`?api-version=$apiDcr"
    $dcrImmutableId = $dcrResult.properties.immutableId
    if ($dcrResult.properties.PSObject.Properties.Name -contains 'endpoints') {
        $dcrEndpoint = $dcrResult.properties.endpoints.logsIngestion
    }
}
Write-Ok "DCR $dcrName (immutableId: $dcrImmutableId)"
if ($dcrEndpoint) { Write-Ok "Ingestion endpoint: $dcrEndpoint" }

# --- 3. Connector definition ---------------------------------------------------
Write-Step "Deploying connector definition"
$connDefRaw = (Get-Content $connDefFile -Raw).Replace('{{location}}', $Location)
$connDef    = $connDefRaw | ConvertFrom-Json -Depth 100
$connDefName = $connDef.name
$connDefBody = @{
    kind         = $connDef.kind
    location     = $Location
    properties   = $connDef.properties
}
if ($connDef.PSObject.Properties.Name -contains 'tags' -and $connDef.tags) { $connDefBody.tags = $connDef.tags }
$connDefBody = $connDefBody | ConvertTo-Json -Depth 100

$connDefUrl = "https://management.azure.com$workspaceResourceId/providers/Microsoft.SecurityInsights/dataConnectorDefinitions/$connDefName`?api-version=$apiConnDef"
Invoke-AzRestPut -Url $connDefUrl -BodyJson $connDefBody | Out-Null
Write-Ok "Connector definition $connDefName"

# --- 4. Data connector pollers (optional) --------------------------------------
if ($ClientId -and $ClientSecret) {
    if (-not $dcrEndpoint) {
        throw "DCR did not expose a logs ingestion endpoint; cannot deploy pollers automatically. Complete the connection from the Sentinel UI instead."
    }

    Write-Step "Deploying data connector pollers"
    $plainSecret = [System.Net.NetworkCredential]::new('', $ClientSecret).Password

    $pollingRaw = (Get-Content $pollingFile -Raw).
        Replace('{{location}}', $Location).
        Replace('{{dataCollectionEndpoint}}', $dcrEndpoint).
        Replace('{{dataCollectionRuleImmutableId}}', $dcrImmutableId).
        Replace('{{clientId}}', $ClientId).
        Replace('{{clientSecret}}', $plainSecret)

    $pollers = $pollingRaw | ConvertFrom-Json -Depth 100
    foreach ($poller in $pollers) {
        $pollerName = $poller.name
        $pollerBody = @{
            kind       = $poller.kind
            properties = $poller.properties
        } | ConvertTo-Json -Depth 100

        $pollerUrl = "https://management.azure.com$workspaceResourceId/providers/Microsoft.SecurityInsights/dataConnectors/$pollerName`?api-version=$apiConnector"
        Invoke-AzRestPut -Url $pollerUrl -BodyJson $pollerBody | Out-Null
        Write-Ok "Poller $pollerName"
    }
    $plainSecret = $null
}
else {
    Write-Step "Skipping poller deployment (no credentials supplied)"
    Write-Host "    Complete the connection in Microsoft Sentinel:" -ForegroundColor Yellow
    Write-Host "    Data connectors > 'Sophos Central (using REST API)' > Connect" -ForegroundColor Yellow
}

Write-Host "`nDeployment complete." -ForegroundColor Green
