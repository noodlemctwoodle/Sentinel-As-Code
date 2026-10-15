#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for how the cost estimate prices a workspace.

.DESCRIPTION
    Get-SentinelCostEstimate prices each table's billable GB at its plan's
    public list price: the simplified Microsoft Sentinel meters when the
    price list has them, the classic Log Analytics and Sentinel pair when it
    does not, a commitment tier at its price a day with the GB above it at
    the tier's effective rate, data-lake-only tables at lake ingestion plus
    processing, and the tables a data grant may cover at list, reported
    beside the total. These tests drive it with small inline price lists.

.NOTES
    File:         Tests/iSOCBlueprint/Cost-Estimate.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-14
    Version:      0.1.0
    Last Updated: 2026-10-14
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:engine = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine'
    $script:resources = Join-Path $script:engine 'Private/Resources'
    . (Join-Path $script:engine 'Private/Get-SentinelCostEstimate.ps1')

    # UK South prices as the Retail Prices API publishes them.
    $script:Simplified = @(
        @{ serviceName = 'Sentinel'; meterName = 'Pay-as-you-go Analysis'; unitPrice = 4.0605 }
        @{ serviceName = 'Sentinel'; meterName = 'Basic Logs Analysis'; unitPrice = 0.8529 }
        @{ serviceName = 'Sentinel'; meterName = 'Classic Auxiliary Logs Analysis'; unitPrice = 0.0472 }
        @{ serviceName = 'Sentinel'; meterName = 'Data lake ingestion Data Processed'; unitPrice = 0.0472 }
        @{ serviceName = 'Sentinel'; meterName = 'Data processing Data Processed'; unitPrice = 0.0943 }
        @{ serviceName = 'Sentinel'; meterName = '50 GB Commitment Tier Capacity Reservation'; unitPrice = 152.1284 }
        @{ serviceName = 'Sentinel'; meterName = '100 GB Commitment Tier Capacity Reservation'; unitPrice = 279.2558 }
        @{ serviceName = 'Sentinel'; meterName = '200 GB Commitment Tier Capacity Reservation'; unitPrice = 517.0006 }
        @{ serviceName = 'Log Analytics'; meterName = 'Analytics Logs Data Ingestion'; unitPrice = 0.0 }
        @{ serviceName = 'Log Analytics'; meterName = 'Analytics Logs Data Ingestion'; unitPrice = 2.1737 }
        @{ serviceName = 'Log Analytics'; meterName = 'Analytics Logs Data Analyzed'; unitPrice = 1.7359 }
    )
    $script:Classic = @($script:Simplified | Where-Object { $_.serviceName -eq 'Log Analytics' })

    # A workspace: tables as @{ Name = @(GB over 30 days, plan) }.
    function Invoke-Estimate([hashtable]$Tables, [object[]]$Prices, [string]$Sku = 'PerGB2018', [int]$Level = 0, [switch]$Lake, [string]$SentinelSku = '') {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("bp-cost-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $tw = @(foreach ($k in $Tables.Keys) { [ordered]@{ DataType = $k; BillableLast30d = [double]$Tables[$k][0] } })
        $wt = @(foreach ($k in $Tables.Keys) { [ordered]@{ name = $k; properties = [ordered]@{ plan = $Tables[$k][1] } } })
        $skuDoc = [ordered]@{ name = $Sku }; if ($Level) { $skuDoc['capacityReservationLevel'] = $Level }
        ConvertTo-Json -InputObject $tw -Depth 5 | Set-Content (Join-Path $dir 'tables-with-data.json')
        ConvertTo-Json -InputObject $wt -Depth 5 | Set-Content (Join-Path $dir 'workspace-tables.json')
        ConvertTo-Json -InputObject ([ordered]@{ properties = [ordered]@{ sku = $skuDoc } }) -Depth 5 | Set-Content (Join-Path $dir 'workspace.json')
        ConvertTo-Json -InputObject ([ordered]@{ LookbackDays = 30 }) | Set-Content (Join-Path $dir 'run-context.json')
        ConvertTo-Json -InputObject ([ordered]@{ FetchedAtUtc = '2026-10-14T09:00:00Z'; Region = 'uksouth'; Prices = @($Prices | ForEach-Object { $_ + @{ currencyCode = 'GBP' } }) }) -Depth 5 | Set-Content (Join-Path $dir 'retail-prices.json')
        if ($Lake) { ConvertTo-Json -InputObject @(@{ name = 'default' }) | Set-Content (Join-Path $dir 'sentinel-data-lake.json') }
        if ($SentinelSku) { ConvertTo-Json -InputObject @([ordered]@{ name = 'SecurityInsights(ws)'; plan = [ordered]@{ product = 'OMSGallery/SecurityInsights' }; properties = [ordered]@{ sku = [ordered]@{ name = $SentinelSku } } }) -Depth 5 | Set-Content (Join-Path $dir 'solutions-installed.json') }
        try { Get-SentinelCostEstimate -InputRoot $dir -ResourcesRoot $script:resources } finally { Remove-Item $dir -Recurse -Force }
    }
    function Get-Row($Estimate, [string]$Table) { @($Estimate.AllTablesByCost | Where-Object Table -eq $Table)[0] }
}

