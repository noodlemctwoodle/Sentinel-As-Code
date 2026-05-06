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

    Context '99-references.md is a copy of REFERENCES.md' {
        It 'exists and contains the API versions table' {
            $p = Join-Path $script:tempWsRoot '99-references.md'
            (Get-Content $p -Raw) | Should -Match '## API versions in use'
        }
    }
}
