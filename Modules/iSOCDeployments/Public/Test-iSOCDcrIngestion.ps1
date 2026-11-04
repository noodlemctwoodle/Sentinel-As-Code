#Requires -Version 7.2

<#
.SYNOPSIS
    Stream synthetic records into a data collection rule as a service principal, and see them arrive.

.DESCRIPTION
    Test-iSOCDcrIngestion replaces
    Tools/ClassicToDcr/Rehearsal/Test-DcrIngestion.ps1.

.NOTES
    File:         Modules/iSOCDeployments/Public/Test-iSOCDcrIngestion.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-iSOCDcrIngestion {
    <#
    .SYNOPSIS
        Stream synthetic records into a data collection rule as a service
        principal, and see them arrive.

    .DESCRIPTION
        The last step of rehearsing a migration: proving data sent to the
        rule's logs ingestion endpoint lands in the table. The rule is read
        through the Az sign-in for its immutable id, endpoint, stream
        declaration (so the records match the schema) and destination; the
        records are then posted through the Logs Ingestion API in batches on
        an interval, as a service principal by the client-credentials flow,
        which needs Monitoring Metrics Publisher on the rule
        (-GrantIngestionRole assigns it). A 204 is the main signal: the
        token, the endpoint and the schema are right. With -Follow each
        batch reports the rows that have arrived, and after the stream the
        command waits for the run's rows to land.

        The tenant, client id and secret come from the parameters, else the
        environment (DCR_INGEST_TENANT_ID or AZURE_TENANT_ID,
        DCR_INGEST_CLIENT_ID or AZURE_CLIENT_ID, DCR_INGEST_CLIENT_SECRET or
        AZURE_CLIENT_SECRET), else a .env file, which keeps the secret out
        of the shell history; the environment is never changed. The secret
        is held in memory only and never shown, and no token is requested
        under -WhatIf.

    .PARAMETER DcrName
        The rule.

    .PARAMETER DcrResourceGroupName
        Its resource group.

    .PARAMETER TenantId
        The sending service principal's tenant.

    .PARAMETER ClientId
        Its application (client) id.

    .PARAMETER ClientSecret
        Its secret, as a SecureString.

    .PARAMETER EnvFile
        A dotenv file of KEY=VALUE lines read for the settings. Defaults to
        the file .env in the current folder; one that does not exist is
        ignored. Keep it out of source control.

    .PARAMETER StreamName
        The stream, for example Custom-MyApp_CL; needed only when the rule
        declares several.

    .PARAMETER BatchSize
        Records per post, 1 to 1000. Default 10; keep the body under 1 MB.

    .PARAMETER IntervalSeconds
        Seconds between batches, 1 to 3600. Default 5.

    .PARAMETER DurationSeconds
        Stop after this long.

    .PARAMETER BatchCount
        Stop after this many batches. With neither this nor
        -DurationSeconds, the stream runs until Ctrl-C.

    .PARAMETER Follow
        Count the run's rows in the destination table as they arrive, and
        wait for them after the stream.

    .PARAMETER ArrivalTimeoutSeconds
        How long -Follow waits after the stream, 0 to 1800. Default 300.

    .PARAMETER GrantIngestionRole
        Give the service principal Monitoring Metrics Publisher on the rule
        when it does not have it.

    .PARAMETER AuthorityHost
        The Entra authority host. Defaults to the Az sign-in's cloud's.

    .PARAMETER IngestionAudience
        The Logs Ingestion API's token audience. Defaults to the Az
        sign-in's cloud's.

    .PARAMETER Context
        The workspace, from Connect-iSOCWorkspace. Defaults to the
        connected one; the rule is read in its subscription.

    .OUTPUTS
        [pscustomobject] DcrName, Stream, Destination, RunId, BatchesSent,
        BatchesOk, BatchesFailed, RecordsSent and Arrived. Nothing under
        -WhatIf.

    .EXAMPLE
        $env:DCR_INGEST_CLIENT_SECRET = '<secret>'
        Test-iSOCDcrIngestion -DcrName dcr-myapp -DcrResourceGroupName rg-scratch -TenantId $tid -ClientId $appId -Follow

        Streams 10 records every 5 seconds into the rule's stream until
        Ctrl-C, reporting arrivals.

    .EXAMPLE
        Test-iSOCDcrIngestion -DcrName dcr-myapp -DcrResourceGroupName rg-scratch -BatchCount 3 -BatchSize 5

        Sends three batches of five records, with the service principal's
        settings from .env.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $DcrName,

        [Parameter(Mandatory)]
        [string] $DcrResourceGroupName,

        [string] $TenantId,

        [string] $ClientId,

        [securestring] $ClientSecret,

        [string] $EnvFile = '.env',

        [string] $StreamName,

        [ValidateRange(1, 1000)]
        [int] $BatchSize = 10,

        [ValidateRange(1, 3600)]
        [int] $IntervalSeconds = 5,

        [int] $DurationSeconds,

        [int] $BatchCount,

        [switch] $Follow,

        [ValidateRange(0, 1800)]
        [int] $ArrivalTimeoutSeconds = 300,

        [switch] $GrantIngestionRole,

        [string] $AuthorityHost,

        [string] $IngestionAudience,

        [psobject] $Context
    )

    $ctx = Resolve-iSOCContext -Context $Context
    $steps = @('Connect')
    if ($Follow) { $steps += 'Migrate' }
    Assert-iSOCPrerequisite -Step $steps
    Write-iSOCLog 'DCR ingestion stream test' -Level Section

    if (-not $AuthorityHost) {
        $AuthorityHost = switch ($ctx.Environment) { 'AzureUSGovernment' { 'https://login.microsoftonline.us' } 'AzureChinaCloud' { 'https://login.chinacloudapi.cn' } default { 'https://login.microsoftonline.com' } }
    }
    if (-not $IngestionAudience) {
        $IngestionAudience = switch ($ctx.Environment) { 'AzureUSGovernment' { 'https://monitor.azure.us' } 'AzureChinaCloud' { 'https://monitor.azure.cn' } default { 'https://monitor.azure.com' } }
    }

    $envPath = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path (Get-Location).Path $EnvFile }
    $fromFile = Import-iSOCDotEnv -Path $envPath
    if ($fromFile.Count -gt 0) { Write-iSOCLog "Loaded $($fromFile.Count) setting(s) from $envPath" }

    $TenantId = Resolve-iSOCSetting -Explicit $TenantId -EnvName 'DCR_INGEST_TENANT_ID', 'AZURE_TENANT_ID' -File $fromFile
    $ClientId = Resolve-iSOCSetting -Explicit $ClientId -EnvName 'DCR_INGEST_CLIENT_ID', 'AZURE_CLIENT_ID' -File $fromFile
    if (-not $TenantId) { throw 'No tenant ID. Pass -TenantId, or set DCR_INGEST_TENANT_ID / AZURE_TENANT_ID (e.g. in .env).' }
    if (-not $ClientId) { throw 'No client ID. Pass -ClientId, or set DCR_INGEST_CLIENT_ID / AZURE_CLIENT_ID (e.g. in .env).' }
    if (-not $ClientSecret) {
        $secretPlain = Resolve-iSOCSetting -EnvName 'DCR_INGEST_CLIENT_SECRET', 'AZURE_CLIENT_SECRET' -File $fromFile
        if (-not $secretPlain) { throw 'No client secret. Pass -ClientSecret (SecureString), or set DCR_INGEST_CLIENT_SECRET / AZURE_CLIENT_SECRET (e.g. in .env).' }
        $ClientSecret = ConvertTo-iSOCSecureString -Plain $secretPlain
    }

    Write-iSOCLog 'Resolving the DCR' -Level Section
    $dcrResourceId = "/subscriptions/$($ctx.SubscriptionId)/resourceGroups/$DcrResourceGroupName/providers/Microsoft.Insights/dataCollectionRules/$DcrName"
    $dcr = Invoke-iSOCRestRequest -Method GET -Path $dcrResourceId -ApiVersion (Get-iSOCApiVersion DataCollectionRules) -Context $ctx
    $target = Get-iSOCDcrIngestionTarget -Dcr $dcr
    $stream = Get-iSOCDcrStreamName -Dcr $dcr -Requested $StreamName
    $columns = @(Get-iSOCDcrStreamColumn -Dcr $dcr -Stream $stream)
    $destTable = Get-iSOCDcrDestinationTable -Dcr $dcr -Stream $stream
    $ingestUri = '{0}/dataCollectionRules/{1}/streams/{2}?api-version=2023-01-01' -f $target.Endpoint.TrimEnd('/'), $target.ImmutableId, $stream
    Write-iSOCLog "DCR          : $DcrName"
    Write-iSOCLog "Immutable ID : $($target.ImmutableId)"
    Write-iSOCLog "Endpoint     : $($target.Endpoint)"
    Write-iSOCLog "Stream       : $stream ($($columns.Count) columns)"
    Write-iSOCLog "Destination  : $destTable"

    Write-iSOCLog 'Checking the service principal' -Level Section
    Confirm-iSOCIngestionRole -Context $ctx -ClientId $ClientId -DcrId $dcrResourceId -DcrName $DcrName -Grant:$GrantIngestionRole | Out-Null

    $followTarget = [pscustomobject]@{ WorkspaceId = $null; Column = $null }
    if ($Follow) {
        $followTarget = Get-iSOCDcrFollowTarget -Context $ctx -Dcr $dcr -StreamColumn $columns
        if (-not $followTarget.WorkspaceId) { Write-iSOCLog 'Could not resolve the destination workspace for -Follow. Arrival counts will be skipped.' -Level Warning }
    }

    Write-iSOCLog 'Streaming' -Level Section
    $runId = ([guid]::NewGuid()).ToString('N').Substring(0, 12)
    $limitText = @()
    if ($DurationSeconds) { $limitText += "$DurationSeconds s" }
    if ($BatchCount) { $limitText += "$BatchCount batches" }
    if ($limitText.Count -eq 0) { $limitText = @('until Ctrl-C') }
    Write-iSOCLog "Run marker   : $runId"
    Write-iSOCLog "Cadence      : $BatchSize records every ${IntervalSeconds}s"
    Write-iSOCLog "Runs for     : $($limitText -join ', ')"

    if (-not $PSCmdlet.ShouldProcess($ingestUri, "Stream records ($($limitText -join ', '))")) {
        Write-iSOCLog 'WhatIf: no data sent.' -Level Warning
        return
    }

    $sent = Invoke-iSOCIngestionStream -IngestUri $ingestUri -StreamColumn $columns -RunId $runId -BatchSize $BatchSize -IntervalSeconds $IntervalSeconds `
        -DurationSeconds $DurationSeconds -BatchCount $BatchCount -Destination $destTable -FollowWorkspaceId $followTarget.WorkspaceId -FollowColumn $followTarget.Column `
        -TokenRequest @{ AuthorityHost = $AuthorityHost; TenantId = $TenantId; ClientId = $ClientId; Audience = $IngestionAudience; ClientSecret = $ClientSecret }

    $arrived = $null
    if ($Follow -and $followTarget.WorkspaceId -and $sent.RecordsSent -gt 0 -and $ArrivalTimeoutSeconds -gt 0) {
        $query = if ($followTarget.Column) { "$destTable | where $($followTarget.Column) has '$runId' | count" } else { "$destTable | where TimeGenerated > ago(1h) | count" }
        $arrived = Wait-iSOCIngestionArrival -WorkspaceId $followTarget.WorkspaceId -Query $query -Sent $sent.RecordsSent -TimeoutSeconds $ArrivalTimeoutSeconds
    }

    [pscustomobject]@{
        DcrName       = $DcrName
        Stream        = $stream
        Destination   = $destTable
        RunId         = $runId
        BatchesSent   = $sent.BatchesSent
        BatchesOk     = $sent.BatchesOk
        BatchesFailed = $sent.BatchesFailed
        RecordsSent   = $sent.RecordsSent
        Arrived       = $arrived
    }
}
