#Requires -Version 7.6

<#
.SYNOPSIS
    One request through the Microsoft Graph SDK sign-in.

.DESCRIPTION
    Replaces the Get-Mg and New-Mg cmdlets Deploy/setup/Setup-ServicePrincipal.ps1
    used, so only Microsoft.Graph.Authentication is needed rather than the
    Identity.Governance and Applications modules the script installed.

.NOTES
    File:         Modules/iSOCDeployments/Private/Graph/Invoke-iSOCGraphRequest.ps1
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

function Invoke-iSOCGraphRequest {
    <#
    .SYNOPSIS
        Send a Graph request through Invoke-MgGraphRequest and return the
        result, every page of a collection.

    .PARAMETER Method
        GET or POST.

    .PARAMETER Uri
        The URL, relative to the Graph host (v1.0/servicePrincipals) or
        whole.

    .PARAMETER Body
        The body, serialised to JSON.

    .OUTPUTS
        [psobject] The object, or each item of a collection.

    .EXAMPLE
        Invoke-iSOCGraphRequest -Method GET -Uri "v1.0/servicePrincipals/$id/appRoleAssignments"
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST')]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Uri,

        [object] $Body
    )

    $parameters = @{ Method = $Method; Uri = $Uri; OutputType = 'PSObject'; ErrorAction = 'Stop' }
    if ($null -ne $Body) {
        $parameters.Body = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
        $parameters.ContentType = 'application/json'
    }
    $response = Invoke-MgGraphRequest @parameters
    if ($Method -ne 'GET' -or -not $response.PSObject.Properties['value']) { return $response }
    while ($true) {
        foreach ($item in @($response.value)) { $item }
        $next = $response.PSObject.Properties['@odata.nextLink']
        if (-not $next -or -not $next.Value) { break }
        $response = Invoke-MgGraphRequest -Method GET -Uri $next.Value -OutputType PSObject -ErrorAction Stop
    }
}
