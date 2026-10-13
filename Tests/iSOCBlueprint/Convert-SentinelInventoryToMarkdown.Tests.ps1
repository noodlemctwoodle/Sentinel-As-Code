#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for the iSOC Blueprint renderer.

.DESCRIPTION
    Drives Convert-SentinelInventoryToMarkdown.ps1 against the fixture under
    Tests/iSOCBlueprint/Fixtures/sample/_raw and asserts that the expected Markdown
    section files are produced and contain the headings + signal phrases the
    template promises.

    Output is written to a temp folder so repeated test runs don't pollute the
    fixture or the working tree.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Convert-SentinelInventoryToMarkdown.Tests.ps1

    Runs the full renderer suite against the sample fixture.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Convert-SentinelInventoryToMarkdown.Tests.ps1 -Output Detailed

    Runs with per-assertion output, for working out which section file
    failed to render.

.NOTES
    File:         Tests/iSOCBlueprint/Convert-SentinelInventoryToMarkdown.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-06-03
    Version:      0.4.1
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $script:repoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:fixtureWs  = Join-Path $script:repoRoot 'Tests/iSOCBlueprint/Fixtures/sample'
    $script:fixtureRaw = Join-Path $script:fixtureWs '_raw'
    $script:renderer   = Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Convert-SentinelInventoryToMarkdown.ps1'
    $script:resources  = Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Private/Resources'

    $script:outDir = Join-Path ([System.IO.Path]::GetTempPath()) "blueprint-test-$(New-Guid)"
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

