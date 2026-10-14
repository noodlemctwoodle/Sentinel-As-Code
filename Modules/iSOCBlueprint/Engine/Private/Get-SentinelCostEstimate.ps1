#Requires -Version 7.2

<#
.SYNOPSIS
    Compute an estimated monthly cost for the workspace from the captured Usage over the run's lookback,
    table-plan attribution, and the Azure Retail Prices snapshot.

.DESCRIPTION
    Pure data-in / data-out so the calculator can be exercised by Pester fixtures with
    no Azure dependency.

    Inputs (all written by Export-SentinelInventory.ps1):
      - tables-with-data.json    per-table BillableGB / IngestedGB over the lookback (BillableLast30d)
      - workspace-tables.json    per-table plan + retention
      - workspace.json           workspace SKU + commitment level
      - retail-prices.json       Sentinel + Log Analytics retail meters for the region
      - sentinel-data-lake.json  whether the workspace is onboarded to the data lake
      - sentinel-benefit-tables.json  the data grants and the tables each covers

    Output (cost-estimate.json):
      MonthlyTotal                 number, in the API-reported currency
      Currency                     string (e.g. 'GBP')
      Region                       workspace region
      AsOfUtc                      timestamp the prices were fetched
      ByPlan                       hashtable: plan name -> @{ Gb30d; MonthlyCost }
                                   (Gb30d is the GB in the window, MonthlyCost
                                   that projected to 30 days)
      Top10TablesByCost            array of @{ Table; Plan; Gb30d; MonthlyCost; Benefit }
      AllTablesByCost              the same for every table with billable data
      CommitmentTierWhatIf         array of @{ Rung; ProjectedMonthlyCost; DeltaVsCurrent }
      CommitmentTier               the workspace's tier (Level, DailyPrice,
                                   EffectivePerGb, DailyAverageGb, Utilisation),
                                   $null on pay-as-you-go
      BenefitEligible              array of @{ Benefit; Allowance; Tables; Gb30d;
                                   MonthlyCost; Learn }: the data grants that may
                                   cover part of the cost, not deducted
      PricingModel                 'Simplified' or 'Classic'
      DedicatedClusterCandidate    bool
      Caveats                      array of strings, items NOT priced
      WindowDays                   days of Usage the estimate is projected from
      MethodologyVersion           '2.0.0'

    Methodology notes
    -----------------
    1. Analytics-plan tables are priced at the simplified Microsoft Sentinel
       'Pay-as-you-go Analysis' meter, which covers Sentinel analysis and Log
       Analytics ingestion together. A price list without it (an older
       capture) falls back to the classic pair: Log Analytics ingestion plus
       the Sentinel analysis meter.
    2. A workspace on a commitment tier pays the tier's fixed price a day for
       its GB, and the Analytics GB above it at the tier's effective rate (the
       tier price over its GB), as Microsoft bills it. The cost is shared out
       over the Analytics tables by their GB.
    3. Basic tables use 'Basic Logs Analysis'; data-lake-only tables pay data
       lake ingestion plus data processing; Auxiliary tables pay the same once
       the workspace is onboarded to the data lake, else the Auxiliary meters.
    4. Data grants (Microsoft 365 E5 and Defender for Servers Plan 2) cover
       named tables up to an allowance per licensed user or server that the
       Blueprint cannot read, so they are not deducted; the eligible volume and
       its cost are reported beside the total instead.
    5. The what-if prices every published commitment tier against the window's
       Analytics ingest and reports the cheapest when it beats the current cost.

    Caveats, explicitly NOT priced:
      - Query-time billing for Basic/Auxiliary plans.
      - Search-job and restore-log storage.
      - Retention beyond the free 90 days and data lake storage.
      - Data export egress.
      - Cross-region transfer.
      - Defender XDR-side meters.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/Get-SentinelCostEstimate.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-05-06
    Version:      0.3.0
    Last Updated: 2026-10-14
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-SentinelCostEstimate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputRoot,

        [Parameter(Mandatory = $true)]
        [string]$ResourcesRoot
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    function Read-Json([string]$Path) {
        if (-not (Test-Path $Path)) { return $null }
        $raw = Get-Content $Path -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json -Depth 32)
    }

    $tables       = @(Read-Json (Join-Path $InputRoot 'tables-with-data.json'))
    $schemas      = @(Read-Json (Join-Path $InputRoot 'workspace-tables.json'))
    $workspace    = Read-Json (Join-Path $InputRoot 'workspace.json')
    $pricesBlob   = Read-Json (Join-Path $InputRoot 'retail-prices.json')
    $benefitJson  = Read-Json (Join-Path $ResourcesRoot 'sentinel-benefit-tables.json')
    # The days of Usage the tables carry: the run's lookback (run-context.json),
    # 30 for a run collected before the setting existed. A month is projected
    # from it as 30 days at the window's rate.
    $runContext   = Read-Json (Join-Path $InputRoot 'run-context.json')
    $windowDays   = 30
    if ($runContext -and $runContext.PSObject.Properties['LookbackDays'] -and [int]$runContext.LookbackDays -ge 1) { $windowDays = [int]$runContext.LookbackDays }
    $toMonth      = 30.0 / $windowDays

    $caveats = @(
        'Query-time billing for Basic/Auxiliary plans not included.',
        'Search-job and restored-log storage not included.',
        'Data-export egress and cross-region transfer not included.',
        'Retention beyond the free 90 days and data lake storage not included.',
        'Defender XDR-side meters not included.',
        'Data grants (Microsoft 365 E5 and Defender for Servers Plan 2) are not deducted: they depend on licence and server counts the Blueprint does not read. The eligible volume is listed as the most they could save.'
    )

    $byPlan = @{
        Analytics = @{ Gb30d = 0.0; MonthlyCost = 0.0 }
        Basic     = @{ Gb30d = 0.0; MonthlyCost = 0.0 }
        Auxiliary = @{ Gb30d = 0.0; MonthlyCost = 0.0 }
        DataLake  = @{ Gb30d = 0.0; MonthlyCost = 0.0 }
    }

    if (-not $tables -or -not $schemas) {
        return [pscustomobject]@{
            MonthlyTotal              = 0.0
            Currency                  = 'unknown'
            Region                    = $null
            AsOfUtc                   = $null
            ByPlan                    = $byPlan
            Top10TablesByCost         = @()
            CommitmentTierWhatIf      = @()
            DedicatedClusterCandidate = $false
            Caveats                   = $caveats + 'No table or usage data available, workspace may be empty or KQL Usage query failed.'
            MethodologyVersion        = '1.0.0'
        }
    }

    # Plan lookup: table name -> plan
    $planByTable = @{}
    foreach ($t in $schemas) {
        $name = $t.name
        $plan = ($t.properties.plan) -as [string]
        if ($name) { $planByTable[$name] = $plan }
    }

    # The data grants and the tables each covers: table -> grant. A table on
    # two lists goes to the first. An older file (a flat 'tables' list) reads
    # as one unnamed grant.
    $benefitOf = @{}
    $benefitGroups = @()
    if ($benefitJson) {
        if ($benefitJson.PSObject.Properties.Name -contains 'benefits' -and $benefitJson.benefits) {
            $benefitGroups = @($benefitJson.benefits)
        } elseif ($benefitJson.PSObject.Properties.Name -contains 'tables') {
            $benefitGroups = @([pscustomobject]@{ name = 'Sentinel data grant'; allowance = ''; learn = ''; tables = @($benefitJson.tables) })
        }
        foreach ($g in $benefitGroups) { foreach ($t in @($g.tables)) { if ($t -and -not $benefitOf.ContainsKey([string]$t)) { $benefitOf[[string]$t] = $g } } }
    }

    # Onboarded to the data lake: a lake resource, unified billing, or a
    # table on the lake-only plan.
    $lakeDoc = @(Read-Json (Join-Path $InputRoot 'sentinel-data-lake.json') | Where-Object { $_ })
    $unifiedBilling = $false
    if ($workspace -and ($workspace.PSObject.Properties.Name -contains 'properties') -and $workspace.properties -and
        ($workspace.properties.PSObject.Properties.Name -contains 'features') -and $workspace.properties.features -and
        ($workspace.properties.features.PSObject.Properties.Name -contains 'unifiedSentinelBillingOnly')) {
        $unifiedBilling = [bool]$workspace.properties.features.unifiedSentinelBillingOnly
    }
    $lakeEnrolled = ($lakeDoc.Count -gt 0) -or $unifiedBilling -or (@($planByTable.Values | Where-Object { $_ -eq 'DataLake' }).Count -gt 0)

    # Pricing table lookup driven by Resources/cost-meters.json. Each
    # category in that file declares either:
    #   - meterNames, exact-match meter strings (case-sensitive), OR
    #   - meterContains, list of substrings that must ALL be present in
    #                     the meter name (used for the Data Lake meter
    #                     whose exact wording has varied).
    # Microsoft renames Retail Prices meters periodically; supporting the
    # Blueprint on a new tenant should be a JSON edit, not a code change.
    #
    # When the API returns more than one row for the same meter (a
    # 0-priced commitment-tier 'included' row plus a non-zero PAYG row),
    # we take the MAX unit price across rows, that yields the PAYG rate,
    # which is the right baseline for an uncommitted workspace. The
    # CommitmentTierWhatIf surface below projects savings from this
    # baseline.
    $metersCatalog = Read-Json (Join-Path $ResourcesRoot 'cost-meters.json')
    if (-not $metersCatalog) {
        throw "cost-meters.json missing or unreadable under $ResourcesRoot"
    }

    $unitPrices = @{}
    foreach ($cat in $metersCatalog.categories) { $unitPrices[$cat.id] = 0.0 }
    $skipMeters = @{}
    if ($metersCatalog.skipMeters) { foreach ($s in $metersCatalog.skipMeters) { $skipMeters[$s] = $true } }

    $currency = 'unknown'
    $asOfUtc  = $null
    $region   = $null

    if ($pricesBlob) {
        $region  = $pricesBlob.Region
        $asOfUtc = $pricesBlob.FetchedAtUtc
        foreach ($p in @($pricesBlob.Prices)) {
            $meter = ($p.meterName)    -as [string]
            $price = ($p.unitPrice)    -as [double]
            $cc    = ($p.currencyCode) -as [string]
            if ($cc) { $currency = $cc }
            if (-not $meter -or $skipMeters.ContainsKey($meter)) { continue }

            foreach ($cat in $metersCatalog.categories) {
                $hit = $false
                if ($cat.PSObject.Properties.Name -contains 'meterNames' -and $cat.meterNames) {
                    if ($cat.meterNames -contains $meter) { $hit = $true }
                }
                if (-not $hit -and $cat.PSObject.Properties.Name -contains 'meterContains' -and $cat.meterContains) {
                    $allMatch = $true
                    foreach ($needle in $cat.meterContains) {
                        if ($meter -notlike "*$needle*") { $allMatch = $false; break }
                    }
                    if ($allMatch) { $hit = $true }
                }
                if ($hit -and $price -gt $unitPrices[$cat.id]) {
                    $unitPrices[$cat.id] = $price
                }
            }
        }
    } else {
        $caveats += 'Retail Prices snapshot unavailable, monthly cost is reported as zero.'
    }

    # Commitment tiers: each tier's fixed price a day, by its GB a day.
    $tierDaily = @{}
    if ($pricesBlob) {
        foreach ($p in @($pricesBlob.Prices)) {
            $meter = ($p.meterName) -as [string]
            $price = ($p.unitPrice) -as [double]
            if ($meter -match '^(\d+) GB Commitment Tier Capacity Reservation$' -and $price -gt 0) {
                $gb = [int]$Matches[1]
                if (-not $tierDaily.ContainsKey($gb) -or $price -gt $tierDaily[$gb]) { $tierDaily[$gb] = $price }
            }
        }
    }

    # A property summed over a list, 0 for an empty one (Measure-Object
    # returns nothing to read a Sum from then).
    $sumOf = { param($Items, [string]$Property) $t = 0.0; foreach ($i in @($Items)) { if ($null -ne $i) { $t += [double]$i.$Property } }; $t }

    # Price per GB by plan. The simplified Sentinel meter, when the price
    # list has it, already includes Log Analytics ingestion.
    $up = { param([string]$Key) if ($unitPrices.ContainsKey($Key) -and $unitPrices[$Key]) { [double]$unitPrices[$Key] } else { 0.0 } }
    $simplified = (& $up 'SentinelAnalytics') -gt 0
    $analyticsUnit = if ($simplified) { & $up 'SentinelAnalytics' } else { (& $up 'AnalyticsLaIngestion') + (& $up 'SentinelPremium') }
    $basicUnit = if ((& $up 'SentinelBasic') -gt 0) { & $up 'SentinelBasic' } else { & $up 'BasicIngestion' }
    $lakeUnit = (& $up 'DataLakeIngestion') + (& $up 'DataLakeProcessing')
    $auxUnit = if ($lakeEnrolled -and $lakeUnit -gt 0) { $lakeUnit } else { (& $up 'SentinelAuxiliary') + (& $up 'AuxiliaryIngestion') }
    # Older property names, kept for any caller reading them.
    $unitPrices.AnalyticsIngestionPerGb = $analyticsUnit
    $unitPrices.BasicIngestionPerGb     = $basicUnit
    $unitPrices.AuxiliaryIngestionPerGb = $auxUnit
    $unitPrices.DataLakeIngestionPerGb  = $lakeUnit

    # Every table with billable data in the window, at its plan's price per
    # GB, projected to 30 days.
    $rows = foreach ($t in $tables) {
        $name = $t.DataType
        $billable30d = [double]($t.BillableLast30d)
        if ($billable30d -le 0 -or -not $name) { continue }
        $plan = if ($planByTable.ContainsKey($name) -and $planByTable[$name]) { $planByTable[$name] } else { 'Analytics' }
        $unit = switch ($plan) {
            'Basic'     { $basicUnit }
            'Auxiliary' { $auxUnit }
            'DataLake'  { $lakeUnit }
            default     { $analyticsUnit }
        }
        [pscustomobject]@{ Table = $name; Plan = $plan; Gb = $billable30d; Cost = $billable30d * $unit * $toMonth
            Benefit = $(if ($benefitOf.ContainsKey($name)) { $g = $benefitOf[$name]; if ($g.PSObject.Properties.Name -contains 'short' -and $g.short) { [string]$g.short } else { [string]$g.name } } else { '' }) }
    }
    $rows = @($rows)

    $sku = $null
    $level = 0
    # Guard against a missing or corrupt workspace.json. Under StrictMode,
    # navigating $workspace.properties.sku.name on a null would throw and abort
    # the whole estimate, so treat an unreadable SKU as unknown.
    if ($workspace -and
        ($workspace.PSObject.Properties.Name -contains 'properties') -and $workspace.properties -and
        ($workspace.properties.PSObject.Properties.Name -contains 'sku') -and $workspace.properties.sku) {
        $sku = ($workspace.properties.sku.name) -as [string]
        if ($workspace.properties.sku.PSObject.Properties.Name -contains 'capacityReservationLevel') { $level = [int]($workspace.properties.sku.capacityReservationLevel -as [int]) }
    }

    # On a commitment tier, the Analytics data costs the tier's price a day
    # for its GB and the effective rate for the GB above it; that is shared
    # out over the Analytics tables by their GB.
    $analyticsRows = @($rows | Where-Object { $_.Plan -notin @('Basic', 'Auxiliary', 'DataLake') })
    $analyticsGb = & $sumOf $analyticsRows 'Gb'
    $dailyAnalytics = $analyticsGb / $windowDays
    $commitment = $null
    if ($sku -eq 'CapacityReservation' -and $level -gt 0) {
        if ($tierDaily.ContainsKey($level)) {
            $price = $tierDaily[$level]
            $effective = $price / $level
            $tierMonthly = 30.0 * ($price + [math]::Max(0.0, $dailyAnalytics - $level) * $effective)
            foreach ($r in $analyticsRows) { $r.Cost = $(if ($analyticsGb -gt 0) { $tierMonthly * $r.Gb / $analyticsGb } else { 0.0 }) }
            $commitment = [pscustomobject]@{
                Level          = $level
                DailyPrice     = [math]::Round($price, 2)
                EffectivePerGb = [math]::Round($effective, 4)
                DailyAverageGb = [math]::Round($dailyAnalytics, 1)
                Utilisation    = [math]::Round(100.0 * $dailyAnalytics / $level, 1)
            }
        } else {
            $caveats += "The workspace is on the $level GB a day commitment tier, but the price list has no price for it, so its Analytics data is priced at pay-as-you-go."
        }
    }

    $perTable = @(foreach ($r in $rows) {
        [pscustomobject]@{ Table = $r.Table; Plan = $r.Plan; Gb30d = [math]::Round($r.Gb, 2); MonthlyCost = [math]::Round($r.Cost, 2); Benefit = $r.Benefit }
        $bucket = if ($byPlan.ContainsKey($r.Plan)) { $r.Plan } else { 'Analytics' }
        $byPlan[$bucket].Gb30d       += $r.Gb
        $byPlan[$bucket].MonthlyCost += [math]::Round($r.Cost, 2)
    })

    $monthlyTotal = & $sumOf $perTable 'MonthlyCost'

    $perTableSorted = @($perTable | Sort-Object -Property MonthlyCost -Descending)
    $top10 = $perTableSorted | Select-Object -First 10

    # The data grants: what each could cover, at list price, not deducted.
    $benefitEligible = @(foreach ($g in $benefitGroups) {
        $label = if ($g.PSObject.Properties.Name -contains 'short' -and $g.short) { [string]$g.short } else { [string]$g.name }
        $covered = @($perTable | Where-Object { $_.Benefit -eq $label })
        if ($covered.Count -eq 0) { continue }
        [pscustomobject]@{
            Benefit     = [string]$g.name
            Allowance   = $(if ($g.PSObject.Properties.Name -contains 'allowance') { [string]$g.allowance } else { '' })
            Tables      = (@($covered | Sort-Object -Property Gb30d -Descending | ForEach-Object { $_.Table }) -join ', ')
            Gb30d       = [math]::Round((& $sumOf $covered 'Gb30d'), 2)
            MonthlyCost = [math]::Round((& $sumOf $covered 'MonthlyCost'), 2)
            Learn       = $(if ($g.PSObject.Properties.Name -contains 'learn') { [string]$g.learn } else { '' })
        }
    })

    # Commitment-tier what-if: every published tier priced against the
    # window's Analytics ingest; the cheapest is reported when it beats the
    # current cost by more than 1%. A price list without the tiers (an older
    # capture) keeps the earlier illustrative projection for pay-as-you-go.
    $commitmentWhatIf = @()
    $currentAnalytics = & $sumOf @($perTable | Where-Object { $_.Plan -notin @('Basic', 'Auxiliary', 'DataLake') }) 'MonthlyCost'
    if ($tierDaily.Count -gt 0 -and $dailyAnalytics -gt 0) {
        $best = $null
        foreach ($r in $tierDaily.Keys) {
            $m = 30.0 * ($tierDaily[$r] + [math]::Max(0.0, $dailyAnalytics - $r) * $tierDaily[$r] / $r)
            if ($null -eq $best -or $m -lt $best.Monthly) { $best = @{ Rung = $r; Monthly = $m } }
        }
        if ($best -and $best.Rung -ne $level -and $best.Monthly -lt $currentAnalytics * 0.99) {
            $projected = [math]::Round($monthlyTotal - $currentAnalytics + $best.Monthly, 2)
            $commitmentWhatIf += [pscustomobject]@{
                Rung                 = $best.Rung
                ProjectedMonthlyCost = $projected
                DeltaVsCurrent       = [math]::Round($projected - $monthlyTotal, 2)
            }
        }
    } elseif ($sku -eq 'PerGB2018') {
        $commitmentTiers = Read-Json (Join-Path $ResourcesRoot 'commitment-tiers.json')
        if ($commitmentTiers) {
            $totalGb30d = ($byPlan.Values | Measure-Object -Property Gb30d -Sum).Sum
            $dailyAvg = $totalGb30d / $windowDays
            $smallestRung = ($commitmentTiers.rungsGbPerDay | Measure-Object -Minimum).Minimum
            $qualifying   = @($commitmentTiers.rungsGbPerDay | Where-Object { $dailyAvg -ge $_ })
            $rung = if ($qualifying) {
                ($qualifying | Measure-Object -Maximum).Maximum
            } elseif ($dailyAvg -ge ($smallestRung * 0.8)) {
                $smallestRung
            } else {
                $null
            }
            if ($null -ne $rung) {
                # Illustrative: a ~25% discount at the rung, without published tier prices.
                $projected = [math]::Round(($monthlyTotal * 0.75), 2)
                $commitmentWhatIf += [pscustomobject]@{
                    Rung                 = $rung
                    ProjectedMonthlyCost = $projected
                    DeltaVsCurrent       = [math]::Round($projected - $monthlyTotal, 2)
                }
            }
        }
    }

    $totalGb30d = ($byPlan.Values | Measure-Object -Property Gb30d -Sum).Sum
    $clusterCandidate = ($totalGb30d / $windowDays) -gt 500.0

    [pscustomobject]@{
        MonthlyTotal              = [math]::Round($monthlyTotal, 2)
        Currency                  = $currency
        Region                    = $region
        AsOfUtc                   = $asOfUtc
        ByPlan                    = $byPlan
        Top10TablesByCost         = @($top10)
        AllTablesByCost           = @($perTableSorted)
        CommitmentTierWhatIf      = @($commitmentWhatIf)
        CommitmentTier            = $commitment
        BenefitEligible           = @($benefitEligible)
        PricingModel              = $(if ($simplified) { 'Simplified' } else { 'Classic' })
        DedicatedClusterCandidate = $clusterCandidate
        Caveats                   = $caveats
        WindowDays                = $windowDays
        MethodologyVersion        = '2.0.0'
    }
}
