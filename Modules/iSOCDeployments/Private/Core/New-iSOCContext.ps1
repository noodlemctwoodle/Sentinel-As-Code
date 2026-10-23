#Requires -Version 7.2

<#
.SYNOPSIS
    Build the read-only workspace context every command works against.

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/New-iSOCContext.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function New-iSOCContext {
    <#
    .SYNOPSIS
        Turn the values Connect-iSOCWorkspace resolved into a context object.

    .DESCRIPTION
        Every property is a getter with no setter, so a command handed a
        context cannot change it for the next one: assigning to a property
        throws. The context carries no token; requests are signed by the Az
        sign-in at the time they are made.

        Properties: TenantId, SubscriptionId, ResourceGroup, WorkspaceName,
        WorkspaceResourceId (the ARM path, no host), WorkspaceId (the Log
        Analytics customer id), Region, PlaybookResourceGroup, Environment
        (the Az environment name), IsGov, ArmUrl and GraphUrl (no trailing
        slash) and Account (the signed-in account id).

    .PARAMETER Value
        The property values, by name. Every property above is required.

    .OUTPUTS
        [pscustomobject] with the type name iSOCDeployments.Context.

    .EXAMPLE
        New-iSOCContext -Value $resolved
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; nothing outside the call changes.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Value
    )

    $names = 'TenantId', 'SubscriptionId', 'ResourceGroup', 'WorkspaceName', 'WorkspaceResourceId',
    'WorkspaceId', 'Region', 'PlaybookResourceGroup', 'Environment', 'IsGov', 'ArmUrl', 'GraphUrl', 'Account'
    $missing = @($names | Where-Object { -not $Value.ContainsKey($_) })
    if ($missing.Count -gt 0) { throw "A context needs $($missing -join ', ')." }

    $context = [pscustomobject]@{ PSTypeName = 'iSOCDeployments.Context' }
    foreach ($name in $names) {
        $captured = $Value[$name]
        $context | Add-Member -MemberType ScriptProperty -Name $name -Value ({ $captured }.GetNewClosure())
    }
    $context
}
