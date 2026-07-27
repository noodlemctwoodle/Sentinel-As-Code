#
# Sentinel-As-Code/Tools/Test-DcrIngestion.ps1
#
# Created by noodlemctwoodle on 23/07/2026.
#

#Requires -Version 7.2
#Requires -Modules Az.Accounts, Az.OperationalInsights, Az.Resources

<#
.SYNOPSIS
    Streams synthetic records into a DCR through the Logs Ingestion API to
    prove a migrated table ingests live, using a service principal.

.DESCRIPTION
    The last step of testing a classic-to-DCR migration is confirming the
    new path works: that data sent to the Data Collection Rule's logs
    ingestion endpoint actually lands in the destination table. This is the
    Logs Ingestion API (the HTTP ingestion API), the successor to the
    HTTP Data Collector API, and it is a different API from the one the
    fixture used to create the classic table:

      - New-ClassicTableFixture.ps1 -> HTTP Data Collector API (SharedKey),
        creates the classic table.
      - New-DcrFromClassicTable.ps1 -> migrates the table, deploys the DCR.
      - THIS script -> Logs Ingestion API (AAD bearer), streams data into
        the migrated table through the DCR.

    The tool reads everything it needs from the DCR itself under your Az
    context: the immutable ID, the logs ingestion endpoint, the stream
    declaration (so generated records match the schema), and the
    destination table and workspace (for the optional arrival check). It
    then streams batches on an interval, authenticated as a service
    principal via the OAuth2 client-credentials flow. Your own Az session
    is used only for the read-side work; only the ingestion POSTs use the
    service principal, which needs the Monitoring Metrics Publisher role on
    the DCR.

    A successful POST (HTTP 204) is the primary signal: it means auth, the
    endpoint, and the schema are all correct. -Follow additionally queries
    the destination table to watch rows arrive, subject to ingestion
    latency.

.PARAMETER DcrName
    Name of the deployed Data Collection Rule to send to.

.PARAMETER DcrResourceGroupName
    Resource group containing the DCR.

.PARAMETER TenantId
    Entra tenant ID of the sending service principal. If omitted, taken from
    DCR_INGEST_TENANT_ID or AZURE_TENANT_ID (including from a .env file).

.PARAMETER ClientId
    Application (client) ID of the sending service principal. If omitted,
    taken from DCR_INGEST_CLIENT_ID or AZURE_CLIENT_ID.

.PARAMETER ClientSecret
    Client secret as a SecureString. If omitted, taken from
    DCR_INGEST_CLIENT_SECRET or AZURE_CLIENT_SECRET, which keeps the secret
    out of your shell history and the process argument list.

.PARAMETER EnvFile
    Path to a dotenv file of KEY=VALUE lines loaded into the environment
    before the tenant, client and secret are resolved. Defaults to '.env'
    in the current directory; ignored if it does not exist. Values already
    present in the environment are not overwritten. Keep this file out of
    source control (the repo .gitignore excludes .env).

.PARAMETER StreamName
    Input stream to send to, for example 'Custom-MyApp_CL'. Optional when
    the DCR declares exactly one stream, which is the usual case for a
    migrated table.

.PARAMETER BatchSize
    Records per POST. Defaults to 10. Keep the JSON body under 1 MB.

.PARAMETER IntervalSeconds
    Seconds to wait between batches. Defaults to 5.

.PARAMETER DurationSeconds
    Stop after this many seconds. Omit for no time limit.

.PARAMETER BatchCount
    Stop after this many batches. Omit for no batch limit. If neither
    -DurationSeconds nor -BatchCount is given, the stream runs until you
    press Ctrl-C.

.PARAMETER Follow
    After each batch, query the destination table for rows from this run
    and report how many have arrived. Subject to ingestion latency.

.PARAMETER GrantIngestionRole
    Grant the service principal Monitoring Metrics Publisher on the DCR if
    it does not already have it. Off by default: the script otherwise
    checks and prints the command for you to run.

.PARAMETER AuthorityHost
    Entra authority host. Defaults to the public cloud
    'https://login.microsoftonline.com'. Azure Government:
    'https://login.microsoftonline.us'.

.PARAMETER IngestionAudience
    Token audience (scope host) for the Logs Ingestion API. Defaults to the
    public cloud 'https://monitor.azure.com'. Azure Government:
    'https://monitor.azure.us'.

