#Requires -Version 7.6

<#
.SYNOPSIS
    Initialize-iSOCServicePrincipal: give the deployment service principal
    everything the pipelines need, once.

.DESCRIPTION
    Replaces Deploy/setup/Setup-ServicePrincipal.ps1. Its consent prompt is the confirmation ShouldProcess asks
    for, its Graph modules are one Graph SDK sign-in with every scope the
    steps need, and its Az cmdlets are the REST client (MIGRATION.md edit
    E34).

.NOTES
    File:         Modules/iSOCDeployments/Public/Initialize-iSOCServicePrincipal.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Initialize-iSOCServicePrincipal {
    <#
    .SYNOPSIS
        Grant a deployment service principal the Azure roles, the directory
        role and the Graph application permission the pipelines need.

    .DESCRIPTION
        Run once by someone with Owner on the subscription and at least
        Privileged Role Administrator in Entra ID; afterwards the pipelines
        need no further manual grants. It gives the service principal:

        1. Contributor on the subscription;
        2. User Access Administrator on the subscription, conditioned (ABAC)
           so it can assign and remove only Microsoft Sentinel Responder,
           Microsoft Sentinel Reader, Log Analytics Reader, Logic App
           Contributor and Managed Identity Operator;
        3. the Security Administrator directory role, for UEBA and Entity
           Analytics (-SkipEntraRole leaves it out);
        4. the Microsoft Graph application permission
           CustomDetection.ReadWrite.All, with admin consent, for Defender
           XDR custom detections (-SkipGraphPermission leaves it out).

        Each grant the service principal already has is left alone. The
        Azure roles go through the Az sign-in. The directory role and the
        Graph permission need a Microsoft Graph SDK sign-in with
        RoleManagement.ReadWrite.Directory, AppRoleAssignment.ReadWrite.All
        and Application.Read.All, to the Az sign-in's tenant; one is opened
        when the current one lacks them. These are subscription- and
        tenant-wide permissions: review them against your organisation's
        policies, and audit them regularly. Each grant asks for
        confirmation unless -Confirm:$false is given; -WhatIf grants
        nothing. No workspace is needed: this runs before the pipelines
        create one.

    .PARAMETER ServicePrincipalAppId
        The service principal's application (client) id.

    .PARAMETER SubscriptionId
        The subscription. Defaults to the Az sign-in's.

    .PARAMETER SkipEntraRole
        Leave out the Security Administrator directory role; UEBA and
        Entity Analytics then need enabling by hand.

    .PARAMETER SkipGraphPermission
        Leave out CustomDetection.ReadWrite.All; the Defender XDR stage
        then fails until it is granted.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.PermissionRun: Results (one
        iSOCDeployments.PermissionResult per grant), the counts, Duration
        and ExitCode (1 when a grant failed).

    .EXAMPLE
        Connect-AzAccount
        Initialize-iSOCServicePrincipal -ServicePrincipalAppId $appId -WhatIf

        Says what would be granted, granting nothing.

    .EXAMPLE
        Initialize-iSOCServicePrincipal -ServicePrincipalAppId $appId -SkipEntraRole

        Grants the Azure roles and the Graph permission, asking before each.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('iSOCDeployments.PermissionRun')]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
        [string] $ServicePrincipalAppId,

        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
        [string] $SubscriptionId,

        [switch] $SkipEntraRole,

        [switch] $SkipGraphPermission
    )

    $started = Get-Date
    $steps = @('Connect')
    if (-not ($SkipEntraRole -and $SkipGraphPermission)) { $steps += 'Setup' }
    Assert-iSOCPrerequisite -Step $steps
    $session = Get-iSOCAzSession -SubscriptionId $SubscriptionId
    $ctx = New-iSOCContext -Value @{
        TenantId = $session.TenantId; SubscriptionId = $session.SubscriptionId; Account = $session.Account
        Environment = $session.Environment; IsGov = $session.IsGov; ArmUrl = $session.ArmUrl; GraphUrl = $session.GraphUrl
        ResourceGroup = $null; WorkspaceName = $null; WorkspaceResourceId = $null; WorkspaceId = $null; Region = $null; PlaybookResourceGroup = $null
    }
    $setup = Get-iSOCServicePrincipalSetup -SubscriptionId $ctx.SubscriptionId
    $subscription = "/subscriptions/$($ctx.SubscriptionId)"

    Write-iSOCLog 'Resolving service principal...'
    $filter = { param([string] $Expression) '$filter=' + [Uri]::EscapeDataString($Expression) }
    $spn = @(Invoke-iSOCRestRequest -Method GET -Api Graph -ApiVersion 'v1.0' -Path "/servicePrincipals?$(& $filter "appId eq '$ServicePrincipalAppId'")" -Context $ctx) | Select-Object -First 1
    if (-not $spn) { throw "Service principal with Application ID '$ServicePrincipalAppId' not found." }
    $objectId = [string]$spn.id
    $name = [string]$spn.displayName
    Write-iSOCLog "  Display Name: $name" -Level Success

    Write-iSOCLog "Grants for '$name'" -Level Section
    Write-iSOCLog '  1. Contributor on the subscription'
    Write-iSOCLog "  2. User Access Administrator on the subscription, able to assign only: $(@($setup.UserAccessAdministrator.AllowedRoles.Keys) -join ', ')"
    Write-iSOCLog $(if ($SkipEntraRole) { '  3. Security Administrator (Entra ID): skipped (-SkipEntraRole)' } else { '  3. Security Administrator (Entra ID), for UEBA and Entity Analytics' })
    Write-iSOCLog $(if ($SkipGraphPermission) { "  4. $($setup.GraphAppRole) (Graph): skipped (-SkipGraphPermission)" } else { "  4. $($setup.GraphAppRole) (Graph), for Defender XDR custom detections" })
    Write-iSOCLog 'These are subscription- and tenant-wide permissions: review them against your organisation''s policies and audit them regularly.' -Level Warning

    $results = [System.Collections.Generic.List[object]]::new()
    $add = { param([string] $Role, [string] $Scope, [string] $Outcome, [string] $Reason = '') $results.Add((New-iSOCPermissionResult -Name $name -PrincipalId $objectId -Role $Role -Scope $Scope -Outcome $Outcome -Reason $Reason)) }

    $existing = $null
    foreach ($grant in @(
            @{ Role = 'Contributor'; Id = $setup.Contributor; Condition = $null }
            @{ Role = 'User Access Administrator (conditioned)'; Id = $setup.UserAccessAdministrator.RoleDefinitionId; Condition = $setup.UserAccessAdministrator.Condition }
        )) {
        try {
            if ($null -eq $existing) { $existing = @(Get-iSOCRoleAssignment -Context $ctx -Scope $subscription) }
            if (@(Find-iSOCRoleAssignment -Assignment $existing -PrincipalId $objectId -RoleDefinitionId $grant.Id -Scope $subscription).Count -gt 0) {
                Write-iSOCLog "  $($grant.Role): already assigned."
                & $add $grant.Role $subscription 'Unchanged' 'already assigned'
                continue
            }
            if (-not $PSCmdlet.ShouldProcess("$($grant.Role) on the subscription", "Assign to '$name'")) {
                & $add $grant.Role $subscription 'WhatIf' 'would be assigned'
                continue
            }
            $created = New-iSOCRoleAssignment -Context $ctx -Scope $subscription -RoleDefinitionId $grant.Id -PrincipalId $objectId -Condition $grant.Condition
            Write-iSOCLog "  $($grant.Role): $($created.ToLowerInvariant())." -Level Success
            & $add $grant.Role $subscription $(if ($created -eq 'Exists') { 'Unchanged' } else { 'Assigned' }) $(if ($created -eq 'Exists') { 'already assigned (conflict)' } else { '' })
        }
        catch {
            Write-iSOCLog "  $($grant.Role): failed - $($_.Exception.Message)" -Level Error
            & $add $grant.Role $subscription 'Failed' $_.Exception.Message
        }
    }

    $graphSteps = @()
    if (-not $SkipEntraRole) { $graphSteps += 'Entra' }
    if (-not $SkipGraphPermission) { $graphSteps += 'Graph' }
    if ($SkipEntraRole) { & $add 'Security Administrator (Entra ID)' 'directory' 'Skipped' 'skipped (-SkipEntraRole); UEBA and Entity Analytics need enabling by hand' }

    if ($graphSteps.Count -gt 0) {
        $scopes = @()
        if ($graphSteps -contains 'Entra') { $scopes += 'RoleManagement.ReadWrite.Directory' }
        if ($graphSteps -contains 'Graph') { $scopes += 'AppRoleAssignment.ReadWrite.All', 'Application.Read.All' }
        $signedIn = $null
        try { Connect-iSOCGraphSession -Scope $scopes -TenantId $ctx.TenantId -Environment $ctx.Environment; $signedIn = $true }
        catch { $signedIn = $_.Exception.Message }

        if ($graphSteps -contains 'Entra') {
            $role = 'Security Administrator (Entra ID)'
            try {
                if ($signedIn -ne $true) { throw "Microsoft Graph sign-in failed: $signedIn" }
                $template = $setup.SecurityAdministratorTemplateId
                $held = @(Invoke-iSOCGraphRequest -Method GET -Uri "v1.0/roleManagement/directory/roleAssignments?$(& $filter "principalId eq '$objectId' and roleDefinitionId eq '$template'")")
                if ($held.Count -gt 0) {
                    Write-iSOCLog "  ${role}: already assigned."
                    & $add $role 'directory' 'Unchanged' 'already assigned'
                }
                elseif (-not $PSCmdlet.ShouldProcess('Security Administrator in Entra ID', "Assign to '$name'")) {
                    & $add $role 'directory' 'WhatIf' 'would be assigned'
                }
                else {
                    Invoke-iSOCGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleAssignments' -Body @{ principalId = $objectId; roleDefinitionId = $template; directoryScopeId = '/' } | Out-Null
                    Write-iSOCLog "  ${role}: assigned." -Level Success
                    & $add $role 'directory' 'Assigned'
                }
            }
            catch {
                Write-iSOCLog "  ${role}: failed - $($_.Exception.Message). Privileged Role Administrator is needed to assign Entra ID roles; -SkipEntraRole leaves it out." -Level Error
                & $add $role 'directory' 'Failed' $_.Exception.Message
            }
        }

        if ($graphSteps -contains 'Graph') {
            $role = "$($setup.GraphAppRole) (Graph)"
            try {
                if ($signedIn -ne $true) { throw "Microsoft Graph sign-in failed: $signedIn" }
                $graph = @(Invoke-iSOCGraphRequest -Method GET -Uri "v1.0/servicePrincipals?$(& $filter "appId eq '$($setup.GraphAppId)'")") | Select-Object -First 1
                if (-not $graph) { throw 'The Microsoft Graph service principal was not found.' }
                $appRole = @($graph.appRoles | Where-Object { $_.value -eq $setup.GraphAppRole }) | Select-Object -First 1
                if (-not $appRole) { throw "$($setup.GraphAppRole) app role not found on the Microsoft Graph service principal." }
                $granted = @(Invoke-iSOCGraphRequest -Method GET -Uri "v1.0/servicePrincipals/$objectId/appRoleAssignments" | Where-Object { $_.appRoleId -eq $appRole.id -and $_.resourceId -eq $graph.id })
                if ($granted.Count -gt 0) {
                    Write-iSOCLog "  ${role}: already granted."
                    & $add $role 'Microsoft Graph' 'Unchanged' 'already granted'
                }
                elseif (-not $PSCmdlet.ShouldProcess("$($setup.GraphAppRole) on Microsoft Graph", "Grant to '$name' with admin consent")) {
                    & $add $role 'Microsoft Graph' 'WhatIf' 'would be granted'
                }
                else {
                    Invoke-iSOCGraphRequest -Method POST -Uri "v1.0/servicePrincipals/$($graph.id)/appRoleAssignedTo" -Body @{ principalId = $objectId; resourceId = $graph.id; appRoleId = $appRole.id } | Out-Null
                    Write-iSOCLog "  ${role}: granted with admin consent." -Level Success
                    & $add $role 'Microsoft Graph' 'Assigned'
                }
            }
            catch {
                Write-iSOCLog "  ${role}: failed - $($_.Exception.Message). Application Administrator or Global Administrator may be needed; -SkipGraphPermission leaves it out." -Level Error
                & $add $role 'Microsoft Graph' 'Failed' $_.Exception.Message
            }
        }
    }
    if ($SkipGraphPermission) { & $add "$($setup.GraphAppRole) (Graph)" 'Microsoft Graph' 'Skipped' 'skipped (-SkipGraphPermission); the Defender XDR stage fails without it' }

    New-iSOCPermissionRun -Results $results.ToArray() -Started $started
}
