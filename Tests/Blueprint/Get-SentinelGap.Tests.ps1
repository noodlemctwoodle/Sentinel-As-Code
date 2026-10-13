#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for the Sentinel Blueprint gap-analysis engine.

.DESCRIPTION
    Drives Get-SentinelGap with the deliberately-broken fixture under
    Tests/Blueprint/Fixtures/sample/_raw and asserts that each rule fires
    against the conditions encoded in the fixture.

    The fixture is constructed so several SENT-* rules fire by design:

      SAC-LOG-03  Daily cap unset                   (workspace.json: dailyQuotaGb = -1)
      SAC-LOG-07  Default retention < 90d           (workspace.json: retentionInDays = 30)
      SAC-DET-05  Disabled rule                     (alert-rules.json: NRT rule disabled)
      SAC-GOV-06  Owner role at workspace scope     (rbac-workspace.json: legacy admin group)
      SAC-PLT-11  Defender migration banner         (always fires)
      SAC-LOG-02  > 50 GB Analytics-plan candidate  (FirewallLogs_CL: 2000 GB / 30d)
      SAC-LOG-11  > 90d retention on Analytics      (FirewallLogs_CL: 730d)
      SAC-LOG-13  Sentinel benefit not applied      (SecurityEvent: 500 GB billable)
      SAC-PLT-05  Replication disabled              (workspace.json)
      SAC-PLT-06  Public network access enabled     (workspace.json)
      SAC-PLT-09  Microsoft.Insights NotRegistered  (resource-providers.json)
      SAC-GOV-07  disableLocalAuth = false          (workspace.json)
      SAC-INV-01  Silent table                      (AuditLogs: 90d data, no recent)
      SAC-INV-04  Orphan table                      (OrphanTable_CL: schema, no data)

    The v2.2 rules (ported from the health-check script contributed to the
    project) fire on these conditions:

      SAC-DET-06  Noisy rule                        (rule-effectiveness.json: aaaa closed 24, 19 FP)
      SAC-DET-03  No entity mappings                (alert-rules.json: eeee enabled, entityMappings [])
      SAC-MON-01  Alert-only rule                   (alert-rules.json: eeee createIncident false)
      SAC-DET-08  Legacy incident-creation rule     (alert-rules.json: dddd MicrosoftSecurityIncidentCreation enabled)
      SAC-TI-02  Rule on legacy TI table           (rule-table-references.json: eeee reads ThreatIntelligenceIndicator)
      SAC-MON-05  High-volume table, no detection   (FirewallLogs_CL, SecurityEvent, OfficeActivity ... unreferenced)
      SAC-MON-06  Silent table with dependent rule  (AuditLogs IngestedLast7d 0, read by aaaa)
      SAC-AUT-02  Playbook failures                 (playbook-runs.json: IncidentEnrich-IP Failed7d 5)
      SAC-DET-13  Deprecated / missing solution     (office365 isDeprecated, legacy-feed not in catalogue)
      SAC-TI-05  Single TI feed                    (data-connectors-classic.json: MicrosoftThreatIntelligence only)
      SAC-LOG-06  AzFW logged twice                 (AzureFirewall* categories + AZFWNetworkRule table)
      SAC-INC-02  Closed unclassified               (incidents-summary.json: 20 of 32 closed Undetermined/Unclassified)
      SAC-HNT-01  No hunting activity               (hunts.json and bookmarks.json both [])
      SAC-DET-14  Rule run failures                 (rule-health.json: Suspicious sign-in from rare country, 3 failed runs)

    Rules that read a capture file the collector only writes on success
    (051, 052, 058) stay quiet when the file is absent; the second Describe
    proves that with a trimmed copy of the fixture.

    Adding new rules requires extending the fixture and adding a row in the
    expected-IDs list.

.EXAMPLE
    Invoke-Pester -Path Tests/Blueprint/Get-SentinelGap.Tests.ps1

    Runs the full gap-analysis suite against the deliberately-broken
    fixture.

.EXAMPLE
    Invoke-Pester -Path Tests/Blueprint/Get-SentinelGap.Tests.ps1 -Output Detailed

    Runs with per-assertion output, for identifying which SENT-* rule
    stopped firing.

