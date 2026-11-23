#Requires -Version 7.6

<#
.SYNOPSIS
    Grant-iSOCPlaybookPermission: give each playbook's managed identity the
    roles its workflow needs.

.DESCRIPTION
    Replaces Deploy/permissions/Set-PlaybookPermissions.ps1. Its
    -SubscriptionId, -PlaybookResourceGroup, -SentinelResourceGroup and
    -SentinelWorkspaceName come from Connect-iSOCWorkspace, and its own
    -WhatIf switch is the common parameter (MIGRATION.md edit E32).

.NOTES
    File:         Modules/iSOCDeployments/Public/Grant-iSOCPlaybookPermission.ps1
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

function Grant-iSOCPlaybookPermission {
    <#
    .SYNOPSIS
        Assign the RBAC roles each playbook this repository deploys needs
        to its Logic App's managed identity.

    .DESCRIPTION
        Every Logic App in the playbook resource group tagged
        Source: Sentinel-As-Code is read, and its workflow tells which roles
        it needs (Get-iSOCPlaybookRequiredRole): the Sentinel, Key Vault and
        Log Analytics connectors it uses, whether it changes incidents or
        watchlists, and the APIs its HTTP actions call with the managed
        identity. Each role is assigned at the Sentinel resource group, or
        the Key Vault for Key Vault Secrets User, unless the identity has it
        there already or from a scope above. Nothing is removed.

        Run it after playbooks are deployed, as an identity with Owner or
        User Access Administrator on those scopes: the pipeline's service
        principal, whose User Access Administrator is conditioned, cannot
        assign the Sentinel roles. With -WhatIf nothing is assigned and
        each role says whether it would be.

    .PARAMETER Name
        Only the Logic Apps whose names match these wildcards.

    .PARAMETER KeyVaultName
        The Key Vault the playbooks read, in the Sentinel resource group.
        Without it, Key Vault roles are skipped.

    .PARAMETER Context
        The workspace. Defaults to the one Connect-iSOCWorkspace connected;
        its PlaybookResourceGroup is where the Logic Apps are.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.PermissionRun: Results (one
        iSOCDeployments.PermissionResult per role per playbook, and one for
        a playbook given none: Name, PrincipalId, Role, Scope, Outcome,
        Reason), the counts Assigned, Unchanged, Skipped, Failed and
        WhatIf, Duration and ExitCode.

    .EXAMPLE
        Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel -PlaybookResourceGroup rg-automation
        Grant-iSOCPlaybookPermission -KeyVaultName kv-sentinel -WhatIf

        Says which roles each playbook would be given, assigning none.

    .EXAMPLE
        Grant-iSOCPlaybookPermission -Name 'Incident-*' -KeyVaultName kv-sentinel

        Assigns the roles the incident playbooks need.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('iSOCDeployments.PermissionRun')]
    param(
        [SupportsWildcards()]
        [string[]] $Name,

        [string] $KeyVaultName,

        [psobject] $Context
    )

    $started = Get-Date
    $ctx = Resolve-iSOCContext -Context $Context
    Assert-iSOCPrerequisite -Step Connect
    $sentinelGroup = $ctx.ResourceGroup
    Write-iSOCLog 'Grant playbook permissions' -Level Section
    Write-iSOCLog "  Playbook RG:        $($ctx.PlaybookResourceGroup)"
    Write-iSOCLog "  Sentinel RG:        $sentinelGroup"
    Write-iSOCLog "  Sentinel workspace: $($ctx.WorkspaceName)"
    if ($KeyVaultName) { Write-iSOCLog "  Key Vault:          $KeyVaultName" }

    $type = Get-iSOCContentTypeDefinition -Name Playbook
    $apps = @(Read-iSOCPlaybookWorkspace -Context $ctx -ContentType $type | Where-Object { [string](Get-iSOCPropertyValue -InputObject $_ -Path 'tags.Source') -eq 'Sentinel-As-Code' })
    if ($Name) { $apps = @($apps | Where-Object { $appName = [string](Get-iSOCPropertyValue -InputObject $_ -Path 'name'); @($Name | Where-Object { $appName -like $_ }).Count -gt 0 }) }
    $results = [System.Collections.Generic.List[object]]::new()
    if ($apps.Count -eq 0) {
        Write-iSOCLog "No Logic Apps found with 'Source: Sentinel-As-Code' tag." -Level Warning
        return (New-iSOCPermissionRun -Results @() -Started $started)
    }
    Write-iSOCLog "Found $($apps.Count) playbook(s) with Source: Sentinel-As-Code tag."

    $groupScope = Resolve-iSOCRoleScope -ScopeType rg -SubscriptionId $ctx.SubscriptionId -ResourceGroup $sentinelGroup
    $existing = [System.Collections.Generic.List[object]]::new()
    foreach ($assignment in @(Get-iSOCRoleAssignment -Context $ctx -Scope $groupScope)) { $existing.Add($assignment) }
    if ($KeyVaultName) {
        $vaultScope = Resolve-iSOCRoleScope -ScopeType keyvault -SubscriptionId $ctx.SubscriptionId -ResourceGroup $sentinelGroup -KeyVaultName $KeyVaultName
        foreach ($assignment in @(Get-iSOCRoleAssignment -Context $ctx -Scope $vaultScope)) { $existing.Add($assignment) }
    }

    foreach ($app in $apps) {
        $appName = [string](Get-iSOCPropertyValue -InputObject $app -Path 'name')
        Write-iSOCLog "Processing: $appName"
        $readError = $app.PSObject.Properties['ReadError']
        if ($readError) {
            Write-iSOCLog "  [FAIL] $($readError.Value)" -Level Error
            $results.Add((New-iSOCPermissionResult -Name $appName -Outcome Failed -Reason ([string]$readError.Value)))
            continue
        }
        $identity = Get-iSOCManagedIdentityPrincipal -Resource $app
        if (-not $identity.Type -or $identity.Type -eq 'None') {
            Write-iSOCLog '  [SKIP] No managed identity configured.'
            $results.Add((New-iSOCPermissionResult -Name $appName -Outcome Skipped -Reason 'no managed identity'))
            continue
        }
        if (-not $identity.PrincipalId) {
            Write-iSOCLog '  [SKIP] Could not determine principal ID.' -Level Warning
            $results.Add((New-iSOCPermissionResult -Name $appName -Outcome Skipped -Reason 'no principal id for its identity'))
            continue
        }
        $required = Get-iSOCPlaybookRequiredRole -Properties (Get-iSOCPropertyValue -InputObject $app -Path 'properties')
        if ($required.Count -eq 0) {
            Write-iSOCLog '  [SKIP] No RBAC roles required (no matching connectors/actions).'
            $results.Add((New-iSOCPermissionResult -Name $appName -PrincipalId $identity.PrincipalId -Outcome Skipped -Reason 'needs no RBAC role'))
            continue
        }
        Write-iSOCLog "  Identity: $($identity.Type) | Roles needed: $((@($required.Keys) | Sort-Object) -join ', ')"

        foreach ($role in @($required.Keys)) {
            $result = @{ Name = $appName; PrincipalId = $identity.PrincipalId; Role = $role }
            $roleId = Get-iSOCRoleDefinitionId -Name $role
            $scope = Resolve-iSOCRoleScope -ScopeType $required[$role] -SubscriptionId $ctx.SubscriptionId -ResourceGroup $sentinelGroup -WorkspaceName $ctx.WorkspaceName -KeyVaultName $KeyVaultName
            if (-not $scope) {
                Write-iSOCLog "  [SKIP] $role - no Key Vault name was given (-KeyVaultName)." -Level Warning
                $results.Add((New-iSOCPermissionResult @result -Outcome Skipped -Reason 'no Key Vault named (-KeyVaultName)'))
                continue
            }
            $result.Scope = $scope
            if (@(Find-iSOCRoleAssignment -Assignment $existing.ToArray() -PrincipalId $identity.PrincipalId -RoleDefinitionId $roleId -Scope $scope).Count -gt 0) {
                Write-iSOCLog "  [OK]   $role - already assigned."
                $results.Add((New-iSOCPermissionResult @result -Outcome Unchanged -Reason 'already assigned'))
                continue
            }
            if (-not $PSCmdlet.ShouldProcess($scope, "Assign '$role' to the identity of '$appName'")) {
                $results.Add((New-iSOCPermissionResult @result -Outcome WhatIf -Reason 'would be assigned'))
                continue
            }
            try {
                $created = New-iSOCRoleAssignment -Context $ctx -Scope $scope -RoleDefinitionId $roleId -PrincipalId $identity.PrincipalId
                if ($created -eq 'Exists') {
                    Write-iSOCLog "  [OK]   $role - already assigned (conflict)."
                    $results.Add((New-iSOCPermissionResult @result -Outcome Unchanged -Reason 'already assigned (conflict)'))
                } else {
                    Write-iSOCLog "  [OK]   Assigned: $role" -Level Success
                    $results.Add((New-iSOCPermissionResult @result -Outcome Assigned))
                }
            } catch {
                Write-iSOCLog "  [FAIL] $role - $($_.Exception.Message)" -Level Error
                $results.Add((New-iSOCPermissionResult @result -Outcome Failed -Reason $_.Exception.Message))
            }
        }
    }
    New-iSOCPermissionRun -Results $results.ToArray() -Started $started
}