.PARAMETER SubscriptionId
    Subscription to operate in. Defaults to the current Az context.

.EXAMPLE
    $env:DCR_INGEST_CLIENT_SECRET = '<secret>'
    ./Tools/Test-DcrIngestion.ps1 -DcrName dcr-myapp -DcrResourceGroupName rg-scratch `
        -TenantId <tid> -ClientId <appid> -Follow

    Streams 10 records every 5 seconds into the DCR's single stream, as the
    service principal, and reports arrival in the destination table until
    you press Ctrl-C.

.EXAMPLE
    ./Tools/Test-DcrIngestion.ps1 -DcrName dcr-myapp -DcrResourceGroupName rg-scratch `
        -TenantId <tid> -ClientId <appid> -ClientSecret (Read-Host -AsSecureString) `
        -BatchCount 3 -BatchSize 5

    Sends three batches of five records and stops.

.NOTES
    Author:       noodlemctwoodle
    Version:      1.0.0
    Last Updated: 2026-07-23
    Repository:   Sentinel-As-Code
    Website:      https://sentinel.blog
    Requires:     PowerShell 7.2+, Az.Accounts, Az.OperationalInsights, Az.Resources

    Runs standalone. Nothing from this repository needs to be alongside it.

    RBAC:
      - Your Az identity: Reader on the DCR, and Log Analytics Reader on the
        workspace if you use -Follow.
      - The service principal: Monitoring Metrics Publisher on the DCR.

    The client secret is held in memory only and never written to output.
    A freshly granted role can take a few minutes to take effect for
    data-plane calls, so expect 401/403 immediately after -GrantIngestionRole.

    Reference:
      https://learn.microsoft.com/azure/azure-monitor/logs/logs-ingestion-api-overview
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string] $DcrName

  , [Parameter(Mandatory)]
    [string] $DcrResourceGroupName

  , [Parameter()]
    [string] $TenantId

  , [Parameter()]
    [string] $ClientId

  , [Parameter()]
    [securestring] $ClientSecret

  , [Parameter()]
    [string] $EnvFile = '.env'

  , [Parameter()]
    [string] $StreamName

  , [Parameter()]
    [ValidateRange(1, 1000)]
    [int] $BatchSize = 10

  , [Parameter()]
    [ValidateRange(1, 3600)]
    [int] $IntervalSeconds = 5

  , [Parameter()]
    [int] $DurationSeconds

  , [Parameter()]
    [int] $BatchCount

  , [Parameter()]
    [switch] $Follow

  , [Parameter()]
    [ValidateRange(0, 1800)]
    [int] $ArrivalTimeoutSeconds = 300

  , [Parameter()]
    [switch] $GrantIngestionRole

  , [Parameter()]
    [string] $AuthorityHost = 'https://login.microsoftonline.com'

  , [Parameter()]
    [string] $IngestionAudience = 'https://monitor.azure.com'

  , [Parameter()]
    [string] $SubscriptionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region -- Logging ------------------------------------------------------------

# Self-contained by design. This kit deliberately does NOT import the repo's
# Sentinel.Common module: it must run unchanged on a jump box or in an
# automation account where that module is absent. Write-PipelineMessage is
# defined locally to mirror Sentinel.Common's behaviour.

function Write-PipelineMessage {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Console output is the point; mirrors Sentinel.Common.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Section', 'Success', 'Debug')]
        [string]$Level = 'Info'
    )

    $isAdo = $null -ne $env:BUILD_BUILDID

    switch ($Level) {
        'Info'    { Write-Host $Message }
        'Warning' {
            if ($isAdo) { Write-Host "##[warning]$Message" } else { Write-Warning $Message }
        }
        'Error'   {
            if ($isAdo) { Write-Host "##[error]$Message" } else { Write-Error $Message -ErrorAction Continue }
        }
        'Section' {
            if ($isAdo) { Write-Host "##[section]$Message" } else { Write-Host "`n$Message" -ForegroundColor Cyan }
        }
        'Success' {
            if ($isAdo) { Write-Host $Message } else { Write-Host $Message -ForegroundColor Green }
        }
        'Debug'   { Write-Verbose $Message }
    }
}

#endregion

#region -- Constants -----------------------------------------------------------

