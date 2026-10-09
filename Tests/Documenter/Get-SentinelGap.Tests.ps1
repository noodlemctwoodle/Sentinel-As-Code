#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for the Sentinel Documenter gap-analysis engine.

.DESCRIPTION
    Drives Get-SentinelGap with the deliberately-broken fixture under
    Tests/Documenter/Fixtures/sample/_raw and asserts that each rule fires
    against the conditions encoded in the fixture.

    The fixture is constructed so several SENT-* rules fire by design:

      SENT-001  Daily cap unset                   (workspace.json: dailyQuotaGb = -1)
      SENT-002  Default retention < 90d           (workspace.json: retentionInDays = 30)
      SENT-007  Disabled rule                     (alert-rules.json: NRT rule disabled)
      SENT-009  Owner role at workspace scope     (rbac-workspace.json: legacy admin group)
      SENT-014  Defender migration banner         (always fires)
      SENT-016  > 50 GB Analytics-plan candidate  (FirewallLogs_CL: 2000 GB / 30d)
      SENT-017  > 90d retention on Analytics      (FirewallLogs_CL: 730d)
      SENT-019  Sentinel benefit not applied      (SecurityEvent: 500 GB billable)
      SENT-020  Replication disabled              (workspace.json)
      SENT-021  Public network access enabled     (workspace.json)
      SENT-022  Microsoft.Insights NotRegistered  (resource-providers.json)
      SENT-024  disableLocalAuth = false          (workspace.json)
      SENT-026  Silent table                      (AuditLogs: 90d data, no recent)
      SENT-027  Orphan table                      (OrphanTable_CL: schema, no data)

    The v2.2 rules (ported from the health-check script contributed to the
    project) fire on these conditions:

      SENT-036  Noisy rule                        (rule-effectiveness.json: aaaa closed 24, 19 FP)
      SENT-037  No entity mappings                (alert-rules.json: eeee enabled, entityMappings [])
      SENT-038  Alert-only rule                   (alert-rules.json: eeee createIncident false)
      SENT-041  Legacy incident-creation rule     (alert-rules.json: dddd MicrosoftSecurityIncidentCreation enabled)
      SENT-050  Rule on legacy TI table           (rule-table-references.json: eeee reads ThreatIntelligenceIndicator)
      SENT-051  High-volume table, no detection   (FirewallLogs_CL, SecurityEvent, OfficeActivity ... unreferenced)
      SENT-052  Silent table with dependent rule  (AuditLogs IngestedLast7d 0, read by aaaa)
      SENT-053  Playbook failures                 (playbook-runs.json: IncidentEnrich-IP Failed7d 5)
      SENT-054  Deprecated / missing solution     (office365 isDeprecated, legacy-feed not in catalogue)
      SENT-055  Single TI feed                    (data-connectors-classic.json: MicrosoftThreatIntelligence only)
      SENT-056  AzFW logged twice                 (AzureFirewall* categories + AZFWNetworkRule table)
      SENT-057  Closed unclassified               (incidents-summary.json: 20 of 32 closed Undetermined/Unclassified)
      SENT-058  No hunting activity               (hunts.json and bookmarks.json both [])

    Rules that read a capture file the collector only writes on success
    (051, 052, 058) stay quiet when the file is absent; the second Describe
    proves that with a trimmed copy of the fixture.

    Adding new rules requires extending the fixture and adding a row in the
    expected-IDs list.

.EXAMPLE
    Invoke-Pester -Path Tests/Documenter/Get-SentinelGap.Tests.ps1

    Runs the full gap-analysis suite against the deliberately-broken
    fixture.

.EXAMPLE
    Invoke-Pester -Path Tests/Documenter/Get-SentinelGap.Tests.ps1 -Output Detailed

    Runs with per-assertion output, for identifying which SENT-* rule
    stopped firing.

.NOTES
    File:         Tests/Documenter/Get-SentinelGap.Tests.ps1
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
    $script:fixtureRaw   = Join-Path $script:repoRoot 'Tests/Documenter/Fixtures/sample/_raw'
    $script:resourcesDir = Join-Path $script:repoRoot 'Tools/Documenter/Private/Resources'
    $script:rulesPath    = Join-Path $script:resourcesDir 'best-practices.json'
    $script:gapChecks    = Join-Path $script:repoRoot 'Tools/Documenter/Private/GapChecks.ps1'
    $script:gapEngine    = Join-Path $script:repoRoot 'Tools/Documenter/Private/Get-SentinelGap.ps1'
}

