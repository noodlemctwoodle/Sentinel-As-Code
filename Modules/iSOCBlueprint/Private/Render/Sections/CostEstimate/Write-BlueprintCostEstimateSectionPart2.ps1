#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 84-cost-estimate.md (part 2 of 2).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/CostEstimate/Write-BlueprintCostEstimateSectionPart2.ps1
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
function Write-BlueprintCostEstimateSectionPart2 {
    <#
    .SYNOPSIS
        Build the figures for and write 84-cost-estimate.md (part 2 of 2).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $allTables = $Context.allTables
    $cost = $Context.cost
    $costCurrencyText = $Context.costCurrencyText
    $costMethodV2 = $Context.costMethodV2
    $costTierText = $Context.costTierText
    $costVisualLine = $Context.costVisualLine
    $grantRows = $Context.grantRows
    $m = $Context.m
    $n = $Context.n
    $planTableRows = $Context.planTableRows
    $sankeyFlowText = $Context.sankeyFlowText
    $sankeyHeight = $Context.sankeyHeight
    $sentinelPricingText = $Context.sentinelPricingText
    $t = $Context.t
    $workspace = $Context.workspace

    $costBody = if (-not $cost) { @"
$(Format-Banner -Title "Estimated Monthly Cost")

_Cost estimate not available. Confirm Export-iSOCBlueprintInventory ran with retail-prices fetch and tables-with-data KQL._
"@ } else {
    @"
$(Format-Banner -Title "Estimated Monthly Cost")

> **Headline** **$(Format-BlueprintMoney $cost.MonthlyTotal $cost.Currency)** for the workspace, projected to a month from the last {lookback} of `Usage` × Azure Retail Prices for $(Get-BlueprintRegionName $cost.Region) as of $(Format-BlueprintDate $cost.AsOfUtc -Time).
$(if ($costTierText) { "`n$costTierText`n" })$(if ($costCurrencyText) { "`n$costCurrencyText`n" })
<!-- bp:tone warning -->

> **Public list prices only.** The estimate uses Azure's public retail prices. It does not include any discount or agreement your organisation may have that is not public, such as Enterprise Agreement or Microsoft Customer Agreement rates, a Microsoft Azure Consumption Commitment (MACC), negotiated pricing or credits, so what you are billed can differ.

## By plan

$(Format-BlueprintTable -Items $planTableRows -Columns 'Plan','Gb30d','MonthlyCost')

## Tables by cost

``````mermaid
---
config:
  xyChart:
    width: 1400
    height: 480
---
xychart-beta
    title "Top tables by billable GB ({lookback-d})"
    x-axis [$(($cost.Top10TablesByCost | ForEach-Object {
        $t = if ($_.Table.Length -gt 14) { $_.Table.Substring(0,14) } else { $_.Table }
        "`"$t`""
    }) -join ', ')]
    y-axis "GB" 0 --> $([math]::Ceiling(([double]($cost.Top10TablesByCost | Measure-Object -Property Gb30d -Maximum).Maximum + 0.5)))
    bar [$(($cost.Top10TablesByCost | ForEach-Object { $_.Gb30d }) -join ', ')]
$(Format-XyFullLabels @($cost.Top10TablesByCost | ForEach-Object { $_.Table }))
``````

Long-tail concentration: the loudest table is always the right first cost-optimisation target. The chart shows the ten costliest tables; the table below lists every table with its full name.

$(Format-BlueprintTable -Items @($allTables | ForEach-Object { [pscustomobject]@{ Table = $_.Table; Plan = $_.Plan; Gb30d = $_.Gb30d; MonthlyCost = (Format-BlueprintMoney $_.MonthlyCost $cost.Currency); Grant = $(if ($_.PSObject.Properties.Name -contains 'Benefit') { [string]$_.Benefit } else { '' }) } }) -Columns 'Table','Plan','Gb30d','MonthlyCost','Grant')

## Cost by source and plan

``````mermaid
---
config:
  sankey:
    showValues: true
    nodeAlignment: justify
    nodePadding: 28
    height: $sankeyHeight
    width: 1200
    useMaxWidth: true
    linkColor: gradient
---
sankey-beta
$costVisualLine

$sankeyFlowText
``````

Where the billable data comes from, by source family and table, and the rate each table bills at, which is its plan's: Analytics, Basic, Auxiliary or the data lake. Findings [SAC-LOG-15], [SAC-LOG-16] and [SAC-LOG-18] flag tables that could move to a cheaper plan through DCR-based splits.

## Commitment-tier what-if

$(if ($cost.CommitmentTierWhatIf.Count -gt 0) {
    Format-BlueprintTable -Items @($cost.CommitmentTierWhatIf | ForEach-Object {
        [pscustomobject]@{ Rung = "$(Format-BlueprintCount $_.Rung) GB a day"; ProjectedMonthlyCost = (Format-BlueprintMoney $_.ProjectedMonthlyCost $cost.Currency); DeltaVsCurrent = (Format-BlueprintMoney $_.DeltaVsCurrent $cost.Currency) }
    }) -Columns 'Rung','ProjectedMonthlyCost','DeltaVsCurrent'
} else { '_No commitment tier would cost less than the current pricing for this ingest, so no change is suggested._' })
$(if ($grantRows.Count -gt 0) { @"

## Data grants that may reduce this

Microsoft covers the ingestion of these tables free up to an allowance that depends on licences and servers the Blueprint does not read, so the estimate above prices them at list. Each figure is the most that grant could save over the month: the Microsoft 365 E5 grant covers up to 5 MB per licensed user a day, the Defender for Servers Plan 2 allowance 500 MB per server a day, and only data collected the way each grant requires.

$(Format-BlueprintTable -Items $grantRows -Columns 'Grant','Allowance','Gb30d','MonthlyCost','Tables')
"@ })

## Methodology (v$($cost.MethodologyVersion))

1. Source of truth for ingestion: `Usage` table over the last {lookback}, `IsBillable` honoured, projected to 30 days for the monthly figures.
2. Plan attribution: each table's current `plan` decides which meter applies (Analytics / Basic / Auxiliary / DataLake).
$(if ($costMethodV2) { @"
3. Unit price: the public prices from the [Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices) for $(Get-BlueprintRegionName $cost.Region) at run-time. Analytics-plan tables are priced at the simplified Microsoft Sentinel rate, which covers Log Analytics ingestion (an older price list falls back to the classic Log Analytics and Sentinel pair); Basic tables at the Basic logs rate; tables on the data lake tier only at data lake ingestion plus data processing, and Auxiliary tables the same once the workspace is onboarded to the data lake.
4. Commitment tier: a workspace on a tier pays its price a day for its GB, and the Analytics GB above it at the tier's effective rate (the price over the GB), as Microsoft bills it; the cost is shared over the Analytics tables by their GB.
5. Data grants: the tables in `Private/Resources/sentinel-benefit-tables.json` are priced at list and reported under Data grants, not deducted, since their allowances depend on licence and server counts.
6. Commitment-tier what-if: every published tier priced against the window's Analytics ingest; the cheapest is shown when it beats the current cost.
7. Dedicated cluster break-even: candidate flag set when daily ingest is above 500 GB and no cluster exists.
"@ } else { @"
3. Unit price: fetched from the [Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices) for $(Get-BlueprintRegionName $cost.Region) at collection.
4. Sentinel free benefit: the tables then listed in `Private/Resources/sentinel-benefit-tables.json` were priced at zero on the assumption the benefit was active.
5. Commitment-tier projection: illustrative, as actual discounts depend on published rates.
6. Dedicated cluster break-even: candidate flag set when daily ingest is above 500 GB and no cluster exists.

This estimate was worked out at collection with that earlier method; the next collection prices with the current one.
"@ })

## Caveats: explicitly NOT priced

$(($cost.Caveats | ForEach-Object { "- $_" }) -join [Environment]::NewLine)

[Sentinel billing (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/billing) · [Reduce costs](https://learn.microsoft.com/azure/sentinel/billing-reduce-costs) · [Cost logs](https://learn.microsoft.com/azure/azure-monitor/logs/cost-logs)
"@
    }
    # How the workspace is billed, from the Microsoft Sentinel solution's SKU
    # and the workspace's own. (The Microsoft.SecurityInsights/pricings endpoint
    # the collector once read is not a documented resource and never answered.)
    $wsSkuName = [string](Get-BlueprintRawProperty (Get-BlueprintRawProperty (Get-BlueprintRawProperty $workspace 'properties' $null) 'sku' $null) 'name' '')
    $wsSkuLevel = Get-BlueprintRawProperty (Get-BlueprintRawProperty (Get-BlueprintRawProperty $workspace 'properties' $null) 'sku' $null) 'capacityReservationLevel' $null
    $billingRows = @(
        [pscustomobject]@{ Setting = 'Microsoft Sentinel pricing'; Value = $sentinelPricingText }
        [pscustomobject]@{ Setting = 'Workspace SKU'; Value = $(if ($wsSkuName) { Format-WorkspaceSku $wsSkuName -WithCode } else { '_(not captured)_' }) }
        [pscustomobject]@{ Setting = 'Commitment tier'; Value = $(if ($wsSkuLevel) { "$(Format-BlueprintCount $wsSkuLevel) GB a day" } else { 'None (pay-as-you-go)' }) }
    )
    $costBody += @"

## How the workspace is billed

The Microsoft Sentinel solution's SKU says whether the workspace is on simplified or classic pricing; the workspace's SKU says whether it is on a commitment tier.

$(Format-BlueprintTable -Items $billingRows -Columns 'Setting','Value')
"@
    Write-BlueprintSection '84-cost-estimate.md' $costBody
}
