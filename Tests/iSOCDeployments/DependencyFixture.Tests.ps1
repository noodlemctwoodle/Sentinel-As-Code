#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for New-iSOCDependencyFixture and Remove-iSOCDependencyFixture,
    against Tools/ClassicToDcr/Rehearsal/New-DependencyFixture.ps1.

.DESCRIPTION
    The naming plan, rule ids, ownership tests, alias guard and body
    builders run beside the script's own and must answer the same.

    Then the script runs unchanged in a child pwsh, its Az cmdlets,
    Invoke-RestMethod and Start-Sleep stood in for, and the commands run
    through mocks of the module's REST client, HTTP client and log query,
    over one stand-in workspace
    (Tests/iSOCDeployments/_helpers/DependencyFixtureStandIn.psm1) that
    validates rule queries, refuses to delete classic tables, checks Data
    Collector signatures, and changes as it is written to. For each run both
    must make the same posts, saved searches, rules, migrations and
    deletions, in order, refuse the same way, and return the same result.

.NOTES
    File:         Tests/iSOCDeployments/DependencyFixture.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeDiscovery {
    $script:runs = @(
        @{ Label = 'every scenario'; Parameters = @{} }
        @{ Label = 'the hunting query, which brings OneHop, with rules enabled'; Parameters = @{ Scenario = @('Hunt'); EnableRules = $true } }
        @{ Label = 'a live query, unclamped'; Parameters = @{ Scenario = @('Direct'); EnableRules = $true; EnableRulesWithLiveQuery = $true } }
        @{ Label = 'a fixture already there'; Existing = $true; Parameters = @{} }
        @{ Label = 'a fixture already there, reseeded'; Existing = $true; Parameters = @{ Reseed = $true; Scenario = @('OneHop', 'Orphan') } }
        @{ Label = 'rules whose queries resolve only on a second try'; RaceOnce = $true; Parameters = @{ Scenario = @('OneHop', 'TwoHop') } }
        @{ Label = 'another prefix'; Parameters = @{ NamePrefix = 'Bravo'; RecordCount = 2 } }
        @{ Label = '-WhatIf'; Parameters = @{ WhatIf = $true } }
        @{ Label = 'a removal'; Remove = $true; Existing = $true; UnmarkedOrphan = $true; Parameters = @{} }
        @{ Label = 'a removal migrating classic tables'; Remove = $true; Existing = $true; UnmarkedOrphan = $true; Parameters = @{ MigrateBeforeRemove = $true } }
        @{ Label = 'a removal taking the unmarked table too'; Remove = $true; Existing = $true; UnmarkedOrphan = $true; Parameters = @{ MigrateBeforeRemove = $true; RemoveUnmarkedTable = $true } }
        @{ Label = 'a removal of one scenario'; Remove = $true; Existing = $true; Parameters = @{ Scenario = @('Direct') } }
        @{ Label = 'a removal under -WhatIf'; Remove = $true; Existing = $true; Parameters = @{ MigrateBeforeRemove = $true; WhatIf = $true } }
        @{ Label = 'a removal from a clean workspace'; Remove = $true; Parameters = @{} }
    )
    $script:refusals = @(
        @{ Label = 'an alias another parser has'; Parameters = @{ NamePrefix = 'Coll' } }
        @{ Label = 'an alias a workspace table has'; Parameters = @{ NamePrefix = 'Sec' } }
        @{ Label = 'a table name taken by someone else'; Parameters = @{ NamePrefix = 'Taken' } }
        @{ Label = 'a workspace without Sentinel'; NotOnboarded = $true; Parameters = @{} }
        @{ Label = 'a live query without -EnableRules'; Parameters = @{ EnableRulesWithLiveQuery = $true } }
    )
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:scriptPath = Join-Path $script:repoRoot 'Tools/ClassicToDcr/Rehearsal/New-DependencyFixture.ps1'
    $script:helperPath = Join-Path $PSScriptRoot '_helpers/DependencyFixtureStandIn.psm1'
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module $script:helperPath -Force

    $script:wrapper = @'
param([string] $Script, [string] $Helper, [string] $Parameters, [string] $Out, [switch] $Existing, [switch] $UnmarkedOrphan, [switch] $NotOnboarded, [switch] $RaceOnce)
$ErrorActionPreference = 'Stop'
Import-Module $Helper -Force
$global:DepState = Get-DependencyFixtureStandIn -Existing:$Existing -UnmarkedOrphan:$UnmarkedOrphan -NotOnboarded:$NotOnboarded -RaceOnce:$RaceOnce
function Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = $global:DepState.SubscriptionId }; Account = [pscustomobject]@{ Id = 'tester' } } }
function Set-AzContext { param($Subscription, $WhatIf) }
function Get-AzOperationalInsightsWorkspace { param($ResourceGroupName, $Name) [pscustomobject]@{ CustomerId = [guid]$global:DepState.WorkspaceId; ResourceId = $global:DepState.WorkspacePath } }
function Get-AzOperationalInsightsWorkspaceSharedKey { param($ResourceGroupName, $Name) [pscustomobject]@{ PrimarySharedKey = $global:DepState.SharedKey } }
function Invoke-AzRestMethod {
    param($Path, $Uri, $Method = 'GET', $Payload)
    $t = if ($Path) { $Path } else { ([Uri]$Uri).PathAndQuery }
    $a = Invoke-DependencyFixtureArm -State $global:DepState -Method $Method -Path $t -Body $Payload
    [pscustomobject]@{ StatusCode = $a.Status; Content = $(if ($null -ne $a.Body) { ConvertTo-Json -InputObject $a.Body -Depth 30 } else { '' }) }
}
function Invoke-RestMethod {
    param($Uri, $Method, $ContentType, $Headers, $Body)
    $s = Invoke-DependencyFixtureCollector -State $global:DepState -Uri $Uri -Headers $Headers -Body $Body
    if ($s -ne 200) { throw "Response status code does not indicate success: $s." }
}
function Invoke-AzOperationalInsightsQuery { param($WorkspaceId, $Query, $ErrorAction) Invoke-DependencyFixtureQuery -State $global:DepState -Query $Query }
function Invoke-AzOperationalInsightsMigrateTable { param($ResourceGroupName, $WorkspaceName, $TableName, $Confirm) $null = Invoke-DependencyFixtureArm -State $global:DepState -Method POST -Path "$($global:DepState.WorkspacePath)/tables/$TableName/migrate" }
function Start-Sleep { param($Seconds) }
$splat = Get-Content -LiteralPath $Parameters -Raw | ConvertFrom-Json -AsHashtable
$code = 0
$result = $null
try { $result = & $Script @splat }
catch { $code = 1; Set-Content -LiteralPath (Join-Path $Out 'error.txt') -Value $_.Exception.Message }
Set-Content -LiteralPath (Join-Path $Out 'results.json') -Value (ConvertTo-Json -InputObject @($result) -Depth 10)
Set-Content -LiteralPath (Join-Path $Out 'writes.json') -Value (ConvertTo-Json -InputObject @($global:DepState.Writes) -Depth 10)
exit $code
'@

    function Invoke-LegacyFixture {
        param([hashtable] $Parameters, [switch] $Remove, [hashtable] $StandIn = @{})
        $tree = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $kit = Join-Path $tree 'Rehearsal'
        $out = Join-Path $tree 'out'
        New-Item -ItemType Directory -Path $kit, $out -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'Tools/ClassicToDcr/data') -Destination $tree -Recurse
        $copy = Join-Path $kit 'New-DependencyFixture.ps1'
        Set-Content -LiteralPath $copy -Value ((Get-Content -LiteralPath $script:scriptPath -Raw) -replace '(?m)^#Requires -Modules[^\r\n]*\r?\n', '') -NoNewline
        Set-Content -LiteralPath (Join-Path $tree 'run.ps1') -Value $script:wrapper
        $splat = @{ ResourceGroupName = 'rg-sentinel'; WorkspaceName = 'law-sentinel'; Confirm = $false } + $Parameters
        if ($Remove) { $splat.Remove = $true }
        Set-Content -LiteralPath (Join-Path $tree 'parameters.json') -Value (ConvertTo-Json -InputObject $splat)
        $switches = @{}
        foreach ($k in 'Existing', 'UnmarkedOrphan', 'NotOnboarded', 'RaceOnce') { if ($StandIn[$k]) { $switches[$k] = $true } }
        $output = & pwsh -NoProfile -NonInteractive -File (Join-Path $tree 'run.ps1') -Script $copy -Helper $script:helperPath -Parameters (Join-Path $tree 'parameters.json') -Out $out @switches 2>&1 | Out-String
        $errorFile = Join-Path $out 'error.txt'
        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output   = $output
            Error    = if (Test-Path -LiteralPath $errorFile) { (Get-Content -LiteralPath $errorFile -Raw).Trim() } else { $null }
            Result   = @(Get-Content -LiteralPath (Join-Path $out 'results.json') -Raw | ConvertFrom-Json -Depth 10 | Where-Object { $null -ne $_ }) | Select-Object -First 1
            Writes   = @(Get-Content -LiteralPath (Join-Path $out 'writes.json') -Raw | ConvertFrom-Json -Depth 10 | Where-Object { $null -ne $_ })
        }
    }

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

    function ConvertTo-ComparableResult {
        param($Result)
        if ($null -eq $Result) { return 'none' }
        $o = [ordered]@{}
        foreach ($n in $Result.PSObject.Properties.Name) { if ($n -notin 'RunId', 'PSTypeName') { $o[$n] = $Result.$n } }
        ConvertTo-StandInCanonical $o
    }
}

