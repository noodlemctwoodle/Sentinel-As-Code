#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the shared data lake tier classifier.

.DESCRIPTION
    Get-TableTier and Get-TableTierProfile feed both the data lake page
    (88-sentinel-data-lake.md) and the SharePoint dashboard's lake panel and
    billing flow. These tests pin the four categories, the Basic and
    Auxiliary side counts, the extended-retention rows and the behaviour on
    a tenant that is not enrolled.

.NOTES
    File:         Tests/Documenter/Get-TableTierProfile.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-12
    Version:      0.1.0
    Last Updated: 2026-10-12
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Tools/Documenter/Private/Get-TableTierProfile.ps1')

    function New-TierTable {
        param([string]$Name, [string]$Plan = 'Analytics', [int]$Retention = 30, [int]$Total = 30)
        [pscustomobject]@{
            name       = $Name
            properties = [pscustomobject]@{ plan = $Plan; retentionInDays = $Retention; totalRetentionInDays = $Total }
        }
    }

    $script:tables = @(
        (New-TierTable -Name 'SecurityEvent' -Retention 30 -Total 30),
        (New-TierTable -Name 'SigninLogs' -Retention 90 -Total 365),
        (New-TierTable -Name 'Firewall_CL' -Plan 'DataLake' -Retention 0 -Total 365),
        (New-TierTable -Name 'Verbose_CL' -Plan 'Basic' -Retention 30 -Total 30),
        (New-TierTable -Name 'Archive_CL' -Plan 'Auxiliary' -Retention 30 -Total 365)
    )
}

Describe 'Get-TableTier' {
    It 'returns LakeOnly for a DataLake plan table whatever the enrolment flag' {
        Get-TableTier -Table $script:tables[2] -LakeEnrolled $false | Should -Be 'LakeOnly'
        Get-TableTier -Table $script:tables[2] -LakeEnrolled $true | Should -Be 'LakeOnly'
    }

    It 'returns MirroredExtended when enrolled and total retention exceeds analytics retention' {
        Get-TableTier -Table $script:tables[1] -LakeEnrolled $true | Should -Be 'MirroredExtended'
    }

    It 'returns MirroredOnly when enrolled and retention matches' {
        Get-TableTier -Table $script:tables[0] -LakeEnrolled $true | Should -Be 'MirroredOnly'
    }

    It 'returns AnalyticsOnly when not enrolled, even with extended retention' {
        Get-TableTier -Table $script:tables[1] -LakeEnrolled $false | Should -Be 'AnalyticsOnly'
    }

    It 'treats a table without properties as AnalyticsOnly or MirroredOnly' {
        $bare = [pscustomobject]@{ name = 'Bare' }
        Get-TableTier -Table $bare -LakeEnrolled $false | Should -Be 'AnalyticsOnly'
        Get-TableTier -Table $bare -LakeEnrolled $true | Should -Be 'MirroredOnly'
    }
}

Describe 'Get-TableTierProfile' {
    It 'counts the four tiers over an enrolled tenant' {
        $p = Get-TableTierProfile -Tables $script:tables -LakeEnrolled $true
        $p.Tiers.AnalyticsOnly | Should -Be 0
        $p.Tiers.MirroredOnly | Should -Be 2
        $p.Tiers.MirroredExtended | Should -Be 2
        $p.Tiers.LakeOnly | Should -Be 1
    }

    It 'records Basic and Auxiliary tables on the side' {
        $p = Get-TableTierProfile -Tables $script:tables -LakeEnrolled $true
        $p.Tiers.Basic | Should -Be 1
        $p.Tiers.Auxiliary | Should -Be 1
    }

    It 'lists the extended-retention and lake-only tables with their day split' {
        $p = Get-TableTierProfile -Tables $script:tables -LakeEnrolled $true
        @($p.RetentionRows).Count | Should -Be 3
        ($p.RetentionRows | Where-Object Table -eq 'SigninLogs').LakeOnlyDays | Should -Be 275
        ($p.RetentionRows | Where-Object Table -eq 'Firewall_CL').Plan | Should -Be 'DataLake'
        ($p.RetentionRows | Where-Object Table -eq 'Archive_CL').TotalDays | Should -Be 365
        $p.LakeOnlyTables | Should -Be @('Firewall_CL')
    }

    It 'puts every table on the analytics tier when the tenant is not enrolled' {
        $p = Get-TableTierProfile -Tables $script:tables -LakeEnrolled $false
        $p.Tiers.AnalyticsOnly | Should -Be 4
        $p.Tiers.LakeOnly | Should -Be 1
        $p.Tiers.MirroredOnly | Should -Be 0
        $p.Tiers.MirroredExtended | Should -Be 0
    }

    It 'returns zero counts and no rows for an empty or null set' {
        $p = Get-TableTierProfile -Tables $null -LakeEnrolled $true
        ($p.Tiers.Values | Measure-Object -Sum).Sum | Should -Be 0
        @($p.RetentionRows).Count | Should -Be 0
        @($p.LakeOnlyTables).Count | Should -Be 0
    }
}
