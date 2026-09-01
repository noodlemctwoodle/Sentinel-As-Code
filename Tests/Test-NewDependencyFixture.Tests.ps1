#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for the pure helpers in Tools/ClassicToDcr/Rehearsal/New-DependencyFixture.ps1.

.DESCRIPTION
    The fixture manufactures dependency chains in a live Log Analytics
    workspace, so the parts worth testing hardest are the ones that decide
    what gets written and what gets deleted:

      Get-FixtureNamingPlan      The whole object graph, including the rule
                                 that must NOT name its table (the indirect
                                 case) and the orphan table that must not be
                                 referenced by anything.
      Test-ReservedTableName     The guard that stops a function alias
                                 shadowing a real table for every query in
                                 the workspace.
      Get-AliasCollisionReason   The three collision checks and their order.
      Test-FixtureOwned*         The ownership gates that authorise a delete.
      New-AlertRuleBody          Disabled by default, with the two required
                                 suppression properties that are easy to miss
                                 and ISO 8601 durations rather than KQL
                                 timespans.

    Deliberately not covered: the live POST, the shared-key fetch, the ARM
    writes and the table polls. Those need a real workspace and the retiring
    Data Collector API, so they cannot be unit tested.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-NewDependencyFixture.Tests.ps1

    Runs the naming-plan and ownership-gate tests. Needs no workspace.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-NewDependencyFixture.Tests.ps1 -FullName '*Test-FixtureOwned*'

    Runs only the ownership gates that authorise a delete, the assertions
    protecting real workspace content from the teardown path.

.NOTES
    File:         Tests/Test-NewDependencyFixture.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-07-28
    Version:      0.1.0
    Last Updated: 2026-09-01
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Tools/ClassicToDcr/Rehearsal/New-DependencyFixture.ps1'

    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop

    # Script-scoped constants the extracted functions close over. Import-ScriptFunctions
    # deliberately does not run the source script's top-level statements, so the
    # caller has to supply these.
    $script:TablesApiVersion        = '2023-09-01'
    $script:SentinelApiVersion      = '2024-03-01'
    $script:SavedSearchApiVersion   = '2020-08-01'
    $script:DataCollectorApiVersion = '2016-04-01'

    $script:FixtureMarker    = 'ClassicToDcr-DependencyFixture'
    $script:FixtureTagName   = 'SacFixture'
    $script:FixtureRunTag    = 'SacFixtureRun'
    $script:FixtureScenTag   = 'SacFixtureScenario'
    $script:MarkerFieldName  = 'SacFixtureMarker'
    $script:MarkerColumnName = 'SacFixtureMarker_s'
    $script:RuleIdNamespace  = 'Sentinel-As-Code/ClassicToDcr/DependencyFixture'
    $script:QueryClamp       = '| where 1 == 0'
    $script:ScenarioOrder    = @('Direct', 'OneHop', 'TwoHop', 'Cycle', 'Orphan', 'Hunt')
    $script:MappingPath      = Join-Path $repoRoot 'Tools/ClassicToDcr/data/solution-mapping.json'

    $script:ReservedTableFloor = @(
        'Alert', 'AzureActivity', 'AzureDiagnostics', 'CommonSecurityLog', 'Event',
        'Heartbeat', 'Perf', 'SecurityEvent', 'SigninLogs', 'Syslog', 'Update', 'Usage'
    )

    Import-ScriptFunctions -Path $scriptPath
}

Describe 'New-DependencyFixture: script-level contract' {
    BeforeAll {
        $script:sourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools/ClassicToDcr/Rehearsal/New-DependencyFixture.ps1'
        $script:sourceText = Get-Content -Path $script:sourcePath -Raw
    }

    It 'parses cleanly' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $script:sourcePath, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'has the correct repo-relative header path' {
        $script:sourceText | Should -Match 'File:\s+Tools/ClassicToDcr/Rehearsal/New-DependencyFixture\.ps1'
        $script:sourceText | Should -Match 'Repository:\s+Sentinel-As-Code'
    }

    It 'is standalone: does not import the Sentinel.Common module' {
        $script:sourceText | Should -Not -Match 'Import-Module[^\r\n]*Sentinel\.Common'
        $script:sourceText | Should -Not -Match 'Sentinel\.Common\.psd1'
        $script:sourceText | Should -Match 'function Write-PipelineMessage'
    }

    It 'uses no em-dashes in prose' {
        $script:sourceText | Should -Not -Match ([char]0x2014)
    }

    It 'uses no section signs in prose' {
        $script:sourceText | Should -Not -Match ([char]0x00A7)
    }

    It 'declares SupportsShouldProcess with a High confirm impact' {
        $script:sourceText | Should -Match 'SupportsShouldProcess'
        $script:sourceText | Should -Match "ConfirmImpact\s*=\s*'High'"
    }

    It 'gates the ingestion post behind ShouldProcess' {
        # The call wraps across two lines, so match non-greedily across them.
        $script:sourceText |
            Should -Match "(?s)\`$PSCmdlet\.ShouldProcess\(.{0,120}?Post \`$RecordCount fixture records via Data Collector API"
    }

    It 'gates every ARM write behind ShouldProcess' {
        $script:sourceText | Should -Match "ShouldProcess\([^)]*'Create fixture hunting query'\)"
        $script:sourceText | Should -Match "'Update fixture parser to close the reference cycle'"
        $script:sourceText | Should -Match "'Create DISABLED fixture analytics rule'"
        $script:sourceText | Should -Match "'Create ENABLED fixture analytics rule'"
    }

    It 'gates every delete behind ShouldProcess' {
        $script:sourceText | Should -Match "ShouldProcess\([^)]*'Delete fixture analytics rule'\)"
        $script:sourceText | Should -Match "ShouldProcess\([^)]*'Delete fixture saved search'\)"
        $script:sourceText | Should -Match "ShouldProcess\([^)]*'Delete fixture table'\)"
    }

    It 'uses the sibling fixture wording verbatim for the classic-table teardown' {
        # Test-NewClassicTableFixture.Tests.ps1 asserts these same two strings.
        # Keeping them identical means an operator sees the same prompt for the
        # same irreversible action in both rehearsal scripts.
        $script:sourceText | Should -Match "ShouldProcess\([^)]*'Migrate \(irreversible\) then delete'\)"
        $script:sourceText | Should -Match "ShouldProcess\([^)]*'Delete fixture table'\)"
    }

    It 'refuses to delete a still-Classic table without -MigrateBeforeRemove' {
        $script:sourceText | Should -Match "is still a Classic table, which the Tables API cannot delete"
        $script:sourceText | Should -Match 'Re-run with -MigrateBeforeRemove'
    }

    It 'never writes the shared key to output' {
        $script:sourceText | Should -Not -Match 'Write-.*\$sharedKey'
        $script:sourceText | Should -Not -Match 'Write-.*SharedKey'
        $script:sourceText | Should -Not -Match 'Write-.*PrimarySharedKey'
    }

    It 'fetches the shared key only after the ShouldProcess gate, so -WhatIf makes no privileged call' {
        $gateIndex = $script:sourceText.IndexOf('Post $RecordCount fixture records via Data Collector API')
        $keyIndex  = $script:sourceText.IndexOf('Get-AzOperationalInsightsWorkspaceSharedKey')

        $gateIndex | Should -BeGreaterThan 0
        $keyIndex  | Should -BeGreaterThan 0
        $keyIndex  | Should -BeGreaterThan $gateIndex
    }

    It 'requires two separate switches before a rule can run a live query' {
        $script:sourceText | Should -Match '\$EnableRulesWithLiveQuery -and -not \$EnableRules'
        $script:sourceText | Should -Match '\[switch\] \$EnableRules'
        $script:sourceText | Should -Match '\[switch\] \$EnableRulesWithLiveQuery'
    }

    It 'derives rule enablement from the opt-in switch alone' {
        # Nothing else may reach the enabled flag: no config file, no YAML, no
        # parameter that could be set by accident.
        $script:sourceText | Should -Match '\$ruleEnabled = \[bool\]\$EnableRules'
    }

    It 'constrains -NamePrefix so it cannot be blanked into a prefix that matches everything' {
        $script:sourceText | Should -Match "ValidatePattern\('\^\[A-Za-z\]\[A-Za-z0-9\]\{2,15\}\$'\)"
    }

    It 'keeps the fixture data volume small by default' {
        $script:sourceText | Should -Match '\[int\] \$RecordCount = 5'
        $script:sourceText | Should -Match 'ValidateRange\(1, 100\)'
    }

    It 'contains no references to AI or LLM tooling' {
        $script:sourceText | Should -Not -Match '(?i)\b(copilot|chatgpt|anthropic|claude|openai)\b'
    }
}

