#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for the pure helpers in Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1.

.DESCRIPTION
    Invoke-TableMigrationReview is the read-only assess-and-plan stage of the
    ClassicToDcr toolkit: it discovers classic custom-log tables, scores their
    dependency impact, and maps each to a Content Hub solution. Most of the
    script talks to Azure and cannot be unit tested, so this suite covers the
    two decisions its report hinges on:

      Test-KqlReferencesTable   Whether a KQL body references a table by name.
                                A substring match here would over-report impact
                                (MyApp_CL matching MyApp_CL_v2), so the
                                word-boundary behaviour is pinned down.
      Resolve-ConnectorKind     Classifying a connector as CCF / AzureFunctions
                                / AMA / Platform / Agent / Legacy from its ID.
                                This drives the "no CCF equivalent" warning that
                                tells an operator a connector needs rebuilding.

    Deliberately not covered: the ARM calls, the Content Hub package fetch, and
    the HTML/CSV/JSON writers. Those need a live workspace.
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1'

    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop
    Import-ScriptFunctions -Path $scriptPath
}

Describe 'Invoke-TableMigrationReview: script-level contract' {
    BeforeAll {
        $script:sourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1'
        $script:sourceText = Get-Content -Path $script:sourcePath -Raw
    }

    It 'parses cleanly' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $script:sourcePath, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'has the correct repo-relative header path' {
        $script:sourceText | Should -Match 'Sentinel-As-Code/Tools/ClassicToDcr/Invoke-TableMigrationReview\.ps1'
    }

    It 'records its origin as the folded-in CLv1 analyzer' {
        # The provenance note keeps the MIT->Apache-2.0 relicensing auditable.
        $script:sourceText | Should -Match 'Sentinel-CLv1-Analyzer'
    }

    It 'reads solution-mapping.json with -AsHashtable' {
        # The bundled mapping contains an empty-string property name, which
        # ConvertFrom-Json only tolerates in hashtable mode. Losing this switch
        # turns every lookup into a silent miss.
        $script:sourceText | Should -Match 'ConvertFrom-Json[^\r\n]*-AsHashtable'
    }

    It 'is read-only: issues no PUT/PATCH/DELETE ARM calls' {
        # The tool is documented as assessment-only. Guard against a mutating
        # verb slipping into the REST helper. Invoke-ArmRequest hard-codes Get.
        $script:sourceText | Should -Not -Match "-Method\s+'?(Put|Patch|Delete)'?"
    }

    It 'uses no em-dashes in prose' {
        $script:sourceText | Should -Not -Match ([char]0x2014)
    }

    It 'is standalone: does not import the Sentinel.Common module' {
        $script:sourceText | Should -Not -Match 'Import-Module[^\r\n]*Sentinel\.Common'
        $script:sourceText | Should -Not -Match 'Sentinel\.Common\.psd1'
    }
}

Describe 'Test-KqlReferencesTable' {
    It 'matches a whole-word table reference' {
        Test-KqlReferencesTable -Query 'MyApp_CL | where Level > 1' -TableName 'MyApp_CL' | Should -BeTrue
    }

    It 'is case-insensitive' {
        Test-KqlReferencesTable -Query 'myapp_cl | count' -TableName 'MyApp_CL' | Should -BeTrue
    }

    It 'does not match a longer table that merely starts with the name' {
        # The over-reporting trap: MyApp_CL must not match MyApp_CL_v2.
        Test-KqlReferencesTable -Query 'MyApp_CL_v2 | count' -TableName 'MyApp_CL' | Should -BeFalse
    }

    It 'does not match the name embedded inside another identifier' {
        Test-KqlReferencesTable -Query 'let x_MyApp_CL_y = 1;' -TableName 'MyApp_CL' | Should -BeFalse
    }

    It 'returns false for an empty query' {
        Test-KqlReferencesTable -Query '' -TableName 'MyApp_CL' | Should -BeFalse
    }
}

Describe 'Get-MatchedTable' {
    It 'returns only the tables the query references' {
        $result = Get-MatchedTable -Query 'union MyApp_CL, Other_CL | count' -TableNames @('MyApp_CL', 'Unused_CL', 'Other_CL')
        $result | Should -Contain 'MyApp_CL'
        $result | Should -Contain 'Other_CL'
        $result | Should -Not -Contain 'Unused_CL'
    }

    It 'returns nothing for an empty query' {
        Get-MatchedTable -Query '' -TableNames @('MyApp_CL') | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-ConnectorKind' {
    It 'classifies "<Id>" as <Expected>' -ForEach @(
        @{ Id = 'MyConnectorCCPDefinition'; Expected = 'CCF' }
        @{ Id = 'AwsS3Serverless';          Expected = 'AzureFunctions' }
        @{ Id = 'SomethingPolling';         Expected = 'AzureFunctions' }
        @{ Id = 'SyslogAma';                Expected = 'AMA' }
        @{ Id = 'AzureActiveDirectory';     Expected = 'Platform' }
        @{ Id = 'Office365';                Expected = 'Platform' }
        @{ Id = 'Syslog';                   Expected = 'Agent' }
        @{ Id = 'CEF';                      Expected = 'Agent' }
        @{ Id = 'SomeVendorCustomLog';      Expected = 'Legacy' }
    ) {
        Resolve-ConnectorKind -ConnectorId $Id | Should -Be $Expected
    }

    It 'returns Unknown for an empty connector id' {
        Resolve-ConnectorKind -ConnectorId '' | Should -Be 'Unknown'
    }
}
