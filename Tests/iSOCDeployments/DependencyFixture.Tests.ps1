#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for New-iSOCDependencyFixture and Remove-iSOCDependencyFixture.

.DESCRIPTION
    The naming plan, rule ids, ownership tests, alias guard and body
    builders are held to explicit expected values for a handful of
    representative inputs.

    The commands run through mocks of the module's REST client, HTTP client
    and log query, over one stand-in workspace
    (Tests/iSOCDeployments/_helpers/DependencyFixtureStandIn.psm1) that
    validates rule queries, refuses to delete classic tables, checks Data
    Collector signatures, and changes as it is written to: each refusal must
    give its message and write nothing, and a full run and a removal must
    write every kind of object.

    Parity with New-DependencyFixture.ps1 was proven on release/26.11.0
    before the script was removed.

.NOTES
    File:         Tests/iSOCDeployments/DependencyFixture.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeDiscovery {
    $script:refusals = @(
        @{ Label = 'an alias another parser has'; Parameters = @{ NamePrefix = 'Coll' }; Message = 'Refusing to create the fixture. A function alias would shadow a table or an existing parser for every query in this workspace. Pick a different -NamePrefix.' }
        @{ Label = 'an alias a workspace table has'; Parameters = @{ NamePrefix = 'Sec' }; Message = 'Refusing to create the fixture. A function alias would shadow a table or an existing parser for every query in this workspace. Pick a different -NamePrefix.' }
        @{ Label = 'a table name taken by someone else'; Parameters = @{ NamePrefix = 'Taken' }; Message = 'Refusing to create the fixture. One or more target names belong to existing content. Nothing was written. Pick a different -NamePrefix.' }
        @{ Label = 'a workspace without Sentinel'; NotOnboarded = $true; Parameters = @{}; Message = 'Microsoft Sentinel is not onboarded on workspace ''law-sentinel''. The analytics rules could never be created, and a partial fixture is worse than none.' }
        @{ Label = 'a live query without -EnableRules'; Parameters = @{ EnableRulesWithLiveQuery = $true }; Message = '-EnableRulesWithLiveQuery only has meaning with -EnableRules. Two separate switches are required on purpose, so neither can be reached by a typo.' }
    )
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:helperPath = Join-Path $PSScriptRoot '_helpers/DependencyFixtureStandIn.psm1'
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module $script:helperPath -Force

    function Invoke-ModuleFixture {
        param([hashtable] $Parameters, [switch] $Remove, [hashtable] $StandIn = @{})
        $switches = @{}
        foreach ($k in 'Existing', 'UnmarkedOrphan', 'NotOnboarded', 'RaceOnce') { if ($StandIn[$k]) { $switches[$k] = $true } }
        $script:depState = Get-DependencyFixtureStandIn @switches
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
        Mock -ModuleName iSOCDeployments Start-Sleep { }
        Mock -ModuleName iSOCDeployments Invoke-iSOCAzLogQuery { Invoke-DependencyFixtureQuery -State $script:depState -Query $Query }
        Mock -ModuleName iSOCDeployments Invoke-iSOCHttpRequest { [pscustomobject]@{ StatusCode = (Invoke-DependencyFixtureCollector -State $script:depState -Uri $Uri -Headers $Headers -Body $Body); Content = '' } }
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
            $json = if ($null -ne $Body) { ConvertTo-Json -InputObject $Body -Depth 30 } else { $null }
            $a = Invoke-DependencyFixtureArm -State $script:depState -Method $Method -Path $Path -Body $json
            if ($a.Status -eq 404 -and $AllowNotFound) { return }
            if ($a.Status -ge 400) {
                $detail = if ($a.Body) { $a.Body.error.message } else { '' }
                throw [System.Net.Http.HttpRequestException]::new("HTTP $($a.Status) from $Method ${Path}: $detail", $null, [System.Net.HttpStatusCode]$a.Status)
            }
            if ($null -eq $a.Body) { return }
            $object = ConvertTo-Json -InputObject $a.Body -Depth 30 | ConvertFrom-Json -Depth 30
            if (@($object.PSObject.Properties.Name) -join ',' -eq 'value') { return $object.value }
            $object
        }
        $ctx = InModuleScope iSOCDeployments -Parameters @{ State = $script:depState } {
            param($State)
            New-iSOCContext -Value @{
                TenantId = 't'; SubscriptionId = $State.SubscriptionId; ResourceGroup = 'rg-sentinel'; WorkspaceName = $State.WorkspaceName
                WorkspaceResourceId = $State.WorkspacePath; WorkspaceId = $State.WorkspaceId; Region = 'uksouth'; PlaybookResourceGroup = 'rg-sentinel'
                Environment = 'AzureCloud'; IsGov = $false; ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'tester'
            }
        }
        $command = if ($Remove) { 'Remove-iSOCDependencyFixture' } else { 'New-iSOCDependencyFixture' }
        $result = $null
        $failure = $null
        try { $result = & $command -Context $ctx -Confirm:$false @Parameters }
        catch { $failure = $_.Exception.Message }
        [pscustomobject]@{ Result = $result; Error = $failure; Writes = @($script:depState.Writes) }
    }
}

