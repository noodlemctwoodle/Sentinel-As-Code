#Requires -Version 7.2

<#
.SYNOPSIS
    The ARM expression for a managed API's id in the deployment's region.

.DESCRIPTION
    Copied from Get-ManagedApiIdExpression (847ef86:Tools/Export-Playbooks.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCManagedApiIdExpression.ps1
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

function Get-iSOCManagedApiIdExpression {
    <#
    .SYNOPSIS
        Return [concat('/subscriptions/', subscription().subscriptionId,
        '/providers/Microsoft.Web/locations/', resourceGroup().location,
        '/managedApis/<api>')].

    .PARAMETER ApiName
        The managed API's name.

    .OUTPUTS
        [string] The expression.

    .EXAMPLE
        Get-iSOCManagedApiIdExpression -ApiName 'azuresentinel'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $ApiName
    )

    "[concat('/subscriptions/', subscription().subscriptionId, '/providers/Microsoft.Web/locations/', resourceGroup().location, '/managedApis/$ApiName')]"
}
