#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the data connector catalogue and its helpers.

.DESCRIPTION
    Two parts. Guards over the shipped resource
    (Modules/iSOCBlueprint/Engine/Private/Resources/connector-catalogue.json): its
    provenance fields, unique ids and table lists. Then the helpers in
    Modules/iSOCBlueprint/Engine/Private/Get-ConnectorCatalogue.ps1 against a small
    hand-built catalogue: connector ids from classic and codeless
    connectors, 7-day activity with free tables included, the per-connector
    status (receiving, silent, not in the catalogue) and the table and
    solution labels.

.NOTES
    File:         Tests/iSOCBlueprint/Get-ConnectorCatalogue.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.1
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Modules/iSOCBlueprint/Engine/Private/Get-ConnectorCatalogue.ps1')
    $script:resource = Join-Path $PSScriptRoot '../../Modules/iSOCBlueprint/Engine/Private/Resources/connector-catalogue.json'

    $script:testCatalogue = Join-Path ([System.IO.Path]::GetTempPath()) "connector-catalogue-$(New-Guid).json"
    @{
        version    = '2026-07-09T15:25:28Z'
        connectors = @(
            @{ id = 'AzureActiveDirectory'; title = 'Microsoft Entra ID'; publisher = 'Microsoft'; solution = 'Microsoft Entra ID'; deprecated = $false; tables = @('AuditLogs', 'SigninLogs') }
            @{ id = 'Office365'; title = 'Microsoft 365'; publisher = 'Microsoft'; solution = 'Microsoft 365'; deprecated = $false; tables = @('OfficeActivity') }
            @{ id = 'AzureDevOpsAuditLogs'; title = 'Azure DevOps Audit Logs'; publisher = 'Microsoft'; solution = 'AzureDevOpsAuditing'; deprecated = $false; tables = @('ADOAuditLogs_CL', 'SigninLogs') }
            @{ id = 'OldAgent'; title = 'Old agent'; publisher = 'Vendor'; solution = 'Vendor Solution'; deprecated = $true; tables = @('CommonSecurityLog') }
            @{ id = 'CefAma'; title = 'CEF via AMA'; publisher = 'Microsoft'; solution = 'Common Event Format'; deprecated = $false; tables = @('CommonSecurityLog') }
            @{ id = 'VendorA'; title = 'Vendor A'; publisher = 'A'; solution = 'Vendor A'; deprecated = $false; tables = @('CommonSecurityLog') }
            @{ id = 'VendorB'; title = 'Vendor B'; publisher = 'B'; solution = 'Vendor B'; deprecated = $false; tables = @('CommonSecurityLog') }
            @{ id = 'Empty'; title = 'No mapping'; publisher = 'X'; solution = 'X'; deprecated = $false; tables = @() }
        )
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:testCatalogue
    $script:cat = Import-ConnectorCatalogue -Path $script:testCatalogue
}

AfterAll {
    if ($script:testCatalogue -and (Test-Path $script:testCatalogue)) { Remove-Item $script:testCatalogue -Force }
}

Describe 'The shipped connector catalogue' {

    BeforeAll { $script:doc = Get-Content -LiteralPath $script:resource -Raw | ConvertFrom-Json -Depth 8 }

    It 'records where it came from' {
        $script:doc.'$comment' | Should -Match 'Update-ConnectorCatalogue.ps1'
        $script:doc.source | Should -Match 'Sentinel-As-Code-Toolkit'
        $script:doc.upstream | Should -Match 'Azure-Sentinel'
        $script:doc.license | Should -Match 'MIT'
    }

    It 'has hundreds of connectors with unique ids, each with a title and a table list' {
        @($script:doc.connectors).Count | Should -BeGreaterThan 400
        $ids = @($script:doc.connectors | ForEach-Object id)
        ($ids | Sort-Object -Unique).Count | Should -Be $ids.Count
        foreach ($c in $script:doc.connectors) {
            $c.title | Should -Not -BeNullOrEmpty -Because $c.id
            ,@($c.tables) | Should -BeOfType [object[]] -Because $c.id
            $c.title | Should -Not -Match '\[deprecated\]' -Because 'the flag carries it'
        }
    }

    It 'knows the core Microsoft connectors and their tables' {
        $loaded = Import-ConnectorCatalogue -Path $script:resource
        @($loaded.ById['AzureActiveDirectory'].tables) | Should -Contain 'SigninLogs'
        @($loaded.ById['Office365'].tables) | Should -Contain 'OfficeActivity'
        $loaded.Version | Should -Match '^\d{4}-\d{2}-\d{2}$'
    }
}

