#Requires -Version 7.2

<#
.SYNOPSIS
    Revoke-iSOCRunbookPermission: take back the roles the DCR watchlist sync
    runbook's managed identity was given.

.DESCRIPTION
    Replaces the -Remove half of Deploy/permissions/Set-RunbookPermissions.ps1. Its -SubscriptionId and
    -SentinelResourceGroup come from Connect-iSOCWorkspace, its consent
    prompt is the confirmation ShouldProcess asks for, and az is the REST
    client (MIGRATION.md edit E33).

.NOTES
    File:         Modules/iSOCDeployments/Public/Revoke-iSOCRunbookPermission.ps1
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

function Revoke-iSOCRunbookPermission {
    <#
    .SYNOPSIS
        Remove the role assignments Grant-iSOCRunbookPermission makes.

    .DESCRIPTION
        Each role's assignment to the identity at exactly its scope is
        deleted; one inherited from above is left, since it was not made
        here. A role the identity does not have there is Unchanged.

        These are subscription-wide permissions. Review them against your
        organisation's least-privilege and compliance policies, and audit
        them regularly; the identity running this needs Owner or User
        Access Administrator on the subscription. Each change asks for
        confirmation unless -Confirm:$false is given, and -WhatIf
        removes nothing.

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
        ExitCode.

    .EXAMPLE
        Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel
        Revoke-iSOCRunbookPermission -AutomationAccountName aa-dcr-watchlist-sync -AutomationResourceGroup rg-dcr-watchlist-sync -WhatIf

        Says what would be removed, changing nothing.
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

    Write-iSOCLog "Permissions to remove for '$AutomationAccountName' (managed identity)" -Level Section
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
            $matching = @(Find-iSOCRoleAssignment -Assignment $existing -PrincipalId $principal -RoleDefinitionId $role.RoleDefinitionId -Scope $role.Scope -Exact)
            if ($matching.Count -eq 0) {
                Write-iSOCLog "  $($role.Name): not assigned at this scope."
                $results.Add((New-iSOCPermissionResult @result -Outcome Unchanged -Reason 'not assigned at this scope'))
                continue
            }
            if (-not $PSCmdlet.ShouldProcess("$($role.Name) on $($role.Scope)", 'Remove role assignment')) {
                $results.Add((New-iSOCPermissionResult @result -Outcome WhatIf -Reason 'would be removed'))
                continue
            }
            foreach ($assignment in $matching) { Remove-iSOCRoleAssignment -Context $ctx -AssignmentId $assignment.Id }
            Write-iSOCLog "  [-] $($role.Name): removed." -Level Success
            $results.Add((New-iSOCPermissionResult @result -Outcome Removed))
        }
        catch {
            Write-iSOCLog "  $($role.Name): failed - $($_.Exception.Message)" -Level Error
            $results.Add((New-iSOCPermissionResult @result -Outcome Failed -Reason $_.Exception.Message))
        }
    }

    New-iSOCPermissionRun -Results $results.ToArray() -Started $started
}
