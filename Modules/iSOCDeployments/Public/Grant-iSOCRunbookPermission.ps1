#Requires -Version 7.2

<#
.SYNOPSIS
    Grant-iSOCRunbookPermission: give the roles the DCR watchlist sync
    runbook's managed identity needs.

.DESCRIPTION
    Replaces the assigning half of Deploy/permissions/Set-RunbookPermissions.ps1. Its -SubscriptionId and
    -SentinelResourceGroup come from Connect-iSOCWorkspace, its consent
    prompt is the confirmation ShouldProcess asks for, and az is the REST
    client (MIGRATION.md edit E33).

.NOTES
    File:         Modules/iSOCDeployments/Public/Grant-iSOCRunbookPermission.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Grant-iSOCRunbookPermission {
    <#
    .SYNOPSIS
        Assign the DCR watchlist sync runbook's two roles to an Automation
        Account's managed identity.

    .DESCRIPTION
        The DCR watchlist sync runbook lists data collection rules and their
        associations across the subscription and writes a Sentinel
        watchlist. Each role is assigned unless the identity has it at that
        scope or above. Afterwards the identity's assignments in the
        subscription are read back into the result.

        These are subscription-wide permissions. Review them against your
        organisation's least-privilege and compliance policies, and audit
        them regularly; the identity running this needs Owner or User
        Access Administrator on the subscription. Each change asks for
        confirmation unless -Confirm:$false is given, and -WhatIf
        assigns nothing.

    .PARAMETER AutomationAccountName
        The Automation Account, with a system-assigned managed identity.

    .PARAMETER AutomationResourceGroup
        Its resource group.

    .PARAMETER Context
        The workspace. Defaults to the one Connect-iSOCWorkspace connected;
        its resource group is the Sentinel resource group.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.PermissionRun: Results (one
        iSOCDeployments.PermissionResult per role), the counts, Duration,
        ExitCode, and Assignments (the identity's role
        assignments in the subscription afterwards: Role and Scope).

    .EXAMPLE
        Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel
        Grant-iSOCRunbookPermission -AutomationAccountName aa-dcr-watchlist-sync -AutomationResourceGroup rg-dcr-watchlist-sync -WhatIf

        Says what would be assigned, changing nothing.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('iSOCDeployments.PermissionRun')]
    param(
        [Parameter(Mandatory)]
        [string] $AutomationAccountName,

        [Parameter(Mandatory)]
        [string] $AutomationResourceGroup,

        [psobject] $Context
    )

    $started = Get-Date
    $ctx = Resolve-iSOCContext -Context $Context
    Assert-iSOCPrerequisite -Step Connect
    $principal = Get-iSOCAutomationPrincipal -Context $ctx -Name $AutomationAccountName -ResourceGroup $AutomationResourceGroup
    $roles = @(Get-iSOCRunbookRole -Context $ctx)

    Write-iSOCLog "Permissions to assign for '$AutomationAccountName' (managed identity)" -Level Section
    foreach ($role in $roles) {
        Write-iSOCLog "  $($role.Name): $($role.Reason)"
        Write-iSOCLog "    Scope: $($role.Scope)"
    }
    Write-iSOCLog 'These are subscription-wide permissions: review them against your organisation''s policies and audit them regularly.' -Level Warning

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($role in $roles) {
        $result = @{ Name = $AutomationAccountName; PrincipalId = $principal; Role = $role.Name; Scope = $role.Scope }
        try {
            $existing = @(Get-iSOCRoleAssignment -Context $ctx -Scope $role.Scope)
            if (@(Find-iSOCRoleAssignment -Assignment $existing -PrincipalId $principal -RoleDefinitionId $role.RoleDefinitionId -Scope $role.Scope).Count -gt 0) {
                Write-iSOCLog "  $($role.Name): already assigned."
                $results.Add((New-iSOCPermissionResult @result -Outcome Unchanged -Reason 'already assigned'))
                continue
            }
            if (-not $PSCmdlet.ShouldProcess("$($role.Name) on $($role.Scope)", 'Create role assignment')) {
                $results.Add((New-iSOCPermissionResult @result -Outcome WhatIf -Reason 'would be assigned'))
                continue
            }
            $created = New-iSOCRoleAssignment -Context $ctx -Scope $role.Scope -RoleDefinitionId $role.RoleDefinitionId -PrincipalId $principal
            $outcome = if ($created -eq 'Exists') { 'Unchanged' } else { 'Assigned' }
            Write-iSOCLog "  [+] $($role.Name): $($outcome.ToLowerInvariant())." -Level Success
            $results.Add((New-iSOCPermissionResult @result -Outcome $outcome -Reason $(if ($created -eq 'Exists') { 'already assigned (conflict)' } else { '' })))
        }
        catch {
            Write-iSOCLog "  $($role.Name): failed - $($_.Exception.Message)" -Level Error
            $results.Add((New-iSOCPermissionResult @result -Outcome Failed -Reason $_.Exception.Message))
        }
    }

    $names = @{}
    $table = Get-iSOCRoleDefinitionId
    foreach ($key in $table.Keys) { $names[$table[$key]] = $key }
    $assignments = @(Get-iSOCRoleAssignment -Context $ctx -PrincipalId $principal | ForEach-Object {
            [pscustomobject]@{ Role = $(if ($names.ContainsKey($_.RoleDefinitionId)) { $names[$_.RoleDefinitionId] } else { $_.RoleDefinitionId }); Scope = $_.Scope }
        })
    foreach ($assignment in $assignments) { Write-iSOCLog "  Has: $($assignment.Role) on $($assignment.Scope)" }
    New-iSOCPermissionRun -Results $results.ToArray() -Started $started -Extra @{ Assignments = $assignments }
}
