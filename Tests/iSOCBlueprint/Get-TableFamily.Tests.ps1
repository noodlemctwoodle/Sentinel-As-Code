#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the Blueprint's source-family helpers.

.DESCRIPTION
    Get-TableFamily groups Log Analytics tables into the families the
    estate flow and the billing Sankey use; Get-ProductFamily does the same
    for the products that raise first-party alerts. Both the Markdown
    renderer and the SharePoint site build rely on them agreeing.

.NOTES
    File:         Tests/iSOCBlueprint/Get-TableFamily.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-12
    Version:      0.1.1
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Get-TableFamily.ps1')
}

Describe 'Get-TableFamily' {
    It 'maps <Table> to <Expected>' -ForEach @(
        @{ Table = 'SigninLogs';            Expected = 'Entra ID / Identity' }
        @{ Table = 'AuditLogs';             Expected = 'Entra ID / Identity' }
        @{ Table = 'DeviceEvents';          Expected = 'Defender XDR' }
        @{ Table = 'CloudAppEvents';        Expected = 'Defender XDR' }
        @{ Table = 'Syslog';                Expected = 'Azure / Syslog' }
        @{ Table = 'AzureActivity';         Expected = 'Azure / Syslog' }
        @{ Table = 'ThreatIntelligenceIndicator'; Expected = 'Threat Intelligence' }
        @{ Table = 'Firewall_CL';           Expected = 'Custom logs' }
        @{ Table = 'Usage';                 Expected = 'Other' }
        @{ Table = '';                      Expected = 'Other' }
    ) {
        Get-TableFamily -Table $Table | Should -Be $Expected
    }
}

Describe 'Get-ProductFamily' {
    It 'maps <Product> to <Expected>' -ForEach @(
        @{ Product = 'Azure Active Directory Identity Protection'; Expected = 'Entra ID / Identity' }
        @{ Product = 'Microsoft Defender for Identity';            Expected = 'Entra ID / Identity' }
        @{ Product = 'Microsoft 365 Defender';                     Expected = 'Defender XDR' }
        @{ Product = 'Microsoft Defender for Endpoint';            Expected = 'Defender XDR' }
        @{ Product = 'Office 365 Advanced Threat Protection';      Expected = 'Defender XDR' }
        @{ Product = 'Microsoft Defender for Cloud';               Expected = 'Azure / Syslog' }
        @{ Product = 'Azure Security Center for IoT';              Expected = 'Azure / Syslog' }
        @{ Product = 'Azure Sentinel';                             Expected = 'Other' }
        @{ Product = 'Contoso SOAR';                               Expected = 'Other' }
        @{ Product = $null;                                        Expected = 'Other' }
    ) {
        Get-ProductFamily -Product $Product | Should -Be $Expected
    }
}