.NOTES
    File:         Tests/Blueprint/Get-SentinelGap.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-06-03
    Version:      0.3.0
    Last Updated: 2026-10-09
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeDiscovery {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:fixtureRaw   = Join-Path $script:repoRoot 'Tests/Blueprint/Fixtures/sample/_raw'
    $script:resourcesDir = Join-Path $script:repoRoot 'Tools/Blueprint/Private/Resources'
    $script:rulesPath    = Join-Path $script:resourcesDir 'best-practices.json'
    $script:gapChecks    = Join-Path $script:repoRoot 'Tools/Blueprint/Private/GapChecks.ps1'
    $script:gapEngine    = Join-Path $script:repoRoot 'Tools/Blueprint/Private/Get-SentinelGap.ps1'
}

BeforeAll {
    $repoRoot     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $fixtureRaw   = Join-Path $repoRoot 'Tests/Blueprint/Fixtures/sample/_raw'
    $resourcesDir = Join-Path $repoRoot 'Tools/Blueprint/Private/Resources'
    $rulesPath    = Join-Path $resourcesDir 'best-practices.json'
    $gapChecks    = Join-Path $repoRoot 'Tools/Blueprint/Private/GapChecks.ps1'
    $gapEngine    = Join-Path $repoRoot 'Tools/Blueprint/Private/Get-SentinelGap.ps1'

    . $gapEngine

    $script:findings = Get-SentinelGap `
        -InputRoot     $fixtureRaw `
        -ResourcesRoot $resourcesDir `
        -RulesPath     $rulesPath `
        -GapChecksPath $gapChecks
}