Describe 'The dependency fixture helpers' {
    BeforeAll {
        $script:state = Get-DependencyFixtureStandIn -Existing -UnmarkedOrphan
        $script:asObjects = { param($Items) @($Items | ForEach-Object { $_ | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30 }) }
    }

    It 'plans the objects, for <Label>' -ForEach @(
        @{ Label = 'every scenario'; Prefix = 'SacDep'; Scenario = $null; Clamp = '| where 1 == 0'
            Expected = '{"Alias":["SacDepOneHopParser","SacDepInnerParser","SacDepOuterParser","SacDepCycleA","SacDepCycleB"],' +
                '"HuntingQuery":[{"DisplayName":"SacDep fixture hunting query via parser","Query":"SacDepOneHopParser\n| summarize Hits = count() by SourceHost_s","SavedSearchId":"SacDep-Hunt","ScenarioName":"Hunt"}],' +
                '"NamePrefix":"SacDep",' +
                '"Parser":[{"Alias":"SacDepOneHopParser","DisplayName":"SacDep fixture one-hop parser","IsCycleClosure":false,"Order":1,"Query":"SacDepOneHop_CL\n| project TimeGenerated, SourceHost_s, Severity_s, SacFixtureMarker_s","SavedSearchId":"SacDep-OneHopParser","ScenarioName":"OneHop"},{"Alias":"SacDepInnerParser","DisplayName":"SacDep fixture inner parser","IsCycleClosure":false,"Order":2,"Query":"SacDepTwoHop_CL\n| project TimeGenerated, SourceHost_s, Severity_s, SacFixtureMarker_s","SavedSearchId":"SacDep-InnerParser","ScenarioName":"TwoHop"},{"Alias":"SacDepOuterParser","DisplayName":"SacDep fixture outer parser","IsCycleClosure":false,"Order":3,"Query":"SacDepInnerParser\n| where isnotempty(SourceHost_s)","SavedSearchId":"SacDep-OuterParser","ScenarioName":"TwoHop"},{"Alias":"SacDepCycleA","DisplayName":"SacDep fixture cycle parser A","IsCycleClosure":false,"Order":4,"Query":"SacDepCycle_CL\n| project TimeGenerated, SourceHost_s, Severity_s, SacFixtureMarker_s","SavedSearchId":"SacDep-CycleA","ScenarioName":"Cycle"},{"Alias":"SacDepCycleB","DisplayName":"SacDep fixture cycle parser B","IsCycleClosure":false,"Order":5,"Query":"SacDepCycleA\n| where isnotempty(SourceHost_s)","SavedSearchId":"SacDep-CycleB","ScenarioName":"Cycle"},{"Alias":"SacDepCycleA","DisplayName":"SacDep fixture cycle parser A","IsCycleClosure":true,"Order":6,"Query":"union SacDepCycle_CL, SacDepCycleB\n| project TimeGenerated, SourceHost_s","SavedSearchId":"SacDep-CycleA","ScenarioName":"Cycle"}],' +
                '"Rule":[{"DisplayName":"SacDep fixture - direct table reference","IsIndirect":false,"Query":"SacDepDirect_CL\n| where 1 == 0","RuleId":"412fec7b-ed6b-b50b-341e-accf45200b25","ScenarioName":"Direct"},{"DisplayName":"SacDep fixture - one hop through a parser","IsIndirect":true,"Query":"SacDepOneHopParser\n| where 1 == 0","RuleId":"00545365-7482-4581-4bc7-ec52f79e0354","ScenarioName":"OneHop"},{"DisplayName":"SacDep fixture - two hops through parsers","IsIndirect":true,"Query":"SacDepOuterParser\n| where 1 == 0","RuleId":"a7364c68-7dfd-3219-7cea-09e53a04ecb3","ScenarioName":"TwoHop"},{"DisplayName":"SacDep fixture - table also read by a cyclic parser pair","IsIndirect":false,"Query":"SacDepCycle_CL\n| where 1 == 0","RuleId":"d080f63f-d32d-07e8-5865-d778be0f3b63","ScenarioName":"Cycle"}],' +
                '"ScenarioName":["Direct","OneHop","TwoHop","Cycle","Orphan","Hunt"],' +
                '"Table":[{"LogType":"SacDepDirect","ScenarioName":"Direct","TableName":"SacDepDirect_CL"},{"LogType":"SacDepOneHop","ScenarioName":"OneHop","TableName":"SacDepOneHop_CL"},{"LogType":"SacDepTwoHop","ScenarioName":"TwoHop","TableName":"SacDepTwoHop_CL"},{"LogType":"SacDepCycle","ScenarioName":"Cycle","TableName":"SacDepCycle_CL"},{"LogType":"SacDepOrphan","ScenarioName":"Orphan","TableName":"SacDepOrphan_CL"}]}'
        }
        @{ Label = 'Hunt alone'; Prefix = 'Alpha'; Scenario = @('Hunt'); Clamp = '| where 1 == 0'
            Expected = '{"Alias":["AlphaOneHopParser"],' +
                '"HuntingQuery":[{"DisplayName":"Alpha fixture hunting query via parser","Query":"AlphaOneHopParser\n| summarize Hits = count() by SourceHost_s","SavedSearchId":"Alpha-Hunt","ScenarioName":"Hunt"}],' +
                '"NamePrefix":"Alpha",' +
                '"Parser":[{"Alias":"AlphaOneHopParser","DisplayName":"Alpha fixture one-hop parser","IsCycleClosure":false,"Order":1,"Query":"AlphaOneHop_CL\n| project TimeGenerated, SourceHost_s, Severity_s, SacFixtureMarker_s","SavedSearchId":"Alpha-OneHopParser","ScenarioName":"OneHop"}],' +
                '"Rule":[{"DisplayName":"Alpha fixture - one hop through a parser","IsIndirect":true,"Query":"AlphaOneHopParser\n| where 1 == 0","RuleId":"d80fc495-839a-a41d-b56a-d2a7969e55cb","ScenarioName":"OneHop"}],' +
                '"ScenarioName":["OneHop","Hunt"],' +
                '"Table":[{"LogType":"AlphaOneHop","ScenarioName":"OneHop","TableName":"AlphaOneHop_CL"}]}'
        }
        @{ Label = 'no clamp'; Prefix = 'Bravo99'; Scenario = @('Cycle', 'direct'); Clamp = ''
            Expected = '{"Alias":["Bravo99CycleA","Bravo99CycleB"],' +
                '"HuntingQuery":[],' +
                '"NamePrefix":"Bravo99",' +
                '"Parser":[{"Alias":"Bravo99CycleA","DisplayName":"Bravo99 fixture cycle parser A","IsCycleClosure":false,"Order":4,"Query":"Bravo99Cycle_CL\n| project TimeGenerated, SourceHost_s, Severity_s, SacFixtureMarker_s","SavedSearchId":"Bravo99-CycleA","ScenarioName":"Cycle"},{"Alias":"Bravo99CycleB","DisplayName":"Bravo99 fixture cycle parser B","IsCycleClosure":false,"Order":5,"Query":"Bravo99CycleA\n| where isnotempty(SourceHost_s)","SavedSearchId":"Bravo99-CycleB","ScenarioName":"Cycle"},{"Alias":"Bravo99CycleA","DisplayName":"Bravo99 fixture cycle parser A","IsCycleClosure":true,"Order":6,"Query":"union Bravo99Cycle_CL, Bravo99CycleB\n| project TimeGenerated, SourceHost_s","SavedSearchId":"Bravo99-CycleA","ScenarioName":"Cycle"}],' +
                '"Rule":[{"DisplayName":"Bravo99 fixture - direct table reference","IsIndirect":false,"Query":"Bravo99Direct_CL","RuleId":"d3e59fda-4962-8e5e-215d-96d7130da334","ScenarioName":"Direct"},{"DisplayName":"Bravo99 fixture - table also read by a cyclic parser pair","IsIndirect":false,"Query":"Bravo99Cycle_CL","RuleId":"295c5405-3741-a2b1-05e6-e8c92f9146bb","ScenarioName":"Cycle"}],' +
                '"ScenarioName":["Direct","Cycle"],' +
                '"Table":[{"LogType":"Bravo99Direct","ScenarioName":"Direct","TableName":"Bravo99Direct_CL"},{"LogType":"Bravo99Cycle","ScenarioName":"Cycle","TableName":"Bravo99Cycle_CL"}]}'
        }
    ) {
        $new = InModuleScope iSOCDeployments -Parameters @{ P = $Prefix; S = $Scenario; C = $Clamp } { param($P, $S, $C) Get-iSOCFixtureNamingPlan -NamePrefix $P -ScenarioName $S -QueryClamp $C }
        (ConvertTo-StandInCanonical $new) | Should -BeExactly $Expected
    }

    It 'judges ownership' {
        $tables = & $script:asObjects ((Invoke-DependencyFixtureArm -State $script:state -Method GET -Path "$($script:state.WorkspacePath)/tables").Body.value)
        $saved = & $script:asObjects $script:state.Saved.Values
        $rules = & $script:asObjects $script:state.Rules.Values
        $names = @('SacDepDirect_CL', 'SacDepOneHop_CL', 'SacDepOrphan_CL', 'SecOneHopParser')
        $ids = @('412fec7b-ed6b-b50b-341e-accf45200b25', '00545365-7482-4581-4bc7-ec52f79e0354', 'a7364c68-7dfd-3219-7cea-09e53a04ecb3', 'd080f63f-d32d-07e8-5865-d778be0f3b63')
        $new = InModuleScope iSOCDeployments -Parameters @{ T = $tables; S = $saved; R = $rules; N = $names; I = $ids } {
            param($T, $S, $R, $N, $I)
            $m = (Get-iSOCDependencyFixtureSetting).FixtureMarker
            [ordered]@{
                Tables = @($T | ForEach-Object { Test-iSOCFixtureOwnedTable -Table $_ -ExpectedTableName $N })
                Saved  = @($S | ForEach-Object { Test-iSOCFixtureOwnedSavedSearch -SavedSearch $_ -FixtureMarker $m })
                Rules  = @($R | ForEach-Object { Test-iSOCFixtureOwnedAlertRule -AlertRule $_ -FixtureMarker $m -ExpectedRuleId $I })
                Sub    = @($T | ForEach-Object { $s = [string](Get-iSOCPropertyValue -InputObject $_ -Path 'properties.schema.tableSubType'); if ($s) { $s } else { 'Unknown' } })
            }
        }
        @($tables.name) | Should -Be @('SecurityEvent', 'SigninLogs', 'SecOneHopParser', 'TakenDirect_CL', 'SacDepDirect_CL', 'SacDepOneHop_CL', 'SacDepTwoHop_CL', 'SacDepCycle_CL', 'SacDepOrphan_CL')
        @($saved.name) | Should -Be @('cust-parser', 'SacDepNotes', 'SacDep-OneHopParser', 'SacDep-InnerParser', 'SacDep-OuterParser', 'SacDep-CycleA', 'SacDep-CycleB', 'SacDep-Hunt', 'SacDep-OldStray')
        @($rules.name) | Should -Be @('cust-rule', 'hub-rule', '412fec7b-ed6b-b50b-341e-accf45200b25', '00545365-7482-4581-4bc7-ec52f79e0354', 'a7364c68-7dfd-3219-7cea-09e53a04ecb3', 'd080f63f-d32d-07e8-5865-d778be0f3b63')
        (ConvertTo-StandInCanonical $new) | Should -BeExactly '{"Rules":[false,false,true,true,true,true],"Saved":[false,false,true,true,true,true,true,true,true],"Sub":["Any","Any","DataCollectionRuleBased","Classic","DataCollectionRuleBased","Classic","Classic","DataCollectionRuleBased","Classic"],"Tables":[false,false,false,false,true,true,false,false,false]}'
        @($new.Tables) | Should -Contain $true
        @($new.Tables) | Should -Contain $false
        @($new.Rules) | Should -Contain $true
    }

    It 'guards aliases and decides actions' {
        $cases = @(
            @{ A = 'SigninLogs'; Reason = 'alias ''SigninLogs'' matches a table that exists in this workspace; a function alias shadows a table for every query in the workspace' }
            @{ A = 'signinlogs'; Reason = 'alias ''signinlogs'' matches a table that exists in this workspace; a function alias shadows a table for every query in the workspace' }
            @{ A = 'OfficeActivity'; Reason = 'alias ''OfficeActivity'' matches a known Log Analytics or Content Hub table name' }
            @{ A = 'CollOneHopParser'; Reason = 'alias ''CollOneHopParser'' is already used by a saved search that this fixture does not own' }
            @{ A = 'FreshParser'; Reason = $null }
        )
        $new = InModuleScope iSOCDeployments -Parameters @{ Cases = $cases } { param($Cases) foreach ($c in $Cases) { , @(Get-iSOCAliasCollisionReason -Alias $c.A -WorkspaceTableName 'SigninLogs' -ReservedName 'OfficeActivity' -ForeignAlias 'CollOneHopParser') } }
        @($new).Count | Should -Be $cases.Count
        for ($i = 0; $i -lt $cases.Count; $i++) {
            $reason = @(@($new)[$i] | Where-Object { $null -ne $_ })
            if ($null -eq $cases[$i].Reason) { $reason | Should -BeNullOrEmpty -Because $cases[$i].A }
            else { $reason | Should -BeExactly @($cases[$i].Reason) -Because $cases[$i].A }
        }
        $newActs = InModuleScope iSOCDeployments { foreach ($e in $null, 'x') { foreach ($o in $true, $false) { foreach ($r in $true, $false) { Get-iSOCFixtureObjectAction -Existing $e -IsOwned $o -ForRemoval:$r } } } }
        @($newActs) | Should -BeExactly @('ABSENT', 'CREATE', 'ABSENT', 'CREATE', 'DELETE', 'UPDATE', 'SKIP', 'ABORT')
    }

    It 'builds the saved search and rule bodies and records' {
        $at = [datetime]::new(2026, 11, 4, 9, 0, 0, [System.DateTimeKind]::Utc)
        $new = InModuleScope iSOCDeployments -Parameters @{ At = $at } {
            param($At)
            [ordered]@{
                Saved   = New-iSOCFixtureSavedSearchBody -Category 'C' -DisplayName 'D' -Query 'Q' -FixtureMarker 'M' -RunId 'R' -ScenarioName 'S' -FunctionAlias 'A'
                Hunt    = New-iSOCFixtureSavedSearchBody -Category 'Hunting Queries' -DisplayName 'D' -Query 'Q' -FixtureMarker 'M' -RunId 'R' -ScenarioName 'S'
                Rule    = New-iSOCFixtureAlertRuleBody -DisplayName 'D' -Description 'X' -Query 'Q' -Enabled $true
                Records = New-iSOCDependencyFixtureRecord -Count 4 -ReferenceTime $At -Marker 'M|R' -ScenarioName 'OneHop'
                Id      = New-iSOCFixtureRuleId -NamePrefix 'SacDep' -ScenarioName 'TwoHop'
            }
        }
        $expected = '{"Hunt":{"etag":"*","properties":{"category":"Hunting Queries","displayName":"D","query":"Q","tags":[{"name":"SacFixture","value":"M"},{"name":"SacFixtureRun","value":"R"},{"name":"SacFixtureScenario","value":"S"}],"version":2}},' +
            '"Id":"a7364c68-7dfd-3219-7cea-09e53a04ecb3",' +
            '"Records":[{"Message":"Dependency fixture record 0 for scenario OneHop.","SacFixtureMarker":"M|R","Scenario":"OneHop","Severity":"Information","SourceHost":"fixture-01","Timestamp":"2026-11-04T09:00:00.0000000Z"},{"Message":"Dependency fixture record 1 for scenario OneHop.","SacFixtureMarker":"M|R","Scenario":"OneHop","Severity":"Warning","SourceHost":"fixture-02","Timestamp":"2026-11-04T08:59:59.0000000Z"},{"Message":"Dependency fixture record 2 for scenario OneHop.","SacFixtureMarker":"M|R","Scenario":"OneHop","Severity":"Information","SourceHost":"fixture-03","Timestamp":"2026-11-04T08:59:58.0000000Z"},{"Message":"Dependency fixture record 3 for scenario OneHop.","SacFixtureMarker":"M|R","Scenario":"OneHop","Severity":"Warning","SourceHost":"fixture-01","Timestamp":"2026-11-04T08:59:57.0000000Z"}],' +
            '"Rule":{"kind":"Scheduled","properties":{"description":"X","displayName":"D","enabled":true,"eventGroupingSettings":{"aggregationKind":"SingleAlert"},"incidentConfiguration":{"createIncident":false,"groupingConfiguration":{"enabled":false,"lookbackDuration":"PT5H","matchingMethod":"AllEntities","reopenClosedIncident":false}},"query":"Q","queryFrequency":"PT24H","queryPeriod":"PT24H","severity":"Informational","suppressionDuration":"PT1H","suppressionEnabled":false,"triggerOperator":"GreaterThan","triggerThreshold":0}},' +
            '"Saved":{"etag":"*","properties":{"category":"C","displayName":"D","functionAlias":"A","query":"Q","tags":[{"name":"SacFixture","value":"M"},{"name":"SacFixtureRun","value":"R"},{"name":"SacFixtureScenario","value":"S"}],"version":2}}}'
        (ConvertTo-StandInCanonical $new) | Should -BeExactly $expected
        $new.Id | Should -Be (Get-StandInRuleId -Prefix 'SacDep' -Scenario 'TwoHop')
    }
}

