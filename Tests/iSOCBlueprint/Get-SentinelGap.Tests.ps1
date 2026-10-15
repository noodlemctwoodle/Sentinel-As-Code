#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for the iSOC Blueprint gap-analysis engine.

.DESCRIPTION
    Drives Get-SentinelGap with the deliberately-broken fixture under
    Tests/iSOCBlueprint/Fixtures/sample/_raw and asserts that each rule fires
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
    Invoke-Pester -Path Tests/iSOCBlueprint/Get-SentinelGap.Tests.ps1

    Runs the full gap-analysis suite against the deliberately-broken
    fixture.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Get-SentinelGap.Tests.ps1 -Output Detailed

    Runs with per-assertion output, for identifying which SENT-* rule
    stopped firing.

.NOTES
    File:         Tests/iSOCBlueprint/Get-SentinelGap.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-06-03
    Version:      0.4.0
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeDiscovery {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:fixtureRaw   = Join-Path $script:repoRoot 'Tests/iSOCBlueprint/Fixtures/sample/_raw'
    $script:resourcesDir = Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Private/Resources'
    $script:rulesPath    = Join-Path $script:resourcesDir 'best-practices.json'
    $script:gapChecks    = Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1'
    $script:gapEngine    = Join-Path $script:repoRoot 'Modules/iSOCBlueprint/Engine/Private/Get-SentinelGap.ps1'
}