$script:DcrApiVersion       = '2023-03-11'   # carries the endpoints property
$script:IngestionApiVersion = '2023-01-01'
$script:TokenRefreshSkewSec = 120            # refresh when this close to expiry

#endregion

#region -- Helpers -------------------------------------------------------------

function Invoke-ArmRequest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string] $Uri
      , [Parameter()]          [string] $Method = 'GET'
      , [Parameter()]          [int[]]  $SuccessCodes = @(200, 201, 202, 204)
    )

    $response = if ([System.Uri]::IsWellFormedUriString($Uri, [System.UriKind]::Absolute)) {
        Invoke-AzRestMethod -Uri $Uri -Method $Method
    }
    else {
        Invoke-AzRestMethod -Path $Uri -Method $Method
    }

    if ($response.StatusCode -notin $SuccessCodes) {
        throw "ARM request failed [$Method $Uri]: HTTP $($response.StatusCode) $($response.Content)"
    }

    return $response
}

function Get-DcrIngestionTarget {
    <#
    .SYNOPSIS
        Extracts the immutable ID and logs ingestion endpoint from a parsed
        DCR, failing clearly when the endpoint is absent.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)] [object] $Dcr
    )

    $props = $Dcr.properties

    $immutableProp = $props.PSObject.Properties['immutableId']
    $immutableId   = if ($immutableProp) { [string]$immutableProp.Value } else { $null }

    $endpoint = $null
    $endpointsProp = $props.PSObject.Properties['endpoints']
    if ($endpointsProp -and $endpointsProp.Value) {
        $ingestProp = $endpointsProp.Value.PSObject.Properties['logsIngestion']
        if ($ingestProp) { $endpoint = [string]$ingestProp.Value }
    }

    if ([string]::IsNullOrWhiteSpace($endpoint)) {
        throw 'This DCR has no logsIngestion endpoint. Endpoints exist only on DCRs created with kind Direct on api-version 2023-03-11 or later, and cannot be added afterwards. Recreate the DCR, or use a Data Collection Endpoint.'
    }

    if ([string]::IsNullOrWhiteSpace($immutableId)) {
        throw 'This DCR has no immutableId. It may not have finished provisioning.'
    }

    return [pscustomobject] @{ ImmutableId = $immutableId; Endpoint = $endpoint }
}

function Get-DcrStreamName {
    <#
    .SYNOPSIS
        Resolves the stream to send to. Uses the sole stream declaration
        when there is only one, otherwise requires an explicit choice.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [object] $Dcr
      , [Parameter()]          [string] $Requested
    )

    # Wrap the whole if-expression in @(): capturing @(...) from inside an
    # if-block unwraps a single-element result back to a scalar string, which
    # would then index by character. The common case is a one-stream DCR.
    $declProp = $Dcr.properties.PSObject.Properties['streamDeclarations']
    $declared = @(
        if ($declProp -and $declProp.Value) {
            $declProp.Value.PSObject.Properties.Name
        }
    )

    if ($Requested) {
        if ($declared -notcontains $Requested) {
            throw "Stream '$Requested' is not declared in this DCR. Declared: $($declared -join ', ')."
        }
        return $Requested
    }

    if ($declared.Count -eq 1) { return $declared[0] }
    if ($declared.Count -eq 0) { throw 'This DCR declares no streams.' }

    throw "This DCR declares $($declared.Count) streams ($($declared -join ', ')). Pass -StreamName to choose one."
}

function Get-DcrStreamColumn {
    <#
    .SYNOPSIS
        Returns the column definitions for a named stream declaration.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param (
        [Parameter(Mandatory)] [object] $Dcr
      , [Parameter(Mandatory)] [string] $Stream
    )

    $decl = $Dcr.properties.streamDeclarations.$Stream
    $colsProp = $decl.PSObject.Properties['columns']

    if (-not $colsProp -or -not $colsProp.Value) {
        throw "Stream '$Stream' has no column definitions."
    }

    return @($colsProp.Value)
}

