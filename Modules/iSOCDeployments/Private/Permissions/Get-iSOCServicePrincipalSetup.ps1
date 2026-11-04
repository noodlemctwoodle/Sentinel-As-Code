#Requires -Version 7.2

<#
.SYNOPSIS
    What the deployment service principal is given.

.DESCRIPTION
    Replaces the role ids, the ABAC condition and the summary text of
    Deploy/setup/Setup-ServicePrincipal.ps1.

.NOTES
    File:         Modules/iSOCDeployments/Private/Permissions/Get-iSOCServicePrincipalSetup.ps1
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

function Get-iSOCServicePrincipalSetup {
    <#
    .SYNOPSIS
        Return the grants a deployment service principal needs, with the
        conditioned User Access Administrator's ABAC condition.

    .DESCRIPTION
        - Contributor on the subscription: resource groups, the workspace,
          Bicep and content.
        - User Access Administrator on the subscription, conditioned so it
          can assign and remove only Microsoft Sentinel Responder,
          Microsoft Sentinel Reader, Log Analytics Reader, Logic App
          Contributor and Managed Identity Operator: for the playbook
          identities' role assignments during ARM deployment.
        - The Security Administrator directory role: UEBA and Entity
          Analytics settings.
        - The Microsoft Graph application permission
          CustomDetection.ReadWrite.All: Defender XDR custom detections.

    .PARAMETER SubscriptionId
        The subscription.

    .OUTPUTS
        [hashtable] Contributor, UserAccessAdministrator (RoleDefinitionId,
        Condition, AllowedRoles), SecurityAdministratorTemplateId,
        GraphAppId and GraphAppRole.

    .EXAMPLE
        $setup = Get-iSOCServicePrincipalSetup -SubscriptionId $sub
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $SubscriptionId
    )

    $allowed = [ordered]@{
        'Microsoft Sentinel Responder' = '3e150937-b8fe-4cfb-8069-0eaf05ecd056'
        'Microsoft Sentinel Reader'    = '8d289c81-5878-46d4-8554-54e1e3d8b5cb'
        'Log Analytics Reader'         = '73c42c96-874c-492b-b04d-ab87d138a893'
        'Logic App Contributor'        = '87a39d53-fc1b-424a-814c-f7e04687dc9e'
        'Managed Identity Operator'    = 'f1a07417-d97a-45cb-824c-7a7467783830'
    }
    $roleExpr = (@($allowed.Values) | ForEach-Object { "(@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] StringEquals '/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions/$_')" }) -join ' OR '
    @{
        Contributor                     = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
        UserAccessAdministrator         = @{
            RoleDefinitionId = '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'
            AllowedRoles     = $allowed
            Condition        = "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR ($roleExpr)) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR ($roleExpr))"
        }
        SecurityAdministratorTemplateId = '194ae4cb-b126-40b2-bd5b-6091b380977d'
        GraphAppId                      = '00000003-0000-0000-c000-000000000000'
        GraphAppRole                    = 'CustomDetection.ReadWrite.All'
    }
}