BeforeAll {
    $repoRoot     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $fixtureRaw   = Join-Path $repoRoot 'Tests/iSOCBlueprint/Fixtures/sample/_raw'
    $resourcesDir = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Resources'
    $rulesPath    = Join-Path $resourcesDir 'best-practices.json'
    $gapChecks    = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1'
    $gapEngine    = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Get-SentinelGap.ps1'

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
            $f.Evidence | Should -Match '27\.0 hours'
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
            $f.Evidence | Should -Match 'FirewallLogs_CL 2,000\.00 GB'
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
            $f.Evidence | Should -Match 'IncidentEnrich-IP \(5 of 42 runs failed, last 5 May 2026 22:15 UTC\)'
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

        It 'fires SAC-LOG-22 because dc01 sent 310 SecurityEvent records more than once' {
            $f = $findings | Where-Object Id -eq 'SAC-LOG-22'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'dc01\.contoso\.local \(310 duplicated events\)'
        }

        It 'fires SAC-LOG-23 because a forwarder put CEF messages into Syslog' {
            $f = $findings | Where-Object Id -eq 'SAC-LOG-23'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'syslog-forwarder-01 \(2,310 records\)'
        }

        It 'does not fire the newer rules the sample satisfies' {
            foreach ($id in 'SAC-COV-08', 'SAC-DET-15', 'SAC-LOG-19', 'SAC-LOG-20', 'SAC-LOG-21', 'SAC-PLT-12') {
                ($findings | Where-Object Id -eq $id).Count | Should -Be 0 -Because "$id passes on the sample"
            }
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
            $f.Evidence | Should -Match 'Suspicious sign-in from rare country \(3 failed runs: Query execution exceeded'
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
        . (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1')
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
        $script:f.Evidence | Should -Match '12 of them were last modified on 31 Aug 2026'
    }

    It 'lists the disabled rules that produced alerts in the last 30 days' {
        @($script:f.Detail.FiredThenDisabled).Count | Should -Be 1
        $script:f.Detail.FiredThenDisabled[0].Rule | Should -Be 'Still firing'
        $script:f.Evidence | Should -Match 'Still firing \(382 alerts in 30 days, disabled 19 Sep 2026\)'
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
        . (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1')
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
        . (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1')
        $script:tables = @([pscustomobject]@{ DataType = 'DeviceProcessEvents'; BillableLast30d = 40 })
    }

    It 'fires when nothing reads a high-volume table' {
        $inv = [pscustomobject]@{ RawFiles = @('rule-table-references.json'); TablesWithData = $script:tables; RuleTableReferences = @(); TemplateTableReferences = @(); CustomDetectionRefs = @() }
        (Test-HighVolumeTableWithoutDetection -Inventory $inv).Evidence | Should -Match 'DeviceProcessEvents 40\.00 GB'
    }

    It 'stays quiet when an enabled custom detection reads the table' {
        $inv = [pscustomobject]@{ RawFiles = @('rule-table-references.json'); TablesWithData = $script:tables; RuleTableReferences = @(); TemplateTableReferences = @();
            CustomDetectionRefs = @([pscustomobject]@{ RuleId = 'cd-1'; RuleName = 'LSASS'; Enabled = $true; Tables = @('DeviceProcessEvents') }) }
        Test-HighVolumeTableWithoutDetection -Inventory $inv | Should -BeNullOrEmpty
    }

    It 'never suggests a template only a deprecated Content Hub solution ships' {
        $d = { param($ids) [pscustomobject]@{ criteria = @(foreach ($i in $ids) { [pscustomobject]@{ contentId = $i; kind = 'AnalyticsRule' } }) } }
        $inv = [pscustomobject]@{ RawFiles = @('rule-table-references.json'); TablesWithData = $script:tables; RuleTableReferences = @(); CustomDetectionRefs = @()
            TemplateTableReferences = @(
                [pscustomobject]@{ TemplateId = 'old-1'; DisplayName = 'TI map old'; Deprecated = $false; AlreadyDeployed = $false; Tables = @('DeviceProcessEvents'); Severity = 'High' }
                [pscustomobject]@{ TemplateId = 'new-1'; DisplayName = 'Process injection'; Deprecated = $false; AlreadyDeployed = $false; Tables = @('DeviceProcessEvents'); Severity = 'Medium' })
            ContentPackages = @()
            ContentProductPackages = @(
                [pscustomobject]@{ properties = [pscustomobject]@{ contentId = 'ti'; displayName = 'Threat Intelligence'; isDeprecated = 'true'; dependencies = (& $d @('old-1')) } }
                [pscustomobject]@{ properties = [pscustomobject]@{ contentId = 'ep'; displayName = 'Endpoint'; isDeprecated = 'false'; dependencies = (& $d @('new-1')) } }) }
        $f = Test-HighVolumeTableWithoutDetection -Inventory $inv
        $f.Evidence | Should -Match 'Process injection'
        $f.Evidence | Should -Not -Match 'TI map old'
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
        $script:catalogue = Get-Content (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Resources/best-practices.json') -Raw | ConvertFrom-Json
        $script:areaIds = @('DET', 'PLT', 'COV', 'AUT', 'MON', 'INC', 'INV', 'TI', 'HNT', 'LOG', 'GOV')
    }

    It 'names every rule in the maturity id scheme, uniquely' {
        $ids = @($script:catalogue.rules | ForEach-Object { $_.id })
        $ids.Count | Should -Be 67
        ($ids | Sort-Object -Unique).Count | Should -Be 67
        foreach ($id in $ids) { $id | Should -Match '^SAC-[A-Z]{2,4}-\d{2}$' }
    }

    It 'keeps the retired SENT id as a unique legacy alias on the rules that had one, and names an area on every rule' {
        # Rules added after the rename (catalogue 3.1.0 on) never had a SENT id.
        $added = @('SAC-COV-08', 'SAC-DET-15', 'SAC-LOG-19', 'SAC-LOG-20', 'SAC-LOG-21', 'SAC-LOG-22', 'SAC-LOG-23', 'SAC-PLT-12')
        $withLegacy = @($script:catalogue.rules | Where-Object { $_.PSObject.Properties['legacyId'] })
        @($withLegacy | ForEach-Object id | Where-Object { $_ -in $added }).Count | Should -Be 0
        @($script:catalogue.rules | Where-Object { -not $_.PSObject.Properties['legacyId'] } | ForEach-Object id | Sort-Object) | Should -Be ($added | Sort-Object)
        $legacy = @($withLegacy | ForEach-Object { $_.legacyId })
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
        $fixtureRaw   = Join-Path $repoRoot 'Tests/iSOCBlueprint/Fixtures/sample/_raw'
        $resourcesDir = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Resources'
        $rulesPath    = Join-Path $resourcesDir 'best-practices.json'
        $gapChecks    = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1'
        . (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Get-SentinelGap.ps1')

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

    It 'keeps the newer rules quiet when their captures are missing' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) "gap-newer-absent-$(New-Guid)"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            Get-ChildItem $fixtureRaw -File | Copy-Item -Destination $dir
            foreach ($name in 'security-event-duplicates.json', 'cef-in-syslog.json', 'la-query-logs.json', 'summary-rules.json', 'table-query-usage.json', 'ueba-data-presence.json') {
                Remove-Item (Join-Path $dir $name) -Force -ErrorAction SilentlyContinue
            }
            $out = [System.Collections.Generic.List[object]]::new()
            $null = Get-SentinelGap -InputRoot $dir -ResourcesRoot $resourcesDir -RulesPath $rulesPath -GapChecksPath $gapChecks -OutcomeCollector $out
            foreach ($id in 'SAC-COV-08', 'SAC-LOG-19', 'SAC-LOG-21', 'SAC-LOG-22', 'SAC-LOG-23', 'SAC-PLT-12') {
                ($out | Where-Object Id -eq $id).Outcome | Should -Be 'Passed' -Because "$id has no input to judge"
            }
        } finally { Remove-Item $dir -Recurse -Force }
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
        $fixtureRaw   = Join-Path $repoRoot 'Tests/iSOCBlueprint/Fixtures/sample/_raw'
        $resourcesDir = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Resources'
        $rulesPath    = Join-Path $resourcesDir 'best-practices.json'
        $gapChecks    = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1'
        . (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Get-SentinelGap.ps1')

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
        $plain = Get-SentinelGap -InputRoot (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Tests/iSOCBlueprint/Fixtures/sample/_raw') `
            -ResourcesRoot (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/iSOCBlueprint/Engine/Private/Resources') `
            -RulesPath (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/iSOCBlueprint/Engine/Private/Resources/best-practices.json') `
            -GapChecksPath (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1')
        @($plain | ForEach-Object Id) | Should -Be @($withCollector | ForEach-Object Id)
    }
}

Describe 'Rules ported from health check build 38' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        . (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1')
        function New-Table([string] $Name, [int] $Analytics, [int] $Total, [string] $Plan = 'Analytics') {
            [pscustomobject]@{ name = $Name; properties = [pscustomobject]@{ plan = $Plan; retentionInDays = $Analytics; totalRetentionInDays = $Total } }
        }
    }

    Context 'SAC-COV-08 entity analytics' {
        It 'fires with no provider and no IdentityInfo rows' {
            $inv = [pscustomobject]@{ RawFiles = @('settings.json', 'ueba-data-presence.json')
                Settings = [pscustomobject]@{ EntityAnalytics = [pscustomobject]@{ properties = [pscustomobject]@{} } }
                UebaDataPresence = @([pscustomobject]@{ TableName = 'BehaviorAnalytics'; Count = 10 }) }
            (Test-EntityAnalyticsEnabled -Inventory $inv).Evidence | Should -Match 'no identity provider'
        }
        It 'stays quiet with a provider configured, or with IdentityInfo rows' {
            $withProvider = [pscustomobject]@{ RawFiles = @('settings.json', 'ueba-data-presence.json')
                Settings = [pscustomobject]@{ EntityAnalytics = [pscustomobject]@{ properties = [pscustomobject]@{ entityProviders = @('AzureActiveDirectory') } } }
                UebaDataPresence = @() }
            Test-EntityAnalyticsEnabled -Inventory $withProvider | Should -BeNullOrEmpty
            $withRows = [pscustomobject]@{ RawFiles = @('settings.json', 'ueba-data-presence.json'); Settings = [pscustomobject]@{ EntityAnalytics = $null }
                UebaDataPresence = @([pscustomobject]@{ TableName = 'IdentityInfo'; Count = 0; Count14d = 42 }) }
            Test-EntityAnalyticsEnabled -Inventory $withRows | Should -BeNullOrEmpty
        }
    }

    Context 'SAC-LOG-19 summary rules' {
        It 'fires with no summary rules and a table at 50 GB or more, summing per-solution rows' {
            $inv = [pscustomobject]@{ RawFiles = @('summary-rules.json'); SummaryRules = @()
                TablesWithData = @([pscustomobject]@{ DataType = 'CommonSecurityLog'; BillableLast30d = 30 }, [pscustomobject]@{ DataType = 'CommonSecurityLog'; BillableLast30d = 25 }, [pscustomobject]@{ DataType = 'Syslog'; BillableLast30d = 5 }) }
            $f = Test-SummaryRulesInUse -Inventory $inv
            $f.Evidence | Should -Match 'CommonSecurityLog \(55\.00 GB\)'
            $f.Evidence | Should -Not -Match 'Syslog'
        }
        It 'stays quiet when a summary rule exists or nothing is high volume' {
            Test-SummaryRulesInUse -Inventory ([pscustomobject]@{ RawFiles = @('summary-rules.json'); SummaryRules = @([pscustomobject]@{ name = 'r' }); TablesWithData = @([pscustomobject]@{ DataType = 'T'; BillableLast30d = 500 }) }) | Should -BeNullOrEmpty
            Test-SummaryRulesInUse -Inventory ([pscustomobject]@{ RawFiles = @('summary-rules.json'); SummaryRules = @(); TablesWithData = @([pscustomobject]@{ DataType = 'T'; BillableLast30d = 4 }) }) | Should -BeNullOrEmpty
        }
    }

    Context 'SAC-LOG-20 retention order' {
        It 'fires when analytics retention exceeds total retention, and only then' {
            $inv = [pscustomobject]@{ RawFiles = @('workspace-tables.json'); WorkspaceTables = @((New-Table 'Bad' 180 90), (New-Table 'Good' 90 365), (New-Table 'Equal' 30 30)) }
            $f = Test-RetentionOrder -Inventory $inv
            $f.Evidence | Should -Match 'Bad \(analytics 180 days, total 90 days\)'
            @($f.Detail.Tables).Count | Should -Be 1
        }
    }

    Context 'SAC-LOG-21 long-term retention usage' {
        BeforeAll {
            $script:lakeInv = {
                param($Refs = @(), $Usage = @(), $Summary = @(), $Extra = @())
                [pscustomobject]@{ RawFiles = @('table-query-usage.json', 'rule-table-references.json')
                    WorkspaceTables = @((New-Table 'LongTable' 30 365), (New-Table 'LakeOnly' 0 730 'DataLake'), (New-Table 'Short' 30 30)) + $Extra
                    RuleTableReferences = $Refs; TableQueryUsage = $Usage; SummaryRules = $Summary }
            }
        }
        It 'lists every long-retention table nothing reads' {
            $f = Test-LongRetentionUsage -Inventory (& $script:lakeInv)
            $f.Evidence | Should -Match 'LakeOnly \(730 days total\)'
            $f.Evidence | Should -Match 'LongTable \(365 days total\)'
            $f.Evidence | Should -Not -Match 'Short'
        }
        It 'counts an enabled rule, a summary rule, a search job or an audited query as use' {
            $inv = & $script:lakeInv -Refs @([pscustomobject]@{ Enabled = $true; Tables = @('LongTable') }) -Usage @([pscustomobject]@{ Table = 'LakeOnly'; Queries = 3 })
            Test-LongRetentionUsage -Inventory $inv | Should -BeNullOrEmpty
            $inv = & $script:lakeInv -Summary @([pscustomobject]@{ properties = [pscustomobject]@{ ruleDefinition = [pscustomobject]@{ query = 'LongTable | summarize count()' } } }) -Extra @([pscustomobject]@{ name = 'LakeOnly_SRCH'; properties = [pscustomobject]@{ plan = 'Analytics'; retentionInDays = 30; totalRetentionInDays = 30 } })
            Test-LongRetentionUsage -Inventory $inv | Should -BeNullOrEmpty
        }
        It 'ignores a disabled rule' {
            $inv = & $script:lakeInv -Refs @([pscustomobject]@{ Enabled = $false; Tables = @('LongTable', 'LakeOnly') })
            (Test-LongRetentionUsage -Inventory $inv).Evidence | Should -Match 'LongTable'
        }
    }

    Context 'SAC-PLT-12 query auditing' {
        It 'fires when LAQueryLogs is empty or missing from the capture, and stays quiet with queries' {
            (Test-QueryAuditing -Inventory ([pscustomobject]@{ RawFiles = @('la-query-logs.json'); LaQueryLogs = @() })).Evidence | Should -Match 'not enabled'
            (Test-QueryAuditing -Inventory ([pscustomobject]@{ RawFiles = @('la-query-logs.json'); LaQueryLogs = @([pscustomobject]@{ QueryCount = 0 }) })).Evidence | Should -Match 'not enabled'
            Test-QueryAuditing -Inventory ([pscustomobject]@{ RawFiles = @('la-query-logs.json'); LaQueryLogs = @([pscustomobject]@{ QueryCount = 12 }) }) | Should -BeNullOrEmpty
        }
    }

    Context 'Get-PropOrDefault' {
        It 'reads through an empty JSON object under strict mode' {
            Set-StrictMode -Version Latest
            $o = '{"EntityAnalytics": {"properties": {}}}' | ConvertFrom-Json
            Get-PropOrDefault $o 'EntityAnalytics.properties.entityProviders' 'none' | Should -Be 'none'
        }
    }
}

Describe 'Gap evidence lists every item' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        . (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1')
    }

    It 'never cuts a list short with a "+ N more" suffix on the sample fixture' {
        foreach ($f in $script:findings) { $f.Evidence | Should -Not -Match '\(\+ \d+ more\)' -Because $f.Id }
    }

    It 'names all nine unmapped rules, not the first five' {
        $rules = @(1..9 | ForEach-Object {
            [pscustomobject]@{ name = "r$_"; kind = 'Scheduled'; properties = [pscustomobject]@{ displayName = "Unmapped rule $_"; enabled = $true; entityMappings = @() } }
        })
        $evidence = (Test-RuleEntityMappingsPresent -Inventory ([pscustomobject]@{ AlertRules = $rules })).Evidence
        foreach ($n in 1..9) { $evidence | Should -Match "Unmapped rule $n\b" }
    }

    It 'suggests every undeployed template for an uncovered table, not the first three' {
        $templates = @(1..5 | ForEach-Object { [pscustomobject]@{ DisplayName = "Template $_"; Severity = 'Medium'; Tables = @('DeviceProcessEvents'); Deprecated = $false; AlreadyDeployed = $false } })
        $inv = [pscustomobject]@{ RawFiles = @('rule-table-references.json'); TablesWithData = @([pscustomobject]@{ DataType = 'DeviceProcessEvents'; BillableLast30d = 40 })
            RuleTableReferences = @(); TemplateTableReferences = $templates; CustomDetectionRefs = @() }
        $f = Test-HighVolumeTableWithoutDetection -Inventory $inv
        @($f.Detail.Tables[0].SuggestedTemplates).Count | Should -Be 5
        $f.Evidence | Should -Match 'Template 1, Template 2, Template 3, Template 4, Template 5'
    }
}

Describe 'SAC-PLT-10 connected connectors that deliver nothing' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        . (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1')
        $script:catalogue = Import-ConnectorCatalogue -Path (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/Resources/connector-catalogue.json')
        $script:inv = {
            param([object[]]$Connectors, [object[]]$Tables)
            [pscustomobject]@{ DataConnectors = $Connectors; TablesWithData = $Tables; ConnectorCatalogue = $script:catalogue }
        }
    }

    It 'does not flag a free table that received data (OfficeActivity bills nothing)' {
        $inv = & $script:inv @([pscustomobject]@{ kind = 'Office365'; properties = [pscustomobject]@{} }) @([pscustomobject]@{ DataType = 'OfficeActivity'; BillableLast24h = 0; BillableLast7d = 0; IngestedLast7d = 40 })
        Test-ConnectorTableMismatch -Inventory $inv | Should -BeNullOrEmpty
    }

    It 'flags a connected codeless connector none of whose catalogue tables received data' {
        $ado = [pscustomobject]@{ kind = 'RestApiPoller'; properties = [pscustomobject]@{ connectorDefinitionName = 'AzureDevOpsAuditLogs' } }
        $f = Test-ConnectorTableMismatch -Inventory (& $script:inv @($ado) @([pscustomobject]@{ DataType = 'Syslog'; IngestedLast7d = 5 }))
        $f.Evidence | Should -Match '1 connector with no data in any table it writes: Azure DevOps Audit Logs'
        $f.Detail.SilentConnectors[0].Id | Should -Be 'AzureDevOpsAuditLogs'
    }

    It 'treats data in any one of a connector''s catalogue tables as delivering' {
        $ado = [pscustomobject]@{ kind = 'RestApiPoller'; properties = [pscustomobject]@{ connectorDefinitionName = 'AzureDevOpsAuditLogs' } }
        Test-ConnectorTableMismatch -Inventory (& $script:inv @($ado) @([pscustomobject]@{ DataType = 'ADOAuditLogs_CL'; IngestedLast7d = 0.2 })) | Should -BeNullOrEmpty
    }

    It 'still checks the core tables of the named connectors one by one' {
        $aad = [pscustomobject]@{ kind = 'AzureActiveDirectory'; properties = [pscustomobject]@{} }
        $f = Test-ConnectorTableMismatch -Inventory (& $script:inv @($aad) @([pscustomobject]@{ DataType = 'SigninLogs'; IngestedLast7d = 3 }))
        $f.Evidence | Should -Match 'AzureActiveDirectory to AuditLogs'
        $f.Evidence | Should -Not -Match 'no data in any table'
    }
}

Describe 'Evidence never names something "?" or leaves a blank entry' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        . (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1')
    }

    It 'names a service principal Azure cannot resolve by its object id' {
        $inv = [pscustomobject]@{ RbacWorkspace = @(
                [pscustomobject]@{ DisplayName = 'ci-deployer-sp'; ObjectType = 'ServicePrincipal'; RoleDefinitionName = 'Contributor'; ObjectId = '11111111-1111-1111-1111-111111111111' }
                [pscustomobject]@{ DisplayName = ''; ObjectType = 'ServicePrincipal'; RoleDefinitionName = 'Owner'; ObjectId = '22222222-2222-2222-2222-222222222222' }
                [pscustomobject]@{ DisplayName = $null; ObjectType = 'ServicePrincipal'; RoleDefinitionName = 'Contributor' }
            ) }
        $f = Test-ServicePrincipalOverPrivileged -Inventory $inv
        $f.Evidence | Should -Match 'ci-deployer-sp; Unnamed service principal, object id 22222222-2222-2222-2222-222222222222 \(deleted or not readable\); Unnamed service principal\.'
        $f.Evidence | Should -Not -Match '\?'
    }

    It 'names a disabled rule with a blank display name by its rule id' {
        $inv = [pscustomobject]@{ AlertRules = @(
                [pscustomobject]@{ name = 'aaaa-1'; kind = 'Scheduled'; properties = [pscustomobject]@{ displayName = '  '; enabled = $false } }
                [pscustomobject]@{ name = 'bbbb-2'; kind = 'Scheduled'; properties = [pscustomobject]@{ displayName = 'Named rule'; enabled = $false } }
            ); RulesFired = @() }
        $f = Test-RulesDisabledOrFailing -Inventory $inv
        $f.Evidence | Should -Match 'aaaa-1; Named rule'
        $f.Evidence | Should -Not -Match ';\s*;'
    }

    It 'falls back for a missing or blank value and keeps a real one' {
        Get-EvidenceName ([pscustomobject]@{ a = ''; b = 'B' }) 'a', 'b' 'F' | Should -Be 'B'
        Get-EvidenceName ([pscustomobject]@{ a = ' ' }) 'a' 'F' | Should -Be 'F'
        Get-EvidenceName $null 'a' 'F' | Should -Be 'F'
    }
}

Describe 'SAC-DET-15 flags stale watchlists that enabled rules still read' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        . (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1')
        $now = (Get-Date).ToUniversalTime()
        $wl = { param($alias, $days, $source) [pscustomobject]@{ properties = [pscustomobject]@{ displayName = "WL $alias"; watchlistAlias = $alias; source = $source; updated = $now.AddDays(-$days).ToString('o') } } }
        $rule = { param($name, $enabled, $q) [pscustomobject]@{ name = $name; properties = [pscustomobject]@{ displayName = $name; enabled = $enabled; query = $q } } }
        $script:inv = [pscustomobject]@{
            Watchlists = @(
                (& $wl 'vips' 400 'vips.csv')
                (& $wl 'assets' 120 'Local file')
                (& $wl 'fresh' 10 'Manual')
                (& $wl 'sapsystems' 900 'ContentHub')
                (& $wl 'unused' 500 'Manual')
            )
            AlertRules = @(
                (& $rule 'VIP sign-in' $true '_GetWatchlist("vips") | join SigninLogs')
                (& $rule 'Asset alert' $true "_GetWatchlist('Assets') | join DeviceEvents")
                (& $rule 'Fresh use' $true "_GetWatchlist('fresh')")
                (& $rule 'SAP rule' $true "_GetWatchlist('sapsystems')")
                (& $rule 'Disabled user' $false "_GetWatchlist('unused')")
            )
        }
    }

    It 'names each stale watchlist an enabled rule reads, oldest first' {
        $f = Test-WatchlistsStale -Inventory $script:inv
        $f.Evidence | Should -Match '^2 watchlists read by enabled analytics rules have not been updated in 90 days or more: WL vips \(400 days, 1 rule\); WL assets \(120 days, 1 rule\)\.$'
    }

    It 'leaves out fresh, Content Hub and only-disabled-rule watchlists' {
        $rows = @(Get-WatchlistFreshness -Watchlists $script:inv.Watchlists -RuleUse (Get-WatchlistRuleUse -Rules $script:inv.AlertRules))
        ($rows | Where-Object Alias -EQ 'fresh').Status | Should -Be 'Current'
        ($rows | Where-Object Alias -EQ 'sapsystems').Status | Should -Be 'Content Hub'
        ($rows | Where-Object Alias -EQ 'unused').Status | Should -Be 'Stale'
        ($rows | Where-Object Alias -EQ 'vips').Status | Should -Be 'Stale, used by rules'
    }

    It 'stays quiet with no watchlist capture' {
        Test-WatchlistsStale -Inventory ([pscustomobject]@{ AlertRules = @() }) | Should -BeNullOrEmpty
    }
}

Describe 'SAC-MON-05 reconciles with the dashboard total for data no detection reads' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        . (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1')
        $script:monInv = {
            param([object[]]$Tables, [object[]]$Refs = @())
            [pscustomobject]@{ RawFiles = @('rule-table-references.json'); TablesWithData = $Tables; RuleTableReferences = $Refs; TemplateTableReferences = @(); CustomDetectionRefs = @() }
        }
        $script:monRow = { param($name, $gb) [pscustomobject]@{ DataType = $name; BillableLast30d = $gb } }
    }

    It 'sums the tables unrounded and rounds the total once' {
        $f = Test-HighVolumeTableWithoutDetection -Inventory (& $script:monInv @((& $script:monRow 'A' 7.004), (& $script:monRow 'B' 7.003)))
        $f.Detail.TotalGb30d | Should -Be 14.01
        $f.Evidence | Should -Match '^2 tables of 5 GB a month or more ingest 14\.01 GB in the last 30 days'
        $f.Evidence | Should -Match ': A 7\.00 GB; B 7\.00 GB\.$'
    }

    It 'says what it covers and gives the all-tables total the dashboard shows' {
        $read = [pscustomobject]@{ Enabled = $true; Tables = @('Read') }
        $f = Test-HighVolumeTableWithoutDetection -Inventory (& $script:monInv @(
                (& $script:monRow 'Big' 40), (& $script:monRow 'Small' 3), (& $script:monRow 'SecurityIncident' 2), (& $script:monRow 'Read' 100), (& $script:monRow 'Idle' 0)) @($read))
        $f.Detail.Count | Should -Be 1
        $f.Detail.TotalGb30d | Should -Be 40
        $f.Detail.AllTablesGb30d | Should -Be 45
        $f.Evidence | Should -Match '^1 table of 5 GB a month or more ingests 40\.00 GB in the last 30 days with no enabled Sentinel rule or Defender custom detection reading it, of 45\.00 GB in every table no detection reads \(the rest is in smaller tables or Sentinel''s own operational tables\): Big 40\.00 GB\.$'
    }

    It 'leaves the all-tables clause out when the two totals are equal' {
        $f = Test-HighVolumeTableWithoutDetection -Inventory (& $script:monInv @((& $script:monRow 'Big' 40)))
        $f.Detail.AllTablesGb30d | Should -Be 40
        $f.Evidence | Should -Not -Match 'in every table'
    }

    It 'matches the dashboard''s uncovered total on the sample fixture' {
        $raw = Join-Path $repoRoot 'Tests/iSOCBlueprint/Fixtures/sample/_raw'
        $read = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($file in 'rule-table-references.json', 'custom-detection-table-references.json') {
            foreach ($r in @(Get-Content (Join-Path $raw $file) -Raw | ConvertFrom-Json)) {
                if ($r.Enabled -eq $true) { foreach ($t in @($r.Tables)) { [void]$read.Add([string]$t) } }
            }
        }
        $all = 0.0; $covered = 0.0
        foreach ($t in @(Get-Content (Join-Path $raw 'tables-with-data.json') -Raw | ConvertFrom-Json)) {
            $gb = [double]$t.BillableLast30d
            if ($gb -le 0) { continue }
            $all += $gb
            if ($read.Contains([string]$t.DataType)) { $covered += $gb }
        }
        $f = $script:findings | Where-Object Id -eq 'SAC-MON-05'
        $f.Detail.AllTablesGb30d | Should -Be ([math]::Round($all - $covered, 2))
        $f.Detail.AllTablesGb30d | Should -BeGreaterThan $f.Detail.TotalGb30d
    }
}

Describe 'SAC-DET-12 counts the rules that fired as the dashboard does' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        . (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1')
        $newRule = { param($id, $title, $kind = 'Scheduled', $enabled = $true) [pscustomobject]@{ name = $id; kind = $kind; properties = [pscustomobject]@{ displayName = $title; enabled = $enabled } } }
        $script:rules = @(
            (& $newRule 'aaaaaaaa-0000-0000-0000-000000000001' 'Fired by id')
            (& $newRule 'aaaaaaaa-0000-0000-0000-000000000002' 'Fired by braced upper-case id')
            (& $newRule 'aaaaaaaa-0000-0000-0000-000000000003' 'Fired by resource path')
            (& $newRule 'aaaaaaaa-0000-0000-0000-000000000004' 'Fired by name only' 'NRT')
            (& $newRule 'aaaaaaaa-0000-0000-0000-000000000005' 'Dead rule')
            (& $newRule 'aaaaaaaa-0000-0000-0000-000000000006' 'Shares a name with a Defender alert')
            (& $newRule 'aaaaaaaa-0000-0000-0000-000000000007' 'Disabled rule' 'Scheduled' $false)
            (& $newRule 'aaaaaaaa-0000-0000-0000-000000000008' 'Fusion' 'Fusion')
        )
        $script:fired = @(
            [pscustomobject]@{ AlertRuleId = 'aaaaaaaa-0000-0000-0000-000000000001'; AlertName = 'Fired by id'; Alerts = 5 }
            [pscustomobject]@{ AlertRuleId = '{AAAAAAAA-0000-0000-0000-000000000002}'; AlertName = 'Renamed since'; Alerts = 2 }
            [pscustomobject]@{ AlertRuleId = '/subscriptions/s/providers/Microsoft.SecurityInsights/alertRules/aaaaaaaa-0000-0000-0000-000000000003'; AlertName = 'Renamed too'; Alerts = 1 }
            [pscustomobject]@{ AlertRuleId = ''; AlertName = 'Fired by name only'; Alerts = 3 }
        )
        $script:volumes = @(
            [pscustomobject]@{ AlertName = 'Fired by id'; ProductName = 'Azure Sentinel'; Alerts = 5 }
            [pscustomobject]@{ AlertName = 'Shares a name with a Defender alert'; ProductName = 'Microsoft Defender XDR'; Alerts = 9 }
        )
    }

    It 'lists the enabled Scheduled and NRT rules no fired row matches, by id or by name' {
        $inv = [pscustomobject]@{ RawFiles = @('rules-fired.json'); AlertRules = $script:rules; RulesFired = $script:fired; AnalyticsRuleVolumes = $script:volumes }
        $f = Test-DeadAnalyticsRule -Inventory $inv
        $f.Detail.Count | Should -Be 2
        $f.Detail.Enabled | Should -Be 6
        $f.Evidence | Should -Match '^2 of 6 enabled Scheduled/NRT rules produced zero alerts in the last 30 days: Dead rule; Shares a name with a Defender alert\.$'
    }

    It 'adds up with the rules that fired, the way the dashboard ring reads' {
        $inv = [pscustomobject]@{ RawFiles = @('rules-fired.json'); AlertRules = $script:rules; RulesFired = $script:fired; AnalyticsRuleVolumes = $script:volumes }
        $f = Test-DeadAnalyticsRule -Inventory $inv
        ($f.Detail.Enabled - $f.Detail.Count) | Should -Be 4
    }

    It 'falls back to the alert names in the volumes when rules-fired was not captured' {
        $inv = [pscustomobject]@{ RawFiles = @(); AlertRules = $script:rules; RulesFired = @(); AnalyticsRuleVolumes = $script:volumes }
        $f = Test-DeadAnalyticsRule -Inventory $inv
        $f.Detail.Count | Should -Be 4
        $f.Evidence | Should -Not -Match 'Fired by id;'
    }

    It 'reports every enabled rule when the capture is empty but other alerts exist' {
        $inv = [pscustomobject]@{ RawFiles = @('rules-fired.json'); AlertRules = $script:rules; RulesFired = @(); AnalyticsRuleVolumes = $script:volumes }
        (Test-DeadAnalyticsRule -Inventory $inv).Detail.Count | Should -Be 6
    }

    It 'stays quiet when there is no alert signal at all' {
        Test-DeadAnalyticsRule -Inventory ([pscustomobject]@{ RawFiles = @('rules-fired.json'); AlertRules = $script:rules; RulesFired = @(); AnalyticsRuleVolumes = @() }) | Should -BeNullOrEmpty
        Test-DeadAnalyticsRule -Inventory ([pscustomobject]@{ RawFiles = @(); AlertRules = $script:rules; RulesFired = @(); AnalyticsRuleVolumes = @() }) | Should -BeNullOrEmpty
    }

    It 'stays quiet when every enabled rule fired' {
        $only = @($script:rules[0])
        $inv = [pscustomobject]@{ RawFiles = @('rules-fired.json'); AlertRules = $only; RulesFired = $script:fired; AnalyticsRuleVolumes = $script:volumes }
        Test-DeadAnalyticsRule -Inventory $inv | Should -BeNullOrEmpty
    }
}

Describe 'Gap evidence writes counts, GB, dates and plurals as the dashboard does' {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:gapChecksPath = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1'
        . $script:gapChecksPath
        $customTable = { param($name) [pscustomobject]@{ name = $name; properties = [pscustomobject]@{ schema = [pscustomobject]@{ tableType = 'CustomLog' } } } }
        $script:orphanInv = { param([string[]]$Names) [pscustomobject]@{ WorkspaceTables = @($Names | ForEach-Object { & $customTable $_ }); TablesWithData = @([pscustomobject]@{ DataType = 'Other' }) } }
    }

    It 'never writes a plural as (s) in a finding on the sample fixture' {
        foreach ($f in $script:findings) { $f.Evidence | Should -Not -Match '\((s|es|ies)\)' -Because $f.Id }
    }

    It 'never writes a plural as (s) in the gap check source' {
        (Get-Content $script:gapChecksPath -Raw) | Should -Not -Match '[A-Za-z]\((s|es|ies)\)'
    }

    It 'separates thousands in the playbook counts and writes the last failure as a date and time' {
        $run = '{ "Playbook": "Notify", "Runs7d": 3343, "Failed7d": 167, "LastFailureUtc": "2026-10-14T23:16:38Z" }' | ConvertFrom-Json
        $f = Test-PlaybookRunFailures -Inventory ([pscustomobject]@{ PlaybookRuns = @($run) })
        $f.Evidence | Should -Match 'Notify \(167 of 3,343 runs failed, last 14 Oct 2026 23:16 UTC\)'
        $f.Detail.Playbooks[0].LastFailureUtc | Should -Be '2026-10-14T23:16:38Z'
    }

    It 'writes GB with two decimals and thousands separators' {
        $inv = [pscustomobject]@{ TablesWithData = @([pscustomobject]@{ DataType = 'CommonSecurityLog'; BillableLast30d = 56858.2 }) }
        $f = Test-CefSplitOpportunity -Inventory $inv
        $f.Evidence | Should -Match '^CommonSecurityLog ingested 56,858\.20 GB in the last 30 days'
        $f.Detail.Gb30d | Should -Be 56858.2
    }

    It 'chooses the singular or the plural by the count' {
        (Test-OrphanTables -Inventory (& $script:orphanInv @('One_CL'))).Evidence | Should -Match '^1 table has a schema but no data in the last 30 days\.$'
        (Test-OrphanTables -Inventory (& $script:orphanInv @('One_CL', 'Two_CL', 'Three_CL'))).Evidence | Should -Match '^3 tables have a schema but no data in the last 30 days\.$'
        $provider = { param($name) [pscustomobject]@{ ProviderNamespace = $name; RegistrationState = 'NotRegistered' } }
        (Test-ResourceProvidersRegistered -Inventory ([pscustomobject]@{ ResourceProviders = @(& $provider 'Microsoft.Insights') })).Evidence | Should -Be 'Resource provider not registered: Microsoft.Insights.'
        (Test-ResourceProvidersRegistered -Inventory ([pscustomobject]@{ ResourceProviders = @((& $provider 'Microsoft.Insights'), (& $provider 'Microsoft.SecurityInsights')) })).Evidence | Should -Be 'Resource providers not registered: Microsoft.Insights, Microsoft.SecurityInsights.'
    }
}
