#Requires -Version 7.6

<#
.SYNOPSIS
    Build the ingestion estate flow and its table list.

.DESCRIPTION
    A step of the SharePoint site build. Steps run in order and pass their results
    to later ones through the build context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Steps/Build-SiteEstateFlow.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Build-SiteEstateFlow {
    <#
    .SYNOPSIS
        Build the ingestion estate flow and its table list.

    .PARAMETER Context
        The build context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the build context.
    $cost = $Context.cost
    $dataLake = $Context.dataLake
    $healthSum = $Context.healthSum
    $n = $Context.n
    $volumes = $Context.volumes
    $wsRaw = $Context.wsRaw

    # ---- Data lake enrolment (shared by the billing flow and the lake panel) ----
    $wsProps = if ($wsRaw -and $wsRaw.PSObject.Properties['properties']) { $wsRaw.properties } else { $null }
    $wsTablesRaw = Read-SiteRawArray 'workspace-tables.json'
    $wsTableByName = @{}
    foreach ($t in $wsTablesRaw) { if ($t -and $t.PSObject.Properties['name'] -and $t.name) { $wsTableByName[[string]$t.name] = $t } }
    $unifiedBilling = [bool]($wsProps -and $wsProps.PSObject.Properties['features'] -and $wsProps.features -and
        $wsProps.features.PSObject.Properties['unifiedSentinelBillingOnly'] -and $wsProps.features.unifiedSentinelBillingOnly)
    $lakePlanTables = @(
        $wsTablesRaw |
            Where-Object {
                $_ -and $_.PSObject.Properties['properties'] -and $_.properties -and $_.properties.PSObject.Properties['plan'] -and $_.properties.plan -eq
                'DataLake'
            }
    ).Count
    $lakeEnrolled = ($dataLake.Count -gt 0) -or $unifiedBilling -or ($lakePlanTables -gt 0)
    # The flow's plan column names the lake tier a table lands in, so an
    # enrolled workspace shows its lake instead of a single "Analytics plan"
    # box. Basic and Auxiliary tables keep their plan name: they are neither
    # analytics-tier nor lake-mirrored.
    $script:FlowTierLabel = @{
        AnalyticsOnly    = 'Analytics plan'
        MirroredOnly     = 'Analytics + Lake mirror'
        MirroredExtended = 'Analytics + Lake extended'
        LakeOnly         = 'Data lake only'
    }

    $flowNodes = @()
    $flowLinks = @()
    if ($cost -and $cost.PSObject.Properties['AllTablesByCost']) {
        $ingest = @($cost.AllTablesByCost | Where-Object { $_ -and [double]$_.Gb30d -gt 0 } | Sort-Object { [double]$_.Gb30d } -Descending)
        $topN = 9
        $top = @($ingest | Select-Object -First $topN)
        $rest = @($ingest | Select-Object -Skip $topN)

        # Each table row carries one or more parts: (plan label, gb, billed gb).
        # A named table has one part; the long-tail node has one part per plan
        # label so its ribbons fan out to every tier the tail lands in.
        $tableRows = @()
        foreach ($t in $top) {
            $gb = [math]::Round([double]$t.Gb30d, 3)
            $billedGb = Get-FlowBilledGb $t $gb
            $tableRows += [ordered]@{
                table  = $t.Table
                family = (Get-TableFamily $t.Table)
                gb     = $gb
                parts  = @([ordered]@{ plan = (Get-FlowPlanLabel -Table $t.Table -Plan ([string]$t.Plan)); gb = $gb; billedGb = $billedGb })
            }
        }
        if ($rest.Count -gt 0) {
            $restParts = [ordered]@{}
            foreach ($t in $rest) {
                $label = Get-FlowPlanLabel -Table $t.Table -Plan ([string]$t.Plan)
                if (-not $restParts.Contains($label)) { $restParts[$label] = [ordered]@{ plan = $label; gb = 0.0; billedGb = 0.0 } }
                $restParts[$label].gb += [double]$t.Gb30d
                $restParts[$label].billedGb += Get-FlowBilledGb $t ([double]$t.Gb30d)
            }
            $restGb = 0.0
            foreach ($pt in $restParts.Values) { $pt.gb = [math]::Round($pt.gb, 3); $pt.billedGb = [math]::Round($pt.billedGb, 3); $restGb += $pt.gb }
            $tableRows += [ordered]@{ table = "Other (+$($rest.Count))"; family = 'Other'; gb = [math]::Round($restGb, 3); parts = @($restParts.Values) }
        }

        # Nodes: families (col0), tables (col1), plans and lake tiers (col2), billed buckets (col3)
        $famAgg = @{}
        foreach ($row in $tableRows) { if (-not $famAgg.ContainsKey($row.family)) { $famAgg[$row.family] = 0.0 }; $famAgg[$row.family] += $row.gb }
        $planAgg = @{}; $planBucket = @{}
        $bucketAgg = @{ 'Billed' = 0.0; 'Grant eligible' = 0.0 }
        foreach ($row in $tableRows) {
            foreach ($pt in $row.parts) {
                if (-not $planAgg.ContainsKey($pt.plan)) { $planAgg[$pt.plan] = 0.0 }
                $planAgg[$pt.plan] += $pt.gb
                $freeGb = [math]::Round($pt.gb - $pt.billedGb, 3)
                $bucketAgg['Billed'] += $pt.billedGb; $bucketAgg['Grant eligible'] += $freeGb
                foreach ($pair in @(@('Billed', $pt.billedGb), @('Grant eligible', $freeGb))) {
                    if ($pair[1] -le 0) { continue }
                    $key = "$($pt.plan)|$($pair[0])"
                    if (-not $planBucket.ContainsKey($key)) { $planBucket[$key] = 0.0 }
                    $planBucket[$key] += $pair[1]
                }
            }
        }

        foreach ($fam in ($famAgg.Keys | Sort-Object { $famAgg[$_] } -Descending)) {
            $flowNodes += [ordered]@{ id = "f:$fam"; col = 0; label = $fam; value = [math]::Round($famAgg[$fam], 3) }
        }
        foreach ($row in $tableRows) {
            $flowNodes += [ordered]@{ id = "t:$($row.table)"; col = 1; label = $row.table; value = $row.gb }
        }
        foreach ($pl in ($planAgg.Keys | Sort-Object { $planAgg[$_] } -Descending)) {
            $flowNodes += [ordered]@{ id = "p:$pl"; col = 2; label = $pl; value = [math]::Round($planAgg[$pl], 3); lake = ($pl -like '*Lake*') }
        }
        foreach ($bk in 'Billed', 'Grant eligible') {
            if ($bucketAgg[$bk] -gt 0) { $flowNodes += [ordered]@{ id = "b:$bk"; col = 3; label = $bk; value = [math]::Round($bucketAgg[$bk], 3) } }
        }

        # Links
        foreach ($row in $tableRows) {
            $flowLinks += [ordered]@{ source = "f:$($row.family)"; target = "t:$($row.table)"; value = $row.gb }
            foreach ($pt in $row.parts) {
                $flowLinks += [ordered]@{ source = "t:$($row.table)"; target = "p:$($pt.plan)"; value = $pt.gb }
            }
        }
        foreach ($key in $planBucket.Keys) {
            $parts = $key -split '\|', 2
            $flowLinks += [ordered]@{ source = "p:$($parts[0])"; target = "b:$($parts[1])"; value = [math]::Round($planBucket[$key], 3) }
        }
    }
    $flow = [ordered]@{ nodes = $flowNodes; links = $flowLinks }
    # Every ingesting table with its family, plan label and billed share, so the
    # dashboard can rebuild the flow for one family or for every table on click
    # instead of folding the long tail into an "Other" node for good.
    $flowTables = @()
    if ($cost -and $cost.PSObject.Properties['AllTablesByCost']) {
        foreach ($t in @($cost.AllTablesByCost | Where-Object { $_ -and [double]$_.Gb30d -gt 0 } | Sort-Object { [double]$_.Gb30d } -Descending)) {
            $gb = [math]::Round([double]$t.Gb30d, 3)
            $flowTables += [ordered]@{
                table    = [string]$t.Table
                family   = (Get-TableFamily $t.Table)
                plan     = (Get-FlowPlanLabel -Table ([string]$t.Table) -Plan ([string]$t.Plan))
                gb       = $gb
                billedGb = (Get-FlowBilledGb $t $gb)
            }
        }
    }

    # ---- Top alerting rules (by 30d volume) ----
    $topRules = @()
    foreach ($v in ($volumes | Where-Object { $_ })) {
        $topRules += [ordered]@{ name = $v.AlertName; product = $v.ProductName; severity = $v.AlertSeverity; alerts = [int]$v.Alerts }
    }

    # ---- Operational health ----
    $healthTotal = 0.0; $healthOk = 0.0
    foreach ($h in $healthSum) { if (-not $h) { continue }; $n = [double]$h.LogCount; $healthTotal += $n; if ($h.Status -eq 'Success') { $healthOk += $n } }
    $healthPct = if ($healthTotal -gt 0) { [math]::Round(100.0 * $healthOk / $healthTotal, 1) } else { 0 }

    # Left in the build context for later steps.
    $Context.fam = $fam
    $Context.flow = $flow
    $Context.flowTables = $flowTables
    if (Get-Variable -Name 'gb' -Scope 0 -ErrorAction Ignore) { $Context.gb = $gb }
    $Context.healthPct = $healthPct
    $Context.healthTotal = $healthTotal
    if (Get-Variable -Name 'key' -Scope 0 -ErrorAction Ignore) { $Context.key = $key }
    $Context.lakeEnrolled = $lakeEnrolled
    $Context.lakePlanTables = $lakePlanTables
    if (Get-Variable -Name 'n' -Scope 0 -ErrorAction Ignore) { $Context.n = $n }
    if (Get-Variable -Name 'tableRows' -Scope 0 -ErrorAction Ignore) { $Context.tableRows = $tableRows }
    $Context.topRules = $topRules
    $Context.unifiedBilling = $unifiedBilling
    $Context.v = $v
    $Context.wsTableByName = $wsTableByName
    $Context.wsTablesRaw = $wsTablesRaw
}
