#Requires -Version 7.6

<#
.SYNOPSIS
    Give each identity Monitoring Metrics Publisher on a data collection rule.

.DESCRIPTION
    So it can post to the rule's logs ingestion endpoint. A grant that fails
    is a warning with the command to run by hand.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Grant-iSOCDcrIngestionRole.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Grant-iSOCDcrIngestionRole {
    <#
    .SYNOPSIS
        Give each identity Monitoring Metrics Publisher on a data collection
        rule.

    .DESCRIPTION
        For each identity (an application id or any principal's object id,
        resolved by Resolve-iSOCPrincipal): when it already holds the role
        on the rule or above, it is counted as granted; otherwise, asking
        ShouldProcess, the role is assigned at the rule. A grant that fails
        (assigning needs Owner or User Access Administrator on the rule) is
        a warning with the command to run by hand, and the run goes on.
        Data-plane RBAC can take minutes to apply.

    .PARAMETER Context
        The workspace context.

    .PARAMETER DcrId
        The rule's resource id.

    .PARAMETER DcrName
        The rule's name, for the messages.

    .PARAMETER Identity
        The identities that will send to the rule.

    .OUTPUTS
        [string[]] The identities that hold the role.

    .EXAMPLE
        Grant-iSOCDcrIngestionRole -Context $ctx -DcrId $dcrId -DcrName dcr-myapp -Identity $appId
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $DcrId,

        [Parameter(Mandatory)]
        [string] $DcrName,

        [Parameter(Mandatory)]
        [string[]] $Identity
    )

    $roleName = 'Monitoring Metrics Publisher'
    $roleId = Get-iSOCRoleDefinitionId -Name $roleName
    Write-iSOCLog "Granting $roleName on the DCR"

    foreach ($id in $Identity) {
        try {
            $principal = Resolve-iSOCPrincipal -Context $Context -Identity $id
            $assignments = @(Get-iSOCRoleAssignment -Context $Context -PrincipalId $principal.ObjectId)
            $existing = @(Find-iSOCRoleAssignment -Assignment $assignments -PrincipalId $principal.ObjectId -RoleDefinitionId $roleId -Scope $DcrId)

            if ($existing.Count -gt 0) {
                Write-iSOCLog "  $id already holds $roleName." -Level Success
                $id
            } elseif ($PSCmdlet.ShouldProcess("$DcrName / $id", "Grant $roleName")) {
                $outcome = New-iSOCRoleAssignment -Context $Context -Scope $DcrId -RoleDefinitionId $roleId -PrincipalId $principal.ObjectId -PrincipalType $principal.PrincipalType
                if ($outcome -eq 'Exists') { Write-iSOCLog "  $id already holds $roleName." -Level Success }
                else { Write-iSOCLog "  Granted $roleName to $id. Data-plane RBAC can take a few minutes to take effect." -Level Success }
                $id
            }
        } catch {
            Write-iSOCLog "  Could not grant $roleName to $id (need Owner or User Access Administrator on the DCR): $($_.Exception.Message.Split([char]10)[0])" -Level Warning
            Write-iSOCLog "  Grant it manually: New-AzRoleAssignment -ObjectId <objectId> -RoleDefinitionName '$roleName' -Scope $DcrId" -Level Warning
        }
    }
}