Describe 'Resolve-FixtureScenario' {
    It 'returns every scenario when none is requested' {
        Resolve-FixtureScenario -Scenario @() | Should -Be @('Direct', 'OneHop', 'TwoHop', 'Cycle', 'Orphan', 'Hunt')
    }

    It 'returns every scenario when the selection is null' {
        Resolve-FixtureScenario -Scenario $null | Should -Be @('Direct', 'OneHop', 'TwoHop', 'Cycle', 'Orphan', 'Hunt')
    }

    It 'keeps only the requested scenarios' {
        Resolve-FixtureScenario -Scenario @('Direct', 'Orphan') | Should -Be @('Direct', 'Orphan')
    }

    It 'returns the canonical create order regardless of the order requested' {
        Resolve-FixtureScenario -Scenario @('Orphan', 'Direct') | Should -Be @('Direct', 'Orphan')
    }

    It 'implies OneHop when Hunt is requested, because the hunting query reaches its table through that parser' {
        Resolve-FixtureScenario -Scenario @('Hunt') | Should -Be @('OneHop', 'Hunt')
    }

    It 'matches case-insensitively' {
        Resolve-FixtureScenario -Scenario @('direct') | Should -Be @('Direct')
    }

    It 'ignores blank entries' {
        Resolve-FixtureScenario -Scenario @('Direct', '  ') | Should -Be @('Direct')
    }
}

Describe 'New-FixtureRuleId' {
    It 'produces a valid GUID' {
        $id = New-FixtureRuleId -NamePrefix 'SacDep' -ScenarioName 'Direct'
        { [guid]::Parse($id) } | Should -Not -Throw
    }

    It 'is deterministic, so a re-run converges instead of duplicating rules' {
        $a = New-FixtureRuleId -NamePrefix 'SacDep' -ScenarioName 'Direct'
        $b = New-FixtureRuleId -NamePrefix 'SacDep' -ScenarioName 'Direct'
        $a | Should -Be $b
    }

    It 'differs per scenario' {
        $a = New-FixtureRuleId -NamePrefix 'SacDep' -ScenarioName 'Direct'
        $b = New-FixtureRuleId -NamePrefix 'SacDep' -ScenarioName 'OneHop'
        $a | Should -Not -Be $b
    }

    It 'differs per prefix, so two operators do not collide on the same workspace' {
        $a = New-FixtureRuleId -NamePrefix 'SacDep' -ScenarioName 'Direct'
        $b = New-FixtureRuleId -NamePrefix 'OtherDep' -ScenarioName 'Direct'
        $a | Should -Not -Be $b
    }
}

