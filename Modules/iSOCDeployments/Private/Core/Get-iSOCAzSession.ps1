#Requires -Version 7.2

<#
.SYNOPSIS
    The Az sign-in's tenant, subscription and cloud.

.DESCRIPTION
    Moved out of Connect-iSOCWorkspace, so a command that needs no workspace
    (Initialize-iSOCServicePrincipal) reads the sign-in the same way.

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/Get-iSOCAzSession.ps1
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

function Get-iSOCAzSession {
    <#
    .SYNOPSIS
        Return the current Az sign-in's tenant, subscription, account and
        cloud hosts, moving it to another subscription first when asked.

    .DESCRIPTION
        The ARM host is the environment's; the Graph host its
        MicrosoftGraphUrl, else the one the environment's name implies
        (graph.microsoft.us for US Government, the China cloud's for China,
        graph.microsoft.com otherwise). Throws when there is no sign-in.

    .PARAMETER SubscriptionId
        Move the sign-in to this subscription when it is on another.

    .OUTPUTS
        [hashtable] TenantId, SubscriptionId, Account, Environment, IsGov,
        ArmUrl and GraphUrl.

    .EXAMPLE
        $session = Get-iSOCAzSession -SubscriptionId $sub
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string] $SubscriptionId
    )

    $az = Get-iSOCAzContext
    if (-not $az -or -not (Get-iSOCPropertyValue -InputObject $az -Path 'Subscription.Id')) {
        throw 'No Azure sign-in found. Run Connect-AzAccount (with -Environment AzureUSGovernment for US Government) and try again.'
    }
    if ($SubscriptionId -and $az.Subscription.Id -ne $SubscriptionId) {
        $az = Set-iSOCAzContext -SubscriptionId $SubscriptionId
    }

    $environment = $az.Environment
    $environmentName = [string](Get-iSOCPropertyValue -InputObject $environment -Path 'Name')
    $armUrl = ([string](Get-iSOCPropertyValue -InputObject $environment -Path 'ResourceManagerUrl')).TrimEnd('/')
    $extended = Get-iSOCPropertyValue -InputObject $environment -Path 'ExtendedProperties'
    $graphUrl = if ($extended -and $extended.ContainsKey('MicrosoftGraphUrl')) { [string]$extended['MicrosoftGraphUrl'] } else { $null }
    if (-not $graphUrl) {
        $graphUrl = switch ($environmentName) {
            'AzureUSGovernment' { 'https://graph.microsoft.us' }
            'AzureChinaCloud' { 'https://microsoftgraph.chinacloudapi.cn' }
            default { 'https://graph.microsoft.com' }
        }
    }
    $tenant = Get-iSOCPropertyValue -InputObject $az -Path 'Tenant.Id'
    if (-not $tenant) { $tenant = Get-iSOCPropertyValue -InputObject $az -Path 'Subscription.TenantId' }

    @{
        TenantId       = [string]$tenant
        SubscriptionId = [string]$az.Subscription.Id
        Account        = [string](Get-iSOCPropertyValue -InputObject $az -Path 'Account.Id')
        Environment    = $environmentName
        IsGov          = ($environmentName -eq 'AzureUSGovernment')
        ArmUrl         = $armUrl
        GraphUrl       = $graphUrl.TrimEnd('/')
    }
}