function Get-DestinationTableName {
    <#
    .SYNOPSIS
        Derives the destination table name from the DCR data flow's
        outputStream, for example 'Custom-MyApp_CL' -> 'MyApp_CL'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [object] $Dcr
      , [Parameter(Mandatory)] [string] $Stream
    )

    $flows = @($Dcr.properties.dataFlows)

    $match = $flows | Where-Object { @($_.streams) -contains $Stream } | Select-Object -First 1
    if (-not $match) { $match = $flows | Select-Object -First 1 }

    $outProp = if ($match) { $match.PSObject.Properties['outputStream'] } else { $null }
    $output  = if ($outProp -and $outProp.Value) { [string]$outProp.Value } else { $Stream }

    return ($output -replace '^(Custom|Microsoft)-', '')
}

function Get-IngestionUri {
    <#
    .SYNOPSIS
        Builds the Logs Ingestion API URI for a stream.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $Endpoint
      , [Parameter(Mandatory)] [string] $ImmutableId
      , [Parameter(Mandatory)] [string] $Stream
      , [Parameter()]          [string] $ApiVersion = $script:IngestionApiVersion
    )

    return '{0}/dataCollectionRules/{1}/streams/{2}?api-version={3}' -f `
        $Endpoint.TrimEnd('/'), $ImmutableId, $Stream, $ApiVersion
}

function New-StreamRecord {
    <#
    .SYNOPSIS
        Builds one synthetic record matching a stream's column definitions.

    .DESCRIPTION
        Fills every declared column with a type-appropriate value so the
        POST always matches the schema, whatever table the DCR feeds. The
        RunId is stamped into every string column so -Follow can isolate
        this run's rows, and TimeGenerated is always present.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure function: builds an in-memory record, changes no state.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)] [object[]] $StreamColumn
      , [Parameter(Mandatory)] [int]      $Index
      , [Parameter(Mandatory)] [string]   $RunId
      , [Parameter(Mandatory)] [datetime] $ReferenceTime
    )

    $record = @{}

    foreach ($column in $StreamColumn) {
        $name = $column.name
        $type = ([string]$column.type).ToLowerInvariant()

        $record[$name] = switch ($type) {
            'datetime' { $ReferenceTime.ToString('o') }
            'int'      { $Index }
            'long'     { [long]$Index }
            'real'     { [math]::Round(($Index * 1.5) + 0.5, 2) }
            'boolean'  { (($Index % 2) -eq 0) }
            'dynamic'  { @{ index = $Index; runId = $RunId } }
            default    { "dcr-test $RunId #$Index" }   # string
        }
    }

    if (-not $record.ContainsKey('TimeGenerated')) {
        $record['TimeGenerated'] = $ReferenceTime.ToString('o')
    }

    return $record
}

function New-TokenRequest {
    <#
    .SYNOPSIS
        Builds the URI and form body for an OAuth2 client-credentials token
        request. Split out from the network call so it can be unit tested.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure function: builds a request object, changes no state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)] [string] $AuthorityHost
      , [Parameter(Mandatory)] [string] $TenantId
      , [Parameter(Mandatory)] [string] $ClientId
      , [Parameter(Mandatory)] [string] $Audience
      , [Parameter(Mandatory)] [string] $ClientSecretPlain
    )

    return [pscustomobject] @{
        Uri  = '{0}/{1}/oauth2/v2.0/token' -f $AuthorityHost.TrimEnd('/'), $TenantId
        Body = @{
            client_id     = $ClientId
            scope         = "$($Audience.TrimEnd('/'))/.default"
            client_secret = $ClientSecretPlain
            grant_type    = 'client_credentials'
        }
    }
}

function ConvertFrom-SecureStringPlain {
    <#
    .SYNOPSIS
        Reads a SecureString back to plain text in memory. Isolated so the
        one place this happens is obvious and auditable.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [securestring] $Secure
    )

    return [System.Net.NetworkCredential]::new('', $Secure).Password
}

function ConvertTo-SecureStringFromPlain {
    <#
    .SYNOPSIS
        Wraps a plaintext secret in a SecureString. The single place a
        plaintext secret is promoted, so the analyzer suppression lives
        here and nowhere else.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'The secret arrives as plaintext from an environment variable or .env file; wrapping it in a SecureString is the mitigation, not the exposure.')]
    [CmdletBinding()]
    [OutputType([securestring])]
    param (
        [Parameter(Mandatory)] [string] $Plain
    )

    return ConvertTo-SecureString -String $Plain -AsPlainText -Force
}

function Import-DotEnv {
    <#
    .SYNOPSIS
        Parses a dotenv file into a hashtable of KEY=VALUE pairs.

    .DESCRIPTION
        Ignores blank lines and comments, tolerates an optional 'export '
        prefix, and strips one layer of surrounding single or double quotes
        from the value. Returns an empty hashtable if the file is absent, so
        the caller can always apply the result unconditionally.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)] [string] $Path
    )

    $result = @{}

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return $result
    }

    foreach ($line in Get-Content -Path $Path) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }

        if ($trimmed -match '^(?:export\s+)?(?<k>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?<v>.*)$') {
            $key   = $matches['k']
            $value = $matches['v'].Trim()

            if ($value.Length -ge 2 -and
                (($value[0] -eq '"' -and $value[-1] -eq '"') -or
                 ($value[0] -eq "'" -and $value[-1] -eq "'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }

            $result[$key] = $value
        }
    }

    return $result
}

function Resolve-Setting {
    <#
    .SYNOPSIS
        Returns the first non-empty value: an explicit parameter, else the
        first environment variable in EnvName that is set.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter()] [string]   $Explicit
      , [Parameter(Mandatory)] [string[]] $EnvName
    )

    if (-not [string]::IsNullOrWhiteSpace($Explicit)) {
        return $Explicit
    }

    foreach ($name in $EnvName) {
        $value = [System.Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    return $null
}

function Get-ServicePrincipalToken {
    <#
    .SYNOPSIS
        Requests an access token for the ingestion audience via the
        client-credentials flow. Returns the token and its expiry.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)] [string]       $AuthorityHost
      , [Parameter(Mandatory)] [string]       $TenantId
      , [Parameter(Mandatory)] [string]       $ClientId
      , [Parameter(Mandatory)] [string]       $Audience
      , [Parameter(Mandatory)] [securestring] $ClientSecret
    )

    $secretPlain = ConvertFrom-SecureStringPlain -Secure $ClientSecret
    $request     = New-TokenRequest -AuthorityHost $AuthorityHost -TenantId $TenantId `
                                    -ClientId $ClientId -Audience $Audience `
                                    -ClientSecretPlain $secretPlain

    try {
        $response = Invoke-RestMethod -Method Post -Uri $request.Uri -Body $request.Body `
                                      -ContentType 'application/x-www-form-urlencoded'
    }
    catch {
        throw "Token request failed: $($_.Exception.Message.Split([char]10)[0]). Check the tenant, client ID and secret."
    }

    return [pscustomobject] @{
        AccessToken = $response.access_token
        ExpiresOn   = [datetimeoffset]::UtcNow.AddSeconds([int]$response.expires_in)
    }
}