Describe 'Sentinel gap-analysis engine' {

    Context 'against the deliberately-broken sample fixture' {

        It 'returns at least one finding' {
            $findings.Count | Should -BeGreaterThan 0
        }

        It 'fires SAC-LOG-03 because daily cap is unset' {
            ($findings | Where-Object Id -eq 'SAC-LOG-03').Count | Should -Be 1
        }

        It 'fires SAC-LOG-07 because retention is 30d < 90d' {
            $f = $findings | Where-Object Id -eq 'SAC-LOG-07'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match '30 days'
        }

        It 'fires SAC-DET-05 because an NRT rule is disabled' {
            ($findings | Where-Object Id -eq 'SAC-DET-05').Count | Should -Be 1
        }

        It 'fires SAC-GOV-06 because Owner exists at workspace scope' {
            ($findings | Where-Object Id -eq 'SAC-GOV-06').Count | Should -Be 1
        }

        It 'fires SAC-PLT-11 (Defender migration banner is always emitted)' {
            ($findings | Where-Object Id -eq 'SAC-PLT-11').Count | Should -Be 1
        }

        It 'fires SAC-LOG-02 because FirewallLogs_CL is > 50 GB on Analytics' {
            $f = $findings | Where-Object Id -eq 'SAC-LOG-02'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'FirewallLogs_CL'
        }

        It 'fires SAC-LOG-11 because at least one table has retention > 90d' {
            ($findings | Where-Object Id -eq 'SAC-LOG-11').Count | Should -Be 1
        }

        It 'fires SAC-PLT-05 because replication is disabled' {
            ($findings | Where-Object Id -eq 'SAC-PLT-05').Count | Should -Be 1
        }

        It 'fires SAC-PLT-06 because public network access is Enabled' {
            $f = $findings | Where-Object Id -eq 'SAC-PLT-06'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'Enabled'
        }

        It 'fires SAC-PLT-09 because Microsoft.Insights is NotRegistered' {
            ($findings | Where-Object Id -eq 'SAC-PLT-09').Count | Should -Be 1
        }

        It 'fires SAC-GOV-07 because disableLocalAuth is false' {
            ($findings | Where-Object Id -eq 'SAC-GOV-07').Count | Should -Be 1
        }

        It 'fires SAC-INV-01 because AuditLogs has 90d data but none last 7d' {
            ($findings | Where-Object Id -eq 'SAC-INV-01').Count | Should -Be 1
        }

        It 'fires SAC-INV-04 because OrphanTable_CL has schema and no data' {
            $f = $findings | Where-Object Id -eq 'SAC-INV-04'
            $f.Count | Should -Be 1
        }

        It 'every finding carries a non-empty Learn URL' {
            foreach ($f in $findings) {
                $f.Learn | Should -Not -BeNullOrEmpty
                $f.Learn | Should -Match '^https?://learn\.microsoft\.com'
            }
        }

        It 'every finding carries a non-empty Remediation' {
            foreach ($f in $findings) {
                $f.Remediation | Should -Not -BeNullOrEmpty
            }
        }

        It 'every finding has a Severity in the documented set' {
            foreach ($f in $findings) {
                $f.Severity | Should -BeIn @('Critical','Warning','Info')
            }
        }

        # ----- v2 catalogue additions ------------------------------------

        It 'fires SAC-INC-06 because MTTR is 1620 min (27h) > 24h threshold' {
            $f = $findings | Where-Object Id -eq 'SAC-INC-06'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match '27 hours'
        }

        It 'fires SAC-INC-05 because 20 of 32 closed incidents were never acknowledged (62%)' {
            $f = $findings | Where-Object Id -eq 'SAC-INC-05'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match '20 of 32 closed incidents'
        }

        It 'fires SAC-DET-04 because the Scheduled rule was last modified in 2024 (>1y ago)' {
            $f = $findings | Where-Object Id -eq 'SAC-DET-04'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'Suspicious sign-in from rare country'
        }

        It 'fires SAC-DET-10 because the deployed rule is at v1.0.0 vs template v1.2.0' {
            $f = $findings | Where-Object Id -eq 'SAC-DET-10'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match '1\.0\.0.*1\.2\.0'
        }

        It 'fires SAC-DET-11 because one rule produces 412 of 525 alerts (78%)' {
            $f = $findings | Where-Object Id -eq 'SAC-DET-11'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'Suspicious sign-in from rare country'
        }

        It 'fires SAC-AUT-01 because automation-rules.json is empty' {
            ($findings | Where-Object Id -eq 'SAC-AUT-01').Count | Should -Be 1
        }

        It 'does NOT fire SAC-DET-12 because the only enabled Scheduled/NRT rule is in the noisy set' {
            # The fixture has volumes for "Suspicious sign-in" / "Failed logons" / "Privileged group" only.
            # SAC-DET-12 should NOT flag the disabled rule (filtered out by enabled=false), so it only fires when
            # there exist enabled Scheduled/NRT rules outside the noisy set. The fixture's lone enabled Scheduled
            # rule IS in the noisy set, so we expect zero findings here — confirming the negative path.
            ($findings | Where-Object Id -eq 'SAC-DET-12').Count | Should -Be 0
        }

        It 'fires SAC-GOV-05 because a service principal holds Contributor at workspace scope' {
            $f = $findings | Where-Object Id -eq 'SAC-GOV-05'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'ci-deployer-sp'
        }

        It 'fires SAC-GOV-04 because no identity holds Microsoft Sentinel Responder' {
            ($findings | Where-Object Id -eq 'SAC-GOV-04').Count | Should -Be 1
        }

        It 'does NOT fire SAC-GOV-03 because the fixture has a CanNotDelete lock present' {
            ($findings | Where-Object Id -eq 'SAC-GOV-03').Count | Should -Be 0
        }

        It 'fires SAC-LOG-15 because CommonSecurityLog is 300 GB / 30d (above the 150 GB threshold)' {
            $f = $findings | Where-Object Id -eq 'SAC-LOG-15'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'CommonSecurityLog'
        }

        It 'fires SAC-LOG-16 because Syslog is 280 GB / 30d' {
            $f = $findings | Where-Object Id -eq 'SAC-LOG-16'
            $f.Count | Should -Be 1
        }

        It 'fires SAC-LOG-17 because SecurityEvent is 500 GB / 30d' {
            $f = $findings | Where-Object Id -eq 'SAC-LOG-17'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'SecurityEvent'
        }

        It 'fires SAC-LOG-18 because AzureDiagnostics is 50 GB / 30d (above the 10 GB AzureDiagnostics threshold)' {
            $f = $findings | Where-Object Id -eq 'SAC-LOG-18'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'AzureDiagnostics'
        }

        # ----- v2.1 deprecation-deadline rules ---------------------------

        It 'fires SAC-PLT-02 because LegacyCLv1_CL has data but no DCR points to it' {
            $f = $findings | Where-Object Id -eq 'SAC-PLT-02'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'LegacyCLv1_CL'
            $f.Severity | Should -Be 'Critical'
        }

        It 'does NOT flag FirewallLogs_CL under SAC-PLT-02 (CLv2 — has a DCR)' {
            $f = $findings | Where-Object Id -eq 'SAC-PLT-02'
            $f.Evidence | Should -Not -Match 'FirewallLogs_CL'
        }

        It 'fires SAC-PLT-03 because the fixture shows 8 machines still on MMA' {
            $f = $findings | Where-Object Id -eq 'SAC-PLT-03'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match '8 machine'
            $f.Severity | Should -Be 'Critical'
        }

        It 'fires SAC-TI-01 because ThreatIntelligenceIndicator carries billable data' {
            $f = $findings | Where-Object Id -eq 'SAC-TI-01'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'ThreatIntelligenceIndicator'
            $f.Severity | Should -Be 'Critical'
        }

        It 'notes the new ThreatIntelIndicators table is absent when SAC-TI-01 fires' {
            $f = $findings | Where-Object Id -eq 'SAC-TI-01'
            $f.Evidence | Should -Match 'No data observed in the new'
        }

        # ----- v2.2 health-check rules -----------------------------------

        It 'fires SAC-DET-06 because "Suspicious sign-in" closed 19 of 24 incidents as false positive' {
            $f = $findings | Where-Object Id -eq 'SAC-DET-06'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'Suspicious sign-in from rare country'
            $f.Evidence | Should -Match '19 of 24'
            $f.Detail.Rules[0].FPRate | Should -Be 79.2
        }

        It 'does NOT flag "Failed logons" under SAC-DET-06 (only 8 closed, under the floor of 20)' {
            ($findings | Where-Object Id -eq 'SAC-DET-06').Evidence | Should -Not -Match 'Failed logons'
        }

        It 'fires SAC-DET-03 because the enabled rule "Failed logons" has no entity mappings' {
            $f = $findings | Where-Object Id -eq 'SAC-DET-03'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'Failed logons across multiple accounts'
            $f.Evidence | Should -Match '1 of 2 enabled'
        }

        It 'does NOT name the mapped rule or the disabled rule under SAC-DET-03' {
            $f = $findings | Where-Object Id -eq 'SAC-DET-03'
            $f.Evidence | Should -Not -Match 'Suspicious sign-in'
            $f.Evidence | Should -Not -Match 'Lateral movement'
        }

        It 'fires SAC-MON-01 because "Failed logons" has createIncident false' {
            $f = $findings | Where-Object Id -eq 'SAC-MON-01'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'Failed logons across multiple accounts'
            $f.Evidence | Should -Not -Match 'Suspicious sign-in'
        }

        It 'fires SAC-DET-08 because a MicrosoftSecurityIncidentCreation rule is enabled while XDR syncs incidents' {
            $f = $findings | Where-Object Id -eq 'SAC-DET-08'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'Create incidents from MDE alerts'
            $f.Evidence | Should -Match 'duplicate incidents'
            $f.Detail.XdrIncidentsConnected | Should -BeTrue
        }

        It 'fires SAC-TI-02 because the enabled rule "Failed logons" reads ThreatIntelligenceIndicator' {
            $f = $findings | Where-Object Id -eq 'SAC-TI-02'
            $f.Count | Should -Be 1
            $f.Severity | Should -Be 'Critical'
            $f.Evidence | Should -Match 'Failed logons across multiple accounts'
            $f.Evidence | Should -Not -Match 'Lateral movement'
        }

        It 'fires SAC-MON-05 for the high-volume tables no enabled rule reads' {
            $f = $findings | Where-Object Id -eq 'SAC-MON-05'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'FirewallLogs_CL 2000 GB'
            $f.Detail.Count | Should -Be 8
            @($f.Detail.Tables | ForEach-Object Table) | Should -Not -Contain 'SigninLogs'
            @($f.Detail.Tables | ForEach-Object Table) | Should -Not -Contain 'SecurityIncident'
        }

        It 'suggests an undeployed template under SAC-MON-05 but never a deprecated or deployed one' {
            $f = $findings | Where-Object Id -eq 'SAC-MON-05'
            $office = $f.Detail.Tables | Where-Object Table -eq 'OfficeActivity'
            $office.SuggestedTemplates | Should -Contain 'Data exfiltration'
            $firewall = $f.Detail.Tables | Where-Object Table -eq 'FirewallLogs_CL'
            @($firewall.SuggestedTemplates).Count | Should -Be 0
            $f.Evidence | Should -Not -Match 'Deprecated'
            $f.Evidence | Should -Not -Match 'Suspicious sign-in'
        }

        It 'fires SAC-MON-06 because AuditLogs is read by an enabled rule and ingested nothing in 7 days' {
            $f = $findings | Where-Object Id -eq 'SAC-MON-06'
            $f.Count | Should -Be 1
            $f.Severity | Should -Be 'Critical'
            $f.Evidence | Should -Match 'AuditLogs'
            $f.Evidence | Should -Match 'Suspicious sign-in from rare country'
            $f.Evidence | Should -Not -Match 'SigninLogs'
        }

        It 'fires SAC-AUT-02 because IncidentEnrich-IP failed 5 of 42 runs' {
            $f = $findings | Where-Object Id -eq 'SAC-AUT-02'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'IncidentEnrich-IP \(5 of 42 runs failed, last 2026-05-05T22:15:00Z\)'
            $f.Evidence | Should -Not -Match 'NotifyOnHighSev'
        }

        It 'fires SAC-DET-13 for the deprecated solution and the one missing from the catalogue' {
            $f = $findings | Where-Object Id -eq 'SAC-DET-13'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'Microsoft 365 \(deprecated\)'
            $f.Evidence | Should -Match 'Legacy Threat Feed \(not in catalogue\)'
            $f.Evidence | Should -Not -Match 'Azure Active Directory'
        }

        It 'fires SAC-TI-05 because the only TI feed is MicrosoftThreatIntelligence' {
            $f = $findings | Where-Object Id -eq 'SAC-TI-05'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'single feed \(MicrosoftThreatIntelligence\)'
        }

        It 'fires SAC-LOG-06 because AzureFirewall* categories and the AZFWNetworkRule table both carry data' {
            $f = $findings | Where-Object Id -eq 'SAC-LOG-06'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'AzureFirewallNetworkRule'
            $f.Evidence | Should -Match 'AZFWNetworkRule'
            $f.Detail.LegacyRows7d | Should -Be 12099
        }

        It 'fires SAC-INC-02 because 20 of 32 closed incidents have no classification (62%)' {
            $f = $findings | Where-Object Id -eq 'SAC-INC-02'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match '20 of 32 closed incidents \(62%\)'
        }

        It 'fires SAC-DET-14 because a rule run failed three times' {
            $f = $findings | Where-Object Id -eq 'SAC-DET-14'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'Suspicious sign-in from rare country \(3 failed run\(s\): Query execution exceeded'
            $f.Detail.Rules[0].Status | Should -Be 'Failure'
        }

        It 'fires SAC-HNT-01 because hunts.json and bookmarks.json are both empty' {
            ($findings | Where-Object Id -eq 'SAC-HNT-01').Count | Should -Be 1
        }

        It 'carries no em-dash in any v2.2 rule text' {
            $rules = (Get-Content $rulesPath -Raw | ConvertFrom-Json).rules | Where-Object {
                $_.id -in @('SAC-DET-06','SAC-DET-03','SAC-MON-01','SAC-DET-08') -or $_.id -ge 'SAC-TI-02'
            }
            foreach ($r in $rules) {
                ($r.title + $r.remediation) | Should -Not -Match ([char]0x2014)
            }
        }
    }
}