Describe 'Get-WorkspaceConnectorId' {

    It 'uses the kind of a classic connector' {
        Get-WorkspaceConnectorId -Connector ([pscustomobject]@{ kind = 'Office365'; properties = [pscustomobject]@{ dataTypes = @{} } }) | Should -Be 'Office365'
    }

    It 'uses the connector definition of a codeless connector' {
        Get-WorkspaceConnectorId -Connector ([pscustomobject]@{ kind = 'RestApiPoller'; properties = [pscustomobject]@{ connectorDefinitionName = 'AzureDevOpsAuditLogs' } }) | Should -Be 'AzureDevOpsAuditLogs'
    }
}

Describe 'Get-TableActivity' {

    It 'counts free volume, sums the rows of one table and falls back to billable volume' {
        $a = Get-TableActivity -TablesWithData @(
            [pscustomobject]@{ DataType = 'OfficeActivity'; BillableLast7d = 0; IngestedLast7d = 95 }
            [pscustomobject]@{ DataType = 'SecurityEvent'; IngestedLast7d = 2 }
            [pscustomobject]@{ DataType = 'securityevent'; IngestedLast7d = 3 }
            [pscustomobject]@{ DataType = 'Syslog'; BillableLast7d = 4 }
        )
        $a['OfficeActivity'] | Should -Be 95
        $a['SecurityEvent'] | Should -Be 5
        $a['Syslog'] | Should -Be 4
    }
}

Describe 'Get-ConnectorCatalogueStatus' {

    BeforeAll {
        $activity = @{ 'SigninLogs' = 3.0; 'OfficeActivity' = 0.0 }
        $script:rows = @(Get-ConnectorCatalogueStatus -Catalogue $script:cat -Activity $activity -Connectors @(
                [pscustomobject]@{ kind = 'AzureActiveDirectory'; properties = [pscustomobject]@{} }
                [pscustomobject]@{ kind = 'Office365'; properties = [pscustomobject]@{} }
                [pscustomobject]@{ kind = 'OldAgent'; properties = [pscustomobject]@{} }
                [pscustomobject]@{ kind = 'MicrosoftThreatIntelligence'; properties = [pscustomobject]@{} }
                [pscustomobject]@{ kind = 'Empty'; properties = [pscustomobject]@{} }
            ))
    }

    It 'calls a connector with data in any of its tables receiving, and lists the quiet ones' {
        $aad = $script:rows | Where-Object Id -eq 'AzureActiveDirectory'
        $aad.Status | Should -Be 'Receiving data'
        $aad.WithData | Should -Be @('SigninLogs')
        $aad.Quiet | Should -Be @('AuditLogs')
    }

    It 'calls a connector silent when none of its tables received data' {
        ($script:rows | Where-Object Id -eq 'Office365').Status | Should -Be 'Silent'
    }

    It 'marks deprecated connectors and connectors the catalogue does not know or cannot map' {
        ($script:rows | Where-Object Id -eq 'OldAgent').Deprecated | Should -BeTrue
        ($script:rows | Where-Object Id -eq 'MicrosoftThreatIntelligence').Status | Should -Be 'Not in the catalogue'
        ($script:rows | Where-Object Id -eq 'Empty').Status | Should -Be 'No tables in the catalogue'
    }
}

Describe 'Get-TableConnectorLabel and Get-TableSolutionLabel' {

    It 'credits a row to its own connector when that connector lists the table' {
        Get-TableConnectorLabel -Catalogue $script:cat -Table 'SigninLogs' -ConnectorId 'AzureActiveDirectory' | Should -Be 'Microsoft Entra ID'
    }

    It 'names up to three candidates, marking the connected ones' {
        Get-TableConnectorLabel -Catalogue $script:cat -Table 'SigninLogs' -ConnectedIds @('AzureDevOpsAuditLogs') | Should -Be 'Azure DevOps Audit Logs (connected); Microsoft Entra ID'
    }

    It 'calls a table more connectors list shared, and a table it does not know blank' {
        Get-TableConnectorLabel -Catalogue $script:cat -Table 'CommonSecurityLog' -ConnectedIds @('CefAma') | Should -Be 'Shared by 4 connectors'
        Get-TableConnectorLabel -Catalogue $script:cat -Table 'FirewallLogs_CL' | Should -Be ''
    }

    It 'names the solutions that ship a table and marks the installed ones' {
        Get-TableSolutionLabel -Catalogue $script:cat -Table 'SigninLogs' -InstalledSolutions @('microsoft entra id') | Should -Be 'AzureDevOpsAuditing; Microsoft Entra ID (installed)'
        Get-TableSolutionLabel -Catalogue $script:cat -Table 'CommonSecurityLog' -InstalledSolutions @('Common Event Format') | Should -Be 'Shared by 4 solutions; installed: Common Event Format'
        Get-TableSolutionLabel -Catalogue $script:cat -Table 'Nope_CL' | Should -Be ''
    }
}