#endregion

#region -- Context -------------------------------------------------------------

Write-PipelineMessage 'DCR ingestion stream test' -Level Section

$context = Get-AzContext
if (-not $context) {
    throw 'No Az context found. Run Connect-AzAccount first.'
}

if ($SubscriptionId -and $context.Subscription.Id -ne $SubscriptionId) {
    $context = Set-AzContext -Subscription $SubscriptionId
}

if (-not $context.Subscription) {
    throw 'Az context has no subscription selected. Run Connect-AzAccount or Set-AzContext -Subscription <id> first.'
}

$resolvedSubscriptionId = $context.Subscription.Id

# Load the dotenv file (if present) into the environment. Values already set
# in the environment win, so an explicit export always beats the file.
# Resolution order for a relative path: current directory first, then next
# to this script, so a .env kept alongside the toolkit is found wherever you
# run from.
$envPath = if ([System.IO.Path]::IsPathRooted($EnvFile)) {
    $EnvFile
}
elseif (Test-Path -Path (Join-Path (Get-Location).Path $EnvFile) -PathType Leaf) {
    Join-Path (Get-Location).Path $EnvFile
}
else {
    Join-Path $PSScriptRoot $EnvFile
}
$fromFile = Import-DotEnv -Path $envPath
if ($fromFile.Count -gt 0) {
    Write-PipelineMessage "Loaded $($fromFile.Count) setting(s) from $envPath"
    foreach ($key in $fromFile.Keys) {
        if ([string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($key))) {
            Set-Item -Path "Env:$key" -Value $fromFile[$key]
        }
    }
}

