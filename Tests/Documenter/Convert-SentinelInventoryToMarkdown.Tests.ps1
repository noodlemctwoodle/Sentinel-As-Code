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
    $script:renderer   = Join-Path $script:repoRoot 'Tools/Documenter/Convert-SentinelInventoryToMarkdown.ps1'
    $script:resources  = Join-Path $script:repoRoot 'Tools/Documenter/Private/Resources'

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
            'index.md','00-overview.md','01-live-snapshot.md',
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

    Context '01-live-snapshot.md MITRE headline shape' {
        BeforeAll {
            $script:liveSnap = Get-Content (Join-Path $script:tempWsRoot '01-live-snapshot.md') -Raw
        }

        It 'uses the Covered / Thin / None headline shape' {
            $script:liveSnap | Should -Match 'MITRE tactics .*Covered / Thin / None'
        }

        It 'does not use the old "with coverage" headline shape' {
            $script:liveSnap | Should -Not -Match 'MITRE tactics with coverage'
        }

        It 'enumerates uncovered tactics in the headline when any exist' {
            # The fixture's only enabled Scheduled rule cites InitialAccess +
            # CredentialAccess; the other 12 catalogue tactics are uncovered,
            # which the headline must enumerate after "uncovered:".
            $script:liveSnap | Should -Match 'uncovered:.*Reconnaissance'
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

        It 'resolves T1078 to its catalogue name (Valid Accounts)' {
            # The fixture's first scheduled rule references T1078; the renderer
            # should look up the human-readable name from mitre-attack.json.
            $script:mitre | Should -Match 'T1078 — Valid Accounts'
        }

        It 'resolves T1078.004 sub-technique to its catalogue name (Cloud Accounts)' {
            $script:mitre | Should -Match 'T1078\.004 — Cloud Accounts'
        }

        It 'still links each cell back to attack.mitre.org' {
            $script:mitre | Should -Match 'https://attack\.mitre\.org/techniques/T1078/'
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

    Context '84-cost-estimate.md Sankey collapses the long tail on busy workspaces' {
        BeforeAll {
            # Build a new temp workspace whose cost-estimate.json carries
            # ~80 unique tables — a real-world busy SIEM workspace shape.
            # Top 10 are heavyweight, the remaining 70 are sub-10 GB and
            # spread across multiple sources so the bucketing rule has
            # something to do.
            $busyOut = Join-Path ([System.IO.Path]::GetTempPath()) "documenter-busy-$(New-Guid)"
            $busyWs  = Join-Path $busyOut 'law-sentinel-busy'
            New-Item -ItemType Directory -Path (Join-Path $busyWs '_raw') -Force | Out-Null
            Get-ChildItem -Path $script:fixtureRaw -File | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination (Join-Path $busyWs '_raw') -Force
            }

            $costPath = Join-Path $busyWs '_raw/cost-estimate.json'
            $cost = Get-Content $costPath -Raw | ConvertFrom-Json

            $busyTables = @(
                @{ Table='CommonSecurityLog'; Plan='Analytics'; Gb30d=2400.0; MonthlyCost=4800.0 },
                @{ Table='Syslog';             Plan='Analytics'; Gb30d=1800.0; MonthlyCost=3600.0 },
                @{ Table='SecurityEvent';      Plan='Analytics'; Gb30d=900.0;  MonthlyCost=1800.0 },
                @{ Table='DeviceEvents';       Plan='Analytics'; Gb30d=750.0;  MonthlyCost=1500.0 },
                @{ Table='EmailEvents';        Plan='Analytics'; Gb30d=600.0;  MonthlyCost=1200.0 },
                @{ Table='SigninLogs';         Plan='Analytics'; Gb30d=420.0;  MonthlyCost=840.0 },
                @{ Table='AuditLogs';          Plan='Analytics'; Gb30d=200.0;  MonthlyCost=400.0 },
                @{ Table='AzureActivity';      Plan='Analytics'; Gb30d=140.0;  MonthlyCost=280.0 },
                @{ Table='AzureDiagnostics';   Plan='Analytics'; Gb30d=130.0;  MonthlyCost=260.0 },
                @{ Table='OfficeActivity';     Plan='Analytics'; Gb30d=110.0;  MonthlyCost=220.0 }
            )
            for ($i = 1; $i -le 70; $i++) {
                $prefix = switch ($i % 5) {
                    0 { 'Misc1_CL_' }
                    1 { 'Misc2_CL_' }
                    2 { 'Custom_CL_' }
                    3 { 'DeviceSmall_' }
                    4 { 'IntuneTiny_' }
                }
                # Deterministic small GB values — no Get-Random in tests
                # so the assertion remains stable run-to-run.
                $busyTables += @{
                    Table       = ($prefix + $i)
                    Plan        = 'Analytics'
                    Gb30d       = [math]::Round(0.5 + ($i % 8) * 0.5, 2)
                    MonthlyCost = 1.0
                }
            }
            $cost | Add-Member -NotePropertyName AllTablesByCost -NotePropertyValue $busyTables -Force
            $cost | ConvertTo-Json -Depth 32 | Set-Content -Path $costPath

            & $script:renderer `
                -WorkspaceName 'law-sentinel-busy' `
                -InputRoot     $busyWs `
                -OutputRoot    $busyWs `
                -ResourcesRoot $script:resources `
                -InformationAction SilentlyContinue

            $script:busyOut    = $busyOut
            $script:busyCostMd = Get-Content (Join-Path $busyWs '84-cost-estimate.md') -Raw
        }

        AfterAll {
            if ($script:busyOut -and (Test-Path $script:busyOut)) {
                Remove-Item -Recurse -Force -Path $script:busyOut -ErrorAction SilentlyContinue
            }
        }

        It 'emits at least one per-source long-tail bucket node' {
            $script:busyCostMd | Should -Match '\w[\w ]* tail \(\d+\)'
        }

        It 'collapses the Other source tail' {
            # 14 each of Misc1_CL_*, Misc2_CL_*, IntuneTiny_* land in 'Other'
            # because their suffix-int names don't match `_CL$`; Intune_*
            # routes to its own source; Custom_CL_* routes to 'Custom (CCF / DCR)'.
            # All 14 Misc1/Misc2 are well below the top-90% threshold so they
            # must bucket together.
            $script:busyCostMd | Should -Match 'Other tail \(\d+\)'
        }

        It 'keeps the dominant tables individually visible in the Sankey block' {
            # Strip the markdown to just the Sankey block before asserting —
            # the section narrative and methodology reference table names too.
            $sankeyStart = $script:busyCostMd.IndexOf('source → table → billing tier')
            $sankeyEnd   = $script:busyCostMd.IndexOf('Three columns', $sankeyStart)
            $sankey      = $script:busyCostMd.Substring($sankeyStart, $sankeyEnd - $sankeyStart)
            $sankey | Should -Match 'CommonSecurityLog'
            $sankey | Should -Match 'Syslog'
            $sankey | Should -Match 'SecurityEvent'
        }

        It 'leaves small tail-of-one sources individual rather than bucketing one entry' {
            # OfficeActivity is the only Office 365 table and falls under the
            # 90% threshold — the promotion pass should keep it individual,
            # NOT emit a "Office 365 tail (1)" bucket.
            $script:busyCostMd | Should -Not -Match 'Office 365 tail \(1\)'
            # Verify by checking that OfficeActivity appears as a direct
            # Sankey edge from its source.
            $script:busyCostMd | Should -Match 'Office 365,OfficeActivity,110'
        }

        It 'annotates the section narrative with the tail-collapse disclosure' {
            $script:busyCostMd | Should -Match 'collapsed into per-source'
            $script:busyCostMd | Should -Match '\d+ small table\(s\) bucketed'
        }

        It 'sets the Sankey chart height with a sensible floor for busy workspaces' {
            # 80 tables → ~12-14 middle nodes after bucketing → 24*N+200
            # is below the 720 floor, so height stays at 720. Scope the
            # match to the Sankey block since other charts have their own
            # height config earlier in the file.
            $sankeyStart = $script:busyCostMd.IndexOf('sankey:')
            $sankeyEnd   = $script:busyCostMd.IndexOf('sankey-beta', $sankeyStart)
            $sankeyConfig = $script:busyCostMd.Substring($sankeyStart, $sankeyEnd - $sankeyStart)
            $sankeyConfig | Should -Match 'height: \d+'
            $h = ([regex]'height: (\d+)').Match($sankeyConfig).Groups[1].Value -as [int]
            $h | Should -BeGreaterOrEqual 720
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

        It 'surfaces a Data7d column showing Yes when the connector tables received billable data' {
            # Office365 maps to OfficeActivity (BillableLast7d=95.0 in fixture → Yes).
            $script:dcMd | Should -Match '\| Microsoft 365 \(Office 365\) \|[^|]+\|[^|]+\|[^|]+\| Yes \|'
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
            # claimed by any classic connector mapping). The DCR's logAnalytics
            # destination targets the test workspace so it survives the
            # workspace-scope filter.
            $script:dcMd | Should -Match '\| DCR \| dcr-firewall-cl \| FirewallLogs_CL \|'
        }

        It 'filters out DCRs whose destinations target a different workspace' {
            # dcr-other-workspace in the fixture sends Custom-OtherWorkspaceOnly_CL
            # to a different workspace ID — must not appear in this workspace's
            # effective-connectors view, even though the DCR itself lives in the
            # subscription scope captured by the exporter.
            $script:dcMd | Should -Not -Match 'OtherWorkspaceOnly_CL'
            $script:dcMd | Should -Not -Match 'dcr-other-workspace'
        }

        It 'attributes the enabled diagnostic-settings Audit log category to a Diagnostic source' {
            $script:dcMd | Should -Match '\| Diagnostic \| sentinel-self-diag \| Audit \|'
        }

        It 'does not list disabled diagnostic-settings categories' {
            # SummaryLogs is in the fixture but enabled=false — must not appear.
            $script:dcMd | Should -Not -Match '\| Diagnostic \|[^|]+\| SummaryLogs \|'
        }
    }

    Context '70-content-hub.md flags solutions with update available' {
        BeforeAll {
            $script:chMd = Get-Content (Join-Path $script:tempWsRoot '70-content-hub.md') -Raw
        }

        It 'shows azuread with UpdateAvailable = 3.1.0' {
            $script:chMd | Should -Match 'Azure Active Directory \| 3\.0\.0 \| 3\.1\.0 \| 3\.1\.0 \|'
        }

        It 'leaves UpdateAvailable empty for office365 (already current)' {
            $script:chMd | Should -Match 'Microsoft 365 \| 2\.5\.0 \| 2\.5\.0 \|\s*\|'
        }
    }

    Context '80-workspace.md surfaces available service tiers' {
        BeforeAll {
            $script:tierMd = Get-Content (Join-Path $script:tempWsRoot '80-workspace.md') -Raw
        }

        It 'renders the available service tiers heading' {
            $script:tierMd | Should -Match '### Available service tiers'
        }

        It 'renders the PerGB2018 enabled row' {
            $script:tierMd | Should -Match '\| PerGB2018 \|[^|]*\| True \|'
        }

        It 'renders the CapacityReservation tier with reservation level' {
            $script:tierMd | Should -Match '\| CapacityReservation \| 100 \| False \|'
        }
    }

    Context '11-sentinel-health.md surfaces operations summary + query logging' {
        BeforeAll {
            $script:healthMd = Get-Content (Join-Path $script:tempWsRoot '11-sentinel-health.md') -Raw
        }

        It 'renders the operations summary heading' {
            $script:healthMd | Should -Match '## Operations summary'
        }

        It 'renders the Scheduled analytics success row' {
            $script:healthMd | Should -Match '\| Scheduled analytics \| Success \| 1432 \|'
        }

        It 'renders the LAQueryLogs activity count' {
            $script:healthMd | Should -Match '18403 query records'
        }
    }

    Context '80-workspace.md surfaces resource locks' {
        BeforeAll {
            $script:wsLocksMd = Get-Content (Join-Path $script:tempWsRoot '80-workspace.md') -Raw
        }

        It 'renders the Resource locks heading' {
            $script:wsLocksMd | Should -Match '## Resource locks'
        }

        It 'renders the no-delete lock row' {
            $script:wsLocksMd | Should -Match '\| no-delete \| CanNotDelete \|'
        }
    }

    Context '80-workspace.md surfaces usage telemetry' {
        BeforeAll {
            $script:wsUsageMd = Get-Content (Join-Path $script:tempWsRoot '80-workspace.md') -Raw
        }

        It 'renders the Usage telemetry heading' {
            $script:wsUsageMd | Should -Match '## Usage telemetry'
        }

        It 'renders the 30-day total billable value' {
            $script:wsUsageMd | Should -Match '\| 82\.4 \| 71\.8 \|'
        }

        It 'renders the 14-day billable peak value' {
            $script:wsUsageMd | Should -Match '\| 4\.6 \| 4\.1 \|'
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

        It 'joins the MI workspace roles onto the IncidentEnrich-IP row' {
            $script:playbookMd | Should -Match 'IncidentEnrich-IP \|[^|]+\|[^|]*Microsoft Sentinel Responder.*Microsoft Sentinel Reader'
        }

        It 'renders the explicit no-MI label for a playbook without an identity' {
            # NotifyOnHighSev has no identity in the fixture.
            $script:playbookMd | Should -Match 'NotifyOnHighSev \|[^|]+\| _\(no managed identity\)_ \|'
        }
    }

    Context '27-threat-intelligence.md prefers the TI metrics API as source' {
        BeforeAll {
            $script:tiMd = Get-Content (Join-Path $script:tempWsRoot '27-threat-intelligence.md') -Raw
        }

        It 'labels the data source as the TI metrics API when present' {
            $script:tiMd | Should -Match 'TI metrics API'
        }

        It 'renders the Microsoft Defender source from sourceMetrics' {
            $script:tiMd | Should -Match '\| Microsoft Defender Threat Intelligence \| 1700 \|'
        }

        It 'renders the Open Source row from sourceMetrics' {
            $script:tiMd | Should -Match '\| Open Source \| 270 \|'
        }

        It 'renders the url indicator type from threatTypeMetrics' {
            $script:tiMd | Should -Match '\| url \| 482 \|'
        }

        It 'renders the ipv4-addr indicator type from threatTypeMetrics' {
            $script:tiMd | Should -Match '\| ipv4-addr \| 1273 \|'
        }

        It 'renders the domain-name indicator type from threatTypeMetrics' {
            $script:tiMd | Should -Match '\| domain-name \| 215 \|'
        }

        It 'shows the total-indicators headline from sourceMetrics' {
            # 1700 + 270 = 1970 (source totals; the threat-type breakdown also sums to 1970)
            $script:tiMd | Should -Match 'Total active indicators:\*\* 1970'
        }

        It 'orders metrics rows by IndicatorCount descending (Microsoft Defender first)' {
            $script:tiMd | Should -Match 'Microsoft Defender Threat Intelligence \| 1700[\s\S]+Open Source \| 270'
        }

        It 'renders the threat-type breakdown subsection' {
            $script:tiMd | Should -Match '## Indicator breakdown by threat type'
        }
    }

    Context '26-ueba.md surfaces data-presence inference' {
        BeforeAll {
            $script:uebaMd = Get-Content (Join-Path $script:tempWsRoot '26-ueba.md') -Raw
        }

        It 'reports the Producing data row with the active count' {
            # 1247 + 318 + 0 = 1565
            $script:uebaMd | Should -Match 'Producing data \| Yes — 1565 rows'
        }

        It 'mentions the number of producing tables (BehaviorAnalytics + IdentityInfo = 2)' {
            $script:uebaMd | Should -Match '2 UEBA table\(s\)'
        }

        It 'renders the per-table breakdown subsection' {
            $script:uebaMd | Should -Match '## Data-presence inference \(last 12 days\)'
        }

        It 'lists BehaviorAnalytics with its row count' {
            $script:uebaMd | Should -Match '\| BehaviorAnalytics \| 1247 \|'
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

    Context '15-incidents.md surfaces per-provider join detail' {
        BeforeAll {
            $script:incDetMd = Get-Content (Join-Path $script:tempWsRoot '15-incidents.md') -Raw
        }

        It 'renders the Incident detail by provider section heading' {
            $script:incDetMd | Should -Match '## Incident detail by provider'
        }

        It 'renders the MDATP join row' {
            $script:incDetMd | Should -Match '\| MDATP \| Microsoft Defender for Endpoint \| rule-abc \| 521 \|'
        }
    }

    Context '20-analytics-rules.md surfaces MS Incident Creation rule filters' {
        BeforeAll {
            $script:msIncMd = Get-Content (Join-Path $script:tempWsRoot '20-analytics-rules.md') -Raw
        }

        It 'renders the MS Incident Creation rules section heading' {
            $script:msIncMd | Should -Match '## MS Incident Creation rules'
        }

        It 'renders the Product / Severities / Excludes columns for the MDE rule' {
            $script:msIncMd | Should -Match 'Create incidents from MDE alerts'
            $script:msIncMd | Should -Match 'Microsoft Defender Advanced Threat Protection'
            $script:msIncMd | Should -Match 'High, Medium'
            $script:msIncMd | Should -Match 'Test alert; Benign sample'
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

    Context '99-references.md is a copy of Documenter-References.md' {
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