Describe 'Get-FixtureNamingPlan' {
    BeforeAll {
        $script:plan = Get-FixtureNamingPlan -NamePrefix 'SacDep'
    }

    It 'names five tables, all carrying the prefix and the _CL suffix' {
        $names = @($script:plan.Table | ForEach-Object { $_.TableName })
        $names.Count | Should -Be 5
        $names | Should -Contain 'SacDepDirect_CL'
        $names | Should -Contain 'SacDepOneHop_CL'
        $names | Should -Contain 'SacDepTwoHop_CL'
        $names | Should -Contain 'SacDepCycle_CL'
        $names | Should -Contain 'SacDepOrphan_CL'
    }

    It 'strips the _CL suffix from the Data Collector log type, because the API appends it' {
        foreach ($table in $script:plan.Table) {
            $table.LogType | Should -Not -Match '_CL$'
            "$($table.LogType)_CL" | Should -Be $table.TableName
        }
    }

    It 'uses a log type the Data Collector API accepts (letters, digits and underscore only)' {
        foreach ($table in $script:plan.Table) {
            $table.LogType | Should -Match '^[A-Za-z0-9_]+$'
        }
    }

    It 'names five distinct function aliases, all carrying the prefix' {
        $script:plan.Alias.Count | Should -Be 5
        foreach ($alias in $script:plan.Alias) {
            $alias | Should -Match '^SacDep'
            # A function alias may not contain a space or a special character,
            # and may not start with an underscore.
            $alias | Should -Match '^[A-Za-z][A-Za-z0-9]*$'
        }
    }

    It 'keeps the saved search id distinct from the function alias' {
        foreach ($parser in $script:plan.Parser) {
            $parser.SavedSearchId | Should -Not -Be $parser.Alias
            $parser.SavedSearchId | Should -Match '^[A-Za-z0-9][A-Za-z0-9._-]*$'
        }
    }

    It 'points the one-hop parser at the one-hop table' {
        $parser = $script:plan.Parser | Where-Object { $_.Alias -eq 'SacDepOneHopParser' }
        Test-KqlReferencesName -Query $parser.Query -Name 'SacDepOneHop_CL' | Should -BeTrue
    }

    It 'points the outer parser at the inner parser and at no table' {
        $outer = $script:plan.Parser | Where-Object { $_.Alias -eq 'SacDepOuterParser' }
        Test-KqlReferencesName -Query $outer.Query -Name 'SacDepInnerParser' | Should -BeTrue

        foreach ($table in $script:plan.Table) {
            Test-KqlReferencesName -Query $outer.Query -Name $table.TableName | Should -BeFalse
        }
    }

    It 'writes the cycle in three steps, because a cyclic pair cannot be created in two without one dangling' {
        $cycle = @($script:plan.Parser | Where-Object { $_.ScenarioName -eq 'Cycle' })
        $cycle.Count | Should -Be 3
        @($cycle | Where-Object { $_.IsCycleClosure }).Count | Should -Be 1

        # The closure must come last.
        ($cycle | Sort-Object Order | Select-Object -Last 1).IsCycleClosure | Should -BeTrue
    }

    It 'closes the cycle so A reads the table and B, and B reads A' {
        $closure = $script:plan.Parser | Where-Object { $_.IsCycleClosure }
        Test-KqlReferencesName -Query $closure.Query -Name 'SacDepCycle_CL' | Should -BeTrue
        Test-KqlReferencesName -Query $closure.Query -Name 'SacDepCycleB'   | Should -BeTrue

        $cycleB = $script:plan.Parser | Where-Object { $_.Alias -eq 'SacDepCycleB' }
        Test-KqlReferencesName -Query $cycleB.Query -Name 'SacDepCycleA' | Should -BeTrue
    }

    It 'emits parsers in dependency order, inner before outer' {
        $ordered = @($script:plan.Parser | Sort-Object Order | ForEach-Object { $_.Alias })
        [array]::IndexOf($ordered, 'SacDepInnerParser') |
            Should -BeLessThan ([array]::IndexOf($ordered, 'SacDepOuterParser'))
    }

    It 'creates exactly one hunting query, with no function alias, that reaches its table through a parser' {
        $script:plan.HuntingQuery.Count | Should -Be 1
        $hunt = $script:plan.HuntingQuery[0]

        Test-KqlReferencesName -Query $hunt.Query -Name 'SacDepOneHopParser' | Should -BeTrue
        foreach ($table in $script:plan.Table) {
            Test-KqlReferencesName -Query $hunt.Query -Name $table.TableName | Should -BeFalse
        }
    }

    It 'creates four analytics rules, one per non-orphan scenario' {
        $script:plan.Rule.Count | Should -Be 4
        @($script:plan.Rule | ForEach-Object { $_.ScenarioName }) |
            Should -Be @('Direct', 'OneHop', 'TwoHop', 'Cycle')
    }

    It 'names the table directly only in the direct rule' {
        $direct = $script:plan.Rule | Where-Object { $_.ScenarioName -eq 'Direct' }
        Test-KqlReferencesName -Query $direct.Query -Name 'SacDepDirect_CL' | Should -BeTrue
    }

    It 'never names a table in an indirect rule, not even in a comment' {
        # The review tool is a text matcher. A table name anywhere in the query
        # text, comments included, would make the indirect scenario silently
        # prove the direct one instead.
        foreach ($rule in ($script:plan.Rule | Where-Object { $_.IsIndirect })) {
            foreach ($table in $script:plan.Table) {
                Test-KqlReferencesName -Query $rule.Query -Name $table.TableName |
                    Should -BeFalse -Because "rule '$($rule.DisplayName)' must not name $($table.TableName)"
            }
        }
    }

    It 'points the cycle rule at the table, not at a cycle member' {
        # Sentinel validates rule KQL server side. A rule naming a member of an
        # unresolvable cyclic pair is rejected with HTTP 400, so the cycle rule
        # has to be a direct reference.
        $cycleRule = $script:plan.Rule | Where-Object { $_.ScenarioName -eq 'Cycle' }
        Test-KqlReferencesName -Query $cycleRule.Query -Name 'SacDepCycle_CL' | Should -BeTrue
        Test-KqlReferencesName -Query $cycleRule.Query -Name 'SacDepCycleA'   | Should -BeFalse
        Test-KqlReferencesName -Query $cycleRule.Query -Name 'SacDepCycleB'   | Should -BeFalse
    }

    It 'leaves the orphan table referenced by nothing at all' {
        $everyQuery = @($script:plan.Parser | ForEach-Object { $_.Query }) +
                      @($script:plan.HuntingQuery | ForEach-Object { $_.Query }) +
                      @($script:plan.Rule | ForEach-Object { $_.Query })

        foreach ($query in $everyQuery) {
            Test-KqlReferencesName -Query $query -Name 'SacDepOrphan_CL' | Should -BeFalse
        }
    }

    It 'clamps every rule query to zero rows by default' {
        foreach ($rule in $script:plan.Rule) {
            $rule.Query | Should -Match '\|\s*where 1 == 0'
        }
    }

    It 'drops the clamp only when an empty clamp is passed' {
        $live = Get-FixtureNamingPlan -NamePrefix 'SacDep' -QueryClamp ''
        foreach ($rule in $live.Rule) {
            $rule.Query | Should -Not -Match 'where 1 == 0'
        }
    }

    It 'honours a scenario selection' {
        $subset = Get-FixtureNamingPlan -NamePrefix 'SacDep' -ScenarioName @('Direct', 'Orphan')
        $subset.Table.Count  | Should -Be 2
        $subset.Parser.Count | Should -Be 0
        $subset.Rule.Count   | Should -Be 1
        $subset.HuntingQuery.Count | Should -Be 0
    }

    It 'carries a deterministic rule id on every rule' {
        foreach ($rule in $script:plan.Rule) {
            $rule.RuleId | Should -Be (New-FixtureRuleId -NamePrefix 'SacDep' -ScenarioName $rule.ScenarioName)
        }
    }

    It 'renames everything when the prefix changes' {
        $other = Get-FixtureNamingPlan -NamePrefix 'ZzTest'
        @($other.Table | ForEach-Object { $_.TableName }) | Should -Contain 'ZzTestDirect_CL'
        $other.Alias | Should -Contain 'ZzTestOneHopParser'
        foreach ($alias in $other.Alias) { $alias | Should -Match '^ZzTest' }
    }
}