Describe 'Disabled-rules check names bulk changes and rules that still fired' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        . (Join-Path $repoRoot 'Tools/Blueprint/Private/GapChecks.ps1')
        function New-Rule($name, $title, $enabled, $modified) {
            [pscustomobject]@{ name = $name; kind = 'Scheduled'; properties = [pscustomobject]@{ displayName = $title; enabled = $enabled; lastModifiedUtc = $modified } }
        }
        $rules = @(1..12 | ForEach-Object { New-Rule ("r$_") "Rule $_" $false '2026-08-31T10:00:00Z' })
        $rules += New-Rule 'r13' 'Still firing' $false '2026-09-19T08:00:00Z'
        $rules += New-Rule 'r14' 'Kept on' $true '2026-01-01T00:00:00Z'
        $script:inv = [pscustomobject]@{
            AlertRules = $rules
            RulesFired = @([pscustomobject]@{ AlertRuleId = 'R13'; AlertName = 'Still firing'; Alerts = 382 }, [pscustomobject]@{ AlertRuleId = 'r14'; AlertName = 'Kept on'; Alerts = 5 })
        }
        $script:f = Test-RulesDisabledOrFailing -Inventory $script:inv
    }

    It 'counts the disabled rules and names the bulk day' {
        $script:f.Detail.Count | Should -Be 13
        $script:f.Detail.BulkDay | Should -Be '2026-08-31'
        $script:f.Detail.BulkCount | Should -Be 12
        $script:f.Evidence | Should -Match '12 of them were last modified on 2026-08-31'
    }

    It 'lists the disabled rules that produced alerts in the last 30 days' {
        @($script:f.Detail.FiredThenDisabled).Count | Should -Be 1
        $script:f.Detail.FiredThenDisabled[0].Rule | Should -Be 'Still firing'
        $script:f.Evidence | Should -Match 'Still firing \(382 alert\(s\) in 30d, disabled 2026-09-19\)'
    }

    It 'stays quiet about bulk changes when the disabled set is small' {
        $small = [pscustomobject]@{ AlertRules = @((New-Rule 'a' 'A' $false '2026-08-31T10:00:00Z'), (New-Rule 'b' 'B' $false '2026-08-31T10:00:00Z')); RulesFired = @() }
        $r = Test-RulesDisabledOrFailing -Inventory $small
        $r.Detail.BulkDay | Should -BeNullOrEmpty
        $r.Evidence | Should -Not -Match 'bulk change'
    }
}

