#Requires -Version 7.6

<#
.SYNOPSIS
    Post batches of synthetic records to a rule's stream, as a service principal.

.DESCRIPTION
    Until -DurationSeconds or -BatchCount, or Ctrl-C, refreshing the token
    before it expires; with -Follow each batch reports the rows that have
    arrived.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Invoke-iSOCIngestionStream.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCIngestionStream {
    <#
    .SYNOPSIS
        Post batches of synthetic records to a rule's stream, as a service
        principal.

    .DESCRIPTION
        Each batch is -BatchSize records matching the stream's columns
        (New-iSOCStreamRecord), posted as JSON to the Logs Ingestion API with
        the service principal's token, which is renewed two minutes before it
        expires. A 200 or 204 counts the batch sent; anything else is a
        warning with the status, and the stream goes on. With a follow
        workspace each sent batch reports how many of the run's rows have
        arrived (ingestion lags, so the counts start low). The stream stops
        after -DurationSeconds or -BatchCount, or at Ctrl-C, and logs a
        summary whatever ends it. The caller asks ShouldProcess.

    .PARAMETER IngestUri
        The stream's ingestion URL.

    .PARAMETER TokenRequest
        AuthorityHost, TenantId, ClientId, Audience and ClientSecret, for
        Get-iSOCServicePrincipalToken.

    .PARAMETER StreamColumn
        The stream's columns.

    .PARAMETER RunId
        The run marker.

    .PARAMETER BatchSize
        Records per post.

    .PARAMETER IntervalSeconds
        Seconds between batches.

    .PARAMETER DurationSeconds
        Stop after this long.

    .PARAMETER BatchCount
        Stop after this many batches.

    .PARAMETER Destination
        The destination table.

    .PARAMETER FollowWorkspaceId
        The destination workspace's customer id, to count arrivals in.

    .PARAMETER FollowColumn
        The string column that carries the run marker.

    .OUTPUTS
        [pscustomobject] BatchesSent, BatchesOk, BatchesFailed and
        RecordsSent.

    .EXAMPLE
        Invoke-iSOCIngestionStream -IngestUri $uri -TokenRequest $tokenRequest -StreamColumn $columns -RunId $runId -BatchSize 10 -IntervalSeconds 5 -BatchCount 3 -Destination MyApp_CL
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $IngestUri,

        [Parameter(Mandatory)]
        [hashtable] $TokenRequest,

        [Parameter(Mandatory)]
        [object[]] $StreamColumn,

        [Parameter(Mandatory)]
        [string] $RunId,

        [Parameter(Mandatory)]
        [int] $BatchSize,

        [Parameter(Mandatory)]
        [int] $IntervalSeconds,

        [int] $DurationSeconds,

        [int] $BatchCount,

        [Parameter(Mandatory)]
        [string] $Destination,

        [string] $FollowWorkspaceId,

        [string] $FollowColumn
    )

    $sentRecords = 0
    $okBatches = 0
    $failBatches = 0
    $batchIndex = 0
    $deadline = if ($DurationSeconds) { [datetimeoffset]::UtcNow.AddSeconds($DurationSeconds) } else { $null }

    $token = Get-iSOCServicePrincipalToken @TokenRequest
    try {
        while ($true) {
            if ($deadline -and [datetimeoffset]::UtcNow -ge $deadline) { break }
            if ($BatchCount -and $batchIndex -ge $BatchCount) { break }

            if ([datetimeoffset]::UtcNow -ge $token.ExpiresOn.AddSeconds(-120)) { $token = Get-iSOCServicePrincipalToken @TokenRequest }

            $now = [datetime]::UtcNow
            $batch = for ($i = 0; $i -lt $BatchSize; $i++) {
                New-iSOCStreamRecord -StreamColumn $StreamColumn -Index (($batchIndex * $BatchSize) + $i) -RunId $RunId -ReferenceTime $now
            }
            $body = ConvertTo-Json -InputObject @($batch) -Depth 10
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            $response = Invoke-iSOCHttpRequest -Method POST -Uri $IngestUri -Headers @{ Authorization = "Bearer $($token.AccessToken)" } -Body $bodyBytes -ContentType 'application/json'
            $batchIndex++

            if ($response.StatusCode -in 200, 204) {
                $sentRecords += $BatchSize
                $okBatches++
                $line = "[$((Get-Date).ToString('HH:mm:ss'))] batch $batchIndex OK  (+$BatchSize, total $sentRecords)"
                if ($FollowWorkspaceId) {
                    $seen = 0
                    try {
                        $q = if ($FollowColumn) { "$Destination | where $FollowColumn has '$RunId' | count" } else { "$Destination | where TimeGenerated > ago(30m) | count" }
                        $qr = Invoke-iSOCAzLogQuery -WorkspaceId $FollowWorkspaceId -Query $q
                        $rows = Get-iSOCPropertyValue -InputObject $qr -Path 'Results'
                        $seen = [int](@($rows) | Select-Object -First 1).Count
                    } catch {
                        Write-iSOCLog "Follow query failed: $($_.Exception.Message.Split([char]10)[0])" -Level Debug
                    }
                    $line += "  | arrived: $seen"
                }
                Write-iSOCLog $line
            } else {
                $failBatches++
                $bodyText = if ($response.Content) { ([string]$response.Content).Split([char]10)[0] } else { '' }
                Write-iSOCLog "batch $batchIndex FAILED: HTTP $($response.StatusCode) $bodyText" -Level Warning
            }

            $moreToDo = (-not ($BatchCount -and $batchIndex -ge $BatchCount)) -and (-not ($deadline -and [datetimeoffset]::UtcNow -ge $deadline))
            if ($moreToDo) { Start-Sleep -Seconds $IntervalSeconds }
        }
    } finally {
        Write-iSOCLog ''
        Write-iSOCLog 'Summary' -Level Section
        Write-iSOCLog "Batches sent : $batchIndex ($okBatches ok, $failBatches failed)"
        Write-iSOCLog "Records sent : $sentRecords"
        Write-iSOCLog "Run marker   : $RunId"
        if ($FollowWorkspaceId -and $FollowColumn) { Write-iSOCLog "Confirm with : $Destination | where $FollowColumn has '$RunId'" }
        elseif ($sentRecords -gt 0) { Write-iSOCLog "Confirm with : $Destination | where TimeGenerated > ago(1h)" }
    }
    [pscustomobject]@{ BatchesSent = $batchIndex; BatchesOk = $okBatches; BatchesFailed = $failBatches; RecordsSent = $sentRecords }
}
