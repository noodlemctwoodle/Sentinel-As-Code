#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the connector catalogue refresh.

.DESCRIPTION
    Runs Invoke-iSOCBlueprintConnectorCatalogueUpdate against a small
    Toolkit connectors.json built here and checks the catalogue it writes:
    the slimmer connector shape, one connector per line, deprecated titles,
    single-table strings turned into lists, rows without an id dropped and
    the provenance header.

.NOTES
    File:         Tests/iSOCBlueprint/Connector-Catalogue-Update.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeAll {
    $script:moduleRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/iSOCBlueprint'
    Import-Module (Join-Path $script:moduleRoot 'iSOCBlueprint.psd1') -Force
    $script:module = Get-Module iSOCBlueprint

    $script:source = Join-Path $TestDrive 'connectors.json'
    @{
        metadata          = @{ generatedDate = '2026-11-01T10:00:00Z'; sourceRepository = 'Azure/Azure-Sentinel'; extractionMethod = 'csv' }
        tablesByConnector = @(
            @{ connectorId = 'Beta'; connectorTitle = 'Beta [Deprecated]'; publisher = 'P'; source = 'Solutions/Beta'; tables = @('T2', 'T1', 'T1') }
            @{ connectorId = 'Alpha'; connectorTitle = 'Alpha'; publisher = 'Q'; source = 'Solutions/Alpha'; tables = 'OnlyOne' }
            @{ connectorTitle = 'no id' }
        )
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:source
    $script:target = Join-Path $TestDrive 'catalogue.json'
    & $script:module { param($s, $t) Invoke-iSOCBlueprintConnectorCatalogueUpdate -Source $s -OutputPath $t 6> $null } $script:source $script:target
    $script:text = Get-Content -LiteralPath $script:target -Raw
    $script:doc = $script:text | ConvertFrom-Json -Depth 8
}

Describe 'Invoke-iSOCBlueprintConnectorCatalogueUpdate' {
    It 'writes valid JSON with the connectors sorted by id and rows without an id dropped' {
        @($script:doc.connectors | ForEach-Object id) | Should -Be @('Alpha', 'Beta')
    }

    It 'turns a single-table string into a list and sorts and de-duplicates the tables' {
        @(($script:doc.connectors | Where-Object id -eq 'Alpha').tables) | Should -Be @('OnlyOne')
        @(($script:doc.connectors | Where-Object id -eq 'Beta').tables) | Should -Be @('T1', 'T2')
    }

    It 'records a deprecated title without the marker and drops the Solutions/ prefix' {
        $beta = $script:doc.connectors | Where-Object id -eq 'Beta'
        $beta.deprecated | Should -BeTrue
        $beta.title | Should -Be 'Beta'
        $beta.solution | Should -Be 'Beta'
    }

    It 'writes one connector per line so a refresh diffs cleanly' {
        @($script:text -split "`n" | Where-Object { $_ -match '^\s+\{"id":' }).Count | Should -Be 2
    }

    It 'records where it came from' {
        $script:doc.'$comment' | Should -Match 'Update-iSOCBlueprintConnectorCatalogue'
        $script:text | Should -Match '"version": "2026-11-01T10:00:00Z"'
        $script:doc.source | Should -Be $script:source
        $script:doc.upstream | Should -Match 'Azure/Azure-Sentinel'
    }

    It 'refuses a file that is not the Toolkit connectors.json' {
        $bad = Join-Path $TestDrive 'bad.json'
        '{"x":1}' | Set-Content -LiteralPath $bad
        { & $script:module { param($s, $t) Invoke-iSOCBlueprintConnectorCatalogueUpdate -Source $s -OutputPath $t 6> $null } $bad (Join-Path $TestDrive 'never.json') } |
            Should -Throw '*No tablesByConnector*'
        Test-Path (Join-Path $TestDrive 'never.json') | Should -BeFalse
    }
}
