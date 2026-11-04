#Requires -Version 7.2

<#
.SYNOPSIS
    Build an OAuth2 client-credentials token request.

.DESCRIPTION
    The token endpoint of the tenant and the form for the audience's default
    scope.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/New-iSOCTokenRequest.ps1
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

function New-iSOCTokenRequest {
    <#
    .SYNOPSIS
        Build an OAuth2 client-credentials token request.

    .DESCRIPTION
        The tenant's v2.0 token endpoint on the authority host, and the form:
        the client id, the audience's .default scope, the secret and the
        client_credentials grant.

    .PARAMETER AuthorityHost
        The Entra authority host.

    .PARAMETER TenantId
        The tenant.

    .PARAMETER ClientId
        The application (client) id.

    .PARAMETER Audience
        The token's audience.

    .PARAMETER ClientSecretPlain
        The client secret.

    .OUTPUTS
        [pscustomobject] Uri and Body.

    .EXAMPLE
        New-iSOCTokenRequest -AuthorityHost https://login.microsoftonline.com -TenantId $tid -ClientId $cid -Audience https://monitor.azure.com -ClientSecretPlain $secret
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a request in memory; changes nothing.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $AuthorityHost,

        [Parameter(Mandatory)]
        [string] $TenantId,

        [Parameter(Mandatory)]
        [string] $ClientId,

        [Parameter(Mandatory)]
        [string] $Audience,

        [Parameter(Mandatory)]
        [string] $ClientSecretPlain
    )

    [pscustomobject]@{
        Uri  = '{0}/{1}/oauth2/v2.0/token' -f $AuthorityHost.TrimEnd('/'), $TenantId
        Body = @{
            client_id     = $ClientId
            scope         = "$($Audience.TrimEnd('/'))/.default"
            client_secret = $ClientSecretPlain
            grant_type    = 'client_credentials'
        }
    }
}
