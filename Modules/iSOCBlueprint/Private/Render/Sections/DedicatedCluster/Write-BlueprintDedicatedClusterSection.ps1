#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 82-dedicated-cluster.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/DedicatedCluster/Write-BlueprintDedicatedClusterSection.ps1
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
function Write-BlueprintDedicatedClusterSection {
    <#
    .SYNOPSIS
        Build the figures for and write 82-dedicated-cluster.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $m = $Context.m
    $n = $Context.n

    # ---------------------------------------------------------------------------
    # Section: 82 — dedicated cluster
    # ---------------------------------------------------------------------------
    $cluster = Read-BlueprintRaw 'dedicated-cluster.json'
    # An empty capture ({}) means no cluster; reading it as one wrote a table of
    # blanks whose empty code spans broke the table.
    if ($cluster -and $cluster.PSObject.Properties['name'] -and $cluster.name) {
        $clusterBody = @"
$(Format-Banner -Title "Dedicated Cluster")

| Property | Value |
|---|---|
| Name | ``$($cluster.name)`` |
| Capacity reservation | $(Format-BlueprintCount $cluster.properties.sku.capacity) GB a day |
| Billing type | $($cluster.properties.billingType) |
| Double encryption | $($cluster.properties.isDoubleEncryptionEnabled) |
| Availability zones | $($cluster.properties.isAvailabilityZonesEnabled) |
| CMK key vault | ``$($cluster.properties.keyVaultProperties.keyVaultUri)`` |
| Identity type | $($cluster.identity.type) |
| Associated workspaces | $(Format-BlueprintCount ($cluster.properties.associatedWorkspaces | Measure-Object).Count) |

[Dedicated clusters (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/logs/logs-dedicated-clusters) · [Customer-managed keys](https://learn.microsoft.com/azure/azure-monitor/logs/customer-managed-keys)
"@
        Write-BlueprintSection '82-dedicated-cluster.md' $clusterBody
    } else {
        Write-BlueprintSection '82-dedicated-cluster.md' (@"
$(Format-Banner -Title "Dedicated Cluster")

_No dedicated cluster linked to this workspace._

For workspaces sustaining more than 500 GB a day, [a dedicated cluster](https://learn.microsoft.com/azure/azure-monitor/logs/logs-dedicated-clusters) unlocks cluster-level commitment pricing, customer-managed keys and availability-zone redundancy.
"@)
    }
}