Describe 'The dependency fixture helpers, beside the script''s' {
    BeforeAll {
        $script:DataCollectorApiVersion = '2016-04-01'
        $script:FixtureMarker = 'ClassicToDcr-DependencyFixture'
        $script:FixtureTagName = 'SacFixture'
        $script:FixtureRunTag = 'SacFixtureRun'
        $script:FixtureScenTag = 'SacFixtureScenario'
        $script:MarkerFieldName = 'SacFixtureMarker'
        $script:MarkerColumnName = 'SacFixtureMarker_s'
        $script:RuleIdNamespace = 'Sentinel-As-Code/ClassicToDcr/DependencyFixture'
        $script:QueryClamp = '| where 1 == 0'
        $script:ScenarioOrder = @('Direct', 'OneHop', 'TwoHop', 'Cycle', 'Orphan', 'Hunt')
        $script:ReservedTableFloor = @('SecurityEvent', 'SigninLogs')
        Import-Module (Join-Path $script:repoRoot 'Tests/_helpers/Import-ScriptFunctions.psm1') -Force
        Import-ScriptFunctions -Path $script:scriptPath
        $script:state = Get-DependencyFixtureStandIn -Existing -UnmarkedOrphan
        $script:asObjects = { param($Items) @($Items | ForEach-Object { $_ | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30 }) }
    }

    It 'plans the same objects, for <Label>' -ForEach @(
        @{ Label = 'every scenario'; Prefix = 'SacDep'; Scenario = $null; Clamp = '| where 1 == 0' }
        @{ Label = 'Hunt alone'; Prefix = 'Alpha'; Scenario = @('Hunt'); Clamp = '| where 1 == 0' }
        @{ Label = 'no clamp'; Prefix = 'Bravo99'; Scenario = @('Cycle', 'direct'); Clamp = '' }
    ) {
        $old = Get-FixtureNamingPlan -NamePrefix $Prefix -ScenarioName $Scenario -QueryClamp $Clamp
        $new = InModuleScope iSOCDeployments -Parameters @{ P = $Prefix; S = $Scenario; C = $Clamp } { param($P, $S, $C) Get-iSOCFixtureNamingPlan -NamePrefix $P -ScenarioName $S -QueryClamp $C }
        (ConvertTo-StandInCanonical $new) | Should -BeExactly (ConvertTo-StandInCanonical $old)
    }

    It 'judges ownership the same' {
        $tables = & $script:asObjects ((Invoke-DependencyFixtureArm -State $script:state -Method GET -Path "$($script:state.WorkspacePath)/tables").Body.value)
        $saved = & $script:asObjects $script:state.Saved.Values
        $rules = & $script:asObjects $script:state.Rules.Values
        $names = @('SacDepDirect_CL', 'SacDepOneHop_CL', 'SacDepOrphan_CL', 'SecOneHopParser')
        $ids = @((Get-FixtureNamingPlan -NamePrefix SacDep).Rule.RuleId)
        $old = [ordered]@{
            Tables = @($tables | ForEach-Object { Test-FixtureOwnedTable -Table $_ -ExpectedTableName $names })
            Saved  = @($saved | ForEach-Object { Test-FixtureOwnedSavedSearch -SavedSearch $_ -FixtureMarker $script:FixtureMarker })
            Rules  = @($rules | ForEach-Object { Test-FixtureOwnedAlertRule -AlertRule $_ -FixtureMarker $script:FixtureMarker -ExpectedRuleId $ids })
            Sub    = @($tables | ForEach-Object { Get-TableSubType -Table $_ })
        }
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
        (ConvertTo-StandInCanonical $new) | Should -BeExactly (ConvertTo-StandInCanonical $old)
        @($old.Tables) | Should -Contain $true
        @($old.Tables) | Should -Contain $false
        @($old.Rules) | Should -Contain $true
    }

    It 'guards aliases and decides actions the same' {
        $cases = @(@{ A = 'SigninLogs' }, @{ A = 'signinlogs' }, @{ A = 'OfficeActivity' }, @{ A = 'CollOneHopParser' }, @{ A = 'FreshParser' })
        $old = foreach ($c in $cases) { Get-AliasCollisionReason -Alias $c.A -WorkspaceTableName 'SigninLogs' -ReservedName 'OfficeActivity' -ForeignAlias 'CollOneHopParser' }
        $new = InModuleScope iSOCDeployments -Parameters @{ Cases = $cases } { param($Cases) foreach ($c in $Cases) { Get-iSOCAliasCollisionReason -Alias $c.A -WorkspaceTableName 'SigninLogs' -ReservedName 'OfficeActivity' -ForeignAlias 'CollOneHopParser' } }
        @($new) | Should -Be @($old)
        $acts = foreach ($e in $null, 'x') { foreach ($o in $true, $false) { foreach ($r in $true, $false) { Get-FixtureObjectAction -Existing $e -IsOwned $o -ForRemoval:$r } } }
        $newActs = InModuleScope iSOCDeployments { foreach ($e in $null, 'x') { foreach ($o in $true, $false) { foreach ($r in $true, $false) { Get-iSOCFixtureObjectAction -Existing $e -IsOwned $o -ForRemoval:$r } } } }
        @($newActs) | Should -Be @($acts)
    }

    It 'builds the same saved search and rule bodies and records' {
        $at = [datetime]::new(2026, 11, 4, 9, 0, 0, [System.DateTimeKind]::Utc)
        $old = [ordered]@{
            Saved   = New-SavedSearchBody -Category 'C' -DisplayName 'D' -Query 'Q' -FixtureMarker 'M' -RunId 'R' -ScenarioName 'S' -FunctionAlias 'A'
            Hunt    = New-SavedSearchBody -Category 'Hunting Queries' -DisplayName 'D' -Query 'Q' -FixtureMarker 'M' -RunId 'R' -ScenarioName 'S'
            Rule    = New-AlertRuleBody -DisplayName 'D' -Description 'X' -Query 'Q' -Enabled $true
            Records = New-DependencyFixtureRecord -Count 4 -ReferenceTime $at -Marker 'M|R' -ScenarioName 'OneHop'
            Id      = New-FixtureRuleId -NamePrefix 'SacDep' -ScenarioName 'TwoHop'
        }
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
        (ConvertTo-StandInCanonical $new) | Should -BeExactly (ConvertTo-StandInCanonical $old)
        $new.Id | Should -Be (Get-StandInRuleId -Prefix 'SacDep' -Scenario 'TwoHop')
    }
}