Describe 'Test-KqlReferencesName' {
    It 'matches a bare table reference' {
        Test-KqlReferencesName -Query 'SacDepDirect_CL | take 1' -Name 'SacDepDirect_CL' | Should -BeTrue
    }

    It 'matches case-insensitively, because the KQL resolver does' {
        Test-KqlReferencesName -Query 'sacdepdirect_cl | take 1' -Name 'SacDepDirect_CL' | Should -BeTrue
    }

    It 'does not match a longer name that merely starts the same' {
        Test-KqlReferencesName -Query 'SacDepDirect_CL_v2 | take 1' -Name 'SacDepDirect_CL' | Should -BeFalse
    }

    It 'does not match a table name inside a parser alias' {
        Test-KqlReferencesName -Query 'SacDepOneHopParser | take 1' -Name 'SacDepOneHop_CL' | Should -BeFalse
    }

    It 'returns false for an empty or null query' {
        Test-KqlReferencesName -Query '' -Name 'SacDepDirect_CL'   | Should -BeFalse
        Test-KqlReferencesName -Query $null -Name 'SacDepDirect_CL' | Should -BeFalse
    }

    It 'still matches a name that only appears in a comment' {
        # This is why the fixture asserts the absence of the table name in
        # indirect queries: a comment counts.
        Test-KqlReferencesName -Query "// reads SacDepOneHop_CL`nSacDepOneHopParser" -Name 'SacDepOneHop_CL' |
            Should -BeTrue
    }
}

Describe 'Test-ReservedTableName' {
    It 'flags an exact match' {
        Test-ReservedTableName -Name 'Update' -ReservedName @('Update', 'Event') | Should -BeTrue
    }

    It 'flags a match that differs only by case' {
        Test-ReservedTableName -Name 'update' -ReservedName @('Update') | Should -BeTrue
        Test-ReservedTableName -Name 'UPDATE' -ReservedName @('Update') | Should -BeTrue
    }

    It 'does not flag a name that is merely similar' {
        Test-ReservedTableName -Name 'UpdateSummaryExtra' -ReservedName @('Update', 'UpdateSummary') | Should -BeFalse
    }

    It 'does not flag a fixture alias' {
        Test-ReservedTableName -Name 'SacDepOneHopParser' -ReservedName @('Update', 'Event', 'Heartbeat') |
            Should -BeFalse
    }

    It 'returns false when the reserved list is empty or null' {
        Test-ReservedTableName -Name 'Update' -ReservedName @()  | Should -BeFalse
        Test-ReservedTableName -Name 'Update' -ReservedName $null | Should -BeFalse
    }

    It 'ignores blank entries in the reserved list' {
        Test-ReservedTableName -Name 'Update' -ReservedName @('', '   ') | Should -BeFalse
    }
}

Describe 'Get-ReservedTableName' {
    It 'includes the static floor even without a mapping file' {
        $names = Get-ReservedTableName -MappingPath (Join-Path $TestDrive 'no-such-file.json') -WarningAction SilentlyContinue
        $names | Should -Contain 'Update'
        $names | Should -Contain 'SecurityEvent'
        $names | Should -Contain 'Heartbeat'
    }

    It 'falls back to the floor when the path is empty' {
        $names = Get-ReservedTableName -MappingPath '' -WarningAction SilentlyContinue
        $names | Should -Contain 'Event'
    }

    It 'widens the list from the bundled solution mapping' {
        $names = Get-ReservedTableName -MappingPath $script:MappingPath
        $names.Count | Should -BeGreaterThan 500
        $names | Should -Contain 'CommonSecurityLog'
        $names | Should -Contain 'Update'
    }

    It 'survives a mapping file with an empty-string key' {
        # The upstream solution mapping contains one, which plain
        # ConvertFrom-Json refuses to turn into a PSCustomObject.
        $path = Join-Path $TestDrive 'mapping-empty-key.json'
        '{ "tablesToSolutions": { "": ["x"], "WeirdTable_CL": ["y"] } }' | Set-Content -Path $path -Encoding utf8

        $names = Get-ReservedTableName -MappingPath $path
        $names | Should -Contain 'WeirdTable_CL'
        $names | Should -Not -Contain ''
    }

    It 'falls back to the floor when the mapping is not valid JSON' {
        $path = Join-Path $TestDrive 'mapping-broken.json'
        'not json at all' | Set-Content -Path $path -Encoding utf8

        $names = Get-ReservedTableName -MappingPath $path -WarningAction SilentlyContinue
        $names | Should -Contain 'Update'
    }

    It 'de-duplicates case-insensitively' {
        $path = Join-Path $TestDrive 'mapping-dupe.json'
        '{ "tablesToSolutions": { "update": ["x"], "UPDATE": ["y"] } }' | Set-Content -Path $path -Encoding utf8

        $names = Get-ReservedTableName -MappingPath $path
        @($names | Where-Object { $_ -ieq 'update' }).Count | Should -Be 1
    }
}

