#Requires -Version 7.2

<#
.SYNOPSIS
    Send one content item's request to the workspace.

.NOTES
    File:         Modules/iSOCDeployments/Private/Deploy/Send-iSOCContentRequest.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Send-iSOCContentRequest {
    <#
    .SYNOPSIS
        PUT a request built by a content type's ToRequest handler.

    .DESCRIPTION
        The path is the type's scope and collection with the request's
        ResourceName, and the api-version the type's. The caller has
        already checked ShouldProcess; a failure throws the REST client's
        error.

    .PARAMETER Context
        The workspace context.

    .PARAMETER ContentType
        The item's content type.

    .PARAMETER Request
        From the type's ToRequest handler.

    .OUTPUTS
        The response body.

    .EXAMPLE
        Send-iSOCContentRequest -Context $run.Context -ContentType $type -Request $request
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Its callers check ShouldProcess before they send.')]
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [psobject] $ContentType,

        [Parameter(Mandatory)]
        [psobject] $Request
    )

    $path = Get-iSOCResourcePath -Context $Context -ContentType $ContentType -Name $Request.ResourceName
    Invoke-iSOCRestRequest -Method PUT -Path $path -ApiVersion (Get-iSOCApiVersion $ContentType.ApiVersion) -Body $Request.Body
}