Describe 'The price list it reads' {
    It 'fetches the Sentinel service, which is named Sentinel, and Log Analytics' {
        $src = Get-Content (Join-Path $script:engine 'Private/Get-AzureRetailPrice.ps1') -Raw
        $src | Should -Match "\[string\[\]\]\`$ServiceNames = @\('Sentinel', 'Log Analytics'\)"
        $src | Should -Not -Match '\$ServiceNames = @\(''Microsoft Sentinel'''
    }

    It 'maps the simplified Sentinel meters' {
        $m = Get-Content (Join-Path $script:resources 'cost-meters.json') -Raw | ConvertFrom-Json
        (@($m.categories | Where-Object id -eq 'SentinelAnalytics')[0]).meterNames | Should -Contain 'Pay-as-you-go Analysis'
        (@($m.categories | Where-Object id -eq 'SentinelBasic')[0]).meterNames | Should -Contain 'Basic Logs Analysis'
        (@($m.categories | Where-Object id -eq 'DataLakeProcessing')[0]).meterNames | Should -Contain 'Data processing Data Processed'
    }
}

Describe 'Pricing by plan' {
    It 'prices Analytics at the simplified rate, which covers Log Analytics ingestion' {
        $e = Invoke-Estimate @{ CommonSecurityLog = @(300, 'Analytics') } $script:Simplified
        $e.PricingModel | Should -Be 'Simplified'
        (Get-Row $e 'CommonSecurityLog').MonthlyCost | Should -Be ([math]::Round(300 * 4.0605, 2))
    }

    It 'records how the workspace is billed, from the Sentinel solution''s SKU' {
        (Invoke-Estimate @{ CommonSecurityLog = @(300, 'Analytics') } $script:Simplified -SentinelSku 'Unified').BilledPricingModel | Should -Be 'Simplified'
        (Invoke-Estimate @{ CommonSecurityLog = @(300, 'Analytics') } $script:Simplified -SentinelSku 'capacityreservation').BilledPricingModel | Should -Be 'Classic'
        (Invoke-Estimate @{ CommonSecurityLog = @(300, 'Analytics') } $script:Simplified).BilledPricingModel | Should -BeNullOrEmpty
    }

    It 'says when a workspace billed on classic pricing is priced at the simplified rate' {
        $classic = Invoke-Estimate @{ CommonSecurityLog = @(300, 'Analytics') } $script:Simplified -SentinelSku 'PerGB2018'
        @($classic.Caveats) -join ' ' | Should -Match 'billed on classic pricing .* priced at the simplified rate'
        @((Invoke-Estimate @{ CommonSecurityLog = @(300, 'Analytics') } $script:Simplified -SentinelSku 'Unified').Caveats) -join ' ' | Should -Not -Match 'billed on classic pricing'
    }

    It 'falls back to the classic Log Analytics and Sentinel pair without the simplified meter' {
        $e = Invoke-Estimate @{ CommonSecurityLog = @(300, 'Analytics') } $script:Classic
        $e.PricingModel | Should -Be 'Classic'
        (Get-Row $e 'CommonSecurityLog').MonthlyCost | Should -Be ([math]::Round(300 * (2.1737 + 1.7359), 2))
    }

    It 'prices Basic, and lake-only tables at lake ingestion plus processing' {
        $e = Invoke-Estimate @{ ContainerLogV2 = @(100, 'Basic'); NetFlow_CL = @(1000, 'DataLake') } $script:Simplified
        (Get-Row $e 'ContainerLogV2').MonthlyCost | Should -Be ([math]::Round(100 * 0.8529, 2))
        (Get-Row $e 'NetFlow_CL').MonthlyCost | Should -Be ([math]::Round(1000 * (0.0472 + 0.0943), 2))
    }

    It 'prices Auxiliary at the lake meters once onboarded to the lake, else at the Auxiliary meter' {
        $onLake = Invoke-Estimate @{ Proxy_CL = @(1000, 'Auxiliary') } $script:Simplified -Lake
        (Get-Row $onLake 'Proxy_CL').MonthlyCost | Should -Be ([math]::Round(1000 * (0.0472 + 0.0943), 2))
        $offLake = Invoke-Estimate @{ Proxy_CL = @(1000, 'Auxiliary') } $script:Simplified
        (Get-Row $offLake 'Proxy_CL').MonthlyCost | Should -Be ([math]::Round(1000 * 0.0472, 2))
    }
}