Describe 'Rule checks stay quiet on a workspace with no enabled Scheduled or NRT rules' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        . (Join-Path $repoRoot 'Tools/Blueprint/Private/GapChecks.ps1')
        $script:quiet = [pscustomobject]@{
            AlertRules = @(
                [pscustomobject]@{ name = 'off'; kind = 'Scheduled'; properties = [pscustomobject]@{ displayName = 'Switched off'; enabled = $false } },
                [pscustomobject]@{ name = 'fusion'; kind = 'Fusion'; properties = [pscustomobject]@{ displayName = 'Advanced Multistage Attack Detection'; enabled = $true } }
            )
        }
    }

    It 'returns no finding from the entity-mapping check under strict mode' {
        Set-StrictMode -Version Latest
        Test-RuleEntityMappingsPresent -Inventory $script:quiet | Should -BeNullOrEmpty
    }

    It 'returns no finding from the incident-creation check under strict mode' {
        Set-StrictMode -Version Latest
        Test-RuleCreatesIncidents -Inventory $script:quiet | Should -BeNullOrEmpty
    }
}

Describe 'No-detection check counts Defender custom detections as coverage' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        . (Join-Path $repoRoot 'Tools/Blueprint/Private/GapChecks.ps1')
        $script:tables = @([pscustomobject]@{ DataType = 'DeviceProcessEvents'; BillableLast30d = 40 })
    }

    It 'fires when nothing reads a high-volume table' {
        $inv = [pscustomobject]@{ RawFiles = @('rule-table-references.json'); TablesWithData = $script:tables; RuleTableReferences = @(); TemplateTableReferences = @(); CustomDetectionRefs = @() }
        (Test-HighVolumeTableWithoutDetection -Inventory $inv).Evidence | Should -Match 'DeviceProcessEvents 40 GB'
    }

    It 'stays quiet when an enabled custom detection reads the table' {
        $inv = [pscustomobject]@{ RawFiles = @('rule-table-references.json'); TablesWithData = $script:tables; RuleTableReferences = @(); TemplateTableReferences = @();
            CustomDetectionRefs = @([pscustomobject]@{ RuleId = 'cd-1'; RuleName = 'LSASS'; Enabled = $true; Tables = @('DeviceProcessEvents') }) }
        Test-HighVolumeTableWithoutDetection -Inventory $inv | Should -BeNullOrEmpty
    }

    It 'ignores a disabled custom detection' {
        $inv = [pscustomobject]@{ RawFiles = @('rule-table-references.json'); TablesWithData = $script:tables; RuleTableReferences = @(); TemplateTableReferences = @();
            CustomDetectionRefs = @([pscustomobject]@{ RuleId = 'cd-1'; RuleName = 'LSASS'; Enabled = $false; Tables = @('DeviceProcessEvents') }) }
        (Test-HighVolumeTableWithoutDetection -Inventory $inv).Evidence | Should -Match 'no enabled Sentinel rule or Defender custom detection'
    }
}

