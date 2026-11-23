#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 80-workspace.md (part 2 of 2).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Workspace/Write-BlueprintWorkspaceSectionPart2.ps1
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
function Write-BlueprintWorkspaceSectionPart2 {
    <#
    .SYNOPSIS
        Build the figures for and write 80-workspace.md (part 2 of 2).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $features = $Context.features
    $m = $Context.m
    $n = $Context.n
    $sentinelPricingText = $Context.sentinelPricingText
    $timelineBody = $Context.timelineBody
    $usageTrendBlock = $Context.usageTrendBlock
    $workspace = $Context.workspace
    $workspaceAgeVisualLine = $Context.workspaceAgeVisualLine
    $WorkspaceName = $Context.WorkspaceName
    $wsAgeDays = $Context.wsAgeDays
    $wsAgeWarning = $Context.wsAgeWarning
    $wsCreated = $Context.wsCreated
    $wsDefaultDcr = $Context.wsDefaultDcr

    $wsBody = @"
$(Format-Banner -Title 'Workspace Inventory')

## Workspace history

``````mermaid
timeline
$workspaceAgeVisualLine
    title Workspace history: $WorkspaceName
$timelineBody
``````

When the workspace was created and on what terms, and what it holds today. Platform retirements and their dates are on [02-deprecated-legacy-features.md](02-deprecated-legacy-features.md).

## Provenance

| Property | Value |
|---|---|
| Resource ID | ``$($workspace.id)`` |
| Region | $(Format-WorkspaceRegion $workspace.location -WithCode) |
| Created | $(Format-BlueprintDate $wsCreated -Time) |
| Age | $(if ($null -ne $wsAgeDays) { "$(Format-BlueprintPlural $wsAgeDays 'day')$wsAgeWarning" } else { '_(unknown)_' }) |
| Default DCR | $(if ($wsDefaultDcr) { "``$wsDefaultDcr``" } else { '_(none set on the workspace)_' }) |

## SKU and pricing

| Property | Value |
|---|---|
| SKU name | $(Format-WorkspaceSku $workspace.properties.sku.name -WithCode) |
| Microsoft Sentinel pricing | $sentinelPricingText |
| Capacity reservation level | $(if ($workspace.properties.sku.capacityReservationLevel) { "$(Format-BlueprintCount $workspace.properties.sku.capacityReservationLevel) GB a day" } else { '_(n/a)_' }) |
| Default retention | $(Format-BlueprintPlural $workspace.properties.retentionInDays 'day') |
| Daily cap | $(if ($workspace.properties.workspaceCapping.dailyQuotaGb -eq -1 -or $null -eq $workspace.properties.workspaceCapping.dailyQuotaGb) { 'Unlimited' } else { "$(Format-BlueprintGb $workspace.properties.workspaceCapping.dailyQuotaGb) GB" }) |

### Available service tiers

$( $availableTiers = Read-BlueprintRawArray 'available-service-tiers.json'
   $tierRows = $availableTiers | ForEach-Object {
       [pscustomobject]@{
           SkuName            = Format-WorkspaceSku $_.serviceTier -WithCode
           CapacityReservation = if ($_.PSObject.Properties.Name -contains 'capacityReservationLevel') { $_.capacityReservationLevel } else { '' }
           Enabled            = $_.enabled
       }
   }
   Format-BlueprintTable -Items $tierRows -Columns 'SkuName','CapacityReservation','Enabled' )

## Usage telemetry

$( $usage = Read-BlueprintRawArray 'workspace-usage.json' | Select-Object -First 1
   if ($usage) {
@"
| Window | Total GB | Billable GB |
|---|---:|---:|
| Last {lookback} (sum) | $(Format-BlueprintGb $usage.TotalGB) | $(Format-BlueprintGb $usage.BillableTotalGB) |
| Last {lookback} (peak day) | $(Format-BlueprintGb $usage.PeakDailyGB) | $(Format-BlueprintGb $usage.BillablePeakDailyGB) |
| Last {lookback} (average a day) | _(n/a)_ | $(Format-BlueprintGb $usage.BillableAvgDailyGB) |
"@
   } else { '_No usage telemetry captured._' } )
$usageTrendBlock

## Networking + replication

| Property | Value |
|---|---|
| Public ingestion | ``$($workspace.properties.publicNetworkAccessForIngestion)`` |
| Public query | ``$($workspace.properties.publicNetworkAccessForQuery)`` |
| Replication enabled | $(if ($null -eq $workspace.properties.replication -or $null -eq $workspace.properties.replication.enabled) { 'False (not configured)' } else { [string]$workspace.properties.replication.enabled }) |
| Replication location | $(if ($workspace.properties.replication -and $workspace.properties.replication.location) { Format-WorkspaceRegion $workspace.properties.replication.location -WithCode } else { '_(n/a)_' }) |

## Resilience summary

$( $wsProps80 = Get-BlueprintRawProperty $workspace 'properties'
   $repl = Get-BlueprintRawProperty $wsProps80 'replication'
   $replOn = [bool](Get-BlueprintRawProperty $repl 'enabled' $false)
   $plsr = @(Get-BlueprintRawProperty $wsProps80 'privateLinkScopedResources' @()).Count
   $capGb = Get-BlueprintRawProperty (Get-BlueprintRawProperty $wsProps80 'workspaceCapping') 'dailyQuotaGb' -1
   $identityType = [string](Get-BlueprintRawProperty (Get-BlueprintRawProperty $workspace 'identity') 'type' 'None')
   $onb80 = @(Read-BlueprintRawArray 'onboarding-state.json' | Where-Object { $_ }) | Select-Object -First 1
   $cmk80 = Get-BlueprintRawProperty (Get-BlueprintRawProperty $onb80 'properties') 'customerManagedKey'
   $locks80 = @(Read-BlueprintRawArray 'workspace-locks.json' | Where-Object { $_ }).Count
   $resRows = @(
       [pscustomobject]@{ Control = 'Workspace replication'; State = $(if ($replOn) { 'Enabled (' + (Get-BlueprintRegionName ([string](Get-BlueprintRawProperty $repl 'location' '?'))) + ')' } else { 'Not enabled' }); Note = 'Cross-region replica for regional outages; [SAC-PLT-05]' }
       [pscustomobject]@{ Control = 'Private Link scoped resources'; State = $(if ($plsr -gt 0) { "$(Format-BlueprintCount $plsr) linked" } else { 'None' }); Note = 'AMPLS links on the workspace; [SAC-PLT-06] covers public access' }
       [pscustomobject]@{ Control = 'Public ingestion / query'; State = "$(Get-BlueprintRawProperty $wsProps80 'publicNetworkAccessForIngestion' 'Enabled') / $(Get-BlueprintRawProperty $wsProps80 'publicNetworkAccessForQuery' 'Enabled')"; Note = 'Disabled on both means every path goes through Private Link' }
       [pscustomobject]@{ Control = 'Customer-managed key'; State = $(if ($null -eq $cmk80) { 'Unknown (onboarding state not captured)' } elseif ($cmk80) { 'Yes' } else { 'No (platform-managed keys)' }); Note = 'From the Sentinel onboarding state; CMK also needs a dedicated cluster' }
       [pscustomobject]@{ Control = 'Managed identity'; State = $identityType; Note = 'Identity on the workspace resource itself' }
       [pscustomobject]@{ Control = 'Daily cap'; State = $(if ($null -eq $capGb -or [double]$capGb -eq -1) { 'Unlimited' } else { "$(Format-BlueprintGb $capGb) GB a day" }); Note = 'A cap protects spend and drops data once hit; [SAC-LOG-03]' }
       [pscustomobject]@{ Control = 'Resource locks'; State = $(if ($locks80 -gt 0) { Format-BlueprintPlural $locks80 'lock' } else { 'None' }); Note = 'CanNotDelete on the workspace; [SAC-GOV-03]' }
   )
   Format-BlueprintTable -Items $resRows -Columns 'Control','State','Note' )

## Feature flags

| Flag | Value |
|---|---|
| disableLocalAuth | $(Format-FeatureFlag $features 'disableLocalAuth') |
| enableLogAccessUsingOnlyResourcePermissions | $(Format-FeatureFlag $features 'enableLogAccessUsingOnlyResourcePermissions') |
| enableDataExport | $(Format-FeatureFlag $features 'enableDataExport') |
| immediatePurgeDataOn30Days | $(Format-FeatureFlag $features 'immediatePurgeDataOn30Days') |
| clusterResourceId | $(if ($features -and $features.PSObject.Properties.Name -contains 'clusterResourceId' -and $features.clusterResourceId) { "``$($features.clusterResourceId)``, see [82-dedicated-cluster.md](82-dedicated-cluster.md)" } else { '_(none)_' }) |

## Sentinel onboarding

$( $onboarding = @(Read-BlueprintRawArray 'onboarding-state.json' | Where-Object { $_ }) | Select-Object -First 1
   if ($onboarding) {
       $obProps = if ($onboarding.PSObject.Properties['properties']) { $onboarding.properties } else { $null }
       $cmk = if ($obProps -and $obProps.PSObject.Properties['customerManagedKey'] -and $null -ne $obProps.customerManagedKey) { [string]$obProps.customerManagedKey } else { 'not set (platform-managed keys)' }
@"
| Property | Value |
|---|---|
| Onboarding state resource | ``$($onboarding.name)`` |
| Customer-managed key | $cmk |
"@
   } else { '_No Sentinel onboarding state resource was captured; either Sentinel is not enabled on this workspace or the identity cannot read it._' } )

## Resource locks

$( $wsLocks = Read-BlueprintRawArray 'workspace-locks.json'
   $lockRows = $wsLocks | ForEach-Object {
       [pscustomobject]@{ Name = $_.name; Level = $_.properties.level; Notes = $_.properties.notes }
   }
   Format-BlueprintTable -Items $lockRows -Columns 'Name','Level','Notes' )

A non-empty list of locks here is a deletion-protection signal. ``CanNotDelete`` blocks resource deletion; ``ReadOnly`` blocks both modification and deletion.

[Workspace design (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/logs/workspace-design) · [Manage access](https://learn.microsoft.com/azure/azure-monitor/logs/manage-access) · [Replication](https://learn.microsoft.com/azure/azure-monitor/logs/workspace-replication) · [Resource locks](https://learn.microsoft.com/azure/azure-resource-manager/management/lock-resources)
"@
    Write-BlueprintSection '80-workspace.md' $wsBody

    # Left in the render context for later sections.
    if (Get-Variable -Name 'usage' -Scope 0 -ErrorAction Ignore) { $Context.usage = $usage }
}
