#Requires -Version 7.6

<#
.SYNOPSIS
    Read the main captures and build the workspace, counts and cost figures.

.DESCRIPTION
    A step of the SharePoint site build. Steps run in order and pass their results
    to later ones through the build context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Steps/Build-SiteWorkspaceModel.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Build-SiteWorkspaceModel {
    <#
    .SYNOPSIS
        Read the main captures and build the workspace, counts and cost figures.

    .PARAMETER Context
        The build context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the build context.
    $lookbackDays = $Context.lookbackDays
    $recentDays = $Context.recentDays
    $runCtx = $Context.runCtx
    $WorkspaceName = $Context.WorkspaceName

    # ---------------------------------------------------------------------------
    # Build the dashboard model
    # ---------------------------------------------------------------------------

    $wsRaw     = Read-SiteRaw 'workspace.json'
    $cost      = Read-SiteRaw 'cost-estimate.json'
    $gap       = Read-SiteRawArray 'gap-analysis.json'
    $connClass = Read-SiteRawArray 'data-connectors-classic.json'
    $alertRaw  = Read-SiteRawArray 'alert-rules.json'
    $volumes   = Read-SiteRawArray 'analytics-rule-volumes.json'
    $healthSum = Read-SiteRawArray 'sentinel-health-summary.json'
    $rbacWs    = Read-SiteRawArray 'rbac-workspace.json'
    $dataLake  = Read-SiteRawArray 'sentinel-data-lake.json'

    $wsProps = if ($wsRaw) { $wsRaw.properties } else { $null }

    # ---- Headline / workspace ----
    $generatedUtc = if ($runCtx -and $runCtx.StartedAtUtc) { ([datetime]$runCtx.StartedAtUtc).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC' } else { '' }
    $workspace = [ordered]@{
        name            = $WorkspaceName
        id              = if ($wsProps) { $wsProps.customerId } else { '' }
        region          = if ($wsRaw) { $wsRaw.location } else { '' }
        sku             = if ($wsProps -and $wsProps.sku) { $wsProps.sku.name } else { '' }
        # The commitment tier's GB a day, on a CapacityReservation workspace.
        skuCapacity     = if ($wsProps -and $wsProps.sku -and $wsProps.sku.PSObject.Properties['capacityReservationLevel'] -and $wsProps.sku.capacityReservationLevel) { [int]$wsProps.sku.capacityReservationLevel } else { 0 }
        retentionDays   = if ($wsProps) { [int]$wsProps.retentionInDays } else { 0 }
        dailyCap        = if ($wsProps -and $wsProps.workspaceCapping -and $wsProps.workspaceCapping.dailyQuotaGb -ge 0) { "$($wsProps.workspaceCapping.dailyQuotaGb) GB" } else { 'Unlimited' }
        pnaIngestion    = if ($wsProps) { $wsProps.publicNetworkAccessForIngestion } else { '' }
        pnaQuery        = if ($wsProps) { $wsProps.publicNetworkAccessForQuery } else { '' }
        subscriptionId  = if ($runCtx) { $runCtx.SubscriptionId } else { '' }
        resourceGroup   = if ($runCtx) { $runCtx.ResourceGroup } else { '' }
        generatedUtc    = $generatedUtc
        blueprintVer   = if ($runCtx) { $runCtx.BlueprintVersion } else { '' }
    }
    $window = [ordered]@{ days = $lookbackDays; recentDays = $recentDays }

    # ---- Counts ----
    $rulesEnabled = @($alertRaw | Where-Object { $_.properties -and $_.properties.enabled }).Count
    $counts = [ordered]@{
        connectors      = Measure-Count $connClass
        rulesTotal      = Measure-Count $alertRaw
        rulesEnabled    = $rulesEnabled
        automationRules = Measure-Count (Read-SiteRaw 'automation-rules.json')
        watchlists      = Measure-Count (Read-SiteRaw 'watchlists.json')
        workbooks       = Measure-Count (Read-SiteRaw 'workbooks-saved.json')
        dcrs            = Measure-Count (Read-SiteRaw 'dcrs.json')
        tables          = Measure-Count (Read-SiteRaw 'tables-with-data.json')
        rbac            = Measure-Count $rbacWs
        hunting         = Measure-Count (Read-SiteRaw 'hunting-queries.json')
        playbookMi      = Measure-Count (Read-SiteRaw 'rbac-playbook-mi.json')
    }

    # ---- Cost ----
    $costModel = $null
    if ($cost) {
        $costModel = [ordered]@{
            monthlyTotal = [math]::Round([double]$cost.MonthlyTotal, 2)
            currency     = $cost.Currency
            asOf         = if ($cost.AsOfUtc) { ([datetime]$cost.AsOfUtc).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC' } else { '' }
            byPlan       = @()
            topTables    = @()
            allTables    = @()
        }
        if ($cost.ByPlan) {
            foreach ($p in $cost.ByPlan.PSObject.Properties) {
                $costModel.byPlan += [ordered]@{ plan = $p.Name; gb30d = [math]::Round([double]$p.Value.Gb30d, 2); cost = [math]::Round([double]$p.Value.MonthlyCost, 2) }
            }
        }
        foreach ($t in @($cost.Top10TablesByCost | Where-Object { $_ })) {
            $costModel.topTables += [ordered]@{ table = $t.Table; plan = $t.Plan; gb30d = [math]::Round([double]$t.Gb30d, 2); cost = [math]::Round([double]$t.MonthlyCost, 2) }
        }
        if ($cost.PSObject.Properties['AllTablesByCost']) {
            foreach ($t in @($cost.AllTablesByCost | Where-Object { $_ -and [double]$_.Gb30d -gt 0 } | Sort-Object { [double]$_.Gb30d } -Descending)) {
                $costModel.allTables += [ordered]@{ table = $t.Table; plan = $t.Plan; gb30d = [math]::Round([double]$t.Gb30d, 2); cost = [math]::Round([double]$t.MonthlyCost, 2) }
            }
        }
    }

    # Left in the build context for later steps.
    $Context.alertRaw = $alertRaw
    $Context.cost = $cost
    $Context.costModel = $costModel
    $Context.counts = $counts
    $Context.dataLake = $dataLake
    $Context.gap = $gap
    $Context.generatedUtc = $generatedUtc
    $Context.healthSum = $healthSum
    $Context.p = $p
    $Context.rulesEnabled = $rulesEnabled
    $Context.volumes = $volumes
    $Context.window = $window
    $Context.workspace = $workspace
    $Context.wsRaw = $wsRaw
}
