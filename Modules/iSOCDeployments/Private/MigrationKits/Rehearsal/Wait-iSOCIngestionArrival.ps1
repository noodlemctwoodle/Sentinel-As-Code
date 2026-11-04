#Requires -Version 7.2

<#
.SYNOPSIS
    Wait for a run's rows to arrive in the destination table, and count them.

.DESCRIPTION
    Polls every 20 seconds until every row sent is there or the timeout
    passes; Logs Ingestion lands rows minutes after the 204.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Wait-iSOCIngestionArrival.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Wait-iSOCIngestionArrival {
    <#
    .SYNOPSIS
        Wait for a run's rows to arrive in the destination table, and count
        them.

    .DESCRIPTION
        The Logs Ingestion API is asynchronous: rows land a few minutes after
        the 204, so the counts during the stream are low. This polls the
        destination every 20 seconds until every row sent has arrived or
        -TimeoutSeconds pass, and says how many arrived. A query that is not
        ready yet is polled again; a timeout is reported, not taken as lost
        data.

    .PARAMETER WorkspaceId
        The destination workspace's customer id.

    .PARAMETER Query
        The count query for the run's rows.

    .PARAMETER Sent
        The rows sent.

    .PARAMETER TimeoutSeconds
        How long to wait.

    .OUTPUTS
        [int] The rows that arrived; nothing when the query never answered.

    .EXAMPLE
        Wait-iSOCIngestionArrival -WorkspaceId $id -Query "MyApp_CL | where Message_s has '$runId' | count" -Sent 30 -TimeoutSeconds 300
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string] $WorkspaceId,

        [Parameter(Mandatory)]
        [string] $Query,

        [Parameter(Mandatory)]
        [int] $Sent,

        [Parameter(Mandatory)]
        [int] $TimeoutSeconds
    )

    Write-iSOCLog ''
    Write-iSOCLog 'Verifying arrival' -Level Section
    Write-iSOCLog "Rows appear a few minutes after the 204. Polling up to ${TimeoutSeconds}s..."

    $arrived = $null
    $deadline = [datetimeoffset]::UtcNow.AddSeconds($TimeoutSeconds)
    while ($true) {
        try {
            $qr = Invoke-iSOCAzLogQuery -WorkspaceId $WorkspaceId -Query $Query
            $rows = Get-iSOCPropertyValue -InputObject $qr -Path 'Results'
            $arrived = [int](@($rows)[0].Count)
            Write-iSOCLog "  arrived $arrived / $Sent"
        }
        catch {
            Write-iSOCLog "  query not ready yet ($($_.Exception.Message.Split([char]10)[0]))"
        }
        if ($null -ne $arrived -and $arrived -ge $Sent) { break }
        if ([datetimeoffset]::UtcNow.AddSeconds(20) -ge $deadline) { break }
        Start-Sleep -Seconds 20
    }

    if ($null -ne $arrived -and $arrived -ge $Sent) { Write-iSOCLog "All $Sent records arrived." -Level Success }
    elseif ($arrived) { Write-iSOCLog "$arrived of $Sent arrived so far; the rest may still be within ingestion latency. Re-check: $Query" -Level Warning }
    else { Write-iSOCLog "No rows yet after ${TimeoutSeconds}s. Ingestion can lag longer on a brand-new table; re-check: $Query" -Level Warning }
    $arrived
}