BeforeAll {
    $repoRoot     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $fixtureRaw   = Join-Path $repoRoot 'Tests/Documenter/Fixtures/sample/_raw'
    $resourcesDir = Join-Path $repoRoot 'Tools/Documenter/Private/Resources'
    $rulesPath    = Join-Path $resourcesDir 'best-practices.json'
    $gapChecks    = Join-Path $repoRoot 'Tools/Documenter/Private/GapChecks.ps1'
    $gapEngine    = Join-Path $repoRoot 'Tools/Documenter/Private/Get-SentinelGap.ps1'

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

        It 'fires SENT-001 because daily cap is unset' {
            ($findings | Where-Object Id -eq 'SENT-001').Count | Should -Be 1
        }

        It 'fires SENT-002 because retention is 30d < 90d' {
            $f = $findings | Where-Object Id -eq 'SENT-002'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match '30 days'
        }

        It 'fires SENT-007 because an NRT rule is disabled' {
            ($findings | Where-Object Id -eq 'SENT-007').Count | Should -Be 1
        }

        It 'fires SENT-009 because Owner exists at workspace scope' {
            ($findings | Where-Object Id -eq 'SENT-009').Count | Should -Be 1
        }

        It 'fires SENT-014 (Defender migration banner is always emitted)' {
            ($findings | Where-Object Id -eq 'SENT-014').Count | Should -Be 1
        }

        It 'fires SENT-016 because FirewallLogs_CL is > 50 GB on Analytics' {
            $f = $findings | Where-Object Id -eq 'SENT-016'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'FirewallLogs_CL'
        }

        It 'fires SENT-017 because at least one table has retention > 90d' {
            ($findings | Where-Object Id -eq 'SENT-017').Count | Should -Be 1
        }

        It 'fires SENT-020 because replication is disabled' {
            ($findings | Where-Object Id -eq 'SENT-020').Count | Should -Be 1
        }

        It 'fires SENT-021 because public network access is Enabled' {
            $f = $findings | Where-Object Id -eq 'SENT-021'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'Enabled'
        }

        It 'fires SENT-022 because Microsoft.Insights is NotRegistered' {
            ($findings | Where-Object Id -eq 'SENT-022').Count | Should -Be 1
        }

        It 'fires SENT-024 because disableLocalAuth is false' {
            ($findings | Where-Object Id -eq 'SENT-024').Count | Should -Be 1
        }

        It 'fires SENT-026 because AuditLogs has 90d data but none last 7d' {
            ($findings | Where-Object Id -eq 'SENT-026').Count | Should -Be 1
        }

        It 'fires SENT-027 because OrphanTable_CL has schema and no data' {
            $f = $findings | Where-Object Id -eq 'SENT-027'
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

        It 'fires SENT-029 because MTTR is 1620 min (27h) > 24h threshold' {
            $f = $findings | Where-Object Id -eq 'SENT-029'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match '27 hours'
        }

        It 'fires SENT-030 because 20 of 32 closed incidents were never acknowledged (62%)' {
            $f = $findings | Where-Object Id -eq 'SENT-030'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match '20 of 32 closed incidents'
        }

        It 'fires SENT-031 because the Scheduled rule was last modified in 2024 (>1y ago)' {
            $f = $findings | Where-Object Id -eq 'SENT-031'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'Suspicious sign-in from rare country'
        }

        It 'fires SENT-032 because the deployed rule is at v1.0.0 vs template v1.2.0' {
            $f = $findings | Where-Object Id -eq 'SENT-032'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match '1\.0\.0.*1\.2\.0'
        }

        It 'fires SENT-033 because one rule produces 412 of 525 alerts (78%)' {
            $f = $findings | Where-Object Id -eq 'SENT-033'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'Suspicious sign-in from rare country'
        }

        It 'fires SENT-034 because automation-rules.json is empty' {
            ($findings | Where-Object Id -eq 'SENT-034').Count | Should -Be 1
        }

        It 'does NOT fire SENT-035 because the only enabled Scheduled/NRT rule is in the noisy set' {
            # The fixture has volumes for "Suspicious sign-in" / "Failed logons" / "Privileged group" only.
            # SENT-035 should NOT flag the disabled rule (filtered out by enabled=false), so it only fires when
            # there exist enabled Scheduled/NRT rules outside the noisy set. The fixture's lone enabled Scheduled
            # rule IS in the noisy set, so we expect zero findings here — confirming the negative path.
            ($findings | Where-Object Id -eq 'SENT-035').Count | Should -Be 0
        }

        It 'fires SENT-039 because a service principal holds Contributor at workspace scope' {
            $f = $findings | Where-Object Id -eq 'SENT-039'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'ci-deployer-sp'
        }

        It 'fires SENT-040 because no identity holds Microsoft Sentinel Responder' {
            ($findings | Where-Object Id -eq 'SENT-040').Count | Should -Be 1
        }

        It 'does NOT fire SENT-042 because the fixture has a CanNotDelete lock present' {
            ($findings | Where-Object Id -eq 'SENT-042').Count | Should -Be 0
        }

        It 'fires SENT-043 because CommonSecurityLog is 300 GB / 30d (above the 150 GB threshold)' {
            $f = $findings | Where-Object Id -eq 'SENT-043'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'CommonSecurityLog'
        }

        It 'fires SENT-044 because Syslog is 280 GB / 30d' {
            $f = $findings | Where-Object Id -eq 'SENT-044'
            $f.Count | Should -Be 1
        }

        It 'fires SENT-045 because SecurityEvent is 500 GB / 30d' {
            $f = $findings | Where-Object Id -eq 'SENT-045'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'SecurityEvent'
        }

        It 'fires SENT-046 because AzureDiagnostics is 50 GB / 30d (above the 10 GB AzureDiagnostics threshold)' {
            $f = $findings | Where-Object Id -eq 'SENT-046'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'AzureDiagnostics'
        }

        # ----- v2.1 deprecation-deadline rules ---------------------------

        It 'fires SENT-047 because LegacyCLv1_CL has data but no DCR points to it' {
            $f = $findings | Where-Object Id -eq 'SENT-047'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'LegacyCLv1_CL'
            $f.Severity | Should -Be 'Critical'
        }

        It 'does NOT flag FirewallLogs_CL under SENT-047 (CLv2 — has a DCR)' {
            $f = $findings | Where-Object Id -eq 'SENT-047'
            $f.Evidence | Should -Not -Match 'FirewallLogs_CL'
        }

        It 'fires SENT-048 because the fixture shows 8 machines still on MMA' {
            $f = $findings | Where-Object Id -eq 'SENT-048'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match '8 machine'
            $f.Severity | Should -Be 'Critical'
        }

        It 'fires SENT-049 because ThreatIntelligenceIndicator carries billable data' {
            $f = $findings | Where-Object Id -eq 'SENT-049'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'ThreatIntelligenceIndicator'
            $f.Severity | Should -Be 'Critical'
        }

        It 'notes the new ThreatIntelIndicators table is absent when SENT-049 fires' {
            $f = $findings | Where-Object Id -eq 'SENT-049'
            $f.Evidence | Should -Match 'No data observed in the new'
        }

        # ----- v2.2 health-check rules -----------------------------------

        It 'fires SENT-036 because "Suspicious sign-in" closed 19 of 24 incidents as false positive' {
            $f = $findings | Where-Object Id -eq 'SENT-036'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'Suspicious sign-in from rare country'
            $f.Evidence | Should -Match '19 of 24'
            $f.Detail.Rules[0].FPRate | Should -Be 79.2
        }

        It 'does NOT flag "Failed logons" under SENT-036 (only 8 closed, under the floor of 20)' {
            ($findings | Where-Object Id -eq 'SENT-036').Evidence | Should -Not -Match 'Failed logons'
        }

        It 'fires SENT-037 because the enabled rule "Failed logons" has no entity mappings' {
            $f = $findings | Where-Object Id -eq 'SENT-037'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'Failed logons across multiple accounts'
            $f.Evidence | Should -Match '1 of 2 enabled'
        }

        It 'does NOT name the mapped rule or the disabled rule under SENT-037' {
            $f = $findings | Where-Object Id -eq 'SENT-037'
            $f.Evidence | Should -Not -Match 'Suspicious sign-in'
            $f.Evidence | Should -Not -Match 'Lateral movement'
        }

        It 'fires SENT-038 because "Failed logons" has createIncident false' {
            $f = $findings | Where-Object Id -eq 'SENT-038'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'Failed logons across multiple accounts'
            $f.Evidence | Should -Not -Match 'Suspicious sign-in'
        }

        It 'fires SENT-041 because a MicrosoftSecurityIncidentCreation rule is enabled while XDR syncs incidents' {
            $f = $findings | Where-Object Id -eq 'SENT-041'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'Create incidents from MDE alerts'
            $f.Evidence | Should -Match 'duplicate incidents'
            $f.Detail.XdrIncidentsConnected | Should -BeTrue
        }

        It 'fires SENT-050 because the enabled rule "Failed logons" reads ThreatIntelligenceIndicator' {
            $f = $findings | Where-Object Id -eq 'SENT-050'
            $f.Count | Should -Be 1
            $f.Severity | Should -Be 'Critical'
            $f.Evidence | Should -Match 'Failed logons across multiple accounts'
            $f.Evidence | Should -Not -Match 'Lateral movement'
        }

        It 'fires SENT-051 for the high-volume tables no enabled rule reads' {
            $f = $findings | Where-Object Id -eq 'SENT-051'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'FirewallLogs_CL 2000 GB'
            $f.Detail.Count | Should -Be 8
            @($f.Detail.Tables | ForEach-Object Table) | Should -Not -Contain 'SigninLogs'
            @($f.Detail.Tables | ForEach-Object Table) | Should -Not -Contain 'SecurityIncident'
        }

        It 'suggests an undeployed template under SENT-051 but never a deprecated or deployed one' {
            $f = $findings | Where-Object Id -eq 'SENT-051'
            $office = $f.Detail.Tables | Where-Object Table -eq 'OfficeActivity'
            $office.SuggestedTemplates | Should -Contain 'Data exfiltration'
            $firewall = $f.Detail.Tables | Where-Object Table -eq 'FirewallLogs_CL'
            @($firewall.SuggestedTemplates).Count | Should -Be 0
            $f.Evidence | Should -Not -Match 'Deprecated'
            $f.Evidence | Should -Not -Match 'Suspicious sign-in'
        }

        It 'fires SENT-052 because AuditLogs is read by an enabled rule and ingested nothing in 7 days' {
            $f = $findings | Where-Object Id -eq 'SENT-052'
            $f.Count | Should -Be 1
            $f.Severity | Should -Be 'Critical'
            $f.Evidence | Should -Match 'AuditLogs'
            $f.Evidence | Should -Match 'Suspicious sign-in from rare country'
            $f.Evidence | Should -Not -Match 'SigninLogs'
        }

        It 'fires SENT-053 because IncidentEnrich-IP failed 5 of 42 runs' {
            $f = $findings | Where-Object Id -eq 'SENT-053'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'IncidentEnrich-IP \(5 of 42 runs failed, last 2026-05-05T22:15:00Z\)'
            $f.Evidence | Should -Not -Match 'NotifyOnHighSev'
        }

        It 'fires SENT-054 for the deprecated solution and the one missing from the catalogue' {
            $f = $findings | Where-Object Id -eq 'SENT-054'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'Microsoft 365 \(deprecated\)'
            $f.Evidence | Should -Match 'Legacy Threat Feed \(not in catalogue\)'
            $f.Evidence | Should -Not -Match 'Azure Active Directory'
        }

        It 'fires SENT-055 because the only TI feed is MicrosoftThreatIntelligence' {
            $f = $findings | Where-Object Id -eq 'SENT-055'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'single feed \(MicrosoftThreatIntelligence\)'
        }

        It 'fires SENT-056 because AzureFirewall* categories and the AZFWNetworkRule table both carry data' {
            $f = $findings | Where-Object Id -eq 'SENT-056'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match 'AzureFirewallNetworkRule'
            $f.Evidence | Should -Match 'AZFWNetworkRule'
            $f.Detail.LegacyRows7d | Should -Be 12099
        }

        It 'fires SENT-057 because 20 of 32 closed incidents have no classification (62%)' {
            $f = $findings | Where-Object Id -eq 'SENT-057'
            $f.Count | Should -Be 1
            $f.Evidence | Should -Match '20 of 32 closed incidents \(62%\)'
        }

        It 'fires SENT-058 because hunts.json and bookmarks.json are both empty' {
            ($findings | Where-Object Id -eq 'SENT-058').Count | Should -Be 1
        }

        It 'carries no em-dash in any v2.2 rule text' {
            $rules = (Get-Content $rulesPath -Raw | ConvertFrom-Json).rules | Where-Object {
                $_.id -in @('SENT-036','SENT-037','SENT-038','SENT-041') -or $_.id -ge 'SENT-050'
            }
            foreach ($r in $rules) {
                ($r.title + $r.remediation) | Should -Not -Match ([char]0x2014)
            }
        }
    }
}