# Resolve the service principal: explicit parameters win, then the standard
# env var names, so tenant / client / secret can all live in .env.
$TenantId = Resolve-Setting -Explicit $TenantId -EnvName 'DCR_INGEST_TENANT_ID', 'AZURE_TENANT_ID'
$ClientId = Resolve-Setting -Explicit $ClientId -EnvName 'DCR_INGEST_CLIENT_ID', 'AZURE_CLIENT_ID'

if (-not $TenantId) { throw 'No tenant ID. Pass -TenantId, or set DCR_INGEST_TENANT_ID / AZURE_TENANT_ID (e.g. in .env).' }
if (-not $ClientId) { throw 'No client ID. Pass -ClientId, or set DCR_INGEST_CLIENT_ID / AZURE_CLIENT_ID (e.g. in .env).' }

if (-not $ClientSecret) {
    $secretPlain = Resolve-Setting -EnvName 'DCR_INGEST_CLIENT_SECRET', 'AZURE_CLIENT_SECRET'
    if (-not $secretPlain) {
        throw 'No client secret. Pass -ClientSecret (SecureString), or set DCR_INGEST_CLIENT_SECRET / AZURE_CLIENT_SECRET (e.g. in .env).'
    }
    $ClientSecret = ConvertTo-SecureStringFromPlain -Plain $secretPlain
}

#endregion

#region -- Resolve the DCR -----------------------------------------------------

Write-PipelineMessage 'Resolving the DCR' -Level Section

$dcrResourceId = "/subscriptions/$resolvedSubscriptionId/resourceGroups/$DcrResourceGroupName" +
                 "/providers/Microsoft.Insights/dataCollectionRules/$DcrName"

$dcr = (Invoke-ArmRequest -Uri "$dcrResourceId`?api-version=$script:DcrApiVersion" -SuccessCodes @(200)).Content |
        ConvertFrom-Json

$target      = Get-DcrIngestionTarget -Dcr $dcr
$stream      = Get-DcrStreamName -Dcr $dcr -Requested $StreamName
$columns     = Get-DcrStreamColumn -Dcr $dcr -Stream $stream
$destTable   = Get-DestinationTableName -Dcr $dcr -Stream $stream
$ingestUri   = Get-IngestionUri -Endpoint $target.Endpoint -ImmutableId $target.ImmutableId -Stream $stream

Write-PipelineMessage "DCR          : $DcrName"
Write-PipelineMessage "Immutable ID : $($target.ImmutableId)"
Write-PipelineMessage "Endpoint     : $($target.Endpoint)"
Write-PipelineMessage "Stream       : $stream ($($columns.Count) columns)"
Write-PipelineMessage "Destination  : $destTable"

#endregion

#region -- Service principal role ----------------------------------------------

Write-PipelineMessage 'Checking the service principal' -Level Section

$sp = Get-AzADServicePrincipal -ApplicationId $ClientId -ErrorAction SilentlyContinue
if (-not $sp) {
    throw "No service principal found for client ID $ClientId in this tenant."
}

$spObjectId = $sp.Id
$roleName   = 'Monitoring Metrics Publisher'

