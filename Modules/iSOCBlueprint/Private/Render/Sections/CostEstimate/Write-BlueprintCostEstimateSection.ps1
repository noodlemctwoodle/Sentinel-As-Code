#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 84-cost-estimate.md (part 1 of 2).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/CostEstimate/Write-BlueprintCostEstimateSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintCostEstimateSection {
    <#
    .SYNOPSIS
        Build the figures for and write 84-cost-estimate.md (part 1 of 2).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $cost = $Context.cost
    $name = $Context.name

    # ---------------------------------------------------------------------------
    # Section: 84 — cost estimate
    # ---------------------------------------------------------------------------
    if ($cost) {
        $planRows = $cost.ByPlan.PSObject.Properties | ForEach-Object {
            [pscustomobject]@{ Plan = $_.Name; Gb30d = [math]::Round($_.Value.Gb30d, 2); MonthlyCost = $_.Value.MonthlyCost }
        }
        # The same rows for the table: the amounts as the dashboard writes them.
        $planTableRows = @(
            $planRows |
                ForEach-Object { [pscustomobject]@{ Plan = $_.Plan; Gb30d = $_.Gb30d; MonthlyCost = (Format-BlueprintMoney $_.MonthlyCost $cost.Currency) } }
        )
        # How the workspace is priced, its commitment tier, and the data grants
        # that may cover part of it; an estimate from before these were reported
        # has none of them.
        $costField = { param([string]$Name) if ($cost.PSObject.Properties.Name -contains $Name) { $cost.$Name } else { $null } }
        $costTier = & $costField 'CommitmentTier'
        # An estimate worked out before methodology 2.0.0 keeps the method it used.
        $costMethodV2 = $false
        try { $costMethodV2 = [version][string](& $costField 'MethodologyVersion') -ge [version]'2.0.0' } catch { $costMethodV2 = $false }
        $costPricing = [string](& $costField 'PricingModel')
        $costTierText = if ($costTier) {
            "The workspace is on the **$(Format-BlueprintCount $costTier.Level) GB a day commitment tier**: $(Format-BlueprintMoney $costTier.DailyPrice $cost.Currency) a day, an effective $(Format-UnitPrice $costTier.EffectivePerGb $cost.Currency) per GB. Analytics ingest averaged $(Format-BlueprintGb $costTier.DailyAverageGb) GB a day, $($costTier.Utilisation)% of the tier: the tier is paid in full below it, and use above it is billed at its effective rate."
        } elseif ($costPricing -eq 'Simplified') {
            'The workspace is on pay-as-you-go, priced at the simplified Microsoft Sentinel rate, which covers Log Analytics ingestion as well.'
        } elseif ($costPricing -eq 'Classic') {
            'The price list had no simplified Microsoft Sentinel rate, so Analytics data is priced at the classic pair: Log Analytics ingestion plus Sentinel analysis.'
        } else { '' }
        $costCurrencySource = [string](& $costField 'CurrencySource')
        $costCurrencyText = switch ($costCurrencySource) {
            'Region' {
                "Prices are in $($cost.Currency), taken from the workspace's region ($(Get-BlueprintRegionName $cost.Region)); billing currency follows the billing account, so set the collector's ``-Currency`` (the pipelines' currency setting) when that is wrong."
            }
            'Parameter' { "Prices are in $($cost.Currency), as the run's ``-Currency`` setting asked." }
            default { '' }
        }
        $grantRows = @(@(& $costField 'BenefitEligible') | Where-Object { $_ } | ForEach-Object {
                [pscustomobject]@{
                    Grant       = [string]$_.Benefit
                    Allowance   = [string]$_.Allowance
                    Gb30d       = $_.Gb30d
                    MonthlyCost = (Format-BlueprintMoney $_.MonthlyCost $cost.Currency)
                    Tables      = [string]$_.Tables
                }
            })

        # ---------------------------------------------------------------------

        # Use the full per-table cost list when the exporter wrote it; fall back
        # to Top-10 for older captures so the chart still renders.
        $allTables = if ($cost.PSObject.Properties.Name -contains 'AllTablesByCost' -and $cost.AllTablesByCost) {
            @($cost.AllTablesByCost)
        } else {
            @($cost.Top10TablesByCost)
        }

        $flowFiltered = New-Object System.Collections.Generic.List[object]
        foreach ($t in $allTables) {
            $gb = [double]$t.Gb30d
            if ($gb -lt 0.01) { continue }
            # The rate each table bills at is its plan's.
            $tier = switch ([string]$t.Plan) {
                'Basic' { 'Basic rate' } 'Auxiliary' { 'Auxiliary rate' } 'DataLake' { 'Data lake rate' } default { 'Analytics rate' }
            }
            $flowFiltered.Add([pscustomobject]@{
                    Table  = $t.Table
                    Gb     = $gb
                    Source = (Get-BlueprintCostSource $t.Table)
                    Tier   = $tier
                })
        }

        # Decide which tables keep their own middle-column node. On a busy
        # workspace with ~80+ tables the Sankey middle column becomes an
        # unreadable wall — fix by collapsing the cost-insignificant tail into
        # per-source bucket nodes. Rule: tables in the top 90% of billable GB
        # stay individual; the remainder collapse to "<source> tail (N)".
        # Workspaces with ≤25 tables skip the collapse entirely.
        $totalGb = ($flowFiltered | Measure-Object -Property Gb -Sum).Sum
        $sorted = $flowFiltered | Sort-Object -Property Gb -Descending
        $keepIndividual = @{}
        if ($sorted.Count -le 25 -or $totalGb -le 0) {
            foreach ($r in $sorted) { $keepIndividual[$r.Table] = $true }
        } else {
            $cum = 0.0
            $threshold = $totalGb * 0.90
            foreach ($r in $sorted) {
                $keepIndividual[$r.Table] = $true
                $cum += $r.Gb
                if ($cum -ge $threshold) { break }
            }
        }

        # Promote single-occupant tail sources — a bucket of one is uglier than
        # just showing the table.
        $tailCount = @{}
        foreach ($r in $flowFiltered) {
            if (-not $keepIndividual.ContainsKey($r.Table)) {
                if (-not $tailCount.ContainsKey($r.Source)) { $tailCount[$r.Source] = 0 }
                $tailCount[$r.Source]++
            }
        }
        foreach ($r in $flowFiltered) {
            if (-not $keepIndividual.ContainsKey($r.Table) -and $tailCount[$r.Source] -lt 2) {
                $keepIndividual[$r.Table] = $true
            }
        }
        # Recompute counts after promotions so the bucket labels show the
        # accurate post-promotion count.
        $tailCount = @{}
        foreach ($r in $flowFiltered) {
            if (-not $keepIndividual.ContainsKey($r.Table)) {
                if (-not $tailCount.ContainsKey($r.Source)) { $tailCount[$r.Source] = 0 }
                $tailCount[$r.Source]++
            }
        }

        $bySourceTable = @{}
        $byTableTier = @{}
        foreach ($r in $flowFiltered) {
            $tableNode = if ($keepIndividual.ContainsKey($r.Table)) {
                $r.Table
            } else {
                "$($r.Source) tail ($($tailCount[$r.Source]))"
            }
            $stKey = "$($r.Source)||$tableNode"
            $ttKey = "$tableNode||$($r.Tier)"
            if (-not $bySourceTable.ContainsKey($stKey)) { $bySourceTable[$stKey] = 0.0 }
            if (-not $byTableTier.ContainsKey($ttKey)) { $byTableTier[$ttKey] = 0.0 }
            $bySourceTable[$stKey] += $r.Gb
            $byTableTier[$ttKey] += $r.Gb
        }

        $flowRowsList = New-Object System.Collections.Generic.List[string]
        # Largest flows first, then by name: hashtable order changes between runs.
        foreach ($k in @($bySourceTable.Keys | Sort-Object @{ Expression = { $bySourceTable[$_] }; Descending = $true }, @{ Expression = { $_ } })) {
            $parts = $k -split '\|\|'
            $flowRowsList.Add("$($parts[0]),$($parts[1]),$([math]::Round($bySourceTable[$k], 3))")
        }
        foreach ($k in @($byTableTier.Keys | Sort-Object @{ Expression = { $byTableTier[$_] }; Descending = $true }, @{ Expression = { $_ } })) {
            $parts = $k -split '\|\|'
            $flowRowsList.Add("$($parts[0]),$($parts[1]),$([math]::Round($byTableTier[$k], 3))")
        }
        $sankeyFlowText = $flowRowsList -join [Environment]::NewLine

        # Dynamic height — Mermaid sankey-beta crams labels when nodes exceed
        # the configured height. Scale with the middle-column count (the wide
        # axis) and the source-column count, whichever's larger.
        $middleNodeCount = @(($bySourceTable.Keys | ForEach-Object { ($_ -split '\|\|')[1] }) | Sort-Object -Unique).Count
        $sourceCount = @(($bySourceTable.Keys | ForEach-Object { ($_ -split '\|\|')[0] }) | Sort-Object -Unique).Count
        $tallestColumn = [Math]::Max($middleNodeCount, $sourceCount)
        $sankeyHeight = [Math]::Max(720, 24 * $tallestColumn + 200)

        # The cost as data for the SharePoint graphic: the total, GB and cost by
        # plan, and every source family with every one of its tables (no tail
        # buckets: the graphic lists them all behind each family).
        $costVisualLine = Format-VisualLine -Kind 'cost-breakdown' -Data ([ordered]@{
                windowDays   = (Get-BlueprintWindow).Days
                currency     = [string]$cost.Currency
                monthlyTotal = $cost.MonthlyTotal
                totalGb      = [math]::Round([double]$totalGb, 2)
                plans        = @(
                    $planRows |
                        Sort-Object { - [double]$_.Gb30d } |
                        ForEach-Object { [ordered]@{ name = [string]$_.Plan; gb = [double]$_.Gb30d; cost = $_.MonthlyCost } }
                )
                sources      = @($flowFiltered | Group-Object Source | ForEach-Object {
                        [ordered]@{
                            name   = [string]$_.Name
                            gb     = [math]::Round([double](($_.Group | Measure-Object -Property Gb -Sum).Sum), 2)
                            tables = @(
                                $_.Group |
                                    Sort-Object -Property Gb -Descending |
                                    ForEach-Object { [ordered]@{ table = [string]$_.Table; gb = [math]::Round([double]$_.Gb, 2); tier = [string]$_.Tier } }
                                )
                            }
                        } | Sort-Object { - $_.gb })
            })

    }

    # Left in the render context for later sections.
    if (Get-Variable -Name 'allTables' -Scope 0 -ErrorAction Ignore) { $Context.allTables = $allTables }
    if (Get-Variable -Name 'costCurrencyText' -Scope 0 -ErrorAction Ignore) { $Context.costCurrencyText = $costCurrencyText }
    if (Get-Variable -Name 'costMethodV2' -Scope 0 -ErrorAction Ignore) { $Context.costMethodV2 = $costMethodV2 }
    if (Get-Variable -Name 'costTierText' -Scope 0 -ErrorAction Ignore) { $Context.costTierText = $costTierText }
    if (Get-Variable -Name 'costVisualLine' -Scope 0 -ErrorAction Ignore) { $Context.costVisualLine = $costVisualLine }
    if (Get-Variable -Name 'gb' -Scope 0 -ErrorAction Ignore) { $Context.gb = $gb }
    if (Get-Variable -Name 'grantRows' -Scope 0 -ErrorAction Ignore) { $Context.grantRows = $grantRows }
    $Context.k = $k
    if (Get-Variable -Name 'parts' -Scope 0 -ErrorAction Ignore) { $Context.parts = $parts }
    if (Get-Variable -Name 'planTableRows' -Scope 0 -ErrorAction Ignore) { $Context.planTableRows = $planTableRows }
    $Context.r = $r
    if (Get-Variable -Name 'sankeyFlowText' -Scope 0 -ErrorAction Ignore) { $Context.sankeyFlowText = $sankeyFlowText }
    if (Get-Variable -Name 'sankeyHeight' -Scope 0 -ErrorAction Ignore) { $Context.sankeyHeight = $sankeyHeight }
    $Context.t = $t
}