Describe 'Sentinel gap-analysis engine: absent captures stay quiet' {

    BeforeAll {
        $repoRoot     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $fixtureRaw   = Join-Path $repoRoot 'Tests/Documenter/Fixtures/sample/_raw'
        $resourcesDir = Join-Path $repoRoot 'Tools/Documenter/Private/Resources'
        $rulesPath    = Join-Path $resourcesDir 'best-practices.json'
        $gapChecks    = Join-Path $repoRoot 'Tools/Documenter/Private/GapChecks.ps1'
        . (Join-Path $repoRoot 'Tools/Documenter/Private/Get-SentinelGap.ps1')

        # A copy of the fixture without the files the collector only writes
        # when its capture succeeds. "Not captured" must not read as "none".
        $script:trimmed = Join-Path ([System.IO.Path]::GetTempPath()) "gap-absent-$(New-Guid)"
        New-Item -ItemType Directory -Path $script:trimmed -Force | Out-Null
        Get-ChildItem $fixtureRaw -File | Copy-Item -Destination $script:trimmed
        foreach ($name in 'rule-table-references.json', 'template-table-references.json', 'hunts.json', 'playbook-runs.json', 'rule-effectiveness.json', 'azure-diagnostics-categories.json') {
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
        foreach ($id in 'SENT-036', 'SENT-050', 'SENT-051', 'SENT-052', 'SENT-053', 'SENT-056', 'SENT-058') {
            ($absentOutcomes | Where-Object Id -eq $id).Outcome | Should -Be 'Passed' -Because "$id has no input to judge"
        }
    }

    It 'still fires the rules whose inputs are present' {
        foreach ($id in 'SENT-037', 'SENT-038', 'SENT-041', 'SENT-054', 'SENT-055', 'SENT-057') {
            ($absentFindings | Where-Object Id -eq $id).Count | Should -Be 1 -Because "$id reads files that are still there"
        }
    }

    It 'takes the service-reported bookmark count when the list was too large to fetch' {
        # bookmarks.json absent, bookmarks-count.json present with a count: hunting activity exists, SENT-058 stays quiet.
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) "gap-bmcount-$(New-Guid)"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            Get-ChildItem $fixtureRaw -File | Copy-Item -Destination $dir
            Remove-Item (Join-Path $dir 'bookmarks.json') -Force
            '{ "Count": 350, "Source": "too large" }' | Set-Content (Join-Path $dir 'bookmarks-count.json')
            $out = [System.Collections.Generic.List[object]]::new()
            $null = Get-SentinelGap -InputRoot $dir -ResourcesRoot $resourcesDir -RulesPath $rulesPath -GapChecksPath $gapChecks -OutcomeCollector $out
            ($out | Where-Object Id -eq 'SENT-058').Outcome | Should -Be 'Passed'
        } finally { Remove-Item $dir -Recurse -Force }
    }
}