Describe 'Commitment tiers' {
    It 'charges the tier a day, and the GB above it at the tier''s effective rate' {
        # 4,500 GB over 30 days is 150 a day on the 100 GB tier.
        $e = Invoke-Estimate @{ CommonSecurityLog = @(3000, 'Analytics'); Syslog = @(1500, 'Analytics') } $script:Simplified 'CapacityReservation' 100
        $expected = 30 * (279.2558 + 50 * 279.2558 / 100)
        [math]::Round($e.MonthlyTotal, 0) | Should -Be ([math]::Round($expected, 0))
        $e.CommitmentTier.Level | Should -Be 100
        $e.CommitmentTier.Utilisation | Should -Be 150
        $e.CommitmentTier.EffectivePerGb | Should -Be 2.7926
        # Shared over the tables by their GB.
        [math]::Round((Get-Row $e 'CommonSecurityLog').MonthlyCost / (Get-Row $e 'Syslog').MonthlyCost, 2) | Should -Be 2
    }

    It 'charges the whole tier when the ingest is below it' {
        $e = Invoke-Estimate @{ CommonSecurityLog = @(1800, 'Analytics') } $script:Simplified 'CapacityReservation' 100
        [math]::Round($e.MonthlyTotal, 0) | Should -Be ([math]::Round(30 * 279.2558, 0))
    }

    It 'prices at pay-as-you-go and says so when the price list lacks the tier' {
        $e = Invoke-Estimate @{ CommonSecurityLog = @(3000, 'Analytics') } $script:Simplified 'CapacityReservation' 500
        $e.CommitmentTier | Should -BeNullOrEmpty
        (Get-Row $e 'CommonSecurityLog').MonthlyCost | Should -Be ([math]::Round(3000 * 4.0605, 2))
        ($e.Caveats -join ' ') | Should -Match '500 GB a day commitment tier, but the price list has no price for it'
    }

    It 'suggests the cheapest published tier when it beats the current cost' {
        $e = Invoke-Estimate @{ CommonSecurityLog = @(4500, 'Analytics') } $script:Simplified
        @($e.CommitmentTierWhatIf).Count | Should -Be 1
        $e.CommitmentTierWhatIf[0].Rung | Should -Be 100
        $e.CommitmentTierWhatIf[0].ProjectedMonthlyCost | Should -Be ([math]::Round(30 * (279.2558 + 50 * 2.792558), 2))
        $e.CommitmentTierWhatIf[0].DeltaVsCurrent | Should -BeLessThan 0
    }

    It 'suggests nothing when no tier is cheaper' {
        $e = Invoke-Estimate @{ CommonSecurityLog = @(300, 'Analytics') } $script:Simplified
        @($e.CommitmentTierWhatIf).Count | Should -Be 0
    }
}

Describe 'Data grants' {
    It 'prices the tables a grant may cover at list and reports them beside the total' {
        $e = Invoke-Estimate @{ SecurityEvent = @(300, 'Analytics'); SigninLogs = @(30, 'Analytics'); CommonSecurityLog = @(300, 'Analytics') } $script:Simplified
        (Get-Row $e 'SecurityEvent').MonthlyCost | Should -BeGreaterThan 0
        (Get-Row $e 'SecurityEvent').Benefit | Should -Be 'Defender for Servers P2'
        (Get-Row $e 'SigninLogs').Benefit | Should -Be 'Microsoft 365 E5'
        (Get-Row $e 'CommonSecurityLog').Benefit | Should -Be ''
        $grants = @($e.BenefitEligible)
        $grants.Count | Should -Be 2
        (@($grants | Where-Object Benefit -like 'Defender*')[0]).MonthlyCost | Should -Be (Get-Row $e 'SecurityEvent').MonthlyCost
        ($e.Caveats -join ' ') | Should -Match 'Data grants .* are not deducted'
    }

    It 'lists the grants'' tables as Microsoft publishes them, and no others' {
        $b = Get-Content (Join-Path $script:resources 'sentinel-benefit-tables.json') -Raw | ConvertFrom-Json
        $m365 = @($b.benefits | Where-Object id -eq 'm365')[0]
        $dfs = @($b.benefits | Where-Object id -eq 'defenderForServers')[0]
        $m365.tables | Should -Contain 'AADNonInteractiveUserSignInLogs'
        $m365.tables | Should -Contain 'DeviceProcessEvents'
        $dfs.tables | Should -Contain 'SecurityEvent'
        foreach ($t in 'CommonSecurityLog', 'Syslog', 'AzureDiagnostics', 'DnsEvents', 'ThreatIntelIndicators') { $b.tables | Should -Not -Contain $t }
        # The flat list the gap check reads is every grant's tables.
        @($b.tables).Count | Should -Be (@($m365.tables) + @($dfs.tables) | Sort-Object -Unique).Count
    }
}

