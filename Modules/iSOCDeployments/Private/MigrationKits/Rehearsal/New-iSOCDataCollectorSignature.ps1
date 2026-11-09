#Requires -Version 7.6

<#
.SYNOPSIS
    Sign a Data Collector API request with the workspace key.

.DESCRIPTION
    HMAC-SHA256 over the documented string-to-hash, keyed with the
    base64-decoded shared key.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/New-iSOCDataCollectorSignature.ps1
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

function New-iSOCDataCollectorSignature {
    <#
    .SYNOPSIS
        Sign a Data Collector API request with the workspace key.

    .DESCRIPTION
        The SharedKey Authorization value: HMAC-SHA256, keyed with the
        base64-decoded shared key, over the method, content length, content
        type, x-ms-date header and resource, one per line. The content length
        is the body's UTF-8 byte length, not its character length: the two
        differ on any multi-byte character, and a mismatch is a 403.

    .PARAMETER WorkspaceId
        The workspace's customer id.

    .PARAMETER SharedKey
        The workspace's shared key, base64.

    .PARAMETER ContentLength
        The body's length in bytes.

    .PARAMETER Rfc1123Date
        The x-ms-date header's value.

    .PARAMETER Method
        Default POST.

    .PARAMETER ContentType
        Default application/json.

    .PARAMETER Resource
        Default /api/logs.

    .OUTPUTS
        [string] SharedKey <workspace id>:<signature>.

    .EXAMPLE
        New-iSOCDataCollectorSignature -WorkspaceId $id -SharedKey $key -ContentLength $bytes.Length -Rfc1123Date ([datetime]::UtcNow.ToString('r'))
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Computes a signature; changes nothing.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $WorkspaceId,

        [Parameter(Mandatory)]
        [string] $SharedKey,

        [Parameter(Mandatory)]
        [int] $ContentLength,

        [Parameter(Mandatory)]
        [string] $Rfc1123Date,

        [string] $Method = 'POST',

        [string] $ContentType = 'application/json',

        [string] $Resource = '/api/logs'
    )

    $stringToHash = "$Method`n$ContentLength`n$ContentType`nx-ms-date:$Rfc1123Date`n$Resource"
    $bytesToHash = [System.Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [System.Convert]::FromBase64String($SharedKey)

    $hmac = [System.Security.Cryptography.HMACSHA256]::new($keyBytes)
    try {
        $encoded = [System.Convert]::ToBase64String($hmac.ComputeHash($bytesToHash))
    }
    finally {
        $hmac.Dispose()
    }
    "SharedKey ${WorkspaceId}:${encoded}"
}