Describe 'Sentinel gap-analysis engine: per-check outcomes' {

    BeforeAll {
        $repoRoot     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $fixtureRaw   = Join-Path $repoRoot 'Tests/Documenter/Fixtures/sample/_raw'
        $resourcesDir = Join-Path $repoRoot 'Tools/Documenter/Private/Resources'
        $rulesPath    = Join-Path $resourcesDir 'best-practices.json'
        $gapChecks    = Join-Path $repoRoot 'Tools/Documenter/Private/GapChecks.ps1'
        . (Join-Path $repoRoot 'Tools/Documenter/Private/Get-SentinelGap.ps1')

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
                @{ id = 'SENT-901'; title = 't'; category = 'c'; severity = 'Info'; check = 'Test-Throws'; remediation = ''; learn = '' }
                @{ id = 'SENT-902'; title = 't'; category = 'c'; severity = 'Info'; check = 'Test-Missing'; remediation = ''; learn = '' }
                @{ id = 'SENT-903'; title = 't'; category = 'c'; severity = 'Info'; check = 'Test-Quiet'; remediation = ''; learn = '' }
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
        $o = $badOutcomes | Where-Object Id -eq 'SENT-901'
        $o.Outcome | Should -Be 'Errored'
        $o.Message | Should -Match 'boom'
    }

    It 'records a check that is not defined as Undefined' {
        ($badOutcomes | Where-Object Id -eq 'SENT-902').Outcome | Should -Be 'Undefined'
    }

    It 'records a check that returns nothing as Passed' {
        ($badOutcomes | Where-Object Id -eq 'SENT-903').Outcome | Should -Be 'Passed'
    }

    It 'returns the same findings with or without a collector' {
        $plain = Get-SentinelGap -InputRoot (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Tests/Documenter/Fixtures/sample/_raw') `
            -ResourcesRoot (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Tools/Documenter/Private/Resources') `
            -RulesPath (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Tools/Documenter/Private/Resources/best-practices.json') `
            -GapChecksPath (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Tools/Documenter/Private/GapChecks.ps1')
        @($plain | ForEach-Object Id) | Should -Be @($withCollector | ForEach-Object Id)
    }
}
