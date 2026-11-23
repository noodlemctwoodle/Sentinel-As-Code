#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 86-subscription-context.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/SubscriptionContext/Write-BlueprintSubscriptionContextSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintSubscriptionContextSection {
    <#
    .SYNOPSIS
        Build the figures for and write 86-subscription-context.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $m = $Context.m
    $n = $Context.n
    $name = $Context.name
    $s = $Context.s

    # ---------------------------------------------------------------------------
    # Section: 86 — subscription context
    # ---------------------------------------------------------------------------
    $sub = Read-BlueprintRaw 'subscription.json'
    $rps = Read-BlueprintRawArray 'resource-providers.json'
    $locks = Read-BlueprintRawArray 'subscription-locks.json'
    $policies = Read-BlueprintRawArray 'policy-assignments.json'

    $rpRows = $rps | ForEach-Object { [pscustomobject]@{ Provider = $_.ProviderNamespace; State = $_.RegistrationState } }
    $lockRows = $locks | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Level = $_.Properties.level; Notes = $_.Properties.notes } }
    $polRows = $policies | ForEach-Object {
        # Az.Resources policy-assignment shape varies between versions; surface
        # whichever displayName/scope tier is present.
        $name = $null; $scope = $null
        if ($_.Properties) {
            $name = $_.Properties.DisplayName
            $scope = $_.Properties.Scope
        }
        if (-not $name) { $name = $_.DisplayName }
        if (-not $name) { $name = $_.Name }
        if (-not $scope) { $scope = $_.Scope }
        [pscustomobject]@{ Name = $name; Scope = $scope }
    }

    # Resource-provider registration-state pie for the headline.
    $rpStateCounts = @{}
    foreach ($r in $rpRows) {
        $s = if ($r.State) { [string]$r.State } else { 'Unknown' }
        if (-not $rpStateCounts.ContainsKey($s)) { $rpStateCounts[$s] = 0 }
        $rpStateCounts[$s]++
    }
    $rpPieRows = $rpStateCounts.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | ForEach-Object {
        "    `"$($_.Key)`" : $($_.Value)"
    }
    $rpChartBlock = if ($rpRows.Count -gt 0) {
        @"

## Resource-provider registration state

``````mermaid
pie showData title Required resource providers: registration state
$($rpPieRows -join [Environment]::NewLine)
``````

[SAC-PLT-09] fires whenever any required provider is not in the `Registered` state. The pie surfaces that ratio at a glance.
"@
    } else { '' }

    # Who the collector ran as. Snapshots from before the account was recorded
    # say so rather than showing a blank.
    $runCtx86 = Read-BlueprintRaw 'run-context.json'
    $identityBlock = if ($runCtx86 -and $runCtx86.PSObject.Properties['Account']) {
        @"
| | |
|---|---|
| Account | ``$([string]$runCtx86.Account)`` |
| Type | $([string](Get-BlueprintRawProperty $runCtx86 'AccountType' 'Unknown')) |
"@
    } else { '_Not recorded in this snapshot._' }

    Write-BlueprintSection '86-subscription-context.md' (@"
$(Format-Banner -Title "Subscription and Tenant Context")

## Subscription

| | |
|---|---|
| Name | $($sub.Name) |
| ID   | ``$($sub.Id)`` |
| Tenant ID | ``$($sub.TenantId)`` |
| State | $($sub.State) |

## Signed-in identity

The identity the collector ran as: a pipeline signs in as its service connection's service principal or managed identity, a local run as the person running it. Every capture reflects what this identity could read.

$identityBlock
$rpChartBlock

## Resource providers

$(Format-BlueprintTable -Items $rpRows -Columns 'Provider','State')

## Locks

$(Format-BlueprintTable -Items $lockRows -Columns 'Name','Level','Notes')

## Sentinel-relevant policy assignments

$(Format-BlueprintTable -Items $polRows -Columns 'Name','Scope')

[Resource providers (Microsoft Learn)](https://learn.microsoft.com/azure/azure-resource-manager/management/resource-providers-and-types)
"@)

    # Left in the render context for later sections.
    $Context.r = $r
    if (Get-Variable -Name 's' -Scope 0 -ErrorAction Ignore) { $Context.s = $s }
}
