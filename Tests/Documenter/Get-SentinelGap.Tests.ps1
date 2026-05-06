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

    Adding new rules requires extending the fixture and adding a row in the
    expected-IDs list.
#>

BeforeDiscovery {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:fixtureRaw   = Join-Path $script:repoRoot 'Tests/Documenter/Fixtures/sample/_raw'
    $script:resourcesDir = Join-Path $script:repoRoot 'Scripts/Documenter/Private/Resources'
    $script:rulesPath    = Join-Path $script:resourcesDir 'best-practices.json'
    $script:gapChecks    = Join-Path $script:repoRoot 'Scripts/Documenter/Private/GapChecks.ps1'
    $script:gapEngine    = Join-Path $script:repoRoot 'Scripts/Documenter/Private/Get-SentinelGap.ps1'
}

BeforeAll {
    $repoRoot     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $fixtureRaw   = Join-Path $repoRoot 'Tests/Documenter/Fixtures/sample/_raw'
    $resourcesDir = Join-Path $repoRoot 'Scripts/Documenter/Private/Resources'
    $rulesPath    = Join-Path $resourcesDir 'best-practices.json'
    $gapChecks    = Join-Path $repoRoot 'Scripts/Documenter/Private/GapChecks.ps1'
    $gapEngine    = Join-Path $repoRoot 'Scripts/Documenter/Private/Get-SentinelGap.ps1'

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
    }
}
