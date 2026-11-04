#Requires -Version 7.2

<#
.SYNOPSIS
    Send one HTTP request to an endpoint Invoke-AzRestMethod cannot reach.

.DESCRIPTION
    The only file that calls Invoke-WebRequest: the Data Collector API (signed
    with the workspace key), the Entra token endpoint and the Logs Ingestion API
    (with a service principal's token).

.NOTES
    File:         Modules/iSOCDeployments/Private/Http/Invoke-iSOCHttpRequest.ps1
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

function Invoke-iSOCHttpRequest {
    <#
    .SYNOPSIS
        Send one HTTP request to an endpoint Invoke-AzRestMethod cannot
        reach.

    .DESCRIPTION
        For the endpoints that do not take the Az sign-in's ARM or Graph
        token: the HTTP Data Collector API, signed with the workspace key;
        the Entra token endpoint; and the Logs Ingestion API, with a service
        principal's token. The response comes back whatever its status, for
        the caller to judge. Nothing about the request is logged, since its
        headers and body carry credentials. Under -WhatIf a request never
        goes: one that gets here throws, because the command that sent it
        skipped ShouldProcess.

    .PARAMETER Method
        GET or POST.

    .PARAMETER Uri
        The absolute URL.

    .PARAMETER Headers
        The request headers.

    .PARAMETER Body
        The body: bytes, a string, or a hashtable sent as a form.

    .PARAMETER ContentType
        The body's content type.

    .OUTPUTS
        [pscustomobject] StatusCode and Content.

    .EXAMPLE
        Invoke-iSOCHttpRequest -Method POST -Uri $uri -Headers $headers -Body $bytes -ContentType 'application/json'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST')]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Uri,

        [hashtable] $Headers = @{},

        [object] $Body,

        [string] $ContentType
    )

    if ($WhatIfPreference) { throw "Internal error: a $Method reached Invoke-iSOCHttpRequest under -WhatIf." }

    $call = @{ Method = $Method; Uri = $Uri; Headers = $Headers; SkipHttpErrorCheck = $true; ErrorAction = 'Stop' }
    if ($null -ne $Body) { $call.Body = $Body }
    if ($ContentType) { $call.ContentType = $ContentType }
    $response = Invoke-WebRequest @call
    [pscustomobject]@{
        StatusCode = [int]$response.StatusCode
        Content    = [string]$response.Content
    }
}