Describe 'Sentinel gap-analysis rule catalogue' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:catalogue = Get-Content (Join-Path $repoRoot 'Tools/Blueprint/Private/Resources/best-practices.json') -Raw | ConvertFrom-Json
        $script:areaIds = @('DET', 'PLT', 'COV', 'AUT', 'MON', 'INC', 'INV', 'TI', 'HNT', 'LOG', 'GOV')
    }

    It 'names every rule in the maturity id scheme, uniquely' {
        $ids = @($script:catalogue.rules | ForEach-Object { $_.id })
        $ids.Count | Should -Be 59
        ($ids | Sort-Object -Unique).Count | Should -Be 59
        foreach ($id in $ids) { $id | Should -Match '^SAC-[A-Z]{2,4}-\d{2}$' }
    }

    It 'keeps the retired SENT id as a unique legacy alias and names an area on every rule' {
        $legacy = @($script:catalogue.rules | ForEach-Object { $_.legacyId })
        ($legacy | Sort-Object -Unique).Count | Should -Be 59
        foreach ($l in $legacy) { $l | Should -Match '^SENT-\d{3}$' }
        foreach ($r in $script:catalogue.rules) {
            $r.area | Should -BeIn $script:areaIds
            $r.id | Should -Match ('^SAC-' + [regex]::Escape($r.area) + '-\d{2}$')
        }
    }

    It 'gives a rule the id of the criterion it decides' {
        ($script:catalogue.rules | Where-Object legacyId -eq 'SENT-037').id | Should -Be 'SAC-DET-03'
        ($script:catalogue.rules | Where-Object legacyId -eq 'SENT-001').id | Should -Be 'SAC-LOG-03'
        ($script:catalogue.rules | Where-Object legacyId -eq 'SENT-059').id | Should -Be 'SAC-DET-14'
    }
}