Describe 'Refusing: <Label>' -ForEach $script:refusals {
    It 'refuses with its message and writes nothing' {
        $module = Invoke-ModuleFixture -Parameters $Parameters -StandIn @{ NotOnboarded = [bool]$NotOnboarded }
        $module.Error | Should -BeExactly $Message
        $module.Writes | Should -BeNullOrEmpty
    }
}

Describe 'The dependency fixture commands' {
    It 'have something to compare: a full run writes every kind of object' {
        $run = Invoke-ModuleFixture -Parameters @{}
        @($run.Writes.Kind | Sort-Object -Unique) | Should -Be @('Post', 'RulePut', 'SavedPut')
        @($run.Writes | Where-Object Kind -eq 'Post').Count | Should -Be 5
        @($run.Writes | Where-Object Kind -eq 'SavedPut').Count | Should -Be 7
        @($run.Writes | Where-Object Kind -eq 'RulePut').Count | Should -Be 4
        $run.Result.PSObject.TypeNames | Should -Contain 'iSOCDeployments.DependencyFixtureRun'
        $removal = Invoke-ModuleFixture -Remove -StandIn @{ Existing = $true; UnmarkedOrphan = $true } -Parameters @{ MigrateBeforeRemove = $true }
        @($removal.Writes.Kind | Sort-Object -Unique) | Should -Be @('Delete', 'Migrate')
        @($removal.Result.Skipped) | Should -Contain "$($script:depState.WorkspacePath)/tables/SacDepOrphan_CL"
    }

    It 'derives the script''s rule ids, so either removes the other''s fixture' {
        $made = Invoke-ModuleFixture -Parameters @{ Scenario = @('OneHop') }
        $ids = @($made.Writes | Where-Object Kind -eq 'RulePut' | ForEach-Object Target)
        $ids | Should -Contain (Get-StandInRuleId -Prefix 'SacDep' -Scenario 'OneHop')
    }

    It 'names the module''s commands in the rules it makes' {
        $null = Invoke-ModuleFixture -Parameters @{ Scenario = @('Direct') }
        $rule = $script:depState.Rules[(Get-StandInRuleId -Prefix 'SacDep' -Scenario 'Direct')]
        $rule.properties.description | Should -Match 'Remove with Remove-iSOCDependencyFixture -NamePrefix SacDep'
        $rule.properties.enabled | Should -BeFalse
        $rule.properties.query | Should -Match '\| where 1 == 0$'
    }
}
