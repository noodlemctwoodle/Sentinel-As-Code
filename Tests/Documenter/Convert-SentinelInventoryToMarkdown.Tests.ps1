#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for the Sentinel Documenter renderer.

.DESCRIPTION
    Drives Convert-SentinelInventoryToMarkdown.ps1 against the fixture under
    Tests/Documenter/Fixtures/sample/_raw and asserts that the expected Markdown
    section files are produced and contain the headings + signal phrases the
    template promises.

    Output is written to a temp folder so repeated test runs don't pollute the
    fixture or the working tree.
#>

BeforeAll {
    $script:repoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:fixtureWs  = Join-Path $script:repoRoot 'Tests/Documenter/Fixtures/sample'
    $script:fixtureRaw = Join-Path $script:fixtureWs '_raw'
    $script:renderer   = Join-Path $script:repoRoot 'Scripts/Documenter/Convert-SentinelInventoryToMarkdown.ps1'
    $script:resources  = Join-Path $script:repoRoot 'Scripts/Documenter/Private/Resources'

    $script:outDir = Join-Path ([System.IO.Path]::GetTempPath()) "documenter-test-$(New-Guid)"
    New-Item -ItemType Directory -Path $script:outDir -Force | Out-Null

    # Re-shape the fixture into a temp tree the renderer expects: <root>/<workspace>/_raw/*.json.
    $tempWsRoot = Join-Path $script:outDir 'law-sentinel-test'
    New-Item -ItemType Directory -Path (Join-Path $tempWsRoot '_raw') -Force | Out-Null
    Get-ChildItem -Path $script:fixtureRaw -File | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $tempWsRoot '_raw') -Force
    }
    $script:tempWsRoot = $tempWsRoot

    # Run the renderer.
    & $script:renderer `
        -WorkspaceName 'law-sentinel-test' `
        -InputRoot     $tempWsRoot `
        -OutputRoot    $tempWsRoot `
        -ResourcesRoot $script:resources `
        -InformationAction SilentlyContinue
}

AfterAll {
    if ($script:outDir -and (Test-Path $script:outDir)) {
        Remove-Item -Recurse -Force -Path $script:outDir -ErrorAction SilentlyContinue
    }
}

Describe 'Sentinel Documenter renderer' {

    Context 'produces every expected section file' {

        $expected = @(
            'index.md','00-overview.md','01-executive-summary.md',
            '10-data-connectors.md','11-sentinel-health.md','12-soc-optimization.md',
            '15-incidents.md',
            '20-analytics-rules.md','21-analytics-by-volume.md','22-analytics-microsoft-rules.md',
            '23-analytics-modifications.md','24-analytics-by-solution.md',
            '25-mitre-coverage.md','26-ueba.md','27-threat-intelligence.md',
            '30-hunting-queries.md','35-parsers-functions.md',
            '36-data-export.md','37-search-restore.md','38-summary-rules.md',
            '40-workbooks.md','50-watchlists.md','60-automation-rules-playbooks.md',
            '70-content-hub.md','80-workspace.md','81-table-plans-retention.md',
            '82-dedicated-cluster.md','83-data-collection.md','84-cost-estimate.md',
            '85-rbac.md','86-subscription-context.md','87-azure-monitor-agents.md',
            '90-gap-analysis.md','96-references-microsoft.md','99-references.md'
        )

        It 'creates <_>' -ForEach $expected {
            $p = Join-Path $script:tempWsRoot $_
            Test-Path $p | Should -BeTrue -Because "renderer should produce $_"
            (Get-Item $p).Length | Should -BeGreaterThan 0
        }
    }

    Context '00-overview.md surfaces the headline facts' {
        BeforeAll {
            $script:overview = Get-Content (Join-Path $script:tempWsRoot '00-overview.md') -Raw
        }

        It 'contains the workspace SKU' {
            $script:overview | Should -Match 'PerGB2018'
        }

        It 'contains the cost headline currency' {
            $script:overview | Should -Match 'GBP'
        }

        It 'links to the cost-estimate page' {
            $script:overview | Should -Match '\(84-cost-estimate\.md\)'
        }
    }

    Context '25-mitre-coverage.md renders the tactic matrix' {
        BeforeAll {
            $script:mitre = Get-Content (Join-Path $script:tempWsRoot '25-mitre-coverage.md') -Raw
        }

        It 'lists Initial Access (covered by the test fixture rule)' {
            $script:mitre | Should -Match 'Initial Access'
        }

        It 'shows zero-coverage tactics with a red marker' {
            $script:mitre | Should -Match '🔴 None'
        }
    }

    Context '81-table-plans-retention.md surfaces tier and activity columns' {
        BeforeAll {
            $script:tablesMd = Get-Content (Join-Path $script:tempWsRoot '81-table-plans-retention.md') -Raw
        }

        It 'shows the FirewallLogs_CL high-volume custom table' {
            $script:tablesMd | Should -Match 'FirewallLogs_CL'
        }

        It 'lists Active / Silent / Orphan headings' {
            $script:tablesMd | Should -Match 'Active'
            $script:tablesMd | Should -Match 'Silent'
            $script:tablesMd | Should -Match 'Orphan'
        }
    }

    Context '84-cost-estimate.md surfaces the headline and methodology' {
        BeforeAll {
            $script:costMd = Get-Content (Join-Path $script:tempWsRoot '84-cost-estimate.md') -Raw
        }

        It 'shows the monthly total and currency' {
            $script:costMd | Should -Match '5244'
            $script:costMd | Should -Match 'GBP'
        }

        It 'lists the methodology version' {
            $script:costMd | Should -Match 'v1\.0\.0'
        }

        It 'lists at least one caveat' {
            $script:costMd | Should -Match 'NOT priced'
        }
    }

    Context '90-gap-analysis.md renders the findings table' {
        BeforeAll {
            $script:gapMd = Get-Content (Join-Path $script:tempWsRoot '90-gap-analysis.md') -Raw
        }

        It 'lists at least one finding ID' {
            $script:gapMd | Should -Match 'SENT-00\d'
        }

        It 'links to learn.microsoft.com' {
            $script:gapMd | Should -Match 'https://learn\.microsoft\.com'
        }
    }

    Context '10-data-connectors.md renders friendly titles and real state' {
        BeforeAll {
            $script:dcMd = Get-Content (Join-Path $script:tempWsRoot '10-data-connectors.md') -Raw
        }

        It 'renders the Office365 connector with its friendly title' {
            $script:dcMd | Should -Match 'Microsoft 365 \(Office 365\)'
        }

        It 'renders the MicrosoftThreatProtection connector as Microsoft Defender XDR' {
            $script:dcMd | Should -Match 'Microsoft Defender XDR'
        }

        It 'renders the AzureActiveDirectory connector as Microsoft Entra ID' {
            $script:dcMd | Should -Match 'Microsoft Entra ID'
        }

        It 'aggregates all-enabled data types into an "enabled" state' {
            $script:dcMd | Should -Match '\| Microsoft 365 \(Office 365\) \|[^|]+\|[^|]+\| enabled \|'
        }

        It 'aggregates mixed states into a "partial" state' {
            $script:dcMd | Should -Match '\| Microsoft Defender XDR \|[^|]+\|[^|]+\| partial \|'
        }

        It 'lists the connector data types in their own column' {
            $script:dcMd | Should -Match 'sharePoint, exchange, teams'
        }

        It 'does not surface raw GUID resource names in the table' {
            $script:dcMd | Should -Not -Match 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        }

        It 'renders the CCF Publisher column rather than the non-existent connectorKind' {
            $script:dcMd | Should -Match '\| Publisher \|'
            $script:dcMd | Should -Match '\| AzureDevOpsAuditLogs \|.+\| Microsoft \|'
        }

        It 'does not surface the obsolete CCF Kind column header' {
            # The previous renderer had `| Name | Kind | Title |` for CCF.
            $script:dcMd | Should -Not -Match '\| Name \| Kind \| Title \|'
        }
    }

    Context '12-soc-optimization.md uses real API field paths' {
        BeforeAll {
            $script:socMd = Get-Content (Join-Path $script:tempWsRoot '12-soc-optimization.md') -Raw
        }

        It 'renders the humanised Category column for Precision_Coverage' {
            $script:socMd | Should -Match '\| Coverage \|'
        }

        It 'renders the humanised Category column for Precision_DataValue' {
            $script:socMd | Should -Match '\| Data Value \|'
        }

        It 'renders the AffectedItem column with the use-case name for Coverage rows' {
            $script:socMd | Should -Match 'BEC \(Financial Fraud\)'
        }

        It 'renders the AffectedItem column with the table name for DataValue rows' {
            $script:socMd | Should -Match 'SigninLogs'
        }

        It 'no longer emits an empty Priority column header' {
            $script:socMd | Should -Not -Match '\| Priority \|'
        }
    }

    Context '38-summary-rules.md reads the summaryLogs schema' {
        BeforeAll {
            $script:summaryMd = Get-Content (Join-Path $script:tempWsRoot '38-summary-rules.md') -Raw
        }

        It 'renders the rule name from the resource name (not contentTemplate displayName)' {
            $script:summaryMd | Should -Match 'SigninLogsHourlyRollup'
        }

        It 'renders the DestinationTable column' {
            $script:summaryMd | Should -Match 'SigninLogsHourly_CL'
        }

        It 'renders the RuleType column' {
            $script:summaryMd | Should -Match '\| User \|'
        }

        It 'does not surface the obsolete Source column header' {
            # Old renderer emitted `| Name | Source | Version |`.
            $script:summaryMd | Should -Not -Match '\| Name \| Source \| Version \|'
        }
    }

    Context '99-references.md is a copy of REFERENCES.md' {
        It 'exists and contains the API versions table' {
            $p = Join-Path $script:tempWsRoot '99-references.md'
            (Get-Content $p -Raw) | Should -Match '## API versions in use'
        }
    }
}

Describe 'Sentinel Documenter renderer — empty-state safety' {
    # When a _raw/*.json file is missing, the renderer must NOT emit phantom
    # table rows with all-null cells (the @($null) + ForEach-Object bug).
    # Verified by removing specific raw files and re-running the renderer.

    BeforeAll {
        $script:emptyOutDir = Join-Path ([System.IO.Path]::GetTempPath()) "documenter-empty-test-$(New-Guid)"
        New-Item -ItemType Directory -Path $script:emptyOutDir -Force | Out-Null
        $emptyWsRoot = Join-Path $script:emptyOutDir 'law-sentinel-empty'
        New-Item -ItemType Directory -Path (Join-Path $emptyWsRoot '_raw') -Force | Out-Null
        Get-ChildItem -Path $script:fixtureRaw -File | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $emptyWsRoot '_raw') -Force
        }
        # Deliberately remove the files that caused phantom rows on the production run.
        @('threat-intel-counts.json','playbooks.json','rbac-playbook-mi.json') | ForEach-Object {
            $f = Join-Path $emptyWsRoot "_raw/$_"
            if (Test-Path $f) { Remove-Item -Force $f }
        }
        $script:emptyWsRoot = $emptyWsRoot

        & $script:renderer `
            -WorkspaceName 'law-sentinel-empty' `
            -InputRoot     $emptyWsRoot `
            -OutputRoot    $emptyWsRoot `
            -ResourcesRoot $script:resources `
            -InformationAction SilentlyContinue
    }

    AfterAll {
        if ($script:emptyOutDir -and (Test-Path $script:emptyOutDir)) {
            Remove-Item -Recurse -Force -Path $script:emptyOutDir -ErrorAction SilentlyContinue
        }
    }

    Context '27-threat-intelligence.md handles missing threat-intel-counts.json' {
        BeforeAll {
            $script:tiMd = Get-Content (Join-Path $script:emptyWsRoot '27-threat-intelligence.md') -Raw
        }

        It 'does not contain a phantom IndicatorCount=0 row' {
            # The bug was rendering `|  | 0 |  |` from $null.Count.
            $script:tiMd | Should -Not -Match '\|\s*\|\s*0\s*\|\s*\|'
        }

        It 'emits an empty-state message instead of a data row' {
            $script:tiMd | Should -Match '_None\._'
        }
    }

    Context '60-automation-rules-playbooks.md handles missing playbooks.json' {
        BeforeAll {
            $script:playbookMd = Get-Content (Join-Path $script:emptyWsRoot '60-automation-rules-playbooks.md') -Raw
        }

        It 'does not contain a phantom blank-cells playbook row' {
            # The bug was rendering `|  |  |  |` after the Playbooks header.
            $script:playbookMd | Should -Not -Match '## Playbooks \(Logic Apps\)[\s\S]*?\|\s*\|\s*\|\s*\|\s*\|'
        }

        It 'emits an empty-state message under the Playbooks heading' {
            $script:playbookMd | Should -Match '## Playbooks \(Logic Apps\)[\s\S]*?_None\._'
        }
    }
}
