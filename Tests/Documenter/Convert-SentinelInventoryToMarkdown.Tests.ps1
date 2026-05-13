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
            '13-data-source-hygiene.md',
            '14-coverage-breakdowns.md',
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

        It 'renders the connector health table with last-ingested timestamps' {
            $script:dcMd | Should -Match '## Connector health \(24h activity\)'
            $script:dcMd | Should -Match 'BillableLast24hGB'
        }

        It 'joins Office365 data types to OfficeActivity table with 24h volume' {
            $script:dcMd | Should -Match '\| Microsoft 365 \(Office 365\) \| sharePoint \| OfficeActivity \|[^|]+\| 14\.5 \|'
        }

        It 'joins AzureActiveDirectory signInLogs to SigninLogs table' {
            $script:dcMd | Should -Match '\| Microsoft Entra ID \| signInLogs \| SigninLogs \|[^|]+\| 3\.6 \|'
        }

        It 'leaves activity columns blank when no table mapping is known' {
            # MicrosoftThreatProtection/incidents -> SecurityIncident (present in fixture).
            # MicrosoftThreatProtection/alerts -> SecurityAlert (NOT in fixture). So the
            # SecurityAlert row should have empty LastIngested + BillableLast24hGB.
            $script:dcMd | Should -Match '\| Microsoft Defender XDR \| alerts \| SecurityAlert \|\s*\|\s*\|'
        }

        It 'surfaces an Effective connectors synthesised view section' {
            $script:dcMd | Should -Match '## Effective connectors \(synthesised view\)'
            $script:dcMd | Should -Match '\| Source \| Identifier \| Table \| Last24hGB \| LastIngested \|'
        }

        It 'attributes Office365 sharePoint to a Classic source in the synthesis' {
            # Classic precedence: classic owns the table over any later DCR/diagnostic that might cover it.
            $script:dcMd | Should -Match '\| Classic \| Office365/sharePoint \| OfficeActivity \|'
        }

        It 'attributes FirewallLogs_CL DCR-driven ingestion to a DCR source' {
            # The fixture has a DCR for Custom-FirewallLogs_CL (FirewallLogs_CL is not
            # claimed by any classic connector mapping).
            $script:dcMd | Should -Match '\| DCR \| dcr-firewall-cl \| FirewallLogs_CL \|'
        }

        It 'attributes the enabled diagnostic-settings Audit log category to a Diagnostic source' {
            $script:dcMd | Should -Match '\| Diagnostic \| sentinel-self-diag \| Audit \|'
        }

        It 'does not list disabled diagnostic-settings categories' {
            # SummaryLogs is in the fixture but enabled=false — must not appear.
            $script:dcMd | Should -Not -Match '\| Diagnostic \|[^|]+\| SummaryLogs \|'
        }
    }

    Context '80-workspace.md surfaces provenance metadata' {
        BeforeAll {
            $script:wsMd = Get-Content (Join-Path $script:tempWsRoot '80-workspace.md') -Raw
        }

        It 'renders the Provenance section heading' {
            $script:wsMd | Should -Match '## Provenance'
        }

        It 'renders the workspace age in days' {
            $script:wsMd | Should -Match '\| Age \|'
            $script:wsMd | Should -Match '\d+ days'
        }

        It 'renders the workspace created date (PowerShell deserialises the JSON datetime to local format)' {
            $script:wsMd | Should -Match '2024'
            $script:wsMd | Should -Match '\| Created \|'
        }

        It 'renders the default DCR resource id' {
            $script:wsMd | Should -Match 'dcr-default'
        }
    }

    Context '12-soc-optimization.md splits Coverage + Data Value into sub-tables' {
        BeforeAll {
            $script:socMd = Get-Content (Join-Path $script:tempWsRoot '12-soc-optimization.md') -Raw
        }

        It 'renders the Coverage recommendations heading' {
            $script:socMd | Should -Match '## Coverage recommendations'
        }

        It 'renders the Data Value recommendations heading' {
            $script:socMd | Should -Match '## Data Value recommendations'
        }

        It 'lists BEC (Financial Fraud) under Coverage' {
            $script:socMd | Should -Match 'BEC \(Financial Fraud\)'
        }

        It 'lists SigninLogs under Data Value' {
            $script:socMd | Should -Match 'SigninLogs'
        }

        It 'does not emit a Priority column header' {
            $script:socMd | Should -Not -Match '\| Priority \|'
        }
    }

    Context '60-automation-rules-playbooks.md renders playbooks with state, kind, and MI roles' {
        BeforeAll {
            $script:playbookMd = Get-Content (Join-Path $script:tempWsRoot '60-automation-rules-playbooks.md') -Raw
        }

        It 'renders the IncidentEnrich-IP playbook name' {
            $script:playbookMd | Should -Match 'IncidentEnrich-IP'
        }

        It 'renders the Enabled state for the first playbook' {
            $script:playbookMd | Should -Match '\| IncidentEnrich-IP \| Enabled \|'
        }

        It 'renders the Disabled state for the second playbook' {
            $script:playbookMd | Should -Match '\| NotifyOnHighSev \| Disabled \|'
        }

        It 'renders the Kind column with the workflow kind' {
            $script:playbookMd | Should -Match 'Stateful'
        }

        It 'joins the MI workspace roles onto the IncidentEnrich-IP row' {
            $script:playbookMd | Should -Match 'IncidentEnrich-IP \|[^|]+\|[^|]+\|[^|]*Microsoft Sentinel Responder.*Microsoft Sentinel Reader'
        }

        It 'leaves the WorkspaceRoles cell empty for a playbook without an MI' {
            # NotifyOnHighSev has no identity in the fixture, so should have no role names.
            $script:playbookMd | Should -Match 'NotifyOnHighSev \|[^|]+\|[^|]+\|\s*\|'
        }
    }

    Context '27-threat-intelligence.md prefers the TI metrics API as source' {
        BeforeAll {
            $script:tiMd = Get-Content (Join-Path $script:tempWsRoot '27-threat-intelligence.md') -Raw
        }

        It 'labels the data source as the TI metrics API when present' {
            $script:tiMd | Should -Match 'TI metrics API'
        }

        It 'renders the url indicator type from the metrics API' {
            $script:tiMd | Should -Match '\| url \| 482 \|'
        }

        It 'renders the ipv4-addr indicator type from the metrics API' {
            $script:tiMd | Should -Match '\| ipv4-addr \| 1273 \|'
        }

        It 'renders the domain-name indicator type from the metrics API' {
            $script:tiMd | Should -Match '\| domain-name \| 215 \|'
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

    Context '13-data-source-hygiene.md surfaces the four hygiene checks' {
        BeforeAll {
            $script:hygieneMd = Get-Content (Join-Path $script:tempWsRoot '13-data-source-hygiene.md') -Raw
        }

        It 'renders the CEF devices table with a Palo Alto entry' {
            $script:hygieneMd | Should -Match 'Palo Alto Networks'
        }

        It 'renders the CEF in Syslog misroute table' {
            $script:hygieneMd | Should -Match '## CEF records misrouted into Syslog'
            $script:hygieneMd | Should -Match 'syslog-forwarder-01'
        }

        It 'renders the SecurityEvent duplicates table with a per-computer count' {
            $script:hygieneMd | Should -Match 'dc01\.contoso\.local'
        }

        It 'renders the Top 10 noisy event IDs table with EventID 4624' {
            $script:hygieneMd | Should -Match '\| 4624 \|'
        }

        It 'is linked from the index.md sections table' {
            $indexMd = Get-Content (Join-Path $script:tempWsRoot 'index.md') -Raw
            $indexMd | Should -Match '13-data-source-hygiene\.md'
        }
    }

    Context '15-incidents.md surfaces daily incident-flow metrics' {
        BeforeAll {
            $script:incMd = Get-Content (Join-Path $script:tempWsRoot '15-incidents.md') -Raw
        }

        It 'renders Avg daily unique incidents' {
            $script:incMd | Should -Match 'Avg daily unique incidents:\*\* 12\.4'
        }

        It 'renders Peak daily new incidents' {
            $script:incMd | Should -Match 'Peak daily new incidents:\*\* 31'
        }
    }

    Context '20-analytics-rules.md surfaces mouldy + template-mismatch sub-tables' {
        BeforeAll {
            $script:rulesMd = Get-Content (Join-Path $script:tempWsRoot '20-analytics-rules.md') -Raw
        }

        It 'renders the per-kind aggregate count header' {
            $script:rulesMd | Should -Match 'Scheduled-Enabled \| Scheduled-Disabled \| NRT-Enabled \| NRT-Disabled'
        }

        It 'renders the Mouldy rules section heading' {
            $script:rulesMd | Should -Match '## Mouldy rules'
        }

        It 'lists the suspicious-sign-in rule as mouldy (lastModifiedUtc > 1y)' {
            $script:rulesMd | Should -Match 'Suspicious sign-in from rare country'
        }

        It 'renders the Template mismatch section heading' {
            $script:rulesMd | Should -Match '## Template mismatch'
        }

        It 'shows the suspicious-sign-in rule as version-mismatched (1.0.0 vs 1.2.0)' {
            $script:rulesMd | Should -Match '\| Suspicious sign-in from rare country \| Scheduled \| 1\.0\.0 \| 1\.2\.0 \|'
        }
    }

    Context '14-coverage-breakdowns.md surfaces per-source coverage' {
        BeforeAll {
            $script:covMd = Get-Content (Join-Path $script:tempWsRoot '14-coverage-breakdowns.md') -Raw
        }

        It 'renders AzureActivity subscription rows' {
            $script:covMd | Should -Match '## AzureActivity'
            $script:covMd | Should -Match '\| 12450 \|'
        }

        It 'renders AzureDiagnostics provider rows' {
            $script:covMd | Should -Match 'MICROSOFT\.KEYVAULT'
        }

        It 'renders XDR table presence rows' {
            $script:covMd | Should -Match '## XDR table presence'
            $script:covMd | Should -Match '\| DeviceEvents \| 28401 \|'
        }
    }

    Context '87-azure-monitor-agents.md renders the AMA vs MMA migration table' {
        BeforeAll {
            $script:amaMd = Get-Content (Join-Path $script:tempWsRoot '87-azure-monitor-agents.md') -Raw
        }

        It 'renders the migration status section heading' {
            $script:amaMd | Should -Match '## AMA vs MMA migration status'
        }

        It 'renders an In Progress row for Azure VM (both MMA and AMA present)' {
            $script:amaMd | Should -Match '\| Azure VM \| 45 \| 5 \| 42 \| In Progress \|'
        }

        It 'renders a Completed row for Arc-enabled (only AMA present)' {
            $script:amaMd | Should -Match '\| Arc-enabled \| 12 \| 0 \| 12 \| Completed \|'
        }

        It 'renders a Not Started row for Hybrid without Arc (only MMA present)' {
            $script:amaMd | Should -Match '\| Hybrid without Arc \| 3 \| 3 \| 0 \| Not Started \|'
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
        # TI removal needs both sources gone — the renderer falls back from metrics to counts.
        @('threat-intel-counts.json','threat-intel-metrics.json','playbooks.json','rbac-playbook-mi.json') | ForEach-Object {
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
