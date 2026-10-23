#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the Blueprint's text formatting helpers: counts, GB,
    money, dates, plurals and API names written as the dashboard writes
    them.

.DESCRIPTION
    The report pages, the findings and the dashboard must write a figure
    the same way. These pin the house style the helpers implement and the
    dashboard's fmtN, fmtGb, fmtMoney and fmtDate follow.

.NOTES
    File:         Tests/iSOCBlueprint/Format-BlueprintText.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.1.0
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Private/Format-BlueprintText.ps1')
}

Describe 'Counts and numbers' {
    It 'writes counts with thousands separators' {
        Format-BlueprintCount 13858711766 | Should -Be '13,858,711,766'
        Format-BlueprintCount '3343' | Should -Be '3,343'
        Format-BlueprintCount 0 | Should -Be '0'
    }

    It 'writes a fixed number of decimal places with separators' {
        Format-BlueprintNumber 1963.4 | Should -Be '1,963.40'
        Format-BlueprintNumber 2000 -Decimals 0 | Should -Be '2,000'
    }

    It 'returns text it cannot read as given, and nothing for null' {
        Format-BlueprintCount 'n/a' | Should -Be 'n/a'
        Format-BlueprintCount $null | Should -Be ''
    }
}

Describe 'GB' {
    It 'writes GB to two places with separators, keeping the trailing zero' {
        Format-BlueprintGb 56858.2 | Should -Be '56,858.20'
        Format-BlueprintGb '13448.9' | Should -Be '13,448.90'
        Format-BlueprintGb 0 | Should -Be '0.00'
    }

    It 'writes a trace too small to show as <0.01' {
        Format-BlueprintGb 0.001 | Should -Be '<0.01'
    }
}

Describe 'Money' {
    It 'writes the symbol, whole units from 1,000 and pence below, as the dashboard does' {
        Format-BlueprintMoney 137355.53 'GBP' | Should -Be '£137,356'
        Format-BlueprintMoney 491.76 'GBP' | Should -Be '£491.76'
        Format-BlueprintMoney 4528.47 'usd' | Should -Be 'US$4,528'
        Format-BlueprintMoney -4.1 'EUR' | Should -Be '-€4.10'
    }

    It 'writes an unknown currency as its code before the figure' {
        Format-BlueprintMoney 12.5 'SEK' | Should -Be 'SEK 12.50'
    }
}

Describe 'Dates' {
    It 'writes a date as 15 Oct 2026, with invariant month names' {
        Format-BlueprintDate '2026-09-14' | Should -Be '14 Sep 2026'
        Format-BlueprintDate ([datetime]::new(2026, 10, 15, 21, 3, 0, [System.DateTimeKind]::Utc)) | Should -Be '15 Oct 2026'
    }

    It 'adds the time and UTC on request, from any ISO timestamp' {
        Format-BlueprintDate '2026-10-14T23:16:38Z' -Time | Should -Be '14 Oct 2026 23:16 UTC'
    }

    It 'returns text that is not a date as given' {
        Format-BlueprintDate 'soon' | Should -Be 'soon'
        Format-BlueprintDate $null | Should -Be ''
    }
}

Describe 'Plurals' {
    It 'chooses the noun by the count, never table(s)' {
        Format-BlueprintPlural 1 'table' | Should -Be '1 table'
        Format-BlueprintPlural 3343 'run' | Should -Be '3,343 runs'
        Format-BlueprintPlural 2 'policy' 'policies' | Should -Be '2 policies'
        Format-BlueprintPlural 0 'forwarder' | Should -Be '0 forwarders'
        Format-BlueprintPlural 1 'rule' -NoCount | Should -Be 'rule'
    }
}

Describe 'API names in words' {
    It 'writes CamelCase values as words, keeping acronyms' {
        ConvertTo-BlueprintWords 'CredentialAccess' | Should -Be 'Credential access'
        ConvertTo-BlueprintWords 'BenignPositive' | Should -Be 'Benign positive'
        ConvertTo-BlueprintWords 'CommandAndControl' | Should -Be 'Command and control'
        ConvertTo-BlueprintWords 'IPAddress' | Should -Be 'IP address'
        ConvertTo-BlueprintWords 'Undetermined' | Should -Be 'Undetermined'
        ConvertTo-BlueprintWords 'Already words' | Should -Be 'Already words'
    }

    It 'names regions and workspace SKUs as the portal and the dashboard do' {
        Get-BlueprintRegionName 'uksouth' | Should -Be 'UK South'
        Get-BlueprintRegionName 'UK South' | Should -Be 'UK South'
        Get-BlueprintRegionName 'marsnorth' | Should -Be 'marsnorth'
        Get-BlueprintSkuName 'CapacityReservation' | Should -Be 'Commitment tier'
        Get-BlueprintSkuName 'pergb2018' | Should -Be 'Pay-as-you-go'
        Get-BlueprintSkuName 'Unknown' | Should -Be 'Unknown'
    }

    It 'matches the dashboard''s region and SKU names' {
        $html = Get-Content (Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint/templates/sharepoint-dashboard.html') -Raw
        foreach ($k in 'uksouth', 'westeurope', 'eastus2', 'australiacentral2') {
            $html.Contains("${k}:'$(Get-BlueprintRegionName $k)'") | Should -BeTrue -Because $k
        }
        foreach ($k in 'PerGB2018', 'CapacityReservation', 'LACluster') {
            $html.Contains("${k}:'$(Get-BlueprintSkuName $k)'") | Should -BeTrue -Because $k
        }
    }
}
