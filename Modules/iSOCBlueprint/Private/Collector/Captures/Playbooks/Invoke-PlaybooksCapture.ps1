#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'playbooks': writes playbooks.json, rbac-playbook-mi.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Playbooks/Invoke-PlaybooksCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Invoke-PlaybooksCapture {
    <#
    .SYNOPSIS
        Capture 'playbooks': writes playbooks.json, rbac-playbook-mi.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $PlaybookResourceGroup = $Context.PlaybookResourceGroup
    $ResourceGroup = $Context.ResourceGroup
    $SubscriptionId = $Context.SubscriptionId
    $workspaceResourceId = $Context.workspaceResourceId

    # Use the configurable playbook RG when set (Sentinel-As-Code convention),
    # otherwise default to the Sentinel resource group.
    #
    # Why REST and not Get-AzLogicApp: the cmdlet's list-style call returns
    # PSWorkflow objects without the `Identity` property populated even when
    # the workflow has a managed identity attached. Verified against the live
    # workspace where the REST API saw `identity.principalId` for a playbook
    # the cmdlet listed without any Identity at all.
    $playbookRg = if ($PlaybookResourceGroup) { $PlaybookResourceGroup } else { $ResourceGroup }
    $workflows = Invoke-SentinelRest `
        -Path "/subscriptions/$SubscriptionId/resourceGroups/$playbookRg/providers/Microsoft.Logic/workflows" `
        -ApiVersion '2016-06-01'
    $script:Workflows = @($workflows)
    Save-Json -FileName 'playbooks.json' -Data $workflows

    # Resolve the per-playbook MI workspace-scoped role assignments.
    #
    # The REST shape of `identity` depends on the assignment type:
    #   SystemAssigned                  : identity.principalId at top level
    #   UserAssigned                    : identity.userAssignedIdentities.<resourceId>.principalId (no top-level principalId)
    #   SystemAssignedAndUserAssigned   : both
    # Strict mode forbids reading a property that isn't present, so every read
    # is guarded with PSObject.Properties.Name -contains '<name>'. A workflow
    # with no managed identity has the `identity` member absent entirely.
    $miAssignments = @()
    $rbacTried = 0
    $rbacFailures = @()
    foreach ($wf in @($workflows)) {
        if (-not ($wf.PSObject.Properties.Name -contains 'identity')) { continue }
        $mi = $wf.identity
        if ($null -eq $mi) { continue }

        $principalIds = New-Object System.Collections.Generic.List[string]
        if ($mi.PSObject.Properties.Name -contains 'principalId' -and -not [string]::IsNullOrWhiteSpace($mi.principalId)) {
            $principalIds.Add([string]$mi.principalId)
        }
        if ($mi.PSObject.Properties.Name -contains 'userAssignedIdentities' -and $null -ne $mi.userAssignedIdentities) {
            foreach ($uaProp in $mi.userAssignedIdentities.PSObject.Properties) {
                $ua = $uaProp.Value
                if ($null -ne $ua -and $ua.PSObject.Properties.Name -contains 'principalId' -and -not [string]::IsNullOrWhiteSpace($ua.principalId)) {
                    $principalIds.Add([string]$ua.principalId)
                }
            }
        }
        if ($principalIds.Count -eq 0) { continue }

        foreach ($principalId in ($principalIds | Sort-Object -Unique)) {
            $rbacTried++
            try {
                $assignments = Get-AzRoleAssignment -ObjectId $principalId -ErrorAction SilentlyContinue
                $workspaceRoles = @($assignments | Where-Object { $_.Scope -eq $workspaceResourceId } | Select-Object -ExpandProperty RoleDefinitionName)
                $miAssignments += [pscustomobject]@{
                    Playbook         = $wf.name
                    PrincipalId      = $principalId
                    AllAssignments   = $assignments
                    WorkspaceRoles   = $workspaceRoles
                }
            } catch {
                $rbacFailures += [pscustomobject]@{ Name = [string]$wf.name; Message = $_.Exception.Message }
            }
        }
    }
    # One line for the identities that could not be read, not one each.
    foreach ($issue in @(Write-PartialCaptureIssue -Label 'playbooks' -What 'the role assignments of' -Noun 'playbook identity', 'playbook identities' -Total $rbacTried -Failures $rbacFailures)) { $script:CaptureErrors.Add($issue) }
    Save-Json -FileName 'rbac-playbook-mi.json' -Data $miAssignments
}
