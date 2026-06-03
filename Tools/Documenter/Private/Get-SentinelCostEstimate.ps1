#
# Sentinel-As-Code/Tools/Documenter/Private/Get-SentinelCostEstimate.ps1
#
# Created by noodlemctwoodle on 06/05/2026.
#

<#
.SYNOPSIS
    Compute an estimated monthly cost for the workspace from the captured 30-day Usage,
    table-plan attribution, and the Azure Retail Prices snapshot.

.DESCRIPTION
    Pure data-in / data-out so the calculator can be exercised by Pester fixtures with
    no Azure dependency.

    Inputs (all written by Export-SentinelInventory.ps1):
      - tables-with-data.json    per-table 30-day BillableGB / IngestedGB
      - workspace-tables.json    per-table plan + retention
      - workspace.json           workspace SKU + commitment level
      - retail-prices.json       Sentinel + Log Analytics retail meters for the region
      - sentinel-benefit-tables.json  list of tables eligible for the free benefit

    Output (cost-estimate.json):
      MonthlyTotal                 number, in the API-reported currency
      Currency                     string (e.g. 'GBP')
      Region                       workspace region
      AsOfUtc                      timestamp the prices were fetched
      ByPlan                       hashtable: plan name -> @{ Gb30d; MonthlyCost }
      Top10TablesByCost            array of @{ Table; Plan; Gb30d; MonthlyCost }
      CommitmentTierWhatIf         array of @{ Rung; ProjectedMonthlyCost; DeltaVsCurrent }
      DedicatedClusterCandidate    bool
      Caveats                      array of strings, items NOT priced
      MethodologyVersion           '1.0.0'

    Methodology notes
    -----------------
    1. Every table on the Analytics plan is priced against the 'Pay-As-You-Go Data
       Ingestion' meter (or the workspace's commitment-tier overage rate).
    2. Basic and Auxiliary plans use their dedicated ingestion meters.
    3. Sentinel benefit: tables in sentinel-benefit-tables.json have their ingestion
       price reduced/zeroed.
    4. Retention beyond the free interactive period is priced against the 'Data
       Retention' meter (per-GB-month).
    5. Archive (totalRetentionInDays minus retentionInDays) is priced against the
       'Long-Term Retention' meter.

    Caveats, explicitly NOT priced:
      - Query-time billing for Basic/Auxiliary plans.
      - Search-job and restore-log storage.
      - Data export egress.
      - Cross-region transfer.
      - Defender XDR-side meters.
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

    $caveats = @(
        'Query-time billing for Basic/Auxiliary plans not included.',
        'Search-job and restored-log storage not included.',
        'Data-export egress and cross-region transfer not included.',
        'Defender XDR-side meters not included.',
        'Sentinel free-benefit tables are priced at zero on the assumption the benefit is active. SENT-019 flags workspaces with eligible Defender plans where the benefit is not detected.'
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

    # Sentinel benefit set
    $benefitSet = @{}
    if ($benefitJson) { foreach ($t in $benefitJson.tables) { $benefitSet[$t] = $true } }

    # Pricing table lookup driven by Resources/cost-meters.json. Each
    # category in that file declares either:
    #   - meterNames, exact-match meter strings (case-sensitive), OR
    #   - meterContains, list of substrings that must ALL be present in
    #                     the meter name (used for the Data Lake meter
    #                     whose exact wording has varied).
    # Microsoft renames Retail Prices meters periodically; supporting the
    # documenter on a new tenant should be a JSON edit, not a code change.
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

    # Analytics plan = LA ingestion + Sentinel premium (both per-GB and
    # additive on a Sentinel-enabled workspace).
    $unitPrices.AnalyticsIngestionPerGb = $unitPrices.AnalyticsLaIngestion + $unitPrices.SentinelPremium
    # Legacy aliases kept for any callers reading the older property names.
    $unitPrices.BasicIngestionPerGb     = $unitPrices.BasicIngestion
    $unitPrices.AuxiliaryIngestionPerGb = $unitPrices.AuxiliaryIngestion
    $unitPrices.DataLakeIngestionPerGb  = $unitPrices.DataLakeIngestion

    # Per-table cost (30d billable -> monthly = *30/30, i.e. unchanged)
    $perTable = @()
    foreach ($t in $tables) {
        $name = $t.DataType
        $billable30d = [double]($t.BillableLast30d)
        if ($billable30d -le 0 -or -not $name) { continue }

        $plan = if ($planByTable.ContainsKey($name)) { $planByTable[$name] } else { 'Analytics' }
        $unit = switch ($plan) {
            'Basic'     { $unitPrices.BasicIngestionPerGb }
            'Auxiliary' { $unitPrices.AuxiliaryIngestionPerGb }
            'DataLake'  { $unitPrices.DataLakeIngestionPerGb }
            default     { $unitPrices.AnalyticsIngestionPerGb }
        }
        if ($benefitSet.ContainsKey($name)) { $unit = 0.0 }

        $cost = [math]::Round($billable30d * $unit, 2)
        $perTable += [pscustomobject]@{
            Table       = $name
            Plan        = $plan
            Gb30d       = [math]::Round($billable30d, 2)
            MonthlyCost = $cost
        }

        $bucket = if ($byPlan.ContainsKey($plan)) { $plan } else { 'Analytics' }
        $byPlan[$bucket].Gb30d        += $billable30d
        $byPlan[$bucket].MonthlyCost  += $cost
    }

    $monthlyTotal = ($perTable | Measure-Object -Property MonthlyCost -Sum).Sum
    if (-not $monthlyTotal) { $monthlyTotal = 0.0 }

    $perTableSorted = @($perTable | Sort-Object -Property MonthlyCost -Descending)
    $top10 = $perTableSorted | Select-Object -First 10

    # Commitment-tier what-if, only meaningful for PerGB2018 workspaces.
    $commitmentWhatIf = @()
    # Guard against a missing or corrupt workspace.json. Under StrictMode,
    # navigating $workspace.properties.sku.name on a null would throw and abort
    # the whole estimate, so treat an unreadable SKU as unknown (no what-if).
    $sku = $null
    if ($workspace -and
        ($workspace.PSObject.Properties.Name -contains 'properties') -and $workspace.properties -and
        ($workspace.properties.PSObject.Properties.Name -contains 'sku') -and $workspace.properties.sku) {
        $sku = ($workspace.properties.sku.name) -as [string]
    }
    if ($sku -eq 'PerGB2018') {
        $commitmentTiers = Read-Json (Join-Path $ResourcesRoot 'commitment-tiers.json')
        if ($commitmentTiers) {
            $totalGb30d = ($byPlan.Values | Measure-Object -Property Gb30d -Sum).Sum
            $dailyAvg = $totalGb30d / 30.0
            # Recommend a single rung, not one row per rung: the highest rung the
            # workspace already qualifies for, or the smallest rung when ingest is
            # just below it (within 80%), since that is the one decision worth
            # surfacing. Genuinely low-volume workspaces get no recommendation;
            # PerGB2018 is the right plan for them.
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
                # Illustrative projection: a ~25% discount at the rung floor. The
                # real per-rung discount lives in retail-prices.json; this is a
                # planning signal, not a quote.
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
    $clusterCandidate = ($totalGb30d / 30.0) -gt 500.0

    [pscustomobject]@{
        MonthlyTotal              = [math]::Round($monthlyTotal, 2)
        Currency                  = $currency
        Region                    = $region
        AsOfUtc                   = $asOfUtc
        ByPlan                    = $byPlan
        Top10TablesByCost         = @($top10)
        AllTablesByCost           = @($perTableSorted)
        CommitmentTierWhatIf      = @($commitmentWhatIf)
        DedicatedClusterCandidate = $clusterCandidate
        Caveats                   = $caveats
        MethodologyVersion        = '1.0.0'
    }
}
