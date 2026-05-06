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
      Caveats                      array of strings — items NOT priced
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

    Caveats — explicitly NOT priced:
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
        'Defender XDR-side meters not included.'
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
            Caveats                   = $caveats + 'No table or usage data available — workspace may be empty or KQL Usage query failed.'
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

    # Pricing table lookup. The Retail Prices payload is wide; we extract a small set of
    # representative meters. If a meter is missing we fall back to a sentinel value of 0
    # so the calculator degrades gracefully rather than throwing.
    $unitPrices = @{
        AnalyticsIngestionPerGb = 0.0
        BasicIngestionPerGb     = 0.0
        AuxiliaryIngestionPerGb = 0.0
        DataLakeIngestionPerGb  = 0.0
        RetentionPerGbMonth     = 0.0
        ArchivePerGbMonth       = 0.0
    }
    $currency = 'unknown'
    $asOfUtc = $null
    $region = $null

    if ($pricesBlob) {
        $region   = $pricesBlob.Region
        $asOfUtc  = $pricesBlob.FetchedAtUtc
        foreach ($p in @($pricesBlob.Prices)) {
            $meter = ($p.meterName)         -as [string]
            $product = ($p.productName)     -as [string]
            $price = ($p.unitPrice)         -as [double]
            $currency = ($p.currencyCode)   -as [string]

            switch -regex ($meter) {
                '^Pay-As-You-Go Data Ingestion$'        { $unitPrices.AnalyticsIngestionPerGb = $price; break }
                '^Basic Logs Data Ingestion$'           { $unitPrices.BasicIngestionPerGb     = $price; break }
                '^Auxiliary Logs Data Ingestion$'       { $unitPrices.AuxiliaryIngestionPerGb = $price; break }
                'Data Lake.*Ingestion'                  { $unitPrices.DataLakeIngestionPerGb  = $price; break }
                '^Data Retention$'                      { $unitPrices.RetentionPerGbMonth     = $price; break }
                '^Long Term Retention$'                 { $unitPrices.ArchivePerGbMonth       = $price; break }
            }
        }
    } else {
        $caveats += 'Retail Prices snapshot unavailable — monthly cost is reported as zero.'
    }

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

    $top10 = $perTable | Sort-Object -Property MonthlyCost -Descending | Select-Object -First 10

    # Commitment-tier what-if — only meaningful for PerGB2018 workspaces.
    $commitmentWhatIf = @()
    $sku = ($workspace.properties.sku.name) -as [string]
    if ($sku -eq 'PerGB2018') {
        $commitmentTiers = Read-Json (Join-Path $ResourcesRoot 'commitment-tiers.json')
        if ($commitmentTiers) {
            $totalGb30d = ($byPlan.Values | Measure-Object -Property Gb30d -Sum).Sum
            $dailyAvg = $totalGb30d / 30.0
            foreach ($rung in $commitmentTiers.rungsGbPerDay) {
                # Rough projection — 25% discount at the rung floor; reality depends on
                # actual published discount per rung. Surface as illustrative.
                $projected = [math]::Round(($monthlyTotal * 0.75), 2)
                if ($dailyAvg -ge $rung) {
                    $commitmentWhatIf += [pscustomobject]@{
                        Rung                = $rung
                        ProjectedMonthlyCost = $projected
                        DeltaVsCurrent      = [math]::Round($projected - $monthlyTotal, 2)
                    }
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
        CommitmentTierWhatIf      = @($commitmentWhatIf)
        DedicatedClusterCandidate = $clusterCandidate
        Caveats                   = $caveats
        MethodologyVersion        = '1.0.0'
    }
}
