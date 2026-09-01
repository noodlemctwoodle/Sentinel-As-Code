#Requires -Version 7.2
#Requires -Modules Az.Accounts, Az.OperationalInsights

<#
.SYNOPSIS
    Creates a classic (MMA / Data Collector API) custom log table with
    synthetic data, for testing Invoke-ClassicTableMigration.ps1 end to end.

.DESCRIPTION
    A DCR-based migration is one-way, so it must never be rehearsed on a
    table anyone cares about. The only way to manufacture a genuine classic
    table is the HTTP Data Collector API: posting to it auto-creates a table
    whose tableSubType is 'Classic', with the '_s' / '_d' / '_b' / '_g'
    column-name suffixes that the API infers from each field's type. That is
    exactly the shape Invoke-ClassicTableMigration.ps1 has to cope with.

    This script:

      1. Fetches the workspace shared key through the authenticated Az
         session (Get-AzOperationalInsightsWorkspaceSharedKey). You never
         paste a key, and the key is never printed.
      2. Generates synthetic records with a deliberate mix of types so the
         resulting table exercises the type mapping in the migration script.
      3. Signs the request (HMAC-SHA256 over the documented string-to-hash)
         and posts it to the workspace ingestion endpoint.
      4. Polls the Tables API until the table appears, and reports its
         subtype so you can confirm it is 'Classic'.

    Use -Remove to delete a fixture table afterwards.

    The Data Collector API is retired on 2026-09-14. After that date this
    script can no longer create classic tables, because nothing can.

    IMPORTANT: only ever point this at a throwaway or dedicated test
    workspace. It writes real data and creates a real billable table.

.PARAMETER ResourceGroupName
    Resource group containing the Log Analytics workspace.

.PARAMETER WorkspaceName
    Log Analytics workspace name. Use a test workspace.

.PARAMETER TableName
    Custom log type to create, for example 'SacMigrationTest'. The Data
    Collector API appends the '_CL' suffix, so 'SacMigrationTest' becomes
    the table 'SacMigrationTest_CL'. Passing the suffix is tolerated and
    stripped before sending.

.PARAMETER RecordCount
    Number of synthetic records to post. Defaults to 50.

.PARAMETER SubscriptionId
    Subscription to operate in. Defaults to the current Az context.

.PARAMETER OdsEndpointSuffix
    Ingestion endpoint suffix for the Data Collector API. Defaults to the
    public cloud value 'ods.opinsights.azure.com'. For Azure Government use
    'ods.opinsights.azure.us'.

.PARAMETER TimeoutSeconds
    How long to wait for the table to appear via the Tables API before
    giving up the poll. Defaults to 300. The table resource usually appears
    within a few minutes; data becomes queryable separately and can take
    longer on first ingestion. Only used by the one-shot seed.

.PARAMETER Stream
    Keep posting batches on an interval instead of seeding once, to act as
    the legacy source in a cutover test while you migrate the table and
    start the new DCR path. Each batch is signed afresh, as the Data
    Collector signature is time-dependent. RecordCount is the batch size in
    this mode. Does not poll for the table.

.PARAMETER IntervalSeconds
    Seconds between batches when -Stream is set. Defaults to 10.

.PARAMETER DurationSeconds
    Stop streaming after this many seconds. Omit for no time limit.

.PARAMETER BatchCount
    Stop streaming after this many batches. Omit for no batch limit. With
    neither -DurationSeconds nor -BatchCount, streaming runs until Ctrl-C.

.PARAMETER Remove
    Delete the fixture table instead of creating it. Irreversible for that
    table, so it runs behind ShouldProcess. A table that is still Classic
    cannot be deleted through the Tables API; without -MigrateBeforeRemove
    the script reports that and stops rather than throwing a raw ARM error.

.PARAMETER MigrateBeforeRemove
    Used with -Remove. If the table is still Classic, migrate it to
    DCR-based (one-way) so it becomes deletable, then delete it. Only needed
    when cleaning up a table that was never migrated; a table that has
    already been migrated deletes without this switch.

