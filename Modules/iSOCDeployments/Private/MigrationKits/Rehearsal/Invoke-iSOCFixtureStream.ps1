#Requires -Version 7.6

<#
.SYNOPSIS
    Post batches of fixture records on an interval, as the legacy source in a cut-over test.

.DESCRIPTION
    Until -DurationSeconds or -BatchCount, or Ctrl-C; a batch that fails is a
    warning and the stream goes on.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Invoke-iSOCFixtureStream.ps1
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

function Invoke-iSOCFixtureStream {
    <#
    .SYNOPSIS
        Post batches of fixture records on an interval, as the legacy source
        in a cut-over test.

    .DESCRIPTION
        Each batch is new records, signed afresh, posted through the Data
        Collector API. The stream stops after -DurationSeconds or
        -BatchCount, whichever comes first, or at Ctrl-C when neither is
        given; the last batch is not followed by a wait. A batch that fails
        is a warning and the stream goes on, and it counts towards
        -BatchCount, so a stream whose posts all fail still ends. The caller
        asks ShouldProcess.

    .PARAMETER IngestUri
        The workspace's Data Collector endpoint.

    .PARAMETER WorkspaceId
        The workspace's customer id.

    .PARAMETER SharedKey
        The workspace's shared key.

    .PARAMETER LogType
        The table without _CL.

    .PARAMETER Table
        The table, for the messages.

    .PARAMETER RecordCount
        Records per batch.

    .PARAMETER IntervalSeconds
        Seconds between batches.

    .PARAMETER DurationSeconds
        Stop after this long.

    .PARAMETER BatchCount
        Stop after this many batches.

    .OUTPUTS
        [pscustomobject] BatchesSent (failed ones included), BatchesFailed
        and RecordsSent.

    .EXAMPLE
        Invoke-iSOCFixtureStream -IngestUri $uri -WorkspaceId $id -SharedKey $key -LogType SacMigrationTest -Table SacMigrationTest_CL -RecordCount 5 -IntervalSeconds 15 -BatchCount 10
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $IngestUri,

        [Parameter(Mandatory)]
        [string] $WorkspaceId,

        [Parameter(Mandatory)]
        [string] $SharedKey,

        [Parameter(Mandatory)]
        [string] $LogType,

        [Parameter(Mandatory)]
        [string] $Table,

        [Parameter(Mandatory)]
        [int] $RecordCount,

        [Parameter(Mandatory)]
        [int] $IntervalSeconds,

        [int] $DurationSeconds,

        [int] $BatchCount
    )

    $sent = 0
    $batchIndex = 0
    $failed = 0
    $deadline = if ($DurationSeconds) { [datetimeoffset]::UtcNow.AddSeconds($DurationSeconds) } else { $null }
    try {
        while ($true) {
            if ($deadline -and [datetimeoffset]::UtcNow -ge $deadline) { break }
            if ($BatchCount -and $batchIndex -ge $BatchCount) { break }

            $records = New-iSOCFixtureRecord -Count $RecordCount -ReferenceTime ([datetime]::UtcNow)
            $batchIndex++
            try {
                Send-iSOCDataCollectorBatch -IngestUri $IngestUri -WorkspaceId $WorkspaceId -SharedKey $SharedKey -LogType $LogType -Record $records
                $sent += $RecordCount
                Write-iSOCLog "[$((Get-Date).ToString('HH:mm:ss'))] legacy batch $batchIndex OK (+$RecordCount, total $sent)"
            } catch {
                $failed++
                Write-iSOCLog "legacy batch $batchIndex failed: $($_.Exception.Message.Split([char]10)[0])" -Level Warning
            }

            $moreToDo = (-not ($BatchCount -and $batchIndex -ge $BatchCount)) -and (-not ($deadline -and [datetimeoffset]::UtcNow -ge $deadline))
            if ($moreToDo) { Start-Sleep -Seconds $IntervalSeconds }
        }
    } finally {
        Write-iSOCLog "Streamed $sent records in $batchIndex batches to $Table." -Level Success
    }
    [pscustomobject]@{ BatchesSent = $batchIndex; BatchesFailed = $failed; RecordsSent = $sent }
}
