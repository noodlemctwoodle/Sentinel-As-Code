#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'policy-assignments': writes policy-assignments.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Subscription/Invoke-PolicyAssignmentsCapture.ps1
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

function Invoke-PolicyAssignmentsCapture {
    <#
    .SYNOPSIS
        Capture 'policy-assignments': writes policy-assignments.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $SubscriptionId = $Context.SubscriptionId

    # Get-AzPolicyAssignment shape changed across Az.Resources versions: older
    # builds expose .Properties.DisplayName, newer ones expose .DisplayName at
    # the top level. Probe both rather than tying to a single Az version.
    $assigns = Get-AzPolicyAssignment -Scope "/subscriptions/$SubscriptionId" -ErrorAction SilentlyContinue |
        Where-Object {
            $name = $null
            if ($_.PSObject.Properties.Name -contains 'Properties' -and $_.Properties) {
                $name = $_.Properties.DisplayName
            }
            if (-not $name -and $_.PSObject.Properties.Name -contains 'DisplayName') {
                $name = $_.DisplayName
            }
            if (-not $name) { $name = $_.Name }
            ($name -as [string]) -match 'Sentinel|Log Analytics|Monitor|retention|workspace'
        }
    Save-Json -FileName 'policy-assignments.json' -Data $assigns
}