.EXAMPLE
    ./Tools/ClassicToDcr/Rehearsal/New-ClassicTableFixture.ps1 -ResourceGroupName rg-scratch `
        -WorkspaceName law-scratch -TableName SacMigrationTest

    Creates SacMigrationTest_CL with 50 synthetic records and waits for the
    table to appear, reporting its subtype.

.EXAMPLE
    ./Tools/ClassicToDcr/Rehearsal/New-ClassicTableFixture.ps1 -ResourceGroupName rg-scratch `
        -WorkspaceName law-scratch -TableName SacMigrationTest -Stream `
        -RecordCount 5 -IntervalSeconds 15

    Streams five records every fifteen seconds via the legacy Data Collector
    API. Run this as the legacy source during a cutover test while you
    migrate the table and start the new DCR path with Test-DcrIngestion.ps1.

.EXAMPLE
    ./Tools/ClassicToDcr/Rehearsal/New-ClassicTableFixture.ps1 -ResourceGroupName rg-scratch `
        -WorkspaceName law-scratch -TableName SacMigrationTest -Remove

    Deletes the fixture table.

.NOTES
    File:         Tools/ClassicToDcr/Rehearsal/New-ClassicTableFixture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Created:      2026-07-23
    Version:      1.0.1
    Last Updated: 2026-09-01
    Website:      https://sentinel.blog
    Requires:     PowerShell 7.2+, Az.Accounts, Az.OperationalInsights

    Runs standalone. Nothing from this repository needs to be alongside it.

    Required RBAC:
      - Log Analytics Contributor on the workspace (read shared keys,
        delete the table)

    Reference:
      https://learn.microsoft.com/azure/azure-monitor/logs/data-collector-api
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string] $ResourceGroupName

  , [Parameter(Mandatory)]
    [string] $WorkspaceName

  , [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9_]+$')]
    [string] $TableName

  , [Parameter()]
    [ValidateRange(1, 10000)]
    [int] $RecordCount = 50

  , [Parameter()]
    [string] $SubscriptionId

  , [Parameter()]
    [string] $OdsEndpointSuffix = 'ods.opinsights.azure.com'

  , [Parameter()]
    [ValidateRange(30, 1800)]
    [int] $TimeoutSeconds = 300

  , [Parameter()]
    [switch] $Stream

  , [Parameter()]
    [ValidateRange(1, 3600)]
    [int] $IntervalSeconds = 10

  , [Parameter()]
    [int] $DurationSeconds

  , [Parameter()]
    [int] $BatchCount

  , [Parameter()]
    [switch] $Remove

  , [Parameter()]
    [switch] $MigrateBeforeRemove
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

$script:TablesApiVersion        = '2023-09-01'
$script:DataCollectorApiVersion = '2016-04-01'

#endregion

#region -- Helpers -------------------------------------------------------------

function New-DataCollectorSignature {
    <#
    .SYNOPSIS
        Builds the SharedKey Authorization header value for the Data
        Collector API.

    .DESCRIPTION
        Signs the documented string-to-hash with HMAC-SHA256 using the
        base64-decoded workspace shared key.

        ContentLength must be the UTF-8 BYTE length of the request body, not
        its character length. Passing the character length is the classic
        cause of a 403 signature mismatch on any body containing multi-byte
        characters, so the caller computes it from the encoded bytes and the
        two must agree.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure function: computes a signature string, changes no state.')]
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $WorkspaceId
      , [Parameter(Mandatory)] [string] $SharedKey
      , [Parameter(Mandatory)] [int]    $ContentLength
      , [Parameter(Mandatory)] [string] $Rfc1123Date
      , [Parameter()]          [string] $Method      = 'POST'
      , [Parameter()]          [string] $ContentType = 'application/json'
      , [Parameter()]          [string] $Resource    = '/api/logs'
    )

    $xHeaders     = "x-ms-date:$Rfc1123Date"
    $stringToHash = "$Method`n$ContentLength`n$ContentType`n$xHeaders`n$Resource"

    $bytesToHash = [System.Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes    = [System.Convert]::FromBase64String($SharedKey)

    $hmac = [System.Security.Cryptography.HMACSHA256]::new($keyBytes)
    try {
        $hash    = $hmac.ComputeHash($bytesToHash)
        $encoded = [System.Convert]::ToBase64String($hash)
    }
    finally {
        $hmac.Dispose()
    }

    return "SharedKey ${WorkspaceId}:${encoded}"
}