Describe 'The currency it prices in' {
    BeforeAll {
        . (Join-Path $script:engine 'Private/Get-AzureRetailPrice.ps1')
        $script:repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }

    It 'guesses the currency from the region, USD where none fits' {
        $cases = @{ uksouth = 'GBP'; ukwest = 'GBP'; westeurope = 'EUR'; northeurope = 'EUR'; swedencentral = 'EUR'; switzerlandnorth = 'CHF'; norwayeast = 'NOK'
            eastus = 'USD'; southeastasia = 'USD'; canadacentral = 'CAD'; australiaeast = 'AUD'; japaneast = 'JPY'; centralindia = 'INR'; brazilsouth = 'BRL'; '' = 'USD' }
        foreach ($r in $cases.Keys) { Resolve-AzureRetailCurrency -Region $r | Should -Be $cases[$r] -Because $r }
    }

    It 'asks the Retail Prices API for that currency and caches each currency apart' {
        $src = Get-Content (Join-Path $script:engine 'Private/Get-AzureRetailPrice.ps1') -Raw
        $src | Should -Match 'prices\?currencyCode=''\$CurrencyCode''&'
        $src | Should -Match 'retail-prices-\$Region-\$CurrencyCode-\$today\.json'
        $src | Should -Match 'CurrencySource = \$CurrencySource'
    }

    It 'takes -Currency Auto by default, everywhere it is set, and records it' {
        $collector = Get-Content (Join-Path $script:engine 'Export-SentinelInventory.ps1') -Raw
        $collector | Should -Match "\[ValidateSet\('Auto', 'USD'.*'TWD'\)\]\s+\[string\]\`$Currency = 'Auto'"
        $collector | Should -Match 'Currency\s+= \$Currency'
        $collector | Should -Match "\`$currencyCode = if \(\`$Currency -eq 'Auto'\) \{ Resolve-AzureRetailCurrency -Region \`$region \}"
        foreach ($f in 'Public/New-iSOCBlueprint.ps1', 'Public/Export-iSOCBlueprintInventory.ps1') {
            $src = Get-Content (Join-Path $script:repo "Modules/iSOCBlueprint/$f") -Raw
            $src | Should -Match "\[string\] \`$Currency = 'Auto'" -Because $f
            $src | Should -Match 'Currency\s+= \$Currency' -Because $f
        }
        $ado = Get-Content (Join-Path $script:repo 'Pipelines/Sentinel-Blueprint.yml') -Raw
        $ado | Should -Match '- name: currency'
        $ado | Should -Match "\`$params\['Currency'\] = `"\`$\{\{ parameters\.currency \}\}`""
        $gh = Get-Content (Join-Path $script:repo '.github/workflows/sentinel-blueprint.yml') -Raw
        $gh | Should -Match "inputs\.currency \|\| vars\.BLUEPRINT_CURRENCY \|\| 'Auto'"
        $gh | Should -Match '-Currency\s+\$currency'
    }

    It 'says on the cost page which currency it used and why' {
        $renderer = Get-Content (Join-Path $script:engine 'Convert-SentinelInventoryToMarkdown.ps1') -Raw
        $renderer | Should -Match "taken from the workspace's region"
        $renderer | Should -Match 'as the run''s ``-Currency`` setting asked'
        $est = Get-Content (Join-Path $script:engine 'Private/Get-SentinelCostEstimate.ps1') -Raw
        $est | Should -Match 'CurrencySource\s+= \$currencySource'
    }
}

Describe 'The dashboard''s billed split' {
    It 'splits billed in full from grant eligible, keyed on the grant' {
        $build = Get-Content (Join-Path $script:engine 'SharePoint/Build-SentinelDocsSite.ps1') -Raw
        $build | Should -Match "\`$bucketAgg = @\{ 'Billed' = 0\.0; 'Grant eligible' = 0\.0 \}"
        $build | Should -Match "if \(\`$Row\.PSObject\.Properties\['Benefit'\]\) \{ return \`$\(if \(\[string\]\`$Row\.Benefit\) \{ 0\.0 \} else \{ \`$Gb \}\) \}"
        $html = Get-Content (Join-Path $script:engine 'SharePoint/templates/sharepoint-dashboard.html') -Raw
        $html | Should -Match 'Billed vs data grant eligible'
        $html | Should -Not -Match 'Free benefit'
    }
}