Describe 'iSOC Blueprint renderer' {

    Context 'produces every expected section file' {

        $expected = @(
            'index.md','00-overview.md','01-live-snapshot.md','02-deprecated-legacy-features.md',
            '10-data-connectors.md','11-sentinel-health.md','12-soc-optimization.md',
            '13-data-source-hygiene.md',
            '14-coverage-breakdowns.md',
            '15-incidents.md','16-alerts.md',
            '20-analytics-rules.md','21-rule-performance.md','22-rule-health-quality.md',
            '25-mitre-coverage.md','26-ueba.md','27-threat-intelligence.md',
            '28-detection-opportunities.md',
            '30-hunting-queries.md','35-parsers-functions.md',
            '36-data-export.md','37-search-restore.md','38-summary-rules.md',
            '40-workbooks.md','50-watchlists.md','60-automation-rules-playbooks.md',
            '70-content-hub.md','80-workspace.md','81-table-plans-retention.md',
            '82-dedicated-cluster.md','83-data-collection.md','84-cost-estimate.md',
            '85-rbac.md','86-subscription-context.md','87-azure-monitor-agents.md',
            '88-sentinel-data-lake.md','89-retention.md',
            '90-gap-analysis.md','91-maturity-assessment.md',
            '96-references-microsoft.md','99-references.md'
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

        It 'draws the estate flow as a sankey with a Not monitored pool' {
            $script:overview | Should -Match '## Estate flow'
            $script:overview | Should -Match 'sankey-beta'
            $script:overview | Should -Match '"Not monitored"'
            $script:overview | Should -Match '"Entra ID / Identity","Ingestion"'
        }

        It 'rates the four pipeline stages' {
            $script:overview | Should -Match '\| Stage \| In use \| Of \| Share \| Rating \|'
            $script:overview | Should -Match 'Incidents: closed, of those created in 30d \| 32 \| 40 \| 80% \|'
        }

        It 'carries the maturity headline and links to the new pages' {
            $script:overview | Should -Match '\*\*Maturity:\*\* 1\.59 / 5 \(Initial\)'
            $script:overview | Should -Match 'Scored from the Sentinel workspace only: people and processes were not assessed\.'
            $script:overview | Should -Match '\(28-detection-opportunities\.md\)'
            $script:overview | Should -Match '\(91-maturity-assessment\.md\)'
        }
    }

    Context '28-detection-opportunities.md lists uncovered tables and ready templates' {
        BeforeAll {
            $script:opp = Get-Content (Join-Path $script:tempWsRoot '28-detection-opportunities.md') -Raw
        }

        It 'draws the detection headroom chart' {
            $script:opp | Should -Match 'xychart-beta'
            $script:opp | Should -Match 'bar \[3, 4, 2\]'
        }

        It 'lists the highest-volume uncovered table first with no suggestion' {
            $script:opp | Should -Match '\| Table \| Gb30d \| TemplateCount \| Templates \|'
            $script:opp | Should -Match '\| FirewallLogs_CL \| 2000 \| 0 \|\s+\|'
        }

        It 'suggests the undeployed template for OfficeActivity and never the deprecated one' {
            $script:opp | Should -Match '\| OfficeActivity \| 400 \| 1 \| Data exfiltration \|'
            $script:opp | Should -Not -Match 'Deprecated\] Firewall'
        }

        It 'lists the tables no template covers in their own subsection' {
            $script:opp | Should -Match '## Tables with no template available[\s\S]*\| FirewallLogs_CL \| 2000 \|[\s\S]*\| LegacyCLv1_CL \| 10 \|[\s\S]*## Undeployed templates ready to enable'
            $section = ($script:opp -split '## Tables with no template available')[1] -split '## Undeployed templates' | Select-Object -First 1
            $section | Should -Not -Match '\| OfficeActivity \|'
        }

        It 'does not list a table an enabled rule already reads' {
            $script:opp | Should -Not -Match '\| SigninLogs \|'
        }

        It 'lists ready templates highest severity first' {
            $script:opp | Should -Match '## Undeployed templates ready to enable[\s\S]*\| Data exfiltration \| Scheduled \| High \|[\s\S]*\| Low-severity noise \| Scheduled \| Low \|'
        }
    }

    Context '91-maturity-assessment.md renders the assessment' {
        BeforeAll {
            $script:mat = Get-Content (Join-Path $script:tempWsRoot '91-maturity-assessment.md') -Raw
        }

        It 'says what the score is based on and what it covers, even from a maturity.json that carries neither' {
            # The fixture's maturity.json predates the basis and scope, so both come from the criteria file.
            $script:mat | Should -Match 'A custom model based on the SOC-CMM framework\.'
            $script:mat | Should -Match 'not affiliated with or endorsed by the SOC-CMM project'
            $script:mat | Should -Match '(?m)^> \*\*Scope:\*\* The score is based strictly on the Microsoft Sentinel infrastructure and configuration'
            $script:mat | Should -Match 'People \(staffing, skills, roles\) and processes'
        }

        It 'names the methodology and the headline score' {
            $script:mat | Should -Match 'Sentinel-As-Code maturity assessment'
            $script:mat | Should -Match '\*\*Overall:\*\* 1\.59 / 5 \(Initial\)'
            $script:mat | Should -Match '\*\*Target:\*\* 3 \(Established\)'
        }

        It 'charts the eleven areas and tables them' {
            $script:mat | Should -Match 'x-axis \["DET", "PLT", "COV", "AUT", "MON", "INC", "INV", "TI", "HNT", "LOG", "GOV"\]'
            $script:mat | Should -Match '\| DET \| Detection engineering \| 1\.11 \| 1 Initial \|'
        }

        It 'carries the roadmap, quick wins, CSF rollup and criteria' {
            $script:mat | Should -Match '## Roadmap'
            $script:mat | Should -Match '\| 1 \| SAC-INV-02 '
            $script:mat | Should -Match '## Quick wins[\s\S]*- \*\*SAC-INV-02\*\*'
            $script:mat | Should -Match '\| DE Detect \| 30 \| 12 \| 18 \| 0 \|'
            # the criterion shares its id with the daily-cap finding, which fired, so the id links to it
            $script:mat | Should -Match '\| \[SAC-LOG-03\]\(90-gap-analysis\.md#sac-log-03\) \| LOG \| practice \| A daily cap is set \| Gap \|'
        }

        It 'links a criterion id only when the finding that shares it fired' {
            # SAC-DET-03 (entity mappings) fired in the fixture: linked to its finding
            $script:mat | Should -Match '\[SAC-DET-03\]\(90-gap-analysis\.md#sac-det-03\)'
            # SAC-DET-01 is a metric criterion with no finding behind it: plain text
            $script:mat | Should -Match '\| SAC-DET-01 \| DET \|'
            $script:mat | Should -Not -Match '\[SAC-DET-01\]'
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

        It 'counts the tactics against the 14-tactic catalogue' {
            $script:liveSnap | Should -Match 'of 14'
        }

        It 'carries the estate flow and the maturity row' {
            $script:liveSnap | Should -Match 'sankey-beta'
            $script:liveSnap | Should -Match '\| Maturity \(overall / target\) \| 1\.59 / 3 \(Initial, target Established\) \|'
            $script:liveSnap | Should -Match '\(91-maturity-assessment\.md\)'
        }
    }

    Context '15-incidents.md surfaces closure outcomes and rule effectiveness' {
        BeforeAll {
            $script:inc15 = Get-Content (Join-Path $script:tempWsRoot '15-incidents.md') -Raw
        }

        It 'draws the classification pie from ByClassification' {
            $script:inc15 | Should -Match 'pie showData title Closed incidents by classification'
            $script:inc15 | Should -Match '"Undetermined" : 15'
        }

        It 'points to the rule effectiveness on 21-rule-performance.md, which tables it with the source and the false-positive rate' {
            $script:inc15 | Should -Match '\[21-rule-performance\.md\]\(21-rule-performance\.md\)'
            $script:inc15 | Should -Not -Match '## Rule effectiveness'
            Get-Content (Join-Path $script:tempWsRoot '21-rule-performance.md') -Raw | Should -Match '\| Suspicious sign-in from rare country \| Analytics rule \| 30 \| 24 \| 3 \| 19 \| 1 \| 1 \| 79\.2 \|'
        }
    }

    Context '15-incidents.md and 16-alerts.md break incidents and alert volume down the way the dashboard does' {
        BeforeAll {
            $script:inc15b = Get-Content (Join-Path $script:tempWsRoot '15-incidents.md') -Raw
            $script:alerts16 = Get-Content (Join-Path $script:tempWsRoot '16-alerts.md') -Raw
        }

        It 'tables alert volume by severity with shares that add up, on the alerts page' {
            $script:alerts16 | Should -Match '## Alert volume by severity \(last 30d\)'
            $script:alerts16 | Should -Match '\| High \| 430 \| 76\.1% \|'
            $script:alerts16 | Should -Match '\| Medium \| 135 \| 23\.9% \|'
            $script:inc15b | Should -Not -Match '## Alert volume by severity'
        }

        It 'tables alerts by detection source with Sentinel rules named as Microsoft Sentinel' {
            $script:alerts16 | Should -Match '## Alerts by detection source \(last 30d\)'
            $script:alerts16 | Should -Match '\| Microsoft Sentinel \| 525 \| 3 \| 92\.9% \|'
            $script:alerts16 | Should -Match '\| Azure Active Directory Identity Protection \| 40 \| 1 \| 7\.1% \|'
        }

        It 'lists every rule with incidents instead of a top 25' {
            $script:inc15b | Should -Match '## Incidents by rule \(last 30d\)'
            $script:inc15b | Should -Not -Match 'top 25'
        }
    }

    Context '00-overview.md tables the source families beside the estate flow' {
        BeforeAll {
            $script:ov00 = Get-Content (Join-Path $script:tempWsRoot '00-overview.md') -Raw
        }

        It 'has a Source families table with the first-party alerts beside their family' {
            $script:ov00 | Should -Match '### Source families'
            $script:ov00 | Should -Match '\| Entra ID / Identity \|[^\n]*Azure Active Directory Identity Protection 40'
        }

        It 'states how many custom detections were captured' {
            $script:ov00 | Should -Match '\*\*Defender XDR custom detections:\*\* \d+ enabled of \d+ defined'
        }
    }

    Context '20-analytics-rules.md is the rule inventory; 21 and 22 carry performance and quality' {
        BeforeAll {
            $script:rulesMd = Get-Content (Join-Path $script:tempWsRoot '20-analytics-rules.md') -Raw
            $script:perfMd = Get-Content (Join-Path $script:tempWsRoot '21-rule-performance.md') -Raw
        }

        It 'keeps the inventory subsections on 20, in order, and alert volume on 21' {
            $heads = [regex]::Matches($script:rulesMd, '(?m)^## (.+)$') | ForEach-Object { $_.Groups[1].Value }
            $heads | Should -Not -Contain 'By alert volume (last 30d)'
            $heads | Should -Contain 'Microsoft-managed rules'
            $heads | Should -Contain 'Recent modifications'
            $heads | Should -Contain 'By Content Hub solution'
            ([array]::IndexOf($heads, 'Microsoft-managed rules')) | Should -BeLessThan ([array]::IndexOf($heads, 'Recent modifications'))
            ([array]::IndexOf($heads, 'Recent modifications')) | Should -BeLessThan ([array]::IndexOf($heads, 'By Content Hub solution'))
            $perfHeads = [regex]::Matches($script:perfMd, '(?m)^## (.+)$') | ForEach-Object { $_.Groups[1].Value }
            $perfHeads | Should -Be @('By alert volume (last 30d)', 'Rule effectiveness (last 30d)', 'Noisy rules (closed mostly as false positive)')
        }

        It 'keeps the charts and tables, each on its page' {
            $script:perfMd | Should -Match '### Top 10 noisy rules by alert volume'
            $script:rulesMd | Should -Match 'pie showData title Microsoft-managed rules by severity'
            $script:rulesMd | Should -Match 'Rule modifications per month'
            $script:rulesMd | Should -Match 'pie showData title Analytics rules by Content Hub solution'
            $script:perfMd | Should -Match '## Rule effectiveness \(last 30d\)[\s\S]*Failed logons across multiple accounts \| Analytics rule \| 10 \| 8 \|'
        }

        It 'lists the noisy analytics rule (24 closed, 79.2% false positive) on 21' {
            $script:perfMd | Should -Match '## Noisy rules \(closed mostly as false positive\)[\s\S]*\| Suspicious sign-in from rare country \| 30 \| 24 \| 19 \| 79\.2 \|'
            ($script:perfMd -split '## Noisy rules')[1] | Should -Not -Match 'Failed logons across multiple accounts'
        }

        It 'ends with the Learn links once' {
            ([regex]::Matches($script:rulesMd, 'Detect threats from template')).Count | Should -Be 1
            $script:rulesMd.TrimEnd() | Should -Match 'false-positives\)$'
        }

        It 'no longer writes the four separate pages' {
            foreach ($f in '21-analytics-by-volume.md', '22-analytics-microsoft-rules.md', '23-analytics-modifications.md', '24-analytics-by-solution.md') {
                Join-Path $script:tempWsRoot $f | Should -Not -Exist
            }
        }
    }

    Context '27-threat-intelligence.md surfaces STIX objects and feeds' {
        It 'lists the STIX object types and the single Microsoft feed' {
            $md = Get-Content (Join-Path $script:tempWsRoot '27-threat-intelligence.md') -Raw
            $md | Should -Match '## STIX objects \(last 30d\)[\s\S]*\| threat-actor \| 12 \|'
            $md | Should -Match '## Feeds[\s\S]*\| MicrosoftThreatIntelligence \|'
        }
    }

    Context '30-hunting-queries.md renders the Hunts table' {
        It 'shows the empty state because the fixture has no hunts' {
            $md = Get-Content (Join-Path $script:tempWsRoot '30-hunting-queries.md') -Raw
            $md | Should -Match '## Hunts[\s\S]*_None\._'
        }
    }

    Context '60-automation-rules-playbooks.md surfaces playbook run health' {
        It 'warns about the failing playbook and tables the runs' {
            $md = Get-Content (Join-Path $script:tempWsRoot '60-automation-rules-playbooks.md') -Raw
            $md | Should -Match '\*\*1 playbook\(s\) had failed runs in the last 7 days\.\*\*'
            $md | Should -Match '"Succeeded" : 49'
            $md | Should -Match '\| IncidentEnrich-IP \| 42 \| 5 \| Failed \| 2026-05-05 22:15 \|'
        }
    }

    Context '70-content-hub.md lists deprecated and unlisted solutions' {
        It 'names both flagged solutions with their reason' {
            $md = Get-Content (Join-Path $script:tempWsRoot '70-content-hub.md') -Raw
            $md | Should -Match '\| Microsoft 365 \| office365 \| Deprecated \|'
            $md | Should -Match '\| Legacy Threat Feed \| legacy-feed \| Not in catalogue \|'
        }
    }

    Context '80-workspace.md draws the daily ingestion trend' {
        It 'emits an xychart with one point per fixture day' {
            $md = Get-Content (Join-Path $script:tempWsRoot '80-workspace.md') -Raw
            $md | Should -Match '### Daily ingestion \(last 30 days\)'
            $md | Should -Match 'x-axis \["05-04", "05-05", "05-06"\]'
            $md | Should -Match 'line "Billable" \[41\.2, 39\.8, 12\.6\]'
            $md | Should -Match 'line "Free" \['
        }
    }

    Context '11-sentinel-health.md tables ingestion and schema failures' {
        It 'lists the failed DCR transform from the fixture' {
            $md = Get-Content (Join-Path $script:tempWsRoot '11-sentinel-health.md') -Raw
            $md | Should -Match '## Ingestion and schema failures \(last 7d\)[\s\S]*Custom-FirewallLogs_CL \| Ingestion \| 14 \| 2026-05-06 07:12 \|'
        }
    }

    Context '70-content-hub.md lists the legacy management solutions' {
        It 'shows the OMS SecurityInsights solution with its product and publisher' {
            $md = Get-Content (Join-Path $script:tempWsRoot '70-content-hub.md') -Raw
            $md | Should -Match '## Legacy management solutions[\s\S]*\| SecurityInsights\(law-sentinel-test\) \| OMSGallery/SecurityInsights \| Microsoft \| Succeeded \| 2026-02-06 00:00 \|'
        }
    }

    Context '80-workspace.md surfaces the Sentinel onboarding state' {
        It 'shows the onboarding resource and the customer-managed key flag' {
            $md = Get-Content (Join-Path $script:tempWsRoot '80-workspace.md') -Raw
            $md | Should -Match '## Sentinel onboarding[\s\S]*\| Customer-managed key \| False \|'
        }
    }

    Context '88-sentinel-data-lake.md reflects the enrolled fixture' {
        BeforeAll {
            $script:lakeMd = Get-Content (Join-Path $script:tempWsRoot '88-sentinel-data-lake.md') -Raw
        }

        It 'reports the lake as enrolled with no lake-only tables' {
            $script:lakeMd | Should -Match 'Sentinel Data Lake is enrolled on this workspace'
            $script:lakeMd | Should -Match 'Lake provisioned at tenant scope'
        }

        It 'skips the tier pie when every table sits in one tier (the fixture has no extended retention)' {
            $script:lakeMd | Should -Not -Match '## Tier distribution'
            $script:lakeMd | Should -Not -Match 'Analytics \+ Lake extended'
            $script:lakeMd | Should -Match 'No tables currently route to the Lake-only tier'
        }
    }

    Context '10-data-connectors.md reports Defender XDR unification' {
        It 'lists the XDR connector data types and the Defender for Cloud connectors' {
            $md = Get-Content (Join-Path $script:tempWsRoot '10-data-connectors.md') -Raw
            $md | Should -Match '## Defender XDR unification'
            $md | Should -Match '\| Defender XDR connector \(MicrosoftThreatProtection\) \| Present \|'
            $md | Should -Match '\| XDR incidents data type \| enabled \|'
            $md | Should -Match '\| Legacy Microsoft incident-creation rules enabled \| 1 \|'
            $md | Should -Match '\| Defender for Cloud connector \(subscription level\) \| Not configured \|'
            $md | Should -Match '\| Defender portal onboarding \| Not observable \|'
        }
    }

    Context '14-coverage-breakdowns.md lists Entra ID table presence' {
        It 'marks the tables receiving data and the catalogue-only ones' {
            $md = Get-Content (Join-Path $script:tempWsRoot '14-coverage-breakdowns.md') -Raw
            $md | Should -Match '## Entra ID table presence \(last 7d\)'
            $md | Should -Match '\| SigninLogs \|[^\n]*\| 25 \| Receiving data \|'
            $md | Should -Match '\| AuditLogs \| Analytics \| 30 \| 0 \| Catalogue only \|'
            $md | Should -Match '\| AADProvisioningLogs \|[^\n]*\| Not in catalogue \|'
        }
    }

    Context '22-rule-health-quality.md scores rule complexity' {
        It 'scores the fixture rule from its query shape' {
            $md = Get-Content (Join-Path $script:tempWsRoot '22-rule-health-quality.md') -Raw
            $md | Should -Match '## Rule complexity'
            $md | Should -Match '\| Suspicious sign-in from rare country \| Scheduled \| 4 \| 159 \| 1 \| 1 \| 1 \| 1 \|  \| Yes \|'
        }
    }

    Context '80-workspace.md carries a resilience summary' {
        It 'reports replication, keys, the daily cap and locks in one table' {
            $md = Get-Content (Join-Path $script:tempWsRoot '80-workspace.md') -Raw
            $md | Should -Match '## Resilience summary'
            $md | Should -Match '\| Customer-managed key \| No \(platform-managed keys\) \|'
            $md | Should -Match '\| Daily cap \|'
            $md | Should -Match '\| Resource locks \|'
        }
    }

    Context '81-table-plans-retention.md details silent and classic tables' {
        BeforeAll { $script:plansMd = Get-Content (Join-Path $script:tempWsRoot '81-table-plans-retention.md') -Raw }

        It 'splits silent tables by detection impact' {
            $script:plansMd | Should -Match '1 of these are read by enabled analytics rules'
            $script:plansMd | Should -Match '\| AuditLogs \| Analytics \| 50 \| 2026-04-25 07:50 \| 11 \| 1 \| Detection outage \|'
        }

        It 'inventories the classic (Data Collector API) custom tables' {
            $script:plansMd | Should -Match '## Classic custom tables \(legacy Data Collector API\)'
            $script:plansMd | Should -Match '\*\*1\*\* classic table\(s\): \*\*1\*\* still ingesting'
            $script:plansMd | Should -Match '\| LegacyCLv1_CL \| Analytics \| 30 \| 30 \| 30 \| 2026-05-06 07:00 \| Active \(last 24h\) \| 0 \|'
        }
    }

    Context '88-sentinel-data-lake.md assesses lake usage' {
        It 'explains there is nothing to assess when no table extends into the lake, and lists the tables without extension' {
            $md = Get-Content (Join-Path $script:tempWsRoot '88-sentinel-data-lake.md') -Raw
            $md | Should -Match '## Lake usage evidence'
            $md | Should -Match 'No table keeps data in the lake beyond its analytics retention'
            $md | Should -Match '## Analytics tables without extended lake retention'
            $md | Should -Match '\| SecurityEvent \| 30 \| 30 \| 1500 \| 0 \|'
            $md | Should -Match '\| AuditLogs \| 30 \| 30 \| 50 \| 1 \|'
        }
    }

    Context '13-data-source-hygiene.md lists log contributors' {
        It 'shows Syslog contributors by facility and the SecurityEvent hosts' {
            $md = Get-Content (Join-Path $script:tempWsRoot '13-data-source-hygiene.md') -Raw
            $md | Should -Match '## Syslog contributors \(last 7d\)[\s\S]*\| fw-edge-01 \| local4 \| 182000 \| 540.2 \|'
            $md | Should -Match '## SecurityEvent hosts \(last 7d\)[\s\S]*\| DC01.example.test \| 410000 \| 1120.5 \|'
        }
    }

    Context '20-analytics-rules.md lists Defender XDR custom detections' {
        It 'shows each custom detection with its tables and state' {
            $md = Get-Content (Join-Path $script:tempWsRoot '20-analytics-rules.md') -Raw
            $md | Should -Match '## Defender XDR custom detections'
            $md | Should -Match '\| Suspicious LSASS access \| Yes \| high \| 1H \| DeviceProcessEvents, EmailEvents \| 2026-04-02 10:00 \|'
            $md | Should -Match '\| Legacy auth sign-in \(paused\) \| No \| medium \| 24H \| IdentityLogonEvents \|'
        }
    }

    Context '22-rule-health-quality.md reports rule run failures' {
        It 'lists the failing rule with its reason' {
            $md = Get-Content (Join-Path $script:tempWsRoot '22-rule-health-quality.md') -Raw
            $md | Should -Match '## Rule run failures \(last 7d\)'
            $md | Should -Match '\| Suspicious sign-in from rare country \| Failure \| 3 \| 2026-05-06 06:15 \| Query execution exceeded the 2 minute timeout. \|'
        }
    }

    Context '27-threat-intelligence.md breaks indicators down by type' {
        It 'renders the pie and the table' {
            $md = Get-Content (Join-Path $script:tempWsRoot '27-threat-intelligence.md') -Raw
            $md | Should -Match '## Indicators by type \(last 30d\)'
            $md | Should -Match 'pie showData title Indicators by type \(last 30d\)[\s\S]*"IP" : 4200'
            $md | Should -Match '\| Domain \| 1800 \| 1750 \|'
        }
    }

    Context '60-automation-rules-playbooks.md suggests automation per incident title' {
        It 'classifies the titles and maps the phishing title to a response' {
            $md = Get-Content (Join-Path $script:tempWsRoot '60-automation-rules-playbooks.md') -Raw
            $md | Should -Match '## Automation opportunities \(incident titles, last 30d\)'
            $md | Should -Match '\| Phishing email reported by user \| Medium \| 48 \| 46 \| 22.5 \| 41 \| 30 \| 9 \| Mostly false positive \| Soft-delete similar messages'
            $md | Should -Match '\| Brute force attempt against Entra ID \|[^\n]*\| Fast-closing \|[^\n]*\| Disable-AADUser / Confirm-AADRiskyUser \|'
            $md | Should -Match '\| Suspicious sign-in from rare country \|[^\n]*\| Mostly false positive \|'
        }
    }

    Context '81-table-plans-retention.md tables detection coverage' {
        It 'marks SigninLogs covered and FirewallLogs_CL uncovered' {
            $md = Get-Content (Join-Path $script:tempWsRoot '81-table-plans-retention.md') -Raw
            $md | Should -Match '## Tables by detection coverage'
            $md | Should -Match '\| FirewallLogs_CL \| Analytics \| 6000 \| 0 \| 0 \| None \|'
            # AuditLogs is in the fixture catalogue and read by the enabled Scheduled rule
            $md | Should -Match '\| AuditLogs \| Analytics \| 50 \| 1 \| 0 \| Sentinel rule \|'
        }
    }

    Context '25-mitre-coverage.md renders the tactic matrix' {
        BeforeAll {
            $script:mitre = Get-Content (Join-Path $script:tempWsRoot '25-mitre-coverage.md') -Raw
        }

        It 'lists Initial Access (covered by the test fixture rule)' {
            $script:mitre | Should -Match 'Initial Access'
        }

        It 'marks zero-coverage tactics as None, in words' {
            $script:mitre | Should -Match '\| None \|'
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

        It 'reads sub-techniques from the subTechniques array as well as from techniques' {
            # The second fixture rule carries T1110.003 only in subTechniques,
            # the shape the preview alertRules API returns.
            $script:mitre | Should -Match 'T1110\.003 — Password Spraying'
        }

        It 'places a technique under the tactics ATT&CK gives it, not every tactic on the rule' {
            # The first rule is tagged Initial Access and Credential Access and
            # maps T1078 (an Initial Access technique) and T1110 (Credential
            # Access only).
            $initial = [regex]::Match($script:mitre, '(?s)### TA0001 · Initial Access(.*?)(?=\n### |\n## )').Groups[1].Value
            $credential = [regex]::Match($script:mitre, '(?s)### TA0006 · Credential Access(.*?)(?=\n### |\n## )').Groups[1].Value
            $initial | Should -Match 'T1078 — Valid Accounts'
            $initial | Should -Not -Match 'T1110'
            $credential | Should -Match 'T1110 — Brute Force'
            $credential | Should -Not -Match 'T1078 — Valid Accounts'
        }

        It 'gives each sub-technique its own row with the parent''s coverage of sub-techniques' {
            $script:mitre | Should -Match '\| \[T1078 — Valid Accounts\]\([^)]+\) \|  \| 1 \| 1 of 4 \|'
            $script:mitre | Should -Match '\|  \| \[T1078\.004 — Cloud Accounts\]\([^)]+\) \| 1 \|  \|'
        }

        It 'lists every enabled rule once with its mapping, and no rule names in a technique table' {
            $script:mitre | Should -Match '\| Failed logons across multiple accounts \| Enabled \| Credential Access \| T1110 \| T1110\.003 \|'
            $script:mitre | Should -Match '\| Suspicious sign-in from rare country \| Enabled \| Initial Access, Credential Access \| T1078, T1110 \| T1078\.004 \|'
            # Disabled rules are listed too, after the enabled ones, and do
            # not count towards the tactic and technique tables.
            $script:mitre | Should -Match '(?s)\| Suspicious sign-in from rare country \| Enabled \|.*\| Lateral movement detected \| Disabled \| Lateral Movement \| T1021 \| T1021\.001 \|'
            $script:mitre | Should -Not -Match '### TA0008'
            $script:mitre | Should -Match '\*\*4\*\* of \*\*5\*\* rules are enabled'
            $script:mitre | Should -Match 'Enabling the disabled rules would add \*\*1\*\* techniques'
            $script:mitre | Should -Not -Match 'RuleNames'
            $script:mitre | Should -Not -Match 'base only'
        }

        It 'fills in the tactic summary under the chart' {
            $script:mitre | Should -Match '\*\*0 Covered · 2 Thin · 12 None\*\* of 14 tactics'
            $script:mitre | Should -Match 'Enabled rules map \*\*2\*\* techniques and \*\*2\*\* sub-techniques'
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
            $busyOut = Join-Path ([System.IO.Path]::GetTempPath()) "blueprint-busy-$(New-Guid)"
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
            $script:gapMd | Should -Match 'SAC-[A-Z]{2,4}-\d{2}'
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
            $script:dcMd | Should -Match '\| Source \| Identifier \| Table \| CatalogueConnector \| Last24hGB \| LastIngested \|'
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
            $script:uebaMd | Should -Match '\| BehaviorAnalytics \| 790 \| 1247 \| 1402 \|'
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

    Context '22-rule-health-quality.md surfaces stale rules, template drift and the anti-patterns' {
        BeforeAll {
            $script:rulesMd = Get-Content (Join-Path $script:tempWsRoot '20-analytics-rules.md') -Raw
            $script:qualityMd = Get-Content (Join-Path $script:tempWsRoot '22-rule-health-quality.md') -Raw
        }

        It 'renders the per-kind aggregate count header on the inventory page' {
            $script:rulesMd | Should -Match 'Scheduled-Enabled \| Scheduled-Disabled \| NRT-Enabled \| NRT-Disabled'
        }

        It 'lists the suspicious-sign-in rule as stale (lastModifiedUtc > 1y)' {
            $script:qualityMd | Should -Match '## Stale rules \(enabled, last modified over a year ago\)[\s\S]*\| Suspicious sign-in from rare country \| Scheduled \| High \| 2024-01-15 \|'
        }

        It 'shows the suspicious-sign-in rule as behind its template (1.0.0 vs 1.2.0)' {
            $script:qualityMd | Should -Match '## Rules behind their latest template version[\s\S]*\| Suspicious sign-in from rare country \| Scheduled \| 1\.0\.0 \| 1\.2\.0 \|'
        }

        It 'lists the rule with no entity mappings and the rule that creates no incidents' {
            $script:qualityMd | Should -Match '## Rules without entity mappings[\s\S]*\| Failed logons across multiple accounts \| Scheduled \| Medium \|'
            $script:qualityMd | Should -Match '## Rules that raise alerts without incidents[\s\S]*\| Failed logons across multiple accounts \| Scheduled \| Medium \|'
        }

        It 'no longer carries those sections on the inventory page' {
            $script:rulesMd | Should -Not -Match '## Mouldy rules|## Template mismatch|## Rule complexity|## Rule run failures|## By alert volume'
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

    Context '99-references.md is a copy of Blueprint-References.md' {
        It 'exists and contains the API versions table' {
            $p = Join-Path $script:tempWsRoot '99-references.md'
            (Get-Content $p -Raw) | Should -Match '## API versions in use'
        }
    }
}

Describe 'iSOC Blueprint renderer — empty-state safety' {
    # When a _raw/*.json file is missing, the renderer must NOT emit phantom
    # table rows with all-null cells (the @($null) + ForEach-Object bug).
    # Verified by removing specific raw files and re-running the renderer.

    BeforeAll {
        $script:emptyOutDir = Join-Path ([System.IO.Path]::GetTempPath()) "blueprint-empty-test-$(New-Guid)"
        New-Item -ItemType Directory -Path $script:emptyOutDir -Force | Out-Null
        $emptyWsRoot = Join-Path $script:emptyOutDir 'law-sentinel-empty'
        New-Item -ItemType Directory -Path (Join-Path $emptyWsRoot '_raw') -Force | Out-Null
        Get-ChildItem -Path $script:fixtureRaw -File | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $emptyWsRoot '_raw') -Force
        }
        # Deliberately remove the files that caused phantom rows on the production run.
        # TI removal needs both sources gone — the renderer falls back from metrics to counts.
        @('threat-intel-counts.json','threat-intel-metrics.json','playbooks.json','rbac-playbook-mi.json',
          'maturity.json','hunts.json','playbook-runs.json','rule-effectiveness.json',
          'rule-table-references.json','template-table-references.json','workspace-usage-daily.json') | ForEach-Object {
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

        It 'shows no run-health chart or warning when playbook-runs.json is absent' {
            $script:playbookMd | Should -Match '## Playbook runs \(last 7d\)[\s\S]*?_None\._'
            $script:playbookMd | Should -Not -Match 'had failed runs'
            $script:playbookMd | Should -Not -Match 'Playbook runs by outcome'
        }
    }

    Context 'health-check pages fall back cleanly when their captures are absent' {
        It '91-maturity-assessment.md says the assessment was not produced' {
            $md = Get-Content (Join-Path $script:emptyWsRoot '91-maturity-assessment.md') -Raw
            $md | Should -Match 'was not produced in this run'
            $md | Should -Not -Match '## Roadmap'
        }

        It '28-detection-opportunities.md says the mapping was not computed' {
            $md = Get-Content (Join-Path $script:emptyWsRoot '28-detection-opportunities.md') -Raw
            $md | Should -Match 'was not computed in this run'
        }

        It '00-overview.md still draws the estate flow with everything unmonitored' {
            $md = Get-Content (Join-Path $script:emptyWsRoot '00-overview.md') -Raw
            $md | Should -Match 'sankey-beta'
            $md | Should -Not -Match '"Ingestion","Detection'
            $md | Should -Match '_Maturity assessment not available for this run\._'
        }

        It '80-workspace.md omits the ingestion trend without daily usage' {
            $md = Get-Content (Join-Path $script:emptyWsRoot '80-workspace.md') -Raw
            $md | Should -Not -Match 'Daily ingestion \(last 30 days\)'
        }

        It '15-incidents.md and 30-hunting-queries.md show empty states' {
            (Get-Content (Join-Path $script:emptyWsRoot '21-rule-performance.md') -Raw) | Should -Match '## Rule effectiveness \(last 30d\)[\s\S]*?_None\._'
            (Get-Content (Join-Path $script:emptyWsRoot '30-hunting-queries.md') -Raw) | Should -Match '## Hunts[\s\S]*?_None\._'
        }
    }
}

Describe 'iSOC Blueprint renderer - snapshots from before the rename' {
    # The collector wrote DocumenterVersion before the Documenter became
    # Blueprint; a snapshot like that must still show its version.

    BeforeAll {
        $script:legacyOutDir = Join-Path ([System.IO.Path]::GetTempPath()) "blueprint-legacy-test-$(New-Guid)"
        $legacyWsRoot = Join-Path $script:legacyOutDir 'law-sentinel-legacy'
        New-Item -ItemType Directory -Path (Join-Path $legacyWsRoot '_raw') -Force | Out-Null
        Get-ChildItem -Path $script:fixtureRaw -File | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $legacyWsRoot '_raw') -Force
        }
        $ctxPath = Join-Path $legacyWsRoot '_raw/run-context.json'
        $ctx = Get-Content -LiteralPath $ctxPath -Raw | ConvertFrom-Json -AsHashtable
        $ctx['DocumenterVersion'] = '0.0.9'
        $ctx.Remove('BlueprintVersion')
        $ctx | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $ctxPath -Encoding utf8

        & $script:renderer `
            -WorkspaceName 'law-sentinel-legacy' `
            -InputRoot     $legacyWsRoot `
            -OutputRoot    $legacyWsRoot `
            -ResourcesRoot $script:resources `
            -InformationAction SilentlyContinue
        $script:legacyOverview = Get-Content -LiteralPath (Join-Path $legacyWsRoot '00-overview.md') -Raw
    }

    AfterAll {
        if ($script:legacyOutDir -and (Test-Path $script:legacyOutDir)) {
            Remove-Item -Recurse -Force -Path $script:legacyOutDir -ErrorAction SilentlyContinue
        }
    }

    It 'reads DocumenterVersion as the Blueprint version' {
        $script:legacyOverview | Should -Match '\*\*Blueprint\*\* v0\.0\.9'
    }
}

Describe 'iSOC Blueprint renderer - bookmarks on the hunting page' {
    BeforeAll {
        $script:bmOutDir = Join-Path ([System.IO.Path]::GetTempPath()) "blueprint-bookmarks-test-$(New-Guid)"
        $listRoot  = Join-Path $script:bmOutDir 'law-sentinel-list'
        $countRoot = Join-Path $script:bmOutDir 'law-sentinel-count'
        foreach ($root in $listRoot, $countRoot) {
            New-Item -ItemType Directory -Path (Join-Path $root '_raw') -Force | Out-Null
            Get-ChildItem -Path $script:fixtureRaw -File | Copy-Item -Destination (Join-Path $root '_raw') -Force
        }
        @'
[
  { "name": "bm-1", "properties": { "displayName": "Lateral movement from VPN", "created": "2026-09-30T08:15:00Z", "labels": ["hunt", "vpn"], "notes": "Seen on three hosts" } },
  { "name": "bm-2", "properties": { "displayName": "Rare parent process", "created": "2026-09-20T10:00:00Z", "labels": [], "notes": "" } }
]
'@ | Set-Content (Join-Path $listRoot '_raw/bookmarks.json') -Encoding UTF8
        Remove-Item (Join-Path $countRoot '_raw/bookmarks.json') -Force
        '{ "Count": 350, "Source": "too large" }' | Set-Content (Join-Path $countRoot '_raw/bookmarks-count.json') -Encoding UTF8
        foreach ($pair in @(@($listRoot, 'law-sentinel-list'), @($countRoot, 'law-sentinel-count'))) {
            & $script:renderer -WorkspaceName $pair[1] -InputRoot $pair[0] -OutputRoot $pair[0] -ResourcesRoot $script:resources -InformationAction SilentlyContinue
        }
        $script:bmList  = Get-Content (Join-Path $listRoot '30-hunting-queries.md') -Raw
        $script:bmCount = Get-Content (Join-Path $countRoot '30-hunting-queries.md') -Raw
    }

    AfterAll {
        if ($script:bmOutDir -and (Test-Path $script:bmOutDir)) { Remove-Item -Recurse -Force -Path $script:bmOutDir -ErrorAction SilentlyContinue }
    }

    It 'tables the bookmarks newest first with their labels and notes' {
        $script:bmList | Should -Match '## Bookmarks[\s\S]*\| Lateral movement from VPN \| 2026-09-30[^|]*\| hunt, vpn \| Seen on three hosts \|'
        ($script:bmList.IndexOf('Lateral movement from VPN')) | Should -BeLessThan ($script:bmList.IndexOf('Rare parent process'))
    }

    It 'falls back to the service-reported count when the list was too large' {
        $script:bmCount | Should -Match '## Bookmarks[\s\S]*\*\*350 bookmarks\*\* exist'
    }
}

Describe 'iSOC Blueprint renderer - sections from health check build 38' {

    BeforeAll {
        $script:hcRoot = Join-Path ([System.IO.Path]::GetTempPath()) "blueprint-hc38-$(New-Guid)"
        $page = { param($Root, $Name) Get-Content (Join-Path $Root $Name) -Raw }

        # The sample as it is, and two copies: one taken before the newer
        # captures existed, one with a table kept in the lake beyond its
        # analytics retention.
        $full = Join-Path $script:hcRoot 'full'
        $old = Join-Path $script:hcRoot 'old'
        $lake = Join-Path $script:hcRoot 'lake'
        foreach ($dir in $full, $old, $lake) {
            New-Item -ItemType Directory -Path (Join-Path $dir '_raw') -Force | Out-Null
            Get-ChildItem -Path $script:fixtureRaw -File | Copy-Item -Destination (Join-Path $dir '_raw')
        }
        foreach ($name in 'linked-storage-accounts.json', 'agent-heartbeat-mix.json', 'threat-intel-tables.json', 'threat-intel-health.json', 'taxii-clients.json', 'azure-firewall-categories.json') {
            Remove-Item (Join-Path $old "_raw/$name") -Force
        }
        $inc = Get-Content (Join-Path $old '_raw/incidents-summary.json') -Raw | ConvertFrom-Json
        $inc[0].PSObject.Properties.Remove('Count7d'); $inc[0].PSObject.Properties.Remove('ByProvider')
        ConvertTo-Json -InputObject @($inc) -Depth 8 | Set-Content (Join-Path $old '_raw/incidents-summary.json')
        $tables = Get-Content (Join-Path $lake '_raw/workspace-tables.json') -Raw | ConvertFrom-Json
        ($tables | Where-Object name -eq 'AuditLogs').properties.totalRetentionInDays = 365
        ConvertTo-Json -InputObject @($tables) -Depth 16 | Set-Content (Join-Path $lake '_raw/workspace-tables.json')

        foreach ($pair in @(@($full, 'law-hc-full'), @($old, 'law-hc-old'), @($lake, 'law-hc-lake'))) {
            & $script:renderer -WorkspaceName $pair[1] -InputRoot $pair[0] -OutputRoot $pair[0] -ResourcesRoot $script:resources -OutputFormat Markdown -InformationAction SilentlyContinue *> $null
        }
        $script:hc = @{}
        foreach ($n in '01-live-snapshot', '02-deprecated-legacy-features', '10-data-connectors', '11-sentinel-health', '13-data-source-hygiene', '14-coverage-breakdowns', '15-incidents', '16-alerts', '26-ueba', '27-threat-intelligence', '36-data-export', '81-table-plans-retention', '85-rbac', '86-subscription-context', '87-azure-monitor-agents', '89-retention', '91-maturity-assessment') {
            $script:hc[$n] = & $page $full "$n.md"
        }
        $script:hcOld = @{}
        foreach ($n in '14-coverage-breakdowns', '15-incidents', '27-threat-intelligence', '36-data-export', '87-azure-monitor-agents') {
            $script:hcOld[$n] = & $page $old "$n.md"
        }
        $script:hcLake = & $page $lake '89-retention.md'
    }

    AfterAll {
        if ($script:hcRoot -and (Test-Path $script:hcRoot)) { Remove-Item -Recurse -Force -Path $script:hcRoot -ErrorAction SilentlyContinue }
    }

    It 'adds continuous exports, linked storage accounts and ADX clusters to the data export page' {
        $hc['36-data-export'] | Should -Match '## Continuous data exports[\s\S]*\| export-to-eventhub \| Event Hub \|'
        $hc['36-data-export'] | Should -Match '## Linked storage accounts[\s\S]*\| CustomLogs \| stsentinellogs \|'
        $hc['36-data-export'] | Should -Match '## ADX clusters linked to the workspace[\s\S]*\| adxsentinelarchive \|'
    }

    It 'names the identity the collector ran as' {
        $hc['86-subscription-context'] | Should -Match '## Signed-in identity[\s\S]*\| Type \| ServicePrincipal \|'
    }

    It 'breaks the RBAC page down by role, Sentinel roles and high-privilege roles' {
        $hc['85-rbac'] | Should -Match '## Assignments by role[\s\S]*\| Owner \| 1 \| 0 \| 1 \| 0 \|'
        $hc['85-rbac'] | Should -Match '## Microsoft Sentinel role assignments[\s\S]*\| Sentinel SOC Reader \|'
        $hc['85-rbac'] | Should -Match '## Log Analytics and monitoring role assignments\s+_No Log Analytics or monitoring role'
        $hc['85-rbac'] | Should -Match '## High-privilege assignments[\s\S]*\| ci-deployer-sp \|\s+\| ServicePrincipal \| Contributor \|'
    }

    It 'shows all three retention checks with their outcome' {
        $hc['89-retention'] | Should -Match '## Retention recommendations[\s\S]*\| Default retention covers the free 90 days \| Action needed \|'
        $hc['89-retention'] | Should -Match '\| Long retention is set per table \| OK \|'
        $hc['81-table-plans-retention'] | Should -Not -Match '## Retention recommendations'
    }

    It 'lists the agent heartbeat mix with the legacy agent named' {
        $hc['87-azure-monitor-agents'] | Should -Match '## Agent heartbeat mix[\s\S]*\| Windows \| Azure Monitor Agent \| 1\.30\.0\.0 \|'
        $hc['87-azure-monitor-agents'] | Should -Match '\| Windows \| Direct Agent \(MMA, legacy\) \| 10\.20\.18069\.0 \|'
    }

    It 'adds the TI table migration status, indicator health, indicators by source and TAXII clients' {
        $ti = $hc['27-threat-intelligence']
        $ti | Should -Match '## Table migration status\s+\*\*Current\.\*\*'
        $ti | Should -Match '\| ThreatIntelligenceIndicator \(retired\) \| 0 \| 0 \|\s+\|\s+\| No data in 30 days \|'
        $ti | Should -Match '## Indicator health \(last 30d\)[\s\S]*\| Revoked \| 12 \|'
        $ti | Should -Match '## Indicators by source \(last 30d\)[\s\S]*\| Microsoft Defender Threat Intelligence \| 4200 \| 1180 \|'
        $ti | Should -Match '### TAXII clients[\s\S]*\| Open source feed \| 107 \| OnceAnHour \|'
    }

    It 'adds the 7-day incident metrics, incidents by provider and alert volumes by provider' {
        $hc['15-incidents'] | Should -Match '## Incident metrics \(last 7d\)[\s\S]*\| Incidents \| 14 \|[\s\S]*\| Raised through Defender XDR \(unified\) \| 5 \|[\s\S]*\| MTTA \(incidents closed in the window\) \| 60\.5 min \|'
        $hc['15-incidents'] | Should -Match '## Incidents by provider \(last 30d\)[\s\S]*\| Microsoft XDR \| 12 \|'
        $hc['16-alerts'] | Should -Match '## Alert volumes by provider \(last 7d\)[\s\S]*\| ASI NRT Alerts \| Azure Sentinel \| Privileged group membership change \| High \| 4 \|'
    }

    It 'shows unified incidents and legacy alert paths on the unification table' {
        $hc['10-data-connectors'] | Should -Match '\| Incidents raised through Defender XDR \(7d\) \| 5 of 14 \|'
        $hc['10-data-connectors'] | Should -Match '\| Alerts under the retired Azure Security Center name \(30d\) \| 0 \|'
    }

    It 'lists connectors that reported health failures, with the failure count' {
        $hc['11-sentinel-health'] | Should -Match '## Connector and DCR health issues \(last 7d\)[\s\S]*\| Office 365 \| Office365 \| 6 \| 2026-05-05 22:00 \|'
    }

    It 'adds AzureDiagnostics by category and both forms of Azure Firewall logging' {
        $hc['14-coverage-breakdowns'] | Should -Match '## AzureDiagnostics per category \(last 7d\)[\s\S]*\| MICROSOFT\.NETWORK \| AzureFirewallNetworkRule \| 9000 \|'
        $hc['14-coverage-breakdowns'] | Should -Match '## Azure Firewall categories \(last 7d\)\s+\*\*Collected twice\.\*\*'
        $hc['14-coverage-breakdowns'] | Should -Match '\| AZFWNetworkRule \|'
    }

    It 'adds the CEF vendor, duplicate record and event record columns to the hygiene page' {
        $hc['13-data-source-hygiene'] | Should -Match '\| syslog-forwarder-01 \| Palo Alto Networks-PAN-OS \| 2310 \|'
        $hc['13-data-source-hygiene'] | Should -Match '\| dc01\.contoso\.local \| 310 \| 1248 \|'
        $hc['13-data-source-hygiene'] | Should -Match '\| 4624 \| An account was successfully logged on \| 612340 \| 18\.234 \|'
    }

    It 'reports entity analytics beside UEBA' {
        $hc['26-ueba'] | Should -Match '## Entity analytics[\s\S]*\| IdentityInfo rows \(14d\) \| 360 \|[\s\S]*\| Entity analytics \| Enabled \|'
    }

    It 'explains the maturity scale and lists every open gap with its impact' {
        $hc['91-maturity-assessment'] | Should -Match '## Maturity scale[\s\S]*\| 3 \| Established \| 3\.00 to 3\.99 \| Target \|'
        $hc['91-maturity-assessment'] | Should -Match '## Open gaps and their impact[\s\S]*SAC-DET-03'
        $hc['91-maturity-assessment'] | Should -Not -Match 'Top 20 of'
    }

    It 'lists the legacy features still in use on their own page and counts them on the live snapshot' {
        $hc['02-deprecated-legacy-features'] | Should -Match '## Platform deprecation runway[\s\S]*## Legacy features still in use[\s\S]*\| Legacy Log Analytics agent \(MMA / OMS\), retired 31 August 2024 \| In use \| 8 machine'
        $hc['02-deprecated-legacy-features'] | Should -Match '\| Retired ThreatIntelligenceIndicator table \(ingestion\) \| Not in use \|'
        $hc['01-live-snapshot'] | Should -Match '\| Legacy features still in use \| \d+ of \d+ checked; see \[02-deprecated-legacy-features\.md\]'
        $hc['01-live-snapshot'] | Should -Not -Match '## Legacy features still in use|## Platform deprecation runway'
    }

    It 'says a newer capture was not taken rather than claiming there is nothing' {
        $hcOld['36-data-export'] | Should -Match '## Linked storage accounts[\s\S]*?_Not captured in this snapshot\._'
        $hcOld['87-azure-monitor-agents'] | Should -Match '## Agent heartbeat mix[\s\S]*?_Not captured in this snapshot\._'
        $hcOld['27-threat-intelligence'] | Should -Match '## Table migration status\s+_Not captured in this snapshot\._'
        $hcOld['27-threat-intelligence'] | Should -Match '### TAXII clients[\s\S]*?_Not captured in this snapshot\._'
        $hcOld['15-incidents'] | Should -Match '## Incident metrics \(last 7d\)[\s\S]*?_Not captured in this snapshot\._'
        $hcOld['14-coverage-breakdowns'] | Should -Match '## Azure Firewall categories \(last 7d\)\s+_Not captured in this snapshot\._'
    }

    It 'lists every table whose retention rolls into the lake and checks each is still fed' {
        $hcLake | Should -Match '## Retention that rolls into the lake[\s\S]*\| AuditLogs \| Analytics \| 30 \| 335 \| 365 \|'
        $hcLake | Should -Match '## Ingestion validation[\s\S]*\| AuditLogs \| Analytics \| 335 \|[^\n]*\| Check: '
    }
}

Describe 'iSOC Blueprint renderer - full reporting in plain words' {

    BeforeAll {
        $script:wideRoot = Join-Path ([System.IO.Path]::GetTempPath()) "blueprint-wide-$(New-Guid)"
        $wide = Join-Path $script:wideRoot 'wide'
        New-Item -ItemType Directory -Path (Join-Path $wide '_raw') -Force | Out-Null
        Get-ChildItem -Path $script:fixtureRaw -File | Copy-Item -Destination (Join-Path $wide '_raw')
        $raw = { param($Name, $Value) ConvertTo-Json -InputObject $Value -Depth 16 | Set-Content (Join-Path $wide "_raw/$Name") }

        # More of everything than any of the old cut-offs allowed: twelve
        # costed tables, eight TI sources and CEF vendors, fifteen XDR
        # tables and twenty-five catalogue-only schemas.
        $cost = Get-Content (Join-Path $wide '_raw/cost-estimate.json') -Raw | ConvertFrom-Json
        $all = @(@('FirewallLogs_CL', 'Syslog', 'DeviceProcessEvents') + @(1..9 | ForEach-Object { "WideTable$_`_CL" }))
        $cost | Add-Member -NotePropertyName AllTablesByCost -NotePropertyValue @($all | ForEach-Object -Begin { $gb = 2400 } -Process { $gb -= 100; [pscustomobject]@{ Table = $_; Plan = 'Analytics'; Gb30d = $gb; MonthlyCost = $gb * 2 } })
        & $raw 'cost-estimate.json' $cost
        Remove-Item (Join-Path $wide '_raw/threat-intel-metrics.json') -Force
        & $raw 'threat-intel-counts.json' @(1..8 | ForEach-Object { [pscustomobject]@{ SourceSystem = "Feed $_"; Count = 1000 - $_; Indicators = 100; Last = '2026-05-06T07:00:00Z' } })
        & $raw 'cef-devices.json' @(1..8 | ForEach-Object { [pscustomobject]@{ DeviceVendor = "Vendor $_"; DeviceProduct = 'Firewall'; LogCount = 900 - $_ } })
        & $raw 'xdr-table-presence.json' @(@('DeviceNetworkEvents') + @(1..14 | ForEach-Object { "XdrTable$_" }) | ForEach-Object { [pscustomobject]@{ Type = $_; RecordCount = 500 } })
        $tables = @(Get-Content (Join-Path $wide '_raw/workspace-tables.json') -Raw | ConvertFrom-Json)
        $tables += @(1..25 | ForEach-Object { [pscustomobject]@{ name = ('CatalogueOnly{0:D2}' -f $_); properties = [pscustomobject]@{ plan = 'Analytics'; retentionInDays = 30; totalRetentionInDays = 30; schema = [pscustomobject]@{ tableType = 'Microsoft' } } } })
        & $raw 'workspace-tables.json' $tables

        & $script:renderer -WorkspaceName 'law-wide' -InputRoot $wide -OutputRoot $wide -ResourcesRoot $script:resources -OutputFormat Markdown, Json -InformationAction SilentlyContinue *> $null
        $script:wide = $wide
        $script:widePage = { param($Name) Get-Content (Join-Path $script:wide "$Name.md") -Raw }
    }

    AfterAll {
        if ($script:wideRoot -and (Test-Path $script:wideRoot)) { Remove-Item -Recurse -Force -Path $script:wideRoot -ErrorAction SilentlyContinue }
    }

    It 'writes no emoji on any page' {
        foreach ($f in Get-ChildItem -Path $script:tempWsRoot -Filter '*.md') {
            Get-Content $f.FullName -Raw | Should -Not -Match '[\u2600-\u27BF]|[\uD83C-\uD83E][\uDC00-\uDFFF]' -Because $f.Name
        }
    }

    It 'never cuts a list short with "+ N more" or a "first N" sample' {
        foreach ($f in Get-ChildItem -Path $script:wide -Filter '*.md') {
            $md = Get-Content $f.FullName -Raw
            $md | Should -Not -Match '\(\+ \d+ more\)' -Because $f.Name
            $md | Should -Not -Match 'first \d+ names|The 50 most|The first five' -Because $f.Name
        }
    }

    It 'lists every costed table under the top-ten chart' {
        $md = & $script:widePage '84-cost-estimate'
        foreach ($n in 1..9) { $md | Should -Match "\| WideTable$n`_CL \| Analytics \|" }
        $md | Should -Match '\| DeviceProcessEvents \| Analytics \| 2100 \|'
    }

    It 'lists every catalogue-only schema by name' {
        $md = & $script:widePage '81-table-plans-retention'
        $md | Should -Match '## Catalogue-only Microsoft schemas[\s\S]*\| CatalogueOnly01 \|[\s\S]*\| CatalogueOnly25 \|'
    }

    It 'folds the TI and CEF pie tails into one Other slice while the tables keep every row' {
        $ti = & $script:widePage '27-threat-intelligence'
        $ti | Should -Match '"Other \(2\)" : 1985'
        $ti | Should -Match '\| Feed 8 \| 992 \|'
        & $script:widePage '13-data-source-hygiene' | Should -Match '"Other \(2\)" : 1785'
    }

    It 'charts every Defender XDR table and hands SharePoint the full names' {
        $md = & $script:widePage '14-coverage-breakdowns'
        $md | Should -Match 'bar \[(500, ){14}500\]'
        $md | Should -Match '%% x-labels \["DeviceNetworkEvents", "XdrTable1"'
        $chart = @((Get-Content (Join-Path $script:wide 'sections/14-coverage-breakdowns.json') -Raw | ConvertFrom-Json).blocks | Where-Object { $_.type -eq 'chart' -and $_.kind -eq 'xy' })[0]
        @($chart.data.xAxis.labels).Count | Should -Be 15
        $chart.data.xAxis.labels[0] | Should -Be 'DeviceNetworkEvents'
    }
}

Describe 'iSOC Blueprint renderer - connector catalogue, saved searches and Sentinel pricing' {

    BeforeAll {
        $script:catRoot = Join-Path ([System.IO.Path]::GetTempPath()) "blueprint-catalogue-$(New-Guid)"
        $ws = Join-Path $script:catRoot 'cat'
        New-Item -ItemType Directory -Path (Join-Path $ws '_raw') -Force | Out-Null
        Get-ChildItem -Path $script:fixtureRaw -File | Copy-Item -Destination (Join-Path $ws '_raw')
        $raw = { param($Name, $Value) ConvertTo-Json -InputObject $Value -Depth 16 | Set-Content (Join-Path $ws "_raw/$Name") }

        # A codeless connector with no data and a deprecated connector, on top
        # of the sample's four.
        $conn = @(Get-Content (Join-Path $ws '_raw/data-connectors-classic.json') -Raw | ConvertFrom-Json)
        $conn += [pscustomobject]@{ name = 'ado'; kind = 'RestApiPoller'; properties = [pscustomobject]@{ connectorDefinitionName = 'AzureDevOpsAuditLogs' } }
        $conn += [pscustomobject]@{ name = 'dt'; kind = 'DarktraceAma'; properties = [pscustomobject]@{} }
        & $raw 'data-connectors-classic.json' $conn
        $tables = @(Get-Content (Join-Path $ws '_raw/workspace-tables.json') -Raw | ConvertFrom-Json)
        $tables += [pscustomobject]@{ name = 'Dynamics365Activity'; properties = [pscustomobject]@{ plan = 'Analytics'; retentionInDays = 30; totalRetentionInDays = 30; schema = [pscustomobject]@{ tableType = 'Microsoft' } } }
        & $raw 'workspace-tables.json' $tables
        & $raw 'kql-savedsearches.json' @(
            [pscustomobject]@{ name = 'h1'; properties = [pscustomobject]@{ category = 'Hunting Queries'; displayName = 'A hunt'; query = 'SigninLogs' } }
            [pscustomobject]@{ name = 'f1'; properties = [pscustomobject]@{ category = 'Functions'; displayName = 'A parser'; functionAlias = 'MyParser'; query = 'Syslog' } }
            [pscustomobject]@{ name = 'l1'; properties = [pscustomobject]@{ category = 'Log Management'; displayName = 'Failed sign-ins by user'; query = "SigninLogs`n| where ResultType != 0`n| summarize count() by UserPrincipalName" } }
            [pscustomobject]@{ name = 'g1'; properties = [pscustomobject]@{ category = 'General Exploration'; displayName = 'All syslog'; query = 'Syslog' } }
        )
        & $raw 'sentinel-pricing.json' @([pscustomobject]@{ name = 'default'; kind = 'Sentinel'; properties = [pscustomobject]@{ tier = 'CapacityReservation'; capacityGbPerDay = 100 } })

        & $script:renderer -WorkspaceName 'law-cat' -InputRoot $ws -OutputRoot $ws -ResourcesRoot $script:resources -OutputFormat Markdown -InformationAction SilentlyContinue *> $null
        $script:catPage = { param($Name) Get-Content (Join-Path $ws "$Name.md") -Raw }
    }

    AfterAll {
        if ($script:catRoot -and (Test-Path $script:catRoot)) { Remove-Item -Recurse -Force -Path $script:catRoot -ErrorAction SilentlyContinue }
    }

    It 'matches each connected connector against the catalogue, silent ones first' {
        $md = & $script:catPage '10-data-connectors'
        $md | Should -Match '## Connected connectors against the catalogue[\s\S]*\| Azure DevOps Audit Logs \(via Codeless Connector Platform\) \| AzureDevOpsAuditing \| Silent \|'
        $md | Should -Match '\| AI Analyst Darktrace via AMA \| AI Analyst Darktrace \| Receiving data, deprecated connector \| CommonSecurityLog \|'
        $md | Should -Match '\| MicrosoftThreatIntelligence \|\s+\| Not in the catalogue \|'
        $section = ($md -split '## Connected connectors against the catalogue')[1]
        $section.IndexOf('| Silent |') | Should -BeLessThan $section.IndexOf('| Receiving data')
    }

    It 'credits each table in the effective view to a connector' {
        $md = & $script:catPage '10-data-connectors'
        $md | Should -Match '\| Classic \| AzureActiveDirectory/signInLogs \| SigninLogs \| Microsoft Entra ID \|'
        $md | Should -Match '\| CommonSecurityLog \| Shared by \d+ connectors \|'
    }

    It 'lists deprecated connectors still connected among the legacy features' {
        & $script:catPage '02-deprecated-legacy-features' | Should -Match '\| Deprecated data connectors still connected \| In use \| 1 connector\(s\): AI Analyst Darktrace via AMA \|'
    }

    It 'names the connector that would fill a catalogue-only schema and the solutions behind tables with no template' {
        & $script:catPage '81-table-plans-retention' | Should -Match '\| Dynamics365Activity \| Dynamics 365 \|'
        & $script:catPage '28-detection-opportunities' | Should -Match '## Tables with no template available[\s\S]*\| CommonSecurityLog \| 300 \| Shared by \d+ solutions \|'
    }

    It 'lists the saved searches that are neither hunting queries nor parsers' {
        $md = & $script:catPage '35-parsers-functions'
        $md | Should -Match '## Other saved searches[\s\S]*\| General Exploration \| All syslog \| 1 \|[\s\S]*\| Log Management \| Failed sign-ins by user \| 3 \|'
        ($md -split '## Other saved searches')[1] | Should -Not -Match 'A hunt|A parser'
    }

    It 'shows what the Sentinel pricings endpoint reports, setting by setting' {
        $md = & $script:catPage '84-cost-estimate'
        $md | Should -Match '## Sentinel pricing settings[\s\S]*\| default \| tier \| CapacityReservation \|[\s\S]*\| default \| capacityGbPerDay \| 100 \|'
    }

    It 'says when the endpoint returned nothing, as on the sample' {
        Get-Content (Join-Path $script:tempWsRoot '84-cost-estimate.md') -Raw | Should -Match '## Sentinel pricing settings[\s\S]*_The endpoint returned nothing for this workspace\._'
    }
}

Describe 'iSOC Blueprint renderer - findings and maturity as one assessment' {

    BeforeAll {
        $script:gap90 = Get-Content (Join-Path $script:tempWsRoot '90-gap-analysis.md') -Raw
        $script:mat91 = Get-Content (Join-Path $script:tempWsRoot '91-maturity-assessment.md') -Raw
    }

    It 'gives the findings summary a Maturity column' {
        $script:gap90 | Should -Match '\| ID \| Severity \| Category \| Title \| Maturity \|'
        $script:gap90 | Should -Match '\| \[SAC-LOG-03\]\(#sac-log-03\) \| Warning \| Cost \|[^\n]*\| \+0\.075 to LOG \|'
        $script:gap90 | Should -Match '\| \[SAC-LOG-07\]\(#sac-log-07\) \|[^\n]*\| Not scored \|'
    }

    It 'says on each finding card which criterion it decides and what closing it is worth' {
        $script:gap90 | Should -Match '\*\*Maturity:\*\* decides \[SAC-LOG-03\]\(91-maturity-assessment\.md#criteria\) A daily cap is set \(Log management and cost\), now Gap; closing it lifts the overall score by \+0\.075\.'
        $script:gap90 | Should -Match '\*\*Maturity:\*\* not scored\. This is a hygiene or cost check'
    }

    It 'links the two pages to each other' {
        $script:gap90 | Should -Match '\[maturity assessment\]\(91-maturity-assessment\.md\)'
        $script:mat91 | Should -Match '\[gap analysis\]\(90-gap-analysis\.md\) are one assessment'
    }
}

Describe '37-search-restore.md lists the search job and restored tables' {
    BeforeAll {
        $script:srOutDir = Join-Path ([System.IO.Path]::GetTempPath()) "blueprint-sr-$(New-Guid)"
        $root = Join-Path $script:srOutDir 'law-sr'
        New-Item -ItemType Directory -Path (Join-Path $root '_raw') -Force | Out-Null
        # A snapshot from before the collector wrote search-jobs.json and
        # restore-logs.json: the tables are only in the table list.
        Get-ChildItem -Path $script:fixtureRaw -File | Where-Object Name -NotIn 'search-jobs.json', 'restore-logs.json' |
            Copy-Item -Destination (Join-Path $root '_raw')
        $tables = @(Get-Content (Join-Path $script:fixtureRaw 'workspace-tables.json') -Raw | ConvertFrom-Json)
        $tables += [pscustomobject]@{ name = 'SigninLogs_1A2B_SRCH'; properties = [pscustomobject]@{
                createDate = '2026-09-01T10:00:00Z'; totalRetentionInDays = 30
                schema = [pscustomobject]@{ tableType = 'SearchResults' }
                searchResults = [pscustomobject]@{ sourceTable = 'SigninLogs'; query = 'SigninLogs | where ResultType != 0'
                    startSearchTime = '2025-01-01T00:00:00Z'; endSearchTime = '2025-03-31T00:00:00Z' } } }
        $tables += [pscustomobject]@{ name = 'Syslog_RST'; properties = [pscustomobject]@{
                schema = [pscustomobject]@{ tableType = 'RestoredLogs' }
                restoredLogs = [pscustomobject]@{ sourceTable = 'Syslog'; startRestoreTime = '2025-02-01T00:00:00Z'; endRestoreTime = '2025-02-02T00:00:00Z' } } }
        ConvertTo-Json -InputObject $tables -Depth 10 | Set-Content (Join-Path $root '_raw/workspace-tables.json')
        & $script:renderer -WorkspaceName 'law-sr' -InputRoot $root -OutputRoot $root -ResourcesRoot $script:resources -OutputFormat Markdown -InformationAction SilentlyContinue *> $null
        $script:sr37 = Get-Content (Join-Path $root '37-search-restore.md') -Raw
        $script:fx37 = Get-Content (Join-Path $script:tempWsRoot '37-search-restore.md') -Raw
    }

    AfterAll {
        if ($script:srOutDir -and (Test-Path $script:srOutDir)) { Remove-Item -Recurse -Force -Path $script:srOutDir -ErrorAction SilentlyContinue }
    }

    It 'reads them from the table list when the snapshot has neither file' {
        $script:sr37 | Should -Match '\*\*1\*\* search job and \*\*1\*\* restore'
        $script:sr37 | Should -Match '\| SigninLogs_1A2B_SRCH \| SigninLogs \| 2025-01-01 00:00 to 2025-03-31 00:00 \| 2026-09-01 10:00 \| 30 days \| `SigninLogs \\\| where ResultType != 0` \|'
        $script:sr37 | Should -Match '\| Syslog_RST \| Syslog \| 2025-02-01 00:00 to 2025-02-02 00:00 \|'
    }

    It 'says so plainly when there are none, and no longer dumps raw properties' {
        $script:fx37 | Should -Match '_No search job tables in the workspace\._'
        $script:fx37 | Should -Match '_No restored tables in the workspace\._'
        $script:fx37 | Should -Not -Match '\| name \| properties \|'
    }
}

Describe 'Gap evidence lists keep a name that starts with a Markdown marker as text' {
    BeforeAll {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:renderer, [ref]$null, [ref]$null)
        foreach ($name in '_EscapeMdListItem', '_FormatGapEvidence') {
            $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
            . ([scriptblock]::Create($fn.Extent.Text))
        }
    }

    It 'escapes a leading bullet, heading, quote or number marker' {
        _EscapeMdListItem '* Deteccion trafico SMB 1.0' | Should -Be '\* Deteccion trafico SMB 1.0'
        _EscapeMdListItem '- dash' | Should -Be '\- dash'
        _EscapeMdListItem '# hash' | Should -Be '\# hash'
        _EscapeMdListItem '> quote' | Should -Be '\> quote'
        _EscapeMdListItem '1. Test' | Should -Be '1\. Test'
        _EscapeMdListItem 'SAP - Login' | Should -Be 'SAP - Login'
        _EscapeMdListItem '*bold*' | Should -Be '*bold*'
    }

    It 'writes such a name as one bullet, not an empty bullet and a nested one' {
        $ev = '146 rule(s) disabled: ' + ((1..20 | ForEach-Object { "Rule number $_" }) + '* Deteccion trafico SMB 1.0' -join '; ')
        $md = _FormatGapEvidence $ev
        $md | Should -Match '(?m)^  - \\\* Deteccion trafico SMB 1\.0$'
        $md | Should -Not -Match '(?m)^  - \* '
    }
}