function New-FixtureRecord {
    <#
    .SYNOPSIS
        Generates synthetic records with a mix of field types.

    .DESCRIPTION
        The Data Collector API infers a column type per field and appends a
        suffix: string -> _s, double -> _d, boolean -> _b, GUID-shaped
        string -> _g. A clean datetime field nominated as the
        time-generated-field lands as TimeGenerated. The mix here is chosen
        so the resulting classic table gives the migration script real
        _s / _d / _b / _g columns plus a clean TimeGenerated to map.

    .PARAMETER Count
        Number of records to generate.

    .PARAMETER ReferenceTime
        UTC base time. Records are spread backwards from it. Injected so the
        generator is deterministic under test.

    .PARAMETER SeedGuid
        Fixed GUID string used for the GUID-typed field under test. Defaults
        to a fresh GUID per record at runtime.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure function: builds in-memory records, changes no state.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[hashtable]])]
    param (
        [Parameter(Mandatory)] [int]      $Count
      , [Parameter(Mandatory)] [datetime] $ReferenceTime
      , [Parameter()]          [string]   $SeedGuid
    )

    $hosts     = 'web-01', 'web-02', 'db-01', 'app-01'
    $severities= 'Information', 'Warning', 'Error'
    $records   = [System.Collections.Generic.List[hashtable]]::new()

    for ($i = 0; $i -lt $Count; $i++) {
        $guid = if ($SeedGuid) { $SeedGuid } else { [guid]::NewGuid().ToString() }

        $records.Add(@{
            # Nominated as time-generated-field, becomes TimeGenerated.
            Timestamp   = $ReferenceTime.AddSeconds(-1 * $i).ToString('o')
            # string  -> _s
            SourceHost  = $hosts[$i % $hosts.Count]
            SourceIp    = "10.0.$($i % 255).$((($i * 7) % 255))"
            Severity    = $severities[$i % $severities.Count]
            Message     = "Synthetic fixture record $i for classic-table migration testing."
            # double  -> _d
            DurationMs  = [math]::Round((($i * 13.7) % 900) + 1.5, 2)
            # boolean -> _b
            Success     = (($i % 5) -ne 0)
            # GUID    -> _g
            EventId     = $guid
        })
    }

    return $records
}

function Send-DataCollectorBatch {
    <#
    .SYNOPSIS
        Signs and posts one batch to the HTTP Data Collector API.

    .DESCRIPTION
        Every call recomputes the signature. The x-ms-date and content
        length are part of the signed string, so a streaming loop cannot
        reuse a signature between batches: doing so returns 403. Isolating
        the sign-and-send here keeps the one-shot and streaming paths
        identical and correct.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]   $IngestUri
      , [Parameter(Mandatory)] [string]   $WorkspaceId
      , [Parameter(Mandatory)] [string]   $SharedKey
      , [Parameter(Mandatory)] [string]   $LogType
      , [Parameter(Mandatory)] [object[]] $Record
      , [Parameter()]          [string]   $TimeField = 'Timestamp'
    )

    $body      = ConvertTo-Json -InputObject @($Record) -Depth 5
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $rfc1123   = [datetime]::UtcNow.ToString('r')

    $signature = New-DataCollectorSignature -WorkspaceId $WorkspaceId -SharedKey $SharedKey `
                                            -ContentLength $bodyBytes.Length -Rfc1123Date $rfc1123

    $headers = @{
        'Authorization'        = $signature
        'Log-Type'             = $LogType
        'x-ms-date'            = $rfc1123
        'time-generated-field' = $TimeField
    }

    Invoke-RestMethod -Uri $IngestUri -Method Post -ContentType 'application/json' `
                      -Headers $headers -Body $bodyBytes | Out-Null
}

