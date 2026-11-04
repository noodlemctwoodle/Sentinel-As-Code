#Requires -Version 7.2

<#
.SYNOPSIS
    The ids of the built-in Azure roles the module assigns.

.DESCRIPTION
    Replaces $RoleDefinitions (Deploy/permissions/Set-PlaybookPermissions.ps1) and the role names
    Deploy/permissions/Set-RunbookPermissions.ps1 passed to az.

.NOTES
    File:         Modules/iSOCDeployments/Private/Permissions/Get-iSOCRoleDefinitionId.ps1
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

function Get-iSOCRoleDefinitionId {
    <#
    .SYNOPSIS
        Return a built-in role's id by name, or the whole table.

    .DESCRIPTION
        Built-in role ids are the same in every tenant and cloud.

    .PARAMETER Name
        The role's name, in any case.

    .OUTPUTS
        [string] The GUID; [System.Collections.Specialized.OrderedDictionary]
        without a name.

    .EXAMPLE
        Get-iSOCRoleDefinitionId -Name 'Microsoft Sentinel Responder'
    #>
    [CmdletBinding()]
    [OutputType([string], [System.Collections.Specialized.OrderedDictionary])]
    param(
        [string] $Name
    )

    $table = [ordered]@{
        'Microsoft Sentinel Responder'   = '3e150937-b8fe-4cfb-8069-0eaf05ecd056'
        'Microsoft Sentinel Contributor' = 'ab8e14d6-4a74-4a29-9ba8-549422addade'
        'Log Analytics Reader'           = '73c42c96-874c-492b-b04d-ab87d138a893'
        'Key Vault Secrets User'         = '4633458b-17de-408a-b874-0445c86b69e6'
        'Logic App Contributor'          = '87a39d53-fc1b-424a-814c-f7e04687dc9e'
        'Monitoring Reader'              = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
    }
    if (-not $Name) { return $table }
    foreach ($key in $table.Keys) { if ($key -ieq $Name) { return $table[$key] } }
    $null
}