$existing = Get-AzRoleAssignment -ObjectId $spObjectId -Scope $dcrResourceId `
                                 -RoleDefinitionName $roleName -ErrorAction SilentlyContinue

if ($existing) {
    Write-PipelineMessage "Service principal already holds $roleName on the DCR." -Level Success
}
elseif ($GrantIngestionRole) {
    if ($PSCmdlet.ShouldProcess("$DcrName / SP $ClientId", "Grant $roleName")) {
        New-AzRoleAssignment -ObjectId $spObjectId -RoleDefinitionName $roleName -Scope $dcrResourceId | Out-Null
        Write-PipelineMessage "Granted $roleName. Data-plane RBAC can take a few minutes to take effect, so early POSTs may 403." -Level Warning
    }
}
else {
    Write-PipelineMessage "Service principal does not hold $roleName on the DCR. Streaming will 403 until it does." -Level Warning
    Write-PipelineMessage "Grant it with:  New-AzRoleAssignment -ObjectId $spObjectId -RoleDefinitionName '$roleName' -Scope $dcrResourceId" -Level Warning
    Write-PipelineMessage 'Or re-run with -GrantIngestionRole.' -Level Warning
}

#endregion

#region -- Follow setup --------------------------------------------------------

$followWorkspaceId = $null
$followColumn      = $null

if ($Follow) {
    $wsResourceId = $dcr.properties.destinations.logAnalytics[0].workspaceResourceId
    if ($wsResourceId -match '/resourceGroups/(?<rg>[^/]+)/.*/workspaces/(?<name>[^/]+)$') {
        $followWorkspace   = Get-AzOperationalInsightsWorkspace -ResourceGroupName $matches['rg'] -Name $matches['name']
        $followWorkspaceId = $followWorkspace.CustomerId
    }

    # Prefer a string column to filter on the run marker; fall back to time.
    $stringColumn = $columns | Where-Object { ([string]$_.type).ToLowerInvariant() -eq 'string' } | Select-Object -First 1
    $followColumn = if ($stringColumn) { $stringColumn.name } else { $null }

    if (-not $followWorkspaceId) {
        Write-PipelineMessage 'Could not resolve the destination workspace for -Follow. Arrival counts will be skipped.' -Level Warning
    }
}

#endregion

#region -- Stream --------------------------------------------------------------

Write-PipelineMessage 'Streaming' -Level Section

$runId = ([guid]::NewGuid()).ToString('N').Substring(0, 12)
Write-PipelineMessage "Run marker   : $runId"
Write-PipelineMessage "Cadence      : $BatchSize records every ${IntervalSeconds}s"

$limitText = @()
if ($DurationSeconds) { $limitText += "$DurationSeconds s" }
if ($BatchCount)      { $limitText += "$BatchCount batches" }
if ($limitText.Count -eq 0) { $limitText = @('until Ctrl-C') }
Write-PipelineMessage "Runs for     : $($limitText -join ', ')"

$token       = Get-ServicePrincipalToken -AuthorityHost $AuthorityHost -TenantId $TenantId `
                                         -ClientId $ClientId -Audience $IngestionAudience `
                                         -ClientSecret $ClientSecret

$sentRecords = 0
$okBatches   = 0
$failBatches = 0
$batchIndex  = 0
$deadline    = if ($DurationSeconds) { [datetimeoffset]::UtcNow.AddSeconds($DurationSeconds) } else { $null }

if (-not $PSCmdlet.ShouldProcess($ingestUri, "Stream records ($($limitText -join ', '))")) {
    Write-PipelineMessage 'WhatIf: no data sent.' -Level Warning
    return
}

try {
    while ($true) {
        if ($deadline -and [datetimeoffset]::UtcNow -ge $deadline) { break }
        if ($BatchCount -and $batchIndex -ge $BatchCount)          { break }

        # Refresh the token before it expires.
        if ([datetimeoffset]::UtcNow -ge $token.ExpiresOn.AddSeconds(-1 * $script:TokenRefreshSkewSec)) {
            $token = Get-ServicePrincipalToken -AuthorityHost $AuthorityHost -TenantId $TenantId `
                                               -ClientId $ClientId -Audience $IngestionAudience `
                                               -ClientSecret $ClientSecret
        }

        $now   = [datetime]::UtcNow
        $batch = for ($i = 0; $i -lt $BatchSize; $i++) {
            New-StreamRecord -StreamColumn $columns -Index (($batchIndex * $BatchSize) + $i) `
                             -RunId $runId -ReferenceTime $now
        }

        $body     = ConvertTo-Json -InputObject @($batch) -Depth 10
        $bodyBytes= [System.Text.Encoding]::UTF8.GetBytes($body)

        $response = Invoke-WebRequest -Uri $ingestUri -Method Post `
                                      -Headers @{ Authorization = "Bearer $($token.AccessToken)" } `
                                      -ContentType 'application/json' -Body $bodyBytes `
                                      -SkipHttpErrorCheck

        $batchIndex++

        if ($response.StatusCode -in 200, 204) {
            $sentRecords += $BatchSize
            $okBatches++
            $stamp = (Get-Date).ToString('HH:mm:ss')
            $line  = "[$stamp] batch $batchIndex OK  (+$BatchSize, total $sentRecords)"

            if ($Follow -and $followWorkspaceId) {
                $seen = 0
                try {
                    $q = if ($followColumn) {
                        "$destTable | where $followColumn has '$runId' | count"
                    } else {
                        "$destTable | where TimeGenerated > ago(30m) | count"
                    }
                    $qr   = Invoke-AzOperationalInsightsQuery -WorkspaceId $followWorkspaceId -Query $q -ErrorAction Stop
                    $seen = [int]($qr.Results | Select-Object -First 1).Count
                }
                catch {
                    Write-Verbose "Follow query failed: $($_.Exception.Message.Split([char]10)[0])"
                }
                $line += "  | arrived: $seen"
            }

            Write-PipelineMessage $line
        }
        else {
            $failBatches++
            $bodyText = if ($response.Content) { ([string]$response.Content).Split([char]10)[0] } else { '' }
            Write-PipelineMessage "batch $batchIndex FAILED: HTTP $($response.StatusCode) $bodyText" -Level Warning
        }

        # Skip the trailing sleep on the final batch.
        $moreToDo = (-not ($BatchCount -and $batchIndex -ge $BatchCount)) -and
                    (-not ($deadline -and [datetimeoffset]::UtcNow -ge $deadline))
        if ($moreToDo) {
            Start-Sleep -Seconds $IntervalSeconds
        }
    }
}
finally {
    Write-PipelineMessage '' -Level Info
    Write-PipelineMessage 'Summary' -Level Section
    Write-PipelineMessage "Batches sent : $batchIndex ($okBatches ok, $failBatches failed)"
    Write-PipelineMessage "Records sent : $sentRecords"
    Write-PipelineMessage "Run marker   : $runId"

    if ($Follow -and $followWorkspaceId -and $followColumn) {
        Write-PipelineMessage "Confirm with : $destTable | where $followColumn has '$runId'"
    }
    elseif ($sentRecords -gt 0) {
        Write-PipelineMessage "Confirm with : $destTable | where TimeGenerated > ago(1h)"
    }
}

#endregion

#region -- Verify arrival ------------------------------------------------------

# The per-batch "arrived" counts during streaming are almost always low:
# Logs Ingestion is asynchronous and rows surface a few minutes after the
# 204. The authoritative check is this post-run poll, which waits for the
# streamed rows (identified by the run marker) to appear, so the run ends
# with a real count instead of a misleading zero.

$arrived = $null

if ($Follow -and $followWorkspaceId -and $sentRecords -gt 0 -and $ArrivalTimeoutSeconds -gt 0) {
    Write-PipelineMessage ''
    Write-PipelineMessage 'Verifying arrival' -Level Section
    Write-PipelineMessage "Rows appear a few minutes after the 204. Polling up to ${ArrivalTimeoutSeconds}s for run $runId..."

    $arrivalQuery = if ($followColumn) {
        "$destTable | where $followColumn has '$runId' | count"
    }
    else {
        "$destTable | where TimeGenerated > ago(1h) | count"
    }

    $arrivalDeadline = [datetimeoffset]::UtcNow.AddSeconds($ArrivalTimeoutSeconds)

    while ($true) {
        try {
            $qr      = Invoke-AzOperationalInsightsQuery -WorkspaceId $followWorkspaceId -Query $arrivalQuery -ErrorAction Stop
            $arrived = [int](@($qr.Results)[0].Count)
            Write-PipelineMessage "  arrived $arrived / $sentRecords"
        }
        catch {
            Write-PipelineMessage "  query not ready yet ($($_.Exception.Message.Split([char]10)[0]))"
        }

        if ($null -ne $arrived -and $arrived -ge $sentRecords) { break }
        if ([datetimeoffset]::UtcNow.AddSeconds(20) -ge $arrivalDeadline) { break }
        Start-Sleep -Seconds 20
    }

    if ($null -ne $arrived -and $arrived -ge $sentRecords) {
        Write-PipelineMessage "All $sentRecords records arrived." -Level Success
    }
    elseif ($arrived) {
        Write-PipelineMessage "$arrived of $sentRecords arrived so far; the rest may still be within ingestion latency. Re-check: $arrivalQuery" -Level Warning
    }
    else {
        Write-PipelineMessage "No rows yet after ${ArrivalTimeoutSeconds}s. Ingestion can lag longer on a brand-new table; re-check: $arrivalQuery" -Level Warning
    }
}

#endregion

[pscustomobject] @{
    DcrName      = $DcrName
    Stream       = $stream
    Destination  = $destTable
    RunId        = $runId
    BatchesSent  = $batchIndex
    BatchesOk    = $okBatches
    BatchesFailed= $failBatches
    RecordsSent  = $sentRecords
    Arrived      = $arrived
}