function Invoke-ArmRequest {
    <#
    .SYNOPSIS
        Invoke-AzRestMethod wrapper that routes relative paths to -Path and
        absolute URLs to -Uri, so sovereign clouds work without a hardcoded
        host. Matches Invoke-ClassicTableMigration.ps1.
    #>
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

#endregion

#region -- Context -------------------------------------------------------------

Write-PipelineMessage 'Classic table fixture' -Level Section

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

# The Data Collector API always appends _CL, so strip it from the log type.
$logType = $TableName -replace '_CL$', ''
$table   = "${logType}_CL"

$workspace   = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName
$workspaceId = $workspace.CustomerId

$tableUri = "/subscriptions/$resolvedSubscriptionId/resourceGroups/$ResourceGroupName" +
            "/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName" +
            "/tables/$table" + "?api-version=$script:TablesApiVersion"

Write-PipelineMessage "Subscription : $resolvedSubscriptionId"
Write-PipelineMessage "Workspace    : $WorkspaceName"
Write-PipelineMessage "Table        : $table"

#endregion

#region -- Remove --------------------------------------------------------------

if ($Remove) {
    Write-PipelineMessage 'Removing fixture table' -Level Section

    # The Tables API cannot delete a Classic table: a DELETE returns a raw
    # HTTP 400 ("Changing Classic table ... by using DataCollectionRuleBased
    # tables api is forbidden"). Read the subtype first and handle it, rather
    # than letting that confusing error surface.
    $existing = Invoke-AzRestMethod -Path $tableUri -Method GET

    if ($existing.StatusCode -eq 404) {
        Write-PipelineMessage "$table does not exist (already removed)." -Level Success
        return
    }
    if ($existing.StatusCode -ne 200) {
        throw "Could not read $table before removal: HTTP $($existing.StatusCode) $($existing.Content)"
    }

    $detail   = $existing.Content | ConvertFrom-Json
    $subProp  = $detail.properties.schema.PSObject.Properties['tableSubType']
    $subType  = if ($subProp -and $subProp.Value) { [string]$subProp.Value } else { 'Unknown' }

    if ($subType -eq 'Classic') {
        if (-not $MigrateBeforeRemove) {
            Write-PipelineMessage "$table is still a Classic table, which the Tables API cannot delete." -Level Warning
            Write-PipelineMessage 'Re-run with -MigrateBeforeRemove to migrate it (one-way) and then delete, or delete it in the Azure portal.' -Level Warning
            return
        }

        if ($PSCmdlet.ShouldProcess("$WorkspaceName/$table", 'Migrate (irreversible) then delete')) {
            Write-PipelineMessage 'Migrating the Classic table so it becomes deletable. This is one-way.' -Level Warning
            Invoke-AzOperationalInsightsMigrateTable -ResourceGroupName $ResourceGroupName `
                                                     -WorkspaceName $WorkspaceName `
                                                     -TableName $table -Confirm:$false | Out-Null
        }
        else {
            return
        }
    }

    if ($PSCmdlet.ShouldProcess("$WorkspaceName/$table", 'Delete fixture table')) {
        Invoke-ArmRequest -Uri $tableUri -Method DELETE -SuccessCodes @(200, 202, 204) | Out-Null
        Write-PipelineMessage "Deleted $table." -Level Success
    }

    return
}

#endregion

#region -- Post data -----------------------------------------------------------

Write-PipelineMessage 'Generating and posting synthetic data' -Level Section

# The shared key is fetched through the authenticated Az session and kept in
# memory only. It is never written to output or logs.
$keys      = Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $ResourceGroupName -Name $WorkspaceName
$sharedKey = $keys.PrimarySharedKey

if ([string]::IsNullOrWhiteSpace($sharedKey)) {
    throw 'Could not retrieve the workspace primary shared key. Confirm you have Log Analytics Contributor on the workspace.'
}

$ingestUri = "https://$workspaceId.$OdsEndpointSuffix/api/logs?api-version=$script:DataCollectorApiVersion"

if ($Stream) {
    # ---- streaming (legacy cutover source) --------------------------------
    $limitText = @()
    if ($DurationSeconds) { $limitText += "$DurationSeconds s" }
    if ($BatchCount)      { $limitText += "$BatchCount batches" }
    if ($limitText.Count -eq 0) { $limitText = @('until Ctrl-C') }

    Write-PipelineMessage "Streaming    : $RecordCount records every ${IntervalSeconds}s ($($limitText -join ', '))"

    if (-not $PSCmdlet.ShouldProcess("$WorkspaceName/$table", "Stream via Data Collector API ($($limitText -join ', '))")) {
        Write-PipelineMessage 'Skipped streaming (WhatIf).' -Level Warning
        return
    }

    $sent      = 0
    $batchIndex= 0
    $deadline  = if ($DurationSeconds) { [datetimeoffset]::UtcNow.AddSeconds($DurationSeconds) } else { $null }

    try {
        while ($true) {
            if ($deadline -and [datetimeoffset]::UtcNow -ge $deadline) { break }
            if ($BatchCount -and $batchIndex -ge $BatchCount)          { break }

            $records = New-FixtureRecord -Count $RecordCount -ReferenceTime ([datetime]::UtcNow)
            try {
                Send-DataCollectorBatch -IngestUri $ingestUri -WorkspaceId $workspaceId `
                                        -SharedKey $sharedKey -LogType $logType -Record $records
                $sent += $RecordCount
                $batchIndex++
                Write-PipelineMessage "[$((Get-Date).ToString('HH:mm:ss'))] legacy batch $batchIndex OK (+$RecordCount, total $sent)"
            }
            catch {
                Write-PipelineMessage "legacy batch failed: $($_.Exception.Message.Split([char]10)[0])" -Level Warning
            }

            $moreToDo = (-not ($BatchCount -and $batchIndex -ge $BatchCount)) -and
                        (-not ($deadline -and [datetimeoffset]::UtcNow -ge $deadline))
            if ($moreToDo) { Start-Sleep -Seconds $IntervalSeconds }
        }
    }
    finally {
        Write-PipelineMessage "Streamed $sent records in $batchIndex batches to $table." -Level Success
    }

    return
}

# ---- one-shot seed --------------------------------------------------------
Write-PipelineMessage "Records      : $RecordCount"

if ($PSCmdlet.ShouldProcess("$WorkspaceName/$table", "Post $RecordCount records via Data Collector API")) {
    $records = New-FixtureRecord -Count $RecordCount -ReferenceTime ([datetime]::UtcNow)
    Send-DataCollectorBatch -IngestUri $ingestUri -WorkspaceId $workspaceId `
                            -SharedKey $sharedKey -LogType $logType -Record $records

    Write-PipelineMessage "Posted $RecordCount records to $table." -Level Success
}
else {
    Write-PipelineMessage 'Skipped posting (WhatIf). No table poll will run.' -Level Warning
    return
}

#endregion

#region -- Wait for the table --------------------------------------------------

Write-PipelineMessage 'Waiting for the table to appear' -Level Section
Write-PipelineMessage 'The table resource usually appears within a few minutes. Data becomes queryable separately and can take longer on first ingestion.'

$deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
$subType  = $null

while ([datetime]::UtcNow -lt $deadline) {
    try {
        $response = Invoke-ArmRequest -Uri $tableUri -Method GET -SuccessCodes @(200)
        $detail   = $response.Content | ConvertFrom-Json

        $subTypeProp = $detail.properties.schema.PSObject.Properties['tableSubType']
        if ($subTypeProp -and $subTypeProp.Value) {
            $subType = [string]$subTypeProp.Value
            break
        }
    }
    catch {
        # 404 until the table materialises; keep polling.
        Write-Verbose "Table not present yet: $($_.Exception.Message.Split([char]10)[0])"
    }

    Start-Sleep -Seconds 15
}

if ($subType) {
    Write-PipelineMessage "Table $table is present. tableSubType = $subType." -Level Success

    if ($subType -ne 'Classic') {
        Write-PipelineMessage "Expected 'Classic' but got '$subType'. The Data Collector API should have produced a classic table." -Level Warning
    }
    else {
        Write-PipelineMessage 'Ready. Point Invoke-ClassicTableMigration.ps1 at this table to test the migration.' -Level Success
    }
}
else {
    Write-PipelineMessage "Table did not appear within $TimeoutSeconds seconds. First-time creation can be slow; re-check with Invoke-ClassicTableMigration.ps1 -ListOnly shortly." -Level Warning
}

[pscustomobject] @{
    TableName    = $table
    LogType      = $logType
    RecordCount  = $RecordCount
    SubType      = $subType
    WorkspaceId  = $workspaceId
}

#endregion
