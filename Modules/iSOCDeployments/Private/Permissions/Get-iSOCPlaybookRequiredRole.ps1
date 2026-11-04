#Requires -Version 7.2

<#
.SYNOPSIS
    The roles a playbook's workflow needs.

.DESCRIPTION
    Copied from Get-PlaybookRequiredRoles
    (Deploy/permissions/Set-PlaybookPermissions.ps1), with its maps, as
    corrected in the script's 1.0.2: the pattern meant to find a PUT
    request (method.*put) matched any method followed anywhere by inputs or
    outputs, so it gave Microsoft Sentinel Contributor to 44 of this
    repository's 90 playbooks that otherwise needed no more than Responder;
    it now matches a "method": "put" pair. The connections are read only
    when the workflow has them.

.NOTES
    File:         Modules/iSOCDeployments/Private/Permissions/Get-iSOCPlaybookRequiredRole.ps1
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

function Get-iSOCPlaybookRequiredRole {
    <#
    .SYNOPSIS
        Return the RBAC roles a Logic App's workflow needs, each with the
        scope it is needed at.

    .DESCRIPTION
        - Each API connection's managed API: azuresentinel and
          microsoftsentinel need Microsoft Sentinel Responder on the
          Sentinel resource group; keyvault Key Vault Secrets User on the
          vault; azuremonitorlogs and azureloganalyticsdatacollector Log
          Analytics Reader on the resource group.
        - A workflow that changes Sentinel (a /Incidents or /Watchlists
          path, an Update_incident action, or a PUT request) needs
          Microsoft Sentinel Contributor instead of Responder.
        - An HTTP action with managed identity: the Log Analytics API needs
          Log Analytics Reader, Azure Resource Manager Microsoft Sentinel
          Contributor; Microsoft Graph and the Defender API need none, as
          their permissions come through the app registration.

    .PARAMETER Properties
        The Logic App's properties: its definition and parameters.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] The scope (rg or
        keyvault) by role name.

    .EXAMPLE
        Get-iSOCPlaybookRequiredRole -Properties $app.properties
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [object] $Properties
    )

    $connectorRoles = @{
        'azuresentinel'                  = @(@{ Role = 'Microsoft Sentinel Responder'; Scope = 'rg' })
        'microsoftsentinel'              = @(@{ Role = 'Microsoft Sentinel Responder'; Scope = 'rg' })
        'keyvault'                       = @(@{ Role = 'Key Vault Secrets User'; Scope = 'keyvault' })
        'azuremonitorlogs'               = @(@{ Role = 'Log Analytics Reader'; Scope = 'rg' })
        'azureloganalyticsdatacollector' = @(@{ Role = 'Log Analytics Reader'; Scope = 'rg' })
    }
    $contributorPatterns = @('/Incidents', '/Watchlists', '"method"\s*:\s*"put"', 'Update_incident')
    $audienceRoles = @{
        'https://graph.microsoft.com'              = $null
        'https://api.loganalytics.io'              = @{ Role = 'Log Analytics Reader'; Scope = 'rg' }
        'https://api.securitycenter.microsoft.com' = $null
        'https://management.azure.com'             = @{ Role = 'Microsoft Sentinel Contributor'; Scope = 'rg' }
    }

    $roles = [ordered]@{}
    $json = $Properties | ConvertTo-Json -Depth 50 -Compress

    $connections = Get-iSOCPropertyValue -InputObject $Properties -Path 'parameters.$connections.value'
    foreach ($entry in @(Get-iSOCPropertyEntry -InputObject $connections)) {
        $apiId = Get-iSOCPropertyValue -InputObject $entry.Value -Path 'id'
        if ($apiId -and [string]$apiId -match '/managedApis/([^"'']+)') {
            $connector = $Matches[1].ToLower()
            if ($connectorRoles.ContainsKey($connector)) {
                foreach ($mapping in $connectorRoles[$connector]) {
                    if (-not $roles.Contains($mapping.Role)) { $roles[$mapping.Role] = $mapping.Scope }
                }
            }
        }
    }

    $needsContributor = @($contributorPatterns | Where-Object { $json -match $_ }).Count -gt 0
    if ($needsContributor) {
        if ($roles.Contains('Microsoft Sentinel Responder')) { $roles.Remove('Microsoft Sentinel Responder') }
        $roles['Microsoft Sentinel Contributor'] = 'rg'
    }

    foreach ($m in [regex]::Matches($json, '"audience"\s*:\s*"(https://[^"]+)"')) {
        $audience = $m.Groups[1].Value
        if ($audienceRoles.ContainsKey($audience)) {
            $mapping = $audienceRoles[$audience]
            if ($mapping -and -not $roles.Contains($mapping.Role)) { $roles[$mapping.Role] = $mapping.Scope }
        }
    }
    $roles
}
