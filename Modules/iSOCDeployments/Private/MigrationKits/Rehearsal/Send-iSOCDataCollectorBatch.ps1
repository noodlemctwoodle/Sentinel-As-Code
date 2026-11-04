#Requires -Version 7.2

<#
.SYNOPSIS
    Sign and post one batch of records to the HTTP Data Collector API.

.DESCRIPTION
    The signature covers the date and the body length, so every batch is
    signed afresh.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Send-iSOCDataCollectorBatch.ps1
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

function Send-iSOCDataCollectorBatch {
    <#
    .SYNOPSIS
        Sign and post one batch of records to the HTTP Data Collector API.

    .DESCRIPTION
        The records go as one JSON array, UTF-8, with the log type (the
        table without _CL) and the time-generated-field, signed with the
        workspace key (New-iSOCDataCollectorSignature). The date and the
        body's length are part of the signature, so each batch is signed
        afresh. A response other than 2xx throws with its status. The caller
        asks ShouldProcess.

    .PARAMETER IngestUri
        The workspace's Data Collector endpoint.

    .PARAMETER WorkspaceId
        The workspace's customer id.

    .PARAMETER SharedKey
        The workspace's shared key.

    .PARAMETER LogType
        The table without _CL.

    .PARAMETER Record
        The records.

    .PARAMETER TimeField
        The field that becomes TimeGenerated. Default Timestamp.

    .EXAMPLE
        Send-iSOCDataCollectorBatch -IngestUri $uri -WorkspaceId $id -SharedKey $key -LogType SacMigrationTest -Record $records
    #>
    [CmdletBinding()]
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
        [object[]] $Record,

        [string] $TimeField = 'Timestamp'
    )

    $body = ConvertTo-Json -InputObject @($Record) -Depth 5
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $rfc1123 = [datetime]::UtcNow.ToString('r')
    $signature = New-iSOCDataCollectorSignature -WorkspaceId $WorkspaceId -SharedKey $SharedKey -ContentLength $bodyBytes.Length -Rfc1123Date $rfc1123

    $headers = @{
        'Authorization'        = $signature
        'Log-Type'             = $LogType
        'x-ms-date'            = $rfc1123
        'time-generated-field' = $TimeField
    }
    $response = Invoke-iSOCHttpRequest -Method POST -Uri $IngestUri -Headers $headers -Body $bodyBytes -ContentType 'application/json'
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        throw "The Data Collector API answered HTTP $($response.StatusCode): $(([string]$response.Content).Split([char]10)[0])"
    }
}
