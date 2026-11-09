#Requires -Version 7.6

<#
.SYNOPSIS
    Get a service principal's token for an audience, by the client-credentials flow.

.DESCRIPTION
    The token and when it expires; a refused request throws without the
    secret.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Get-iSOCServicePrincipalToken.ps1
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

function Get-iSOCServicePrincipalToken {
    <#
    .SYNOPSIS
        Get a service principal's token for an audience, by the
        client-credentials flow.

    .DESCRIPTION
        Posts the token request (New-iSOCTokenRequest) as a form. A refused
        request throws, saying to check the tenant, client id and secret;
        the secret is never shown.

    .PARAMETER AuthorityHost
        The Entra authority host.

    .PARAMETER TenantId
        The tenant.

    .PARAMETER ClientId
        The application (client) id.

    .PARAMETER Audience
        The token's audience.

    .PARAMETER ClientSecret
        The client secret.

    .OUTPUTS
        [pscustomobject] AccessToken and ExpiresOn.

    .EXAMPLE
        Get-iSOCServicePrincipalToken -AuthorityHost $authority -TenantId $tid -ClientId $cid -Audience https://monitor.azure.com -ClientSecret $secret
    #>
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
        [securestring] $ClientSecret
    )

    $request = New-iSOCTokenRequest -AuthorityHost $AuthorityHost -TenantId $TenantId -ClientId $ClientId -Audience $Audience -ClientSecretPlain (ConvertFrom-iSOCSecureString -Secure $ClientSecret)
    $response = Invoke-iSOCHttpRequest -Method POST -Uri $request.Uri -Body $request.Body -ContentType 'application/x-www-form-urlencoded'
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        $why = try { [string](($response.Content | ConvertFrom-Json).error_description) } catch { '' }
        throw "Token request failed: HTTP $($response.StatusCode) $(([string]$why).Split([char]10)[0]). Check the tenant, client ID and secret."
    }
    $token = $response.Content | ConvertFrom-Json
    [pscustomobject]@{
        AccessToken = [string]$token.access_token
        ExpiresOn   = [datetimeoffset]::UtcNow.AddSeconds([int]$token.expires_in)
    }
}