Describe 'Parity with New-DependencyFixture.ps1: <Label>' -ForEach $script:runs {
    BeforeAll {
        $standIn = @{ Existing = [bool]$Existing; UnmarkedOrphan = [bool]$UnmarkedOrphan; RaceOnce = [bool]$RaceOnce }
        $script:legacy = Invoke-LegacyFixture -Parameters $Parameters -Remove:([bool]$Remove) -StandIn $standIn
        $script:module = Invoke-ModuleFixture -Parameters $Parameters -Remove:([bool]$Remove) -StandIn $standIn
    }

    It 'runs the script and the command to the end' {
        $script:legacy.ExitCode | Should -Be 0 -Because $script:legacy.Output
        $script:module.Error | Should -BeNullOrEmpty
    }

    It 'makes the same writes, in order' {
        @($script:module.Writes | ForEach-Object { ConvertTo-StandInCanonical $_ }) | Should -Be @($script:legacy.Writes | ForEach-Object { ConvertTo-StandInCanonical $_ })
    }

    It 'returns the same result' {
        (ConvertTo-ComparableResult $script:module.Result) | Should -BeExactly (ConvertTo-ComparableResult $script:legacy.Result)
    }
}

Describe 'Refusing as New-DependencyFixture.ps1 does: <Label>' -ForEach $script:refusals {
    It 'refuses with the same message and writes nothing' {
        $standIn = @{ NotOnboarded = [bool]$NotOnboarded }
        $legacy = Invoke-LegacyFixture -Parameters $Parameters -StandIn $standIn
        $module = Invoke-ModuleFixture -Parameters $Parameters -StandIn $standIn
        $legacy.ExitCode | Should -Be 1
        $module.Error | Should -BeExactly $legacy.Error
        $legacy.Writes | Should -BeNullOrEmpty
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
