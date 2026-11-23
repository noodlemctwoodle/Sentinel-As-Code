#Requires -Version 7.6

<#
.SYNOPSIS
    Switch the Az sign-in to another subscription.

.NOTES
    File:         Modules/iSOCDeployments/Private/Az/Set-iSOCAzContext.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    Needs Az.Accounts when it runs. The module checks for it at that point
    (Assert-iSOCPrerequisite) instead of in #Requires, so it imports
    without it.

    Az cmdlets are only called from files under Private/Az/, so the rest of
    the module can be tested with these few wrappers mocked.
#>

# Keeps the file help above from being read as the help of the function below.

function Set-iSOCAzContext {
    <#
    .SYNOPSIS
        Select a subscription in the current Az sign-in and return the context.

    .DESCRIPTION
        Selecting a subscription changes nothing in Azure, so it runs even
        when the caller was given -WhatIf; Set-AzContext would otherwise
        skip it and every read after it would go to the wrong subscription.

    .PARAMETER SubscriptionId
        The subscription to select.

    .OUTPUTS
        [Microsoft.Azure.Commands.Profile.Models.Core.PSAzureContext]

    .EXAMPLE
        $az = Set-iSOCAzContext -SubscriptionId $id
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Selecting a subscription changes no Azure resource and must run under -WhatIf, or every read after it goes to the wrong subscription.')]
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [string] $SubscriptionId
    )

    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop -WarningAction SilentlyContinue -WhatIf:$false -Confirm:$false
}