Describe 'Get-AliasCollisionReason' {
    It 'refuses an alias matching a table that exists in the workspace' {
        $reason = Get-AliasCollisionReason -Alias 'Update' -WorkspaceTableName @('Update', 'Heartbeat')
        $reason | Should -Match 'exists in this workspace'
        $reason | Should -Match 'shadows a table for every query'
    }

    It 'refuses an alias matching a known table that is not installed yet' {
        $reason = Get-AliasCollisionReason -Alias 'Syslog' -WorkspaceTableName @('Heartbeat') -ReservedName @('Syslog')
        $reason | Should -Match 'known Log Analytics or Content Hub table name'
    }

    It 'refuses an alias already used by somebody else''s parser' {
        $reason = Get-AliasCollisionReason -Alias 'CustomerParser' -ForeignAlias @('CustomerParser')
        $reason | Should -Match 'already used by a saved search that this fixture does not own'
    }

    It 'reports the workspace-table collision first, because it is the worst outcome' {
        $reason = Get-AliasCollisionReason -Alias 'Update' `
                                           -WorkspaceTableName @('Update') `
                                           -ReservedName @('Update') `
                                           -ForeignAlias @('Update')
        $reason | Should -Match 'exists in this workspace'
    }

    It 'returns nothing for a safe fixture alias' {
        $reason = Get-AliasCollisionReason -Alias 'SacDepOneHopParser' `
                                           -WorkspaceTableName @('Update', 'Heartbeat', 'SacDepOneHop_CL') `
                                           -ReservedName @('Syslog', 'SecurityEvent') `
                                           -ForeignAlias @('CustomerParser')
        $reason | Should -BeNullOrEmpty
    }

    It 'clears every shipped alias against the real bundled mapping' {
        $reserved = Get-ReservedTableName -MappingPath $script:MappingPath
        $plan     = Get-FixtureNamingPlan -NamePrefix 'SacDep'

        foreach ($alias in $plan.Alias) {
            Get-AliasCollisionReason -Alias $alias -ReservedName $reserved | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-FixtureObjectAction' {
    It 'plans a create for an object that does not exist' {
        Get-FixtureObjectAction -Existing $null -IsOwned $false | Should -Be 'CREATE'
    }

    It 'plans an update for an object that exists and is ours' {
        Get-FixtureObjectAction -Existing ([pscustomobject]@{ name = 'x' }) -IsOwned $true | Should -Be 'UPDATE'
    }

    It 'aborts on an object that exists and is not ours' {
        Get-FixtureObjectAction -Existing ([pscustomobject]@{ name = 'x' }) -IsOwned $false | Should -Be 'ABORT'
    }

    It 'reports absent on the removal path when the object is gone' {
        Get-FixtureObjectAction -Existing $null -IsOwned $false -ForRemoval | Should -Be 'ABSENT'
    }

    It 'plans a delete on the removal path only when the object is ours' {
        Get-FixtureObjectAction -Existing ([pscustomobject]@{ name = 'x' }) -IsOwned $true -ForRemoval |
            Should -Be 'DELETE'
    }

    It 'skips somebody else''s object on the removal path' {
        Get-FixtureObjectAction -Existing ([pscustomobject]@{ name = 'x' }) -IsOwned $false -ForRemoval |
            Should -Be 'SKIP'
    }
}

Describe 'Get-SavedSearchTagValue and Test-FixtureOwnedSavedSearch' {
    BeforeAll {
        # Round-trip through JSON so the objects have the shape ARM actually
        # returns, rather than the shape a hashtable happens to have.
        $script:ownedSaved = @'
{
  "id": "/subscriptions/s/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/ws/savedSearches/SacDep-OneHopParser",
  "name": "SacDep-OneHopParser",
  "etag": "W/\"datetime'2026-07-28T10:15:41Z'\"",
  "properties": {
    "category": "SacDep Fixture",
    "displayName": "SacDep fixture one-hop parser",
    "functionAlias": "SacDepOneHopParser",
    "query": "SacDepOneHop_CL",
    "version": 2,
    "tags": [
      { "name": "SacFixture", "value": "ClassicToDcr-DependencyFixture" },
      { "name": "SacFixtureRun", "value": "11111111-1111-1111-1111-111111111111" },
      { "name": "SacFixtureScenario", "value": "OneHop" }
    ]
  }
}
'@ | ConvertFrom-Json

        $script:foreignSaved = @'
{
  "name": "SacDepSomethingElse",
  "properties": {
    "category": "Customer Parsers",
    "displayName": "A real customer parser",
    "functionAlias": "SacDepSomethingElse",
    "query": "Heartbeat"
  }
}
'@ | ConvertFrom-Json

        # Server casing of the tag members is not guaranteed, so prove the
        # lookup does not depend on it.
        $script:pascalTagSaved = @'
{
  "name": "SacDep-Hunt",
  "properties": {
    "category": "Hunting Queries",
    "query": "SacDepOneHopParser",
    "tags": [ { "Name": "SacFixture", "Value": "ClassicToDcr-DependencyFixture" } ]
  }
}
'@ | ConvertFrom-Json
    }

    It 'reads a tag value' {
        Get-SavedSearchTagValue -SavedSearch $script:ownedSaved -TagName 'SacFixtureScenario' | Should -Be 'OneHop'
    }

    It 'returns nothing for a tag that is not present' {
        Get-SavedSearchTagValue -SavedSearch $script:ownedSaved -TagName 'NotATag' | Should -BeNullOrEmpty
    }

    It 'returns nothing when the object has no tags at all' {
        Get-SavedSearchTagValue -SavedSearch $script:foreignSaved -TagName 'SacFixture' | Should -BeNullOrEmpty
    }

    It 'returns nothing for a null saved search' {
        Get-SavedSearchTagValue -SavedSearch $null -TagName 'SacFixture' | Should -BeNullOrEmpty
    }

    It 'recognises a fixture saved search by its tag' {
        Test-FixtureOwnedSavedSearch -SavedSearch $script:ownedSaved -FixtureMarker $script:FixtureMarker |
            Should -BeTrue
    }

    It 'recognises the tag whatever casing the server returns it in' {
        Test-FixtureOwnedSavedSearch -SavedSearch $script:pascalTagSaved -FixtureMarker $script:FixtureMarker |
            Should -BeTrue
    }

    It 'does not claim a customer parser that merely shares the prefix' {
        Test-FixtureOwnedSavedSearch -SavedSearch $script:foreignSaved -FixtureMarker $script:FixtureMarker |
            Should -BeFalse
    }

    It 'does not claim an object tagged with a different marker' {
        Test-FixtureOwnedSavedSearch -SavedSearch $script:ownedSaved -FixtureMarker 'SomeOtherFixture' |
            Should -BeFalse
    }
}

Describe 'Test-FixtureOwnedAlertRule' {
    BeforeAll {
        $script:expectedId = @(
            (New-FixtureRuleId -NamePrefix 'SacDep' -ScenarioName 'Direct')
            (New-FixtureRuleId -NamePrefix 'SacDep' -ScenarioName 'OneHop')
        )

        $script:byName = [pscustomobject]@{
            name       = $script:expectedId[0]
            properties = [pscustomobject]@{
                displayName = 'somebody renamed this'
                description = 'and rewrote the description'
            }
        }

        $script:bySentinel = @'
{
  "name": "99999999-9999-9999-9999-999999999999",
  "properties": {
    "displayName": "SacDep fixture - direct table reference",
    "description": "line one\nline two\n[SacFixture:ClassicToDcr-DependencyFixture:22222222-2222-2222-2222-222222222222:Direct]",
    "enabled": false
  }
}
'@ | ConvertFrom-Json

        $script:contentHub = [pscustomobject]@{
            name       = $script:expectedId[0]
            properties = [pscustomobject]@{
                displayName           = 'A Content Hub rule'
                description           = '[SacFixture:ClassicToDcr-DependencyFixture:x:Direct]'
                alertRuleTemplateName = '00000000-0000-0000-0000-0000000000aa'
            }
        }

        $script:customerRule = @'
{
  "name": "abcdef01-0000-0000-0000-000000000000",
  "properties": {
    "displayName": "A real customer detection",
    "description": "Detects things that matter",
    "enabled": true
  }
}
'@ | ConvertFrom-Json
    }

    It 'claims a rule whose name equals a recomputed deterministic id, even after a rename' {
        Test-FixtureOwnedAlertRule -AlertRule $script:byName -FixtureMarker $script:FixtureMarker `
                                   -ExpectedRuleId $script:expectedId | Should -BeTrue
    }

    It 'claims a rule carrying the description sentinel, even under an unexpected name' {
        Test-FixtureOwnedAlertRule -AlertRule $script:bySentinel -FixtureMarker $script:FixtureMarker `
                                   -ExpectedRuleId $script:expectedId | Should -BeTrue
    }

    It 'refuses a rule linked to a Content Hub template, whatever else it carries' {
        Test-FixtureOwnedAlertRule -AlertRule $script:contentHub -FixtureMarker $script:FixtureMarker `
                                   -ExpectedRuleId $script:expectedId | Should -BeFalse
    }

    It 'does not claim a real customer rule' {
        Test-FixtureOwnedAlertRule -AlertRule $script:customerRule -FixtureMarker $script:FixtureMarker `
                                   -ExpectedRuleId $script:expectedId | Should -BeFalse
    }

    It 'does not claim a rule whose sentinel names a different marker' {
        Test-FixtureOwnedAlertRule -AlertRule $script:bySentinel -FixtureMarker 'SomeOtherFixture' `
                                   -ExpectedRuleId @() | Should -BeFalse
    }

    It 'returns false for a null rule' {
        Test-FixtureOwnedAlertRule -AlertRule $null -FixtureMarker $script:FixtureMarker | Should -BeFalse
    }
}

Describe 'Test-FixtureOwnedTable' {
    BeforeAll {
        $script:expectedTable = @('SacDepDirect_CL', 'SacDepOneHop_CL', 'SacDepOrphan_CL')

        $script:markedTable = @'
{
  "name": "SacDepDirect_CL",
  "properties": {
    "schema": {
      "name": "SacDepDirect_CL",
      "tableType": "CustomLog",
      "tableSubType": "Classic",
      "columns": [
        { "name": "TimeGenerated", "type": "datetime" },
        { "name": "SourceHost_s", "type": "string" },
        { "name": "SacFixtureMarker_s", "type": "string" }
      ]
    }
  }
}
'@ | ConvertFrom-Json

        $script:unmarkedTable = @'
{
  "name": "SacDepDirect_CL",
  "properties": {
    "schema": {
      "name": "SacDepDirect_CL",
      "tableType": "CustomLog",
      "tableSubType": "Classic",
      "columns": [ { "name": "TimeGenerated", "type": "datetime" } ]
    }
  }
}
'@ | ConvertFrom-Json

        $script:managedTable = @'
{
  "name": "AzureDiagnostics",
  "properties": {
    "schema": {
      "tableType": "CustomLog",
      "tableSubType": "Classic",
      "columns": [ { "name": "SacFixtureMarker_s", "type": "string" } ]
    }
  }
}
'@ | ConvertFrom-Json
    }

    It 'claims a table that passes all four gates' {
        Test-FixtureOwnedTable -Table $script:markedTable -ExpectedTableName $script:expectedTable | Should -BeTrue
    }

    It 'refuses a table with no marker column, which is somebody else''s table' {
        Test-FixtureOwnedTable -Table $script:unmarkedTable -ExpectedTableName $script:expectedTable | Should -BeFalse
    }

    It 'refuses a table whose name is not in the closed fixture set' {
        Test-FixtureOwnedTable -Table $script:markedTable -ExpectedTableName @('SomethingElse_CL') | Should -BeFalse
    }

    It 'refuses AzureDiagnostics even when it somehow carries the marker column' {
        Test-FixtureOwnedTable -Table $script:managedTable -ExpectedTableName @('AzureDiagnostics') | Should -BeFalse
    }

    It 'refuses a table that is not a CustomLog' {
        $t = $script:markedTable | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $t.properties.schema.tableType = 'Microsoft'
        Test-FixtureOwnedTable -Table $t -ExpectedTableName $script:expectedTable | Should -BeFalse
    }

    It 'matches the name case-insensitively' {
        $t = $script:markedTable | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $t.name = 'sacdepdirect_cl'
        Test-FixtureOwnedTable -Table $t -ExpectedTableName $script:expectedTable | Should -BeTrue
    }

    It 'returns false for a null table or an empty expected set' {
        Test-FixtureOwnedTable -Table $null -ExpectedTableName $script:expectedTable | Should -BeFalse
        Test-FixtureOwnedTable -Table $script:markedTable -ExpectedTableName @() | Should -BeFalse
    }
}

Describe 'Get-TableSubType' {
    It 'reads the subtype when it is present' {
        $t = '{ "properties": { "schema": { "tableSubType": "Classic" } } }' | ConvertFrom-Json
        Get-TableSubType -Table $t | Should -Be 'Classic'
    }

    It 'returns Unknown rather than throwing when the member is missing' {
        # Load bearing under Set-StrictMode -Version Latest: a plain property
        # access on a missing member would throw.
        $t = '{ "properties": { "schema": { "tableType": "CustomLog" } } }' | ConvertFrom-Json
        Get-TableSubType -Table $t | Should -Be 'Unknown'
    }

    It 'returns Unknown for a table with no schema, no properties, or no object at all' {
        Get-TableSubType -Table ('{ "properties": {} }' | ConvertFrom-Json) | Should -Be 'Unknown'
        Get-TableSubType -Table ('{}' | ConvertFrom-Json)                   | Should -Be 'Unknown'
        Get-TableSubType -Table $null                                       | Should -Be 'Unknown'
    }
}

Describe 'New-FixtureDescription' {
    BeforeAll {
        $script:description = New-FixtureDescription -NamePrefix 'SacDep' -FixtureMarker $script:FixtureMarker `
                                                     -RunId '33333333-3333-3333-3333-333333333333' `
                                                     -ScenarioName 'OneHop'
    }

    It 'carries the machine-readable sentinel on its own final line' {
        $lines = $script:description -split "`n"
        $lines[-1] | Should -Be '[SacFixture:ClassicToDcr-DependencyFixture:33333333-3333-3333-3333-333333333333:OneHop]'
    }

    It 'is recognised by the alert-rule ownership gate it exists to feed' {
        $rule = [pscustomobject]@{
            name       = 'not-a-derived-guid'
            properties = [pscustomobject]@{ description = $script:description }
        }
        Test-FixtureOwnedAlertRule -AlertRule $rule -FixtureMarker $script:FixtureMarker | Should -BeTrue
    }

    It 'says the rule is disabled by default and tells the operator how to remove it' {
        $script:description | Should -Match 'DISABLED'
        $script:description | Should -Match 'New-DependencyFixture\.ps1 -Remove -NamePrefix SacDep'
    }

    It 'says ENABLED when the rule is created enabled, so the portal is honest about it' {
        $enabled = New-FixtureDescription -NamePrefix 'SacDep' -FixtureMarker $script:FixtureMarker `
                                          -RunId 'r' -ScenarioName 'OneHop' -Enabled $true
        $enabled | Should -Match 'ENABLED'
        $enabled | Should -Not -Match 'DISABLED'
    }
}

Describe 'New-SavedSearchBody' {
    It 'produces a parser: a function alias plus the ownership tags' {
        $body = New-SavedSearchBody -Category 'SacDep Fixture' -DisplayName 'p' -Query 'SacDepOneHop_CL' `
                                    -FunctionAlias 'SacDepOneHopParser' -FixtureMarker $script:FixtureMarker `
                                    -RunId 'r1' -ScenarioName 'OneHop'

        $body.properties['functionAlias'] | Should -Be 'SacDepOneHopParser'
        $body.properties['version']       | Should -Be 2
        $body.etag                        | Should -Be '*'
    }

    It 'produces a hunting query: the right category and NO function alias' {
        # A hunting query with an alias would be classified as a parser by the
        # review tool, and the non-rule content type would go untested.
        $body = New-SavedSearchBody -Category 'Hunting Queries' -DisplayName 'h' -Query 'SacDepOneHopParser' `
                                    -FixtureMarker $script:FixtureMarker -RunId 'r1' -ScenarioName 'Hunt'

        $body.properties.Contains('functionAlias') | Should -BeFalse
        $body.properties['category'] | Should -Be 'Hunting Queries'
    }

    It 'omits the alias when an empty string is passed' {
        $body = New-SavedSearchBody -Category 'Hunting Queries' -DisplayName 'h' -Query 'q' `
                                    -FunctionAlias '' -FixtureMarker $script:FixtureMarker `
                                    -RunId 'r1' -ScenarioName 'Hunt'
        $body.properties.Contains('functionAlias') | Should -BeFalse
    }

    It 'writes the three ownership tags that -Remove gates on' {
        $body = New-SavedSearchBody -Category 'c' -DisplayName 'd' -Query 'q' `
                                    -FixtureMarker $script:FixtureMarker -RunId 'r1' -ScenarioName 'Hunt'

        $tags = @($body.properties['tags'])
        $tags.Count | Should -Be 3
        ($tags | Where-Object { $_['name'] -eq 'SacFixture' }).value         | Should -Be $script:FixtureMarker
        ($tags | Where-Object { $_['name'] -eq 'SacFixtureRun' }).value      | Should -Be 'r1'
        ($tags | Where-Object { $_['name'] -eq 'SacFixtureScenario' }).value | Should -Be 'Hunt'
    }

    It 'round-trips through JSON into something the ownership gate recognises' {
        $body = New-SavedSearchBody -Category 'c' -DisplayName 'd' -Query 'q' `
                                    -FixtureMarker $script:FixtureMarker -RunId 'r1' -ScenarioName 'Hunt'

        $roundTripped = $body | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        Test-FixtureOwnedSavedSearch -SavedSearch $roundTripped -FixtureMarker $script:FixtureMarker |
            Should -BeTrue
    }
}

Describe 'New-AlertRuleBody' {
    BeforeAll {
        $script:ruleBody = New-AlertRuleBody -DisplayName 'SacDep fixture' -Description 'd' `
                                             -Query "SacDepOneHopParser`n| where 1 == 0"
    }

    It 'is a Scheduled rule, with kind as a sibling of properties rather than inside it' {
        $script:ruleBody.kind | Should -Be 'Scheduled'
        $script:ruleBody.properties.Contains('kind') | Should -BeFalse
    }

    It 'is disabled unless enablement is asked for explicitly' {
        $script:ruleBody.properties['enabled'] | Should -BeFalse
    }

    It 'carries all ten required properties, including the two that are easy to miss' {
        foreach ($required in @('displayName', 'enabled', 'query', 'queryFrequency', 'queryPeriod',
                                'severity', 'suppressionDuration', 'suppressionEnabled',
                                'triggerOperator', 'triggerThreshold')) {
            $script:ruleBody.properties.Contains($required) |
                Should -BeTrue -Because "omitting $required is an HTTP 400 at api-version 2024-03-01"
        }
    }

    It 'sends a valid suppressionDuration even though suppression is off' {
        $script:ruleBody.properties['suppressionEnabled']  | Should -BeFalse
        $script:ruleBody.properties['suppressionDuration'] | Should -Be 'PT1H'
    }

    It 'uses ISO 8601 durations, not the KQL timespan format the repo YAML uses' {
        # Sending '24h' here is a 400.
        $script:ruleBody.properties['queryFrequency'] | Should -Match '^P(T.+)?$'
        $script:ruleBody.properties['queryPeriod']    | Should -Match '^P(T.+)?$'
    }

    It 'keeps queryFrequency less than or equal to queryPeriod, and both inside the documented range' {
        $frequency = [System.Xml.XmlConvert]::ToTimeSpan($script:ruleBody.properties['queryFrequency'])
        $period    = [System.Xml.XmlConvert]::ToTimeSpan($script:ruleBody.properties['queryPeriod'])

        $frequency | Should -BeLessOrEqual $period
        $frequency.TotalMinutes | Should -BeGreaterOrEqual 5
        $period.TotalDays       | Should -BeLessOrEqual 14
    }

    It 'creates no incidents' {
        $script:ruleBody.properties['incidentConfiguration']['createIncident'] | Should -BeFalse
    }

    It 'stays at Informational severity' {
        $script:ruleBody.properties['severity'] | Should -Be 'Informational'
    }

    It 'never links a Content Hub template, which would misclassify it as managed content' {
        $script:ruleBody.properties.Contains('alertRuleTemplateName') | Should -BeFalse
    }

    It 'can be enabled explicitly, and says so' {
        $enabled = New-AlertRuleBody -DisplayName 'x' -Description 'd' -Query 'q' -Enabled $true
        $enabled.properties['enabled'] | Should -BeTrue
        # The other three safety layers survive enablement.
        $enabled.properties['severity'] | Should -Be 'Informational'
        $enabled.properties['incidentConfiguration']['createIncident'] | Should -BeFalse
    }

    It 'serialises to JSON without losing the nested incident configuration' {
        $json   = $script:ruleBody | ConvertTo-Json -Depth 10
        $parsed = $json | ConvertFrom-Json
        $parsed.kind | Should -Be 'Scheduled'
        $parsed.properties.incidentConfiguration.createIncident | Should -BeFalse
        $parsed.properties.incidentConfiguration.groupingConfiguration.enabled | Should -BeFalse
    }
}

Describe 'New-DependencyFixtureRecord' {
    BeforeAll {
        $script:refTime = [datetime]::new(2026, 7, 28, 12, 0, 0, [System.DateTimeKind]::Utc)
        $script:records = @(New-DependencyFixtureRecord -Count 5 -ReferenceTime $script:refTime `
                                                        -Marker 'ClassicToDcr-DependencyFixture|run-1' `
                                                        -ScenarioName 'OneHop')
    }

    It 'generates the requested number of records' {
        $script:records.Count | Should -Be 5
    }

    It 'stamps the marker field on every record, since a table can carry no other proof of ownership' {
        foreach ($record in $script:records) {
            $record['SacFixtureMarker'] | Should -Be 'ClassicToDcr-DependencyFixture|run-1'
        }
    }

    It 'includes a nominated time field the Data Collector API can map to TimeGenerated' {
        $script:records[0].Keys | Should -Contain 'Timestamp'
        { [datetime]::Parse($script:records[0]['Timestamp']) } | Should -Not -Throw
    }

    It 'uses only string fields, so every inferred column gets the _s suffix the parsers project' {
        foreach ($key in $script:records[0].Keys) {
            $script:records[0][$key] | Should -BeOfType [string]
        }
    }

    It 'carries the scenario for readability in the portal' {
        $script:records[0]['Scenario'] | Should -Be 'OneHop'
    }

    It 'is deterministic given a reference time' {
        $again = @(New-DependencyFixtureRecord -Count 5 -ReferenceTime $script:refTime `
                                               -Marker 'ClassicToDcr-DependencyFixture|run-1' `
                                               -ScenarioName 'OneHop')
        ($again[0] | ConvertTo-Json) | Should -Be ($script:records[0] | ConvertTo-Json)
    }

    It 'serialises to a JSON array, the shape the Data Collector API expects' {
        $parsed = ConvertTo-Json -InputObject @($script:records) -Depth 5 | ConvertFrom-Json
        @($parsed).Count | Should -Be 5
    }

    It 'produces the marker column name the ownership gate looks for' {
        # The API appends _s to a string field, so SacFixtureMarker becomes
        # SacFixtureMarker_s. If these two ever drift, -Remove stops working.
        "$($script:MarkerFieldName)_s" | Should -Be $script:MarkerColumnName
        $script:records[0].Keys | Should -Contain $script:MarkerFieldName
    }
}

Describe 'New-DataCollectorSignature' {
    BeforeAll {
        $script:key  = [Convert]::ToBase64String([byte[]](1..32))
        $script:wsid = '00000000-0000-0000-0000-000000000000'
        $script:date = 'Tue, 28 Jul 2026 00:00:00 GMT'
    }

    It 'returns a SharedKey header naming the workspace' {
        $sig = New-DataCollectorSignature -WorkspaceId $script:wsid -SharedKey $script:key `
                                          -ContentLength 42 -Rfc1123Date $script:date
        $sig | Should -Match "^SharedKey $($script:wsid):"
    }

    It 'changes when the content length changes, proving the length is really signed' {
        $a = New-DataCollectorSignature -WorkspaceId $script:wsid -SharedKey $script:key -ContentLength 42 -Rfc1123Date $script:date
        $b = New-DataCollectorSignature -WorkspaceId $script:wsid -SharedKey $script:key -ContentLength 43 -Rfc1123Date $script:date
        $a | Should -Not -Be $b
    }

    It 'matches an independent computation of the documented string-to-hash' {
        $len  = 128
        $sth  = "POST`n$len`napplication/json`nx-ms-date:$($script:date)`n/api/logs"
        $hmac = [System.Security.Cryptography.HMACSHA256]::new([Convert]::FromBase64String($script:key))
        try {
            $expected = 'SharedKey {0}:{1}' -f $script:wsid,
                        [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($sth)))
        }
        finally { $hmac.Dispose() }

        New-DataCollectorSignature -WorkspaceId $script:wsid -SharedKey $script:key `
                                   -ContentLength $len -Rfc1123Date $script:date | Should -Be $expected
    }
}

Describe 'Find-ExistingByName' {
    BeforeAll {
        $script:collection = @(
            [pscustomobject]@{ name = 'SacDep-OneHopParser' }
            [pscustomobject]@{ name = 'SomethingElse' }
            [pscustomobject]@{ notName = 'no name member at all' }
        )
    }

    It 'finds an item by its resource name' {
        (Find-ExistingByName -Collection $script:collection -Name 'SacDep-OneHopParser').name |
            Should -Be 'SacDep-OneHopParser'
    }

    It 'matches case-insensitively, as ARM does' {
        Find-ExistingByName -Collection $script:collection -Name 'sacdep-onehopparser' | Should -Not -BeNullOrEmpty
    }

    It 'returns nothing when the name is absent' {
        Find-ExistingByName -Collection $script:collection -Name 'NotThere' | Should -BeNullOrEmpty
    }

    It 'tolerates an empty or null collection' {
        Find-ExistingByName -Collection @() -Name 'x'   | Should -BeNullOrEmpty
        Find-ExistingByName -Collection $null -Name 'x' | Should -BeNullOrEmpty
    }

    It 'skips items with no name member rather than throwing' {
        { Find-ExistingByName -Collection $script:collection -Name 'x' } | Should -Not -Throw
    }
}

Describe 'Get-FixtureResourcePath' {
    BeforeAll {
        $script:paths = Get-FixtureResourcePath -SubscriptionId 'sub' -ResourceGroupName 'rg' -WorkspaceName 'ws'
    }

    It 'uses the api-versions the review tool reads with' {
        $script:paths.TableList | Should -Match 'api-version=2023-09-01'
        $script:paths.SavedList | Should -Match 'api-version=2020-08-01'
        $script:paths.RuleList  | Should -Match 'api-version=2024-03-01'
    }

    It 'nests the Sentinel provider under the workspace, as alertRules requires' {
        $script:paths.RuleList | Should -Match 'Microsoft\.OperationalInsights/workspaces/ws/providers/Microsoft\.SecurityInsights/alertRules'
    }

    It 'emits relative paths, so Invoke-AzRestMethod picks the right sovereign cloud host' {
        foreach ($value in $script:paths.PSObject.Properties.Value) {
            $value | Should -Match '^/subscriptions/'
        }
    }
}