Describe 'Sentinel gap-analysis engine: absent captures stay quiet' {

    BeforeAll {
        $repoRoot     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $fixtureRaw   = Join-Path $repoRoot 'Tests/Blueprint/Fixtures/sample/_raw'
        $resourcesDir = Join-Path $repoRoot 'Tools/Blueprint/Private/Resources'
        $rulesPath    = Join-Path $resourcesDir 'best-practices.json'
        $gapChecks    = Join-Path $repoRoot 'Tools/Blueprint/Private/GapChecks.ps1'
        . (Join-Path $repoRoot 'Tools/Blueprint/Private/Get-SentinelGap.ps1')

        # A copy of the fixture without the files the collector only writes
        # when its capture succeeds. "Not captured" must not read as "none".
        $script:trimmed = Join-Path ([System.IO.Path]::GetTempPath()) "gap-absent-$(New-Guid)"
        New-Item -ItemType Directory -Path $script:trimmed -Force | Out-Null
        Get-ChildItem $fixtureRaw -File | Copy-Item -Destination $script:trimmed
        foreach ($name in 'rule-table-references.json', 'template-table-references.json', 'hunts.json', 'playbook-runs.json', 'rule-effectiveness.json', 'rule-health.json', 'azure-diagnostics-categories.json') {
            Remove-Item (Join-Path $script:trimmed $name) -Force
        }
        $script:absentOutcomes = [System.Collections.Generic.List[object]]::new()
        $script:absentFindings = Get-SentinelGap -InputRoot $script:trimmed -ResourcesRoot $resourcesDir `
            -RulesPath $rulesPath -GapChecksPath $gapChecks -OutcomeCollector $script:absentOutcomes
    }

    AfterAll {
        if ($script:trimmed -and (Test-Path $script:trimmed)) { Remove-Item $script:trimmed -Recurse -Force }
    }

    It 'records every rule as Passed or Fired, none Errored, when capture files are missing' {
        @($absentOutcomes | Where-Object Outcome -in 'Errored', 'Undefined').Count | Should -Be 0
    }

    It 'does not fire the rules whose input capture is absent' {
        foreach ($id in 'SAC-DET-06', 'SAC-TI-02', 'SAC-MON-05', 'SAC-MON-06', 'SAC-AUT-02', 'SAC-LOG-06', 'SAC-HNT-01', 'SAC-DET-14') {
            ($absentOutcomes | Where-Object Id -eq $id).Outcome | Should -Be 'Passed' -Because "$id has no input to judge"
        }
    }

    It 'still fires the rules whose inputs are present' {
        foreach ($id in 'SAC-DET-03', 'SAC-MON-01', 'SAC-DET-08', 'SAC-DET-13', 'SAC-TI-05', 'SAC-INC-02') {
            ($absentFindings | Where-Object Id -eq $id).Count | Should -Be 1 -Because "$id reads files that are still there"
        }
    }

    It 'takes the service-reported bookmark count when the list was too large to fetch' {
        # bookmarks.json absent, bookmarks-count.json present with a count: hunting activity exists, SAC-HNT-01 stays quiet.
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) "gap-bmcount-$(New-Guid)"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            Get-ChildItem $fixtureRaw -File | Copy-Item -Destination $dir
            Remove-Item (Join-Path $dir 'bookmarks.json') -Force
            '{ "Count": 350, "Source": "too large" }' | Set-Content (Join-Path $dir 'bookmarks-count.json')
            $out = [System.Collections.Generic.List[object]]::new()
            $null = Get-SentinelGap -InputRoot $dir -ResourcesRoot $resourcesDir -RulesPath $rulesPath -GapChecksPath $gapChecks -OutcomeCollector $out
            ($out | Where-Object Id -eq 'SAC-HNT-01').Outcome | Should -Be 'Passed'
        } finally { Remove-Item $dir -Recurse -Force }
    }
}

Describe 'Sentinel gap-analysis engine: per-check outcomes' {

    BeforeAll {
        $repoRoot     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $fixtureRaw   = Join-Path $repoRoot 'Tests/Blueprint/Fixtures/sample/_raw'
        $resourcesDir = Join-Path $repoRoot 'Tools/Blueprint/Private/Resources'
        $rulesPath    = Join-Path $resourcesDir 'best-practices.json'
        $gapChecks    = Join-Path $repoRoot 'Tools/Blueprint/Private/GapChecks.ps1'
        . (Join-Path $repoRoot 'Tools/Blueprint/Private/Get-SentinelGap.ps1')

        $script:ruleIds = @((Get-Content $rulesPath -Raw | ConvertFrom-Json).rules | ForEach-Object id)
        $script:outcomes = [System.Collections.Generic.List[object]]::new()
        $script:withCollector = Get-SentinelGap -InputRoot $fixtureRaw -ResourcesRoot $resourcesDir `
            -RulesPath $rulesPath -GapChecksPath $gapChecks -OutcomeCollector $script:outcomes

        # A rules file with one check that throws and one that does not exist,
        # to prove both are recorded rather than silently dropped.
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "gap-outcomes-$(New-Guid)"
        New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
        $badChecks = Join-Path $script:tempDir 'BadChecks.ps1'
        Set-Content -Path $badChecks -Value @(
            'function Test-Throws { param($Inventory) throw "boom" }'
            'function Test-Quiet  { param($Inventory) return $null }'
        )
        $badRules = Join-Path $script:tempDir 'rules.json'
        @{ rules = @(
                @{ id = 'SAC-TST-01'; title = 't'; category = 'c'; severity = 'Info'; check = 'Test-Throws'; remediation = ''; learn = '' }
                @{ id = 'SAC-TST-02'; title = 't'; category = 'c'; severity = 'Info'; check = 'Test-Missing'; remediation = ''; learn = '' }
                @{ id = 'SAC-TST-03'; title = 't'; category = 'c'; severity = 'Info'; check = 'Test-Quiet'; remediation = ''; learn = '' }
            ) } | ConvertTo-Json -Depth 4 | Set-Content -Path $badRules
        $script:badOutcomes = [System.Collections.Generic.List[object]]::new()
        $null = Get-SentinelGap -InputRoot $fixtureRaw -ResourcesRoot $resourcesDir -RulesPath $badRules `
            -GapChecksPath $badChecks -OutcomeCollector $script:badOutcomes -WarningAction SilentlyContinue
    }

    AfterAll {
        if ($script:tempDir -and (Test-Path $script:tempDir)) { Remove-Item $script:tempDir -Recurse -Force }
    }

    It 'records exactly one outcome per rule' {
        $outcomes.Count | Should -Be $ruleIds.Count
        @($outcomes | ForEach-Object Id | Sort-Object -Unique).Count | Should -Be $ruleIds.Count
    }

    It 'marks every finding that fired as Fired' {
        foreach ($f in $withCollector) {
            ($outcomes | Where-Object Id -eq $f.Id).Outcome | Should -Be 'Fired'
        }
    }

    It 'marks rules that produced no finding as Passed' {
        $fired = @($withCollector | ForEach-Object Id)
        $passed = @($outcomes | Where-Object { $_.Id -notin $fired })
        $passed | ForEach-Object { $_.Outcome | Should -Be 'Passed' }
    }

    It 'records a check that throws as Errored with its message' {
        $o = $badOutcomes | Where-Object Id -eq 'SAC-TST-01'
        $o.Outcome | Should -Be 'Errored'
        $o.Message | Should -Match 'boom'
    }

    It 'records a check that is not defined as Undefined' {
        ($badOutcomes | Where-Object Id -eq 'SAC-TST-02').Outcome | Should -Be 'Undefined'
    }

    It 'records a check that returns nothing as Passed' {
        ($badOutcomes | Where-Object Id -eq 'SAC-TST-03').Outcome | Should -Be 'Passed'
    }

    It 'returns the same findings with or without a collector' {
        $plain = Get-SentinelGap -InputRoot (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Tests/Blueprint/Fixtures/sample/_raw') `
            -ResourcesRoot (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Tools/Blueprint/Private/Resources') `
            -RulesPath (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Tools/Blueprint/Private/Resources/best-practices.json') `
            -GapChecksPath (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Tools/Blueprint/Private/GapChecks.ps1')
        @($plain | ForEach-Object Id) | Should -Be @($withCollector | ForEach-Object Id)
    }
}
