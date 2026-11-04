#Requires -Version 7.2

<#
.SYNOPSIS
    A Microsoft Graph SDK sign-in with the delegated scopes asked for.

.DESCRIPTION
    Replaces the Connect-MgGraph calls in Deploy/setup/Setup-ServicePrincipal.ps1, which reused any existing
    Graph sign-in whatever its scopes, so the second Graph step could run
    without the scopes it needs, and signed in to whichever tenant the browser
    chose (MIGRATION.md edit E34). The Az sign-in's Graph token does not carry
    the role management and app role assignment scopes, so these steps cannot
    use the REST client. The only file, with Invoke-iSOCGraphRequest, that runs
    Graph SDK commands (Module.Tests.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Graph/Connect-iSOCGraphSession.ps1
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

function Connect-iSOCGraphSession {
    <#
    .SYNOPSIS
        Sign in to Microsoft Graph with the scopes given, or keep a sign-in
        that already has them.

    .DESCRIPTION
        An existing Graph SDK sign-in is kept when it is to the same tenant
        and holds every scope asked for; otherwise Connect-MgGraph signs in
        again (a browser sign-in) to that tenant and cloud, asking for all
        of them at once.

    .PARAMETER Scope
        The delegated scopes.

    .PARAMETER TenantId
        The tenant: the Az sign-in's.

    .PARAMETER Environment
        The Az environment's name, mapped to the Graph SDK's (AzureCloud is
        Global, AzureUSGovernment USGov, AzureChinaCloud China).

    .EXAMPLE
        Connect-iSOCGraphSession -Scope 'RoleManagement.ReadWrite.Directory' -TenantId $tenant -Environment AzureCloud
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Scope,

        [string] $TenantId,

        [string] $Environment = 'AzureCloud'
    )

    $current = Get-MgContext -ErrorAction SilentlyContinue
    if ($current) {
        $held = @($current.Scopes)
        $missing = @($Scope | Where-Object { $held -notcontains $_ })
        if ($missing.Count -eq 0 -and (-not $TenantId -or [string]$current.TenantId -eq $TenantId)) { return }
    }
    $cloud = switch ($Environment) {
        'AzureUSGovernment' { 'USGov' }
        'AzureChinaCloud' { 'China' }
        default { 'Global' }
    }
    Write-iSOCLog "Connecting to Microsoft Graph for $($Scope -join ', ') (browser sign-in may be required)..."
    $parameters = @{ Scopes = $Scope; Environment = $cloud; NoWelcome = $true; ErrorAction = 'Stop' }
    if ($TenantId) { $parameters.TenantId = $TenantId }
    Connect-MgGraph @parameters | Out-Null
}
