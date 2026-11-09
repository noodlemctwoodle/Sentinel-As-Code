#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for Get-iSOCTableMigrationImpact and Export-iSOCTableMigrationReport.

.DESCRIPTION
    Three layers:

      - Each pure helper (the KQL readers, alias safety, connector kinds, the
        playbook and workbook query readers, the JavaScript literal) is held
        to explicit expected values for a handful of representative inputs.
      - The impact analysis (alias index, direct and chained dependents,
        severed bridges, truncation, fan-out, solution matches) is run over
        one stand-in workspace and held to explicit expected dependents, at
        three chain depths.
      - The commands run over that workspace through a mocked REST client:
        the files they write, the dependents they find, the requests they
        send, and the report template they fill.

    Parity with Invoke-TableMigrationReview.ps1 was proven on
    release/26.11.0 before the script was removed.

.NOTES
    File:         Tests/iSOCDeployments/TableMigration.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeDiscovery {
    $script:impactCases = @(
        @{ Table = 'OfficeActivity_CL'; Depth = 1; Expected = @(
                'OfficeActivity_CL: 2 direct, 3 indirect, 5 affected, truncated True'
                'AnalyticsRules: Rule both (Enabled=True, Severity=Medium, DependencyKind=Direct)'
                'Parsers: OfficeActivityParser (FunctionAlias=OfficeActivityParser, DependencyKind=Direct)'
                'IndirectAnalyticsRules: Rule via parser (Enabled=True, Severity=High, DependencyKind=Indirect) via OfficeActivityParser, depth 1'
                'IndirectParsers: CycleA (FunctionAlias=CycleA, DependencyKind=Indirect) via OfficeActivityParser, depth 1'
                'IndirectParsers: OfficeWrapper (FunctionAlias=OfficeWrapper, DependencyKind=Indirect) via OfficeActivityParser, depth 1'
            )
        }
        @{ Table = 'OfficeActivity_CL'; Depth = 2; Expected = @(
                'OfficeActivity_CL: 2 direct, 12 indirect, 14 affected, truncated True'
                'AnalyticsRules: Rule both (Enabled=True, Severity=Medium, DependencyKind=Direct)'
                'Parsers: OfficeActivityParser (FunctionAlias=OfficeActivityParser, DependencyKind=Direct)'
                'IndirectAnalyticsRules: Rule via parser (Enabled=True, Severity=High, DependencyKind=Indirect) via OfficeActivityParser, depth 1'
                'IndirectAnalyticsRules: Rule quoted (Enabled=True, Severity=Medium, DependencyKind=Indirect) via OfficeWrapper -> OfficeActivityParser, depth 2'
                'IndirectAnalyticsRules: Rule via wrapper (Enabled=False, Severity=Medium, DependencyKind=Indirect) via OfficeWrapper -> OfficeActivityParser, depth 2'
                'IndirectHuntingQueries: Hunt wrapper (Category=Hunting Queries, DependencyKind=Indirect) via OfficeWrapper -> OfficeActivityParser, depth 2'
                'IndirectParsers: CycleA (FunctionAlias=CycleA, DependencyKind=Indirect) via OfficeActivityParser, depth 1'
                'IndirectParsers: OfficeWrapper (FunctionAlias=OfficeWrapper, DependencyKind=Indirect) via OfficeActivityParser, depth 1'
                'IndirectParsers: abc (FunctionAlias=, DependencyKind=Indirect) via OfficeWrapper -> OfficeActivityParser, depth 2'
                'IndirectParsers: CycleB (FunctionAlias=CycleB, DependencyKind=Indirect) via CycleA -> OfficeActivityParser, depth 2'
                'IndirectParsers: DeepOne (FunctionAlias=DeepOne, DependencyKind=Indirect) via OfficeWrapper -> OfficeActivityParser, depth 2'
                'IndirectWorkbooks: Inherited workbook (QueryCount=1, DependencyKind=Indirect) via OfficeWrapper -> OfficeActivityParser, depth 2'
                'IndirectWorkbooks: Office workbook (QueryCount=2, DependencyKind=Indirect) via OfficeWrapper -> OfficeActivityParser, depth 2'
                'IndirectPlaybooks: pb-query (State=Enabled, DependencyKind=Indirect) via OfficeWrapper -> OfficeActivityParser, depth 2'
                'UnresolvedBridges: abc (parser abc, 1 reference(s): SavedSearches/Uses abc) via OfficeWrapper -> OfficeActivityParser'
            )
        }
        @{ Table = 'OfficeActivity_CL'; Depth = 10; Expected = @(
                'OfficeActivity_CL: 2 direct, 14 indirect, 16 affected, truncated False'
                'AnalyticsRules: Rule both (Enabled=True, Severity=Medium, DependencyKind=Direct)'
                'Parsers: OfficeActivityParser (FunctionAlias=OfficeActivityParser, DependencyKind=Direct)'
                'IndirectAnalyticsRules: Rule via parser (Enabled=True, Severity=High, DependencyKind=Indirect) via OfficeActivityParser, depth 1'
                'IndirectAnalyticsRules: Rule quoted (Enabled=True, Severity=Medium, DependencyKind=Indirect) via OfficeWrapper -> OfficeActivityParser, depth 2'
                'IndirectAnalyticsRules: Rule via wrapper (Enabled=False, Severity=Medium, DependencyKind=Indirect) via OfficeWrapper -> OfficeActivityParser, depth 2'
                'IndirectHuntingQueries: Hunt wrapper (Category=Hunting Queries, DependencyKind=Indirect) via OfficeWrapper -> OfficeActivityParser, depth 2'
                'IndirectHuntingQueries: Hunt deeper (Category=Hunting Queries, DependencyKind=Indirect) via DeeperTwo -> DeepOne -> OfficeWrapper -> OfficeActivityParser, depth 4'
                'IndirectParsers: CycleA (FunctionAlias=CycleA, DependencyKind=Indirect) via OfficeActivityParser, depth 1'
                'IndirectParsers: OfficeWrapper (FunctionAlias=OfficeWrapper, DependencyKind=Indirect) via OfficeActivityParser, depth 1'
                'IndirectParsers: abc (FunctionAlias=, DependencyKind=Indirect) via OfficeWrapper -> OfficeActivityParser, depth 2'
                'IndirectParsers: CycleB (FunctionAlias=CycleB, DependencyKind=Indirect) via CycleA -> OfficeActivityParser, depth 2'
                'IndirectParsers: DeepOne (FunctionAlias=DeepOne, DependencyKind=Indirect) via OfficeWrapper -> OfficeActivityParser, depth 2'
                'IndirectParsers: DeeperTwo (FunctionAlias=DeeperTwo, DependencyKind=Indirect) via DeepOne -> OfficeWrapper -> OfficeActivityParser, depth 3'
                'IndirectWorkbooks: Inherited workbook (QueryCount=1, DependencyKind=Indirect) via OfficeWrapper -> OfficeActivityParser, depth 2'
                'IndirectWorkbooks: Office workbook (QueryCount=2, DependencyKind=Indirect) via OfficeWrapper -> OfficeActivityParser, depth 2'
                'IndirectPlaybooks: pb-query (State=Enabled, DependencyKind=Indirect) via OfficeWrapper -> OfficeActivityParser, depth 2'
                'UnresolvedBridges: abc (parser abc, 1 reference(s): SavedSearches/Uses abc) via OfficeWrapper -> OfficeActivityParser'
            )
        }
        @{ Table = 'MyApp_CL'; Depth = 10; Expected = @(
                'MyApp_CL: 8 direct, 0 indirect, 8 affected, truncated False'
                'AnalyticsRules: Rule on MyApp (Enabled=True, Severity=Medium, DependencyKind=Direct)'
                'AnalyticsRules: r-noname (Enabled=True, Severity=Medium, DependencyKind=Direct)'
                'Parsers: Update (FunctionAlias=Update, DependencyKind=Direct)'
                'SavedSearches: MyApp search (Category=General, DependencyKind=Direct)'
                'Workbooks: Office workbook (QueryCount=1, DependencyKind=Direct)'
                'Workbooks: Inherited workbook (QueryCount=1, DependencyKind=Direct)'
                'Playbooks: pb-direct (State=Disabled, DependencyKind=Direct)'
                'Dcrs: dcr-myapp (FlowCount=1, DependencyKind=Direct)'
                'UnresolvedBridges: Update (parser Update, 2 reference(s): AnalyticsRules/Rule on Update, SavedSearches/Update search)'
            )
        }
        @{ Table = 'MyApp_CL_v2'; Depth = 10; Expected = @(
                'MyApp_CL_v2: 2 direct, 0 indirect, 2 affected, truncated False'
                'AnalyticsRules: Rule on v2 (Enabled=True, Severity=Medium, DependencyKind=Direct)'
                'Parsers: Location (FunctionAlias=Location, DependencyKind=Direct)'
                'UnresolvedBridges: Location (parser Location, 2 reference(s): AnalyticsRules/Rule via parser, Parsers/OfficeActivityParser)'
            )
        }
        @{ Table = 'Okta_CL'; Depth = 10; Expected = @(
                'Okta_CL: 2 direct, 1 indirect, 3 affected, truncated False'
                'Parsers: OktaParser (FunctionAlias=OktaParser, DependencyKind=Direct)'
                'Workbooks: Office workbook (QueryCount=1, DependencyKind=Direct)'
                'IndirectAnalyticsRules: Okta rule (Enabled=True, Severity=Medium, DependencyKind=Indirect) via OktaParser, depth 1'
            )
        }
        @{ Table = 'Tenable_IE_CL'; Depth = 10; Expected = @(
                'Tenable_IE_CL: 0 direct, 0 indirect, 0 affected, truncated False'
            )
        }
        @{ Table = 'Lonely_CL'; Depth = 10; Expected = @(
                'Lonely_CL: 0 direct, 0 indirect, 0 affected, truncated False'
            )
        }
    )
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:helperPath = Join-Path $PSScriptRoot '_helpers/TableMigrationStandIn.psm1'
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module $script:helperPath -Force

    $script:standInPath = Join-Path $TestDrive 'standin.json'
    Set-Content -LiteralPath $script:standInPath -Value (ConvertTo-Json -InputObject (Get-TableMigrationStandIn) -Depth 30)
    $script:standIn = Get-Content -LiteralPath $script:standInPath -Raw | ConvertFrom-Json -Depth 30
    $script:sub = $script:standIn.subscriptionId

    $script:toJson = { param($Value) ConvertTo-Json -InputObject $Value -Depth 30 }

    function Invoke-ModuleReview {
        param($StandIn = $script:standIn, [string] $Path = (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))))
        $script:moduleStandIn = $StandIn
        $script:moduleRequests = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
            if ($Method -ne 'GET') { throw "The review sent a $Method" }
            $script:moduleRequests.Add("$Path $ApiVersion")
            $parts = $Path -split '\?', 2
            $query = @{}
            if ($parts.Count -gt 1) {
                foreach ($pair in $parts[1] -split '&') { $k, $v = $pair -split '=', 2; $query[$k] = [Uri]::UnescapeDataString($v) }
            }
            $answer = Get-TableMigrationStandInAnswer -StandIn $script:moduleStandIn -Path $parts[0] -Query $query
            if ($answer -is [System.Collections.IDictionary]) { return $answer.value }
            $answer
        }
        $ctx = InModuleScope iSOCDeployments -Parameters @{ Sub = $StandIn.subscriptionId } {
            param($Sub)
            New-iSOCContext -Value @{
                TenantId = 't'; SubscriptionId = $Sub; ResourceGroup = 'rg-sentinel'; WorkspaceName = 'law-sentinel'
                WorkspaceResourceId = "/subscriptions/$Sub/resourceGroups/rg-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-sentinel"
                WorkspaceId = 'w'; Region = 'uksouth'; PlaybookResourceGroup = 'rg-auto'; Environment = 'AzureCloud'; IsGov = $false
                ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'tester'
            }
        }
        $review = Get-iSOCTableMigrationImpact -Context $ctx
        $files = @($review | Export-iSOCTableMigrationReport -Path $Path)
        [pscustomobject]@{ Review = $review; Files = $files; Path = $Path; Requests = @($script:moduleRequests) }
    }

    function Format-ImpactLine {
        param($Impact)
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add(('{0}: {1} direct, {2} indirect, {3} affected, truncated {4}' -f $Impact.TableName, $Impact.TotalImpacted, $Impact.TotalIndirect, $Impact.TotalAffected, $Impact.ChainTruncated))
        foreach ($p in $Impact.PSObject.Properties) {
            if ($p.Name -in 'TableName', 'TotalImpacted', 'TotalIndirect', 'TotalAffected', 'ChainTruncated') { continue }
            foreach ($e in @($p.Value)) {
                if ($null -eq $e) { continue }
                if ($p.Name -eq 'UnresolvedBridges') {
                    $dependents = @($e.Dependents | ForEach-Object { "$($_.Type)/$($_.Name)" }) -join ', '
                    $line = "$($p.Name): $($e.Alias) (parser $($e.Parser), $($e.ReferenceCount) reference(s): $dependents)"
                    $chain = @($e.ViaChain) -join ' -> '
                    if ($chain) { $line += " via $chain" }
                    $lines.Add($line)
                    continue
                }
                $extra = @($e.PSObject.Properties | Where-Object { $_.Name -notin 'Name', 'ResourceId', 'Via', 'ViaChain', 'Depth' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', '
                $line = "$($p.Name): $($e.Name) ($extra)"
                if ($e.PSObject.Properties['ViaChain']) { $line += " via $(@($e.ViaChain) -join ' -> '), depth $($e.Depth)" }
                $lines.Add($line)
            }
        }
        $lines.ToArray()
    }

    function Format-AliasIndexLine {
        param($Index)
        $nodes = @($Index.Nodes)
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("Aliases: $(@($Index.Aliases) -join ', ')")
        foreach ($s in @($Index.SkippedAliases)) {
            if ($null -eq $s) { continue }
            $dependents = @($s.Dependents | ForEach-Object { "$($_.Type)/$($_.Name)" }) -join ', '
            $lines.Add("Skipped: $($s.Alias) (parser $($s.Parser), $($s.ReferenceCount) reference(s): $dependents): $($s.Reason)")
        }
        foreach ($map in 'References', 'ProviderIds') {
            $keys = [string[]]@($Index.$map.Keys)
            [Array]::Sort($keys, [StringComparer]::Ordinal)
            foreach ($k in $keys) {
                $ids = [int[]]@($Index.$map[$k])
                [Array]::Sort($ids)
                $names = foreach ($id in $ids) {
                    $n = $nodes | Where-Object { $_.Id -eq $id }
                    $count = if ($map -eq 'References' -and $n.MatchCounts -and $n.MatchCounts.ContainsKey($k)) { " x$($n.MatchCounts[$k])" } else { '' }
                    "$($n.Type)/$($n.Name)$count"
                }
                $lines.Add("${map}: $k -> $(@($names) -join ', ')")
            }
        }
        foreach ($w in @($Index.Warnings)) { if ($null -ne $w) { $lines.Add("Warning: $w") } }
        $lines.ToArray()
    }
}

Describe 'The KQL readers' {
    It 'reads each query to its code, names and references' {
        $cases = @(
            @{ Text = $null; Expected = '{"Code":"","Expanded":"","Search":"","Let":[],"Refs":[],"Names":false}' }
            @{ Text = "T | where Name == 'OfficeParser'"; Expected = '{"Code":"T | where Name ==  ","Expanded":"T | where Name == ''OfficeParser''","Search":"T | where Name ==  ","Let":[],"Refs":["Name","T","where"],"Names":true}' }
            @{ Text = "T // OfficeParser`nX"; Expected = '{"Code":"T  \nX","Expanded":"T // OfficeParser\nX","Search":"T  \nX","Let":[],"Refs":["T","X"],"Names":true}' }
            @{ Text = "`````` multi`nOfficeParser `````` Tail"; Expected = '{"Code":"  Tail","Expanded":"``` multi\nOfficeParser ``` Tail","Search":"  Tail","Let":[],"Refs":["Tail"],"Names":true}' }
            @{ Text = "['OfficeParser'] | take 1"; Expected = '{"Code":"[ ] | take 1","Expanded":" OfficeParser  | take 1","Search":"[ ] | take 1","Let":[],"Refs":["1","OfficeParser","take"],"Names":true}' }
            @{ Text = 'cluster("c").database("d").OfficeParser | take 1'; Expected = '{"Code":"cluster( ).database( ).OfficeParser | take 1","Expanded":"cluster(\"c\").database(\"d\").OfficeParser | take 1","Search":"  | take 1","Let":[],"Refs":["1","take"],"Names":true}' }
            @{ Text = 'T | extend OfficeParser = 1'; Expected = '{"Code":"T | extend OfficeParser = 1","Expanded":"T | extend OfficeParser = 1","Search":"T | extend   = 1","Let":[],"Refs":["1","T","extend"],"Names":true}' }
            @{ Text = 'let OfficeParser = T; OfficeParser'; Expected = '{"Code":"let OfficeParser = T; OfficeParser","Expanded":"let OfficeParser = T; OfficeParser","Search":"let   = T; OfficeParser","Let":["OfficeParser"],"Refs":["T","let"],"Names":true}' }
            @{ Text = 'T | where a != b and c <= d'; Expected = '{"Code":"T | where a != b and c <= d","Expanded":"T | where a != b and c <= d","Search":"T | where a != b and c <= d","Let":[],"Refs":["T","a","and","b","c","d","where"],"Names":false}' }
            @{ Text = 'OfficeParser_v2 | take 1'; Expected = '{"Code":"OfficeParser_v2 | take 1","Expanded":"OfficeParser_v2 | take 1","Search":"OfficeParser_v2 | take 1","Let":[],"Refs":["1","OfficeParser_v2","take"],"Names":false}' }
        )
        $new = InModuleScope iSOCDeployments -Parameters @{ Cases = $cases } {
            param($Cases)
            $ordinal = { param($Items) $a = [string[]]@($Items); [Array]::Sort($a, [StringComparer]::Ordinal); , $a }
            foreach ($c in $Cases) {
                $t = $c.Text
                ConvertTo-Json -Depth 5 -Compress -InputObject ([ordered]@{
                        Code     = Get-iSOCKqlCodeText -Text $t
                        Expanded = Expand-iSOCKqlQuotedIdentifier -Text $t
                        Search   = ConvertTo-iSOCKqlNameSearchText -Text (Get-iSOCKqlCodeText -Text $t)
                        Let      = & $ordinal (Get-iSOCKqlLetBoundName -Text $t)
                        Refs     = & $ordinal (Get-iSOCKqlReferenceIdentifierSet -Text @($t))
                        Names    = Test-iSOCKqlTableReference -Query $t -TableName 'OfficeParser'
                    })
            }
        }
        @($new).Count | Should -Be $cases.Count
        for ($i = 0; $i -lt $cases.Count; $i++) { @($new)[$i] | Should -BeExactly $cases[$i].Expected -Because "query $i" }
    }

    It 'judges each alias' {
        $cases = @(
            @{ Alias = $null; Minimum = 3; Expected = '{"Alias":"","IsSafe":false,"Reason":"alias is empty"}' }
            @{ Alias = '  '; Minimum = 3; Expected = '{"Alias":"","IsSafe":false,"Reason":"alias is empty"}' }
            @{ Alias = 'abc'; Minimum = 3; Expected = '{"Alias":"abc","IsSafe":true,"Reason":""}' }
            @{ Alias = 'abc'; Minimum = 4; Expected = '{"Alias":"abc","IsSafe":false,"Reason":"shorter than 4 characters, too generic to match safely"}' }
            @{ Alias = ' OfficeParser '; Minimum = 4; Expected = '{"Alias":"OfficeParser","IsSafe":true,"Reason":""}' }
            @{ Alias = 'Where'; Minimum = 3; Expected = '{"Alias":"Where","IsSafe":false,"Reason":"reserved KQL keyword, scoping function or universal Log Analytics column name"}' }
            @{ Alias = 'TimeGenerated'; Minimum = 4; Expected = '{"Alias":"TimeGenerated","IsSafe":false,"Reason":"reserved KQL keyword, scoping function or universal Log Analytics column name"}' }
            @{ Alias = '1abc'; Minimum = 3; Expected = '{"Alias":"1abc","IsSafe":false,"Reason":"not a plain KQL identifier, so a word-boundary match is not reliable"}' }
            @{ Alias = 'update'; Minimum = 4; Expected = '{"Alias":"update","IsSafe":false,"Reason":"collides with the workspace table ''Update'', so a query naming it far more likely means the table"}' }
            @{ Alias = 'Location'; Minimum = 3; Expected = '{"Alias":"Location","IsSafe":false,"Reason":"collides with the column name ''Location'', and a bare identifier in a column position cannot be told apart from a function call without a full KQL parser"}' }
        )
        $new = InModuleScope iSOCDeployments -Parameters @{ Cases = $cases } {
            param($Cases)
            foreach ($c in $Cases) { ConvertTo-Json -Compress -InputObject (Get-iSOCFunctionAliasSafety -Alias $c.Alias -MinimumLength $c.Minimum -WorkspaceTableName 'Update', 'SecurityEvent' -WorkspaceColumnName 'Location', 'Message') }
        }
        @($new).Count | Should -Be $cases.Count
        for ($i = 0; $i -lt $cases.Count; $i++) { @($new)[$i] | Should -BeExactly $cases[$i].Expected -Because "alias '$($cases[$i].Alias)' at $($cases[$i].Minimum)" }
        $reserved = @(
            'and', 'asc', 'between', 'bool', 'by', 'consume', 'contains', 'count', 'datatable', 'datetime', 'decimal', 'desc', 'distinct', 'dynamic', 'endswith', 'evaluate'
            'extend', 'externaldata', 'facet', 'false', 'find', 'fork', 'getschema', 'guid', 'has', 'in', 'int', 'invoke', 'join', 'let', 'limit', 'long', 'lookup', 'matches'
            'materialize', 'mvexpand', 'not', 'null', 'on', 'or', 'order', 'parse', 'partition', 'print', 'project', 'query', 'range', 'real', 'reduce', 'render', 'restrict'
            'sample', 'scan', 'search', 'serialize', 'set', 'sort', 'source', 'startswith', 'string', 'summarize', 'take', 'timespan', 'top', 'toscalar', 'true', 'union', 'view'
            'where', 'app', 'cluster', 'database', 'workspace', 'timegenerated', 'tenantid', 'sourcesystem', 'type', 'computer', 'rawdata', 'managementgroupname'
        )
        (& $script:toJson @(InModuleScope iSOCDeployments { Get-iSOCReservedAliasName })) | Should -BeExactly (& $script:toJson $reserved)
    }

    It 'classifies each connector' {
        $ids = @($null, 'OktaSSOv2', 'OktaSSO_Polling', 'FooCCPDefinition', 'X_Ccf_', 'AzureActiveDirectory', 'CEF', 'WindowsForwardedEventsAma', 'SomethingServerless', 'Random')
        $new = InModuleScope iSOCDeployments -Parameters @{ Ids = $ids } { param($Ids) foreach ($id in $Ids) { Resolve-iSOCConnectorKind -ConnectorId $id -SolutionName 'S' } }
        $new | Should -Be @('Unknown', 'Legacy', 'AzureFunctions', 'CCF', 'CCF', 'Platform', 'Agent', 'AMA', 'AzureFunctions', 'Legacy')
    }

    It 'reads the queries from each playbook and workbook' {
        $definitions = @($script:standIn.logicApps | ForEach-Object { $_.properties.PSObject.Properties['definition'] ? $_.properties.definition : $null })
        $data = @($script:standIn.workbooks.properties.serializedData) + @($null, '', '[]', '{"query":"a","items":[{"query":"b"},{"x":{"query":5}}]}')
        $new = InModuleScope iSOCDeployments -Parameters @{ Definitions = $definitions; Data = $data } {
            param($Definitions, $Data)
            [ordered]@{
                Playbooks = @($Definitions | ForEach-Object { , @(Get-iSOCPlaybookKqlText -Definition $_ | Sort-Object -CaseSensitive) })
                Workbooks = @($Data | ForEach-Object { , @(Get-iSOCWorkbookQueryText -SerializedData $_) })
            }
        }
        (ConvertTo-Json -InputObject $new -Depth 30 -Compress) | Should -BeExactly '{"Playbooks":[["OfficeWrapper | where Message has \"x\""],[],["MyApp_CL | take 1"],[]],"Workbooks":[["OfficeWrapper | count","MyApp_CL | take 1","Okta_CL | take 1","OfficeWrapper | take 3"],["MyApp_CL | summarize count()","OfficeWrapper | take 3"],[],[],[],[],["a","b"]]}'
    }

    It 'escapes each string for the page' {
        $values = @('', 'plain', '</script><b>', "line$([char]0x2028)sep$([char]0x2029)end", 'quote " back \ end', "tab`tnew`nend")
        $new = InModuleScope iSOCDeployments -Parameters @{ Values = $values } { param($Values) foreach ($v in $Values) { ConvertTo-iSOCJsStringLiteral -Value $v } }
        $new | Should -BeExactly @('', 'plain', '\u003c/script\u003e\u003cb\u003e', 'line\u2028sep\u2029end', 'quote \" back \\ end', 'tab\tnew\nend')
    }
}

Describe 'The impact analysis' {
    BeforeAll {
        $script:content = ConvertTo-TableMigrationContent -StandIn $script:standIn
        $script:tableNames = @($script:standIn.tables.name)
        $script:columnNames = @($script:standIn.tables | ForEach-Object { if ($_.properties.schema.PSObject.Properties['columns']) { $_.properties.schema.columns.name } } | Sort-Object -Unique)
        $script:classic = @('OfficeActivity_CL', 'MyApp_CL', 'MyApp_CL_v2', 'Okta_CL', 'Tenable_IE_CL', 'Lonely_CL')

        $script:analyseNew = {
            param($Content, [int] $Depth)
            InModuleScope iSOCDeployments -Parameters @{ Content = $Content; Depth = $Depth; Tables = $script:tableNames; Columns = $script:columnNames; Classic = $script:classic } {
                param($Content, $Depth, $Tables, $Columns, $Classic)
                $index = Get-iSOCParserAliasIndex -Content $Content -WorkspaceTableName $Tables -WorkspaceColumnName $Columns
                [ordered]@{
                    Index   = $index
                    Impacts = @(foreach ($t in $Classic) { Get-iSOCTableImpactAnalysis -TableName $t -Content $Content -AliasIndex $index -MaxDepth $Depth })
                }
            }
        }
    }

    It 'indexes the parser aliases, and sets aside the ones it cannot follow' {
        $expected = @(
            'Aliases: CycleA, CycleB, DeepOne, DeeperTwo, OfficeActivityParser, OfficeWrapper, OktaParser'
            'Skipped: Update (parser Update Parser, 2 reference(s): AnalyticsRules/Rule on Update, SavedSearches/Update search): collides with the workspace table ''Update'', so a query naming it far more likely means the table'
            'Skipped: Location (parser Location Parser, 2 reference(s): AnalyticsRules/Rule via parser, Parsers/OfficeActivityParser): collides with the column name ''Location'', and a bare identifier in a column position cannot be told apart from a function call without a full KQL parser'
            'Skipped: abc (parser Short Parser, 1 reference(s): SavedSearches/Uses abc): shorter than 4 characters, too generic to match safely'
            'References: CycleA -> Parsers/CycleB x1'
            'References: CycleB -> Parsers/CycleA x1'
            'References: DeepOne -> Parsers/DeeperTwo x1'
            'References: DeeperTwo -> HuntingQueries/Hunt deeper x1'
            'References: OfficeActivityParser -> AnalyticsRules/Rule via parser x1, AnalyticsRules/Rule both x1, Parsers/OfficeWrapper x1, Parsers/CycleA x1'
            'References: OfficeWrapper -> AnalyticsRules/Rule via wrapper x1, AnalyticsRules/Rule quoted x1, HuntingQueries/Hunt wrapper x1, Parsers/DeepOne x1, Parsers/abc x1, Workbooks/Office workbook x2, Workbooks/Inherited workbook x1, Playbooks/pb-query x1'
            'References: OktaParser -> AnalyticsRules/Okta rule x1'
            'ProviderIds: CycleA -> Parsers/CycleA'
            'ProviderIds: CycleB -> Parsers/CycleB'
            'ProviderIds: DeepOne -> Parsers/DeepOne'
            'ProviderIds: DeeperTwo -> Parsers/DeeperTwo'
            'ProviderIds: OfficeActivityParser -> Parsers/OfficeActivityParser'
            'ProviderIds: OfficeWrapper -> Parsers/OfficeWrapper'
            'ProviderIds: OktaParser -> Parsers/OktaParser'
        )
        ((Format-AliasIndexLine (& $script:analyseNew $script:content 10).Index) -join "`n") | Should -BeExactly ($expected -join "`n")
        ((Format-AliasIndexLine (& $script:analyseNew $script:content 1).Index) -join "`n") | Should -BeExactly ($expected -join "`n")
    }

    It 'finds the dependents of <Table>, <Depth> hop(s) deep' -ForEach $script:impactCases {
        $impact = (& $script:analyseNew $script:content $Depth).Impacts | Where-Object TableName -eq $Table
        ((Format-ImpactLine $impact) -join "`n") | Should -BeExactly ($Expected -join "`n")
    }

    It 'has a workspace that reaches every case the analysis handles' {
        $result = & $script:analyseNew $script:content 10
        $office = $result.Impacts | Where-Object TableName -eq 'OfficeActivity_CL'
        ($office.IndirectAnalyticsRules.Name) | Should -Contain 'Rule via wrapper'
        ($office.IndirectAnalyticsRules.Name) | Should -Contain 'Rule quoted'
        ($office.IndirectAnalyticsRules.Name) | Should -Not -Contain 'Rule with comment'
        ($office.IndirectAnalyticsRules.Name) | Should -Not -Contain 'Rule cross workspace'
        ($office.IndirectAnalyticsRules.Name) | Should -Not -Contain 'Rule both'
        ($office.AnalyticsRules.Name) | Should -Contain 'Rule both'
        ($office.IndirectHuntingQueries.Name) | Should -Contain 'Hunt deeper'
        ($office.IndirectHuntingQueries.Name) | Should -Not -Contain 'Hunt case'
        ($office.IndirectSavedSearches.Name) | Should -Not -Contain 'Shadowed'
        ($office.IndirectWorkbooks.Name) | Should -Contain 'Office workbook'
        ($office.IndirectPlaybooks.Name) | Should -Contain 'pb-query'
        ($office.IndirectPlaybooks.Name) | Should -Not -Contain 'pb-key'
        @($office.IndirectDcrs).Count | Should -Be 0
        ($office.UnresolvedBridges.Alias) | Should -Contain 'abc'
        ($result.Impacts | Where-Object TableName -eq 'MyApp_CL').UnresolvedBridges.Alias | Should -Contain 'Update'
        ($result.Impacts | Where-Object TableName -eq 'MyApp_CL_v2').UnresolvedBridges.Alias | Should -Contain 'Location'
        ($result.Impacts | Where-Object TableName -eq 'MyApp_CL').Dcrs.Name | Should -Contain 'dcr-myapp'
        (& $script:analyseNew $script:content 1).Impacts | Where-Object ChainTruncated | Should -Not -BeNullOrEmpty
    }

    It 'warns of an alias most of the workspace names' {
        $hub = [pscustomobject]@{ id = '/x/savedSearches/hub'; name = 'hub'; properties = [pscustomobject]@{ displayName = 'Hub'; category = 'Parsers'; functionAlias = 'HubParser'; query = 'OfficeActivity_CL' } }
        $rules = @(foreach ($n in 1..60) {
                $q = if ($n -le 25) { 'HubParser | take 1' } else { 'SecurityEvent | take 1' }
                [pscustomobject]@{ id = "/x/alertRules/r$n"; name = "r$n"; properties = [pscustomobject]@{ displayName = "Rule $n"; query = $q; enabled = $true; severity = 'Low' } }
            })
        $fan = [pscustomobject]@{ AlertRules = $rules; SavedSearches = @($hub); HuntingQueries = @(); Parsers = @($hub); Workbooks = @(); Dcrs = @(); Playbooks = @() }
        $new = & $script:analyseNew $fan 10
        @($new.Index.Warnings) | Should -HaveCount 1
        $expectedIndex = @(
            'Aliases: HubParser'
            'References: HubParser -> ' + (@(1..25 | ForEach-Object { "AnalyticsRules/Rule $_ x1" }) -join ', ')
            'ProviderIds: HubParser -> Parsers/HubParser'
            'Warning: Parser alias ''HubParser'' is referenced by 25 of 61 content items (41%) - treat the chains it produces as suspect'
        )
        $expectedImpacts = @(
            'OfficeActivity_CL: 1 direct, 25 indirect, 26 affected, truncated False'
            'Parsers: HubParser (FunctionAlias=HubParser, DependencyKind=Direct)'
            @(@(1) + (10..19) + @(2) + (20..25) + (3..9)) | ForEach-Object { "IndirectAnalyticsRules: Rule $_ (Enabled=True, Severity=Low, DependencyKind=Indirect) via HubParser, depth 1" }
            'MyApp_CL: 0 direct, 0 indirect, 0 affected, truncated False'
            'MyApp_CL_v2: 0 direct, 0 indirect, 0 affected, truncated False'
            'Okta_CL: 0 direct, 0 indirect, 0 affected, truncated False'
            'Tenable_IE_CL: 0 direct, 0 indirect, 0 affected, truncated False'
            'Lonely_CL: 0 direct, 0 indirect, 0 affected, truncated False'
        )
        ((Format-AliasIndexLine $new.Index) -join "`n") | Should -BeExactly ($expectedIndex -join "`n")
        (@($new.Impacts | ForEach-Object { Format-ImpactLine $_ }) -join "`n") | Should -BeExactly ($expectedImpacts -join "`n")
    }

    It 'finds only direct dependents when the workspace has no parsers at all' {
        $none = [pscustomobject]@{ AlertRules = $script:content.AlertRules; SavedSearches = @(); HuntingQueries = @(); Parsers = @(); Workbooks = $script:content.Workbooks; Dcrs = $script:content.Dcrs; Playbooks = $script:content.Playbooks }
        $new = & $script:analyseNew $none 10
        $expected = @(
            'OfficeActivity_CL: 1 direct, 0 indirect, 1 affected, truncated False'
            'AnalyticsRules: Rule both (Enabled=True, Severity=Medium, DependencyKind=Direct)'
            'MyApp_CL: 6 direct, 0 indirect, 6 affected, truncated False'
            'AnalyticsRules: Rule on MyApp (Enabled=True, Severity=Medium, DependencyKind=Direct)'
            'AnalyticsRules: r-noname (Enabled=True, Severity=Medium, DependencyKind=Direct)'
            'Workbooks: Office workbook (QueryCount=1, DependencyKind=Direct)'
            'Workbooks: Inherited workbook (QueryCount=1, DependencyKind=Direct)'
            'Playbooks: pb-direct (State=Disabled, DependencyKind=Direct)'
            'Dcrs: dcr-myapp (FlowCount=1, DependencyKind=Direct)'
            'MyApp_CL_v2: 1 direct, 0 indirect, 1 affected, truncated False'
            'AnalyticsRules: Rule on v2 (Enabled=True, Severity=Medium, DependencyKind=Direct)'
            'Okta_CL: 1 direct, 0 indirect, 1 affected, truncated False'
            'Workbooks: Office workbook (QueryCount=1, DependencyKind=Direct)'
            'Tenable_IE_CL: 0 direct, 0 indirect, 0 affected, truncated False'
            'Lonely_CL: 0 direct, 0 indirect, 0 affected, truncated False'
        )
        ((Format-AliasIndexLine $new.Index) -join "`n") | Should -BeExactly 'Aliases: '
        (@($new.Impacts | ForEach-Object { Format-ImpactLine $_ }) -join "`n") | Should -BeExactly ($expected -join "`n")
    }

    It 'maps each table to the solutions the shipped mapping names, and their connector kinds' {
        $packages = @($script:standIn.contentProductPackages | ForEach-Object { $_ | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20 })
        $raw = Get-Content -LiteralPath (Join-Path $script:repoRoot 'Modules/iSOCDeployments/Resources/ClassicToDcr/solution-mapping.json') -Raw | ConvertFrom-Json -AsHashtable -Depth 20
        $byTable = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($k in $raw['tablesToSolutions'].Keys) { $byTable[$k] = $raw['tablesToSolutions'][$k] }
        $byTable.Count | Should -BeGreaterThan 0
        $solutionPackages = @($packages | Where-Object { $_.properties.contentKind -eq 'Solution' })
        $connectorKind = @{ 'Office365' = 'Platform'; 'OktaSSO_Polling' = 'AzureFunctions'; 'TenableIECCPDefinition' = 'CCF' }
        $tables = @($script:classic) + @('SacNoSuchTable_CL')

        $expected = foreach ($t in $tables) {
            $names = @()
            $found = $null
            if ($byTable.TryGetValue($t, [ref] $found)) { $names = @($found) }
            if ($names.Count -eq 0 -and $byTable.TryGetValue(($t -replace '_CL$', ''), [ref] $found)) { $names = @($found) }
            $solutions = @()
            $kinds = @()
            foreach ($name in $names) {
                $pkg = $solutionPackages | Where-Object { $_.properties.displayName -eq $name } | Select-Object -First 1
                $meta = $raw['solutionMetadata'][$name]
                $solutions += [ordered]@{
                    SolutionName   = $name
                    IsInstalled    = [bool]($pkg -and $pkg.properties.PSObject.Properties['installedVersion'] -and $pkg.properties.installedVersion)
                    IsInContentHub = [bool]$pkg
                    GithubUrl      = if ($meta) { $meta['githubUrl'] } else { $null }
                    DisplayName    = if ($pkg) { $pkg.properties.displayName } else { $name }
                }
                $kind = 'Unknown'
                if ($pkg -and $pkg.properties.PSObject.Properties['dependencies']) {
                    $connector = @($pkg.properties.dependencies.criteria | Where-Object { $_.kind -eq 'DataConnector' -and $_.contentId }) | Select-Object -First 1
                    if ($connector) { $kind = $connectorKind[$connector.contentId] }
                }
                $kinds += [ordered]@{ SolutionName = $name; ConnectorKind = $kind }
            }
            ConvertTo-Json -Depth 30 -Compress -InputObject ([ordered]@{ Match = [ordered]@{ TableName = $t; MatchCount = $solutions.Count; Solutions = @($solutions) }; Kinds = @($kinds) })
        }

        $new = InModuleScope iSOCDeployments -Parameters @{ Packages = $packages; Tables = $tables } {
            param($Packages, $Tables)
            $mapping = Get-iSOCSolutionMapping
            foreach ($t in $Tables) { [ordered]@{ Match = Get-iSOCSolutionMatch -TableName $t -StaticMapping $mapping -Packages $Packages; Kinds = @(Get-iSOCConnectorClassification -TableName $t -StaticMapping $mapping -Packages $Packages) } }
        }
        @($new).Count | Should -Be $tables.Count
        for ($i = 0; $i -lt $tables.Count; $i++) {
            (ConvertTo-Json -InputObject @($new)[$i] -Depth 30 -Compress) | Should -BeExactly @($expected)[$i] -Because $tables[$i]
        }
        $absent = @($new)[-1]
        $absent.Match.MatchCount | Should -Be 0
        @($absent.Match.Solutions) | Should -BeNullOrEmpty
        @($absent.Kinds) | Should -BeNullOrEmpty
    }

    It 'returns a table''s solutions in the mapping''s order, looked up without case and then without _CL' {
        $packages = @($script:standIn.contentProductPackages | ForEach-Object { $_ | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20 })
        $tenableUrl = 'https://github.com/Azure/Azure-Sentinel/blob/master/Solutions/TenableAD'
        $m365Url = 'https://github.com/Azure/Azure-Sentinel/blob/master/Solutions/Microsoft%20365'
        $file = Join-Path $TestDrive 'solution-mapping-fixed.json'
        Set-Content -LiteralPath $file -Value (ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
                    tablesToSolutions = [ordered]@{ 'Fixed_CL' = @('TenableAD', 'Okta Single Sign-On', 'Microsoft 365', 'Not In Hub'); 'Bare' = @('microsoft 365') }
                    solutionMetadata  = [ordered]@{ 'TenableAD' = [ordered]@{ githubUrl = $tenableUrl }; 'Microsoft 365' = [ordered]@{ githubUrl = $m365Url } }
                }))
        $run = InModuleScope iSOCDeployments -Parameters @{ File = $file; Packages = $packages } {
            param($File, $Packages)
            $mapping = Get-iSOCSolutionMapping -Path $File
            [ordered]@{
                Fixed       = Get-iSOCSolutionMatch -TableName 'Fixed_CL' -StaticMapping $mapping -Packages $Packages
                Lower       = Get-iSOCSolutionMatch -TableName 'fixed_cl' -StaticMapping $mapping -Packages $Packages
                Bare        = Get-iSOCSolutionMatch -TableName 'Bare_CL' -StaticMapping $mapping -Packages $Packages
                Absent      = Get-iSOCSolutionMatch -TableName 'Absent_CL' -StaticMapping $mapping -Packages $Packages
                Kinds       = @(Get-iSOCConnectorClassification -TableName 'Fixed_CL' -StaticMapping $mapping -Packages $Packages)
                AbsentKinds = @(Get-iSOCConnectorClassification -TableName 'Absent_CL' -StaticMapping $mapping -Packages $Packages)
            }
        }
        $run.Fixed.MatchCount | Should -Be 4
        @($run.Fixed.Solutions | ForEach-Object { $_.SolutionName }) | Should -BeExactly @('TenableAD', 'Okta Single Sign-On', 'Microsoft 365', 'Not In Hub')
        @($run.Fixed.Solutions | ForEach-Object { $_.IsInContentHub }) | Should -Be @($true, $true, $true, $false)
        @($run.Fixed.Solutions | ForEach-Object { $_.IsInstalled }) | Should -Be @($true, $false, $true, $false)
        @($run.Fixed.Solutions | ForEach-Object { [string]$_.GithubUrl }) | Should -BeExactly @($tenableUrl, '', $m365Url, '')
        @($run.Fixed.Solutions | ForEach-Object { $_.DisplayName }) | Should -BeExactly @('TenableAD', 'Okta Single Sign-On', 'Microsoft 365', 'Not In Hub')
        @($run.Kinds | ForEach-Object { "$($_.SolutionName)=$($_.ConnectorKind)" }) | Should -BeExactly @('TenableAD=CCF', 'Okta Single Sign-On=AzureFunctions', 'Microsoft 365=Platform', 'Not In Hub=Unknown')
        (ConvertTo-Json -InputObject @($run.Lower.Solutions) -Depth 5 -Compress) | Should -BeExactly (ConvertTo-Json -InputObject @($run.Fixed.Solutions) -Depth 5 -Compress)
        @($run.Bare.Solutions | ForEach-Object { $_.SolutionName }) | Should -BeExactly @('microsoft 365')
        $run.Bare.Solutions[0].IsInContentHub | Should -BeTrue
        $run.Bare.Solutions[0].DisplayName | Should -BeExactly 'Microsoft 365'
        $run.Absent.MatchCount | Should -Be 0
        @($run.Absent.Solutions) | Should -BeNullOrEmpty
        @($run.AbsentKinds) | Should -BeNullOrEmpty
    }
}

Describe 'A review of the stand-in workspace' {
    BeforeAll {
        $script:module = Invoke-ModuleReview
    }

    It 'returns the five files it wrote' {
        @($script:module.Files.Name) | Should -Be @('tables.csv', 'impact.csv', 'solution-matches.csv', 'report.json', 'report.html')
    }

    It 'finds dependents of every kind, direct and through parsers' {
        $rows = @(Import-Csv -LiteralPath (Join-Path $script:module.Path 'impact.csv'))
        foreach ($type in 'AnalyticsRules', 'HuntingQueries', 'Parsers', 'SavedSearches', 'Workbooks', 'Playbooks', 'Dcrs') {
            @($rows | Where-Object ContentType -eq $type) | Should -Not -BeNullOrEmpty -Because "a $type dependent is in the workspace"
        }
        @($rows | Where-Object DependencyKind -eq 'Indirect') | Should -Not -BeNullOrEmpty
        ($rows | Where-Object { $_.Name -eq 'Rule via wrapper' }).ViaChain | Should -Be 'OfficeWrapper -> OfficeActivityParser -> OfficeActivity_CL'
    }

    It 'reads a workbook the list returns without content on its own, and finds what it names' {
        $script:module.Requests | Should -Contain "/subscriptions/$($script:sub)/resourceGroups/rg-sentinel/providers/Microsoft.Insights/workbooks/wb-inherited?canFetchContent=true 2022-04-01"
        $rows = @(Import-Csv -LiteralPath (Join-Path $script:module.Path 'impact.csv'))
        @($rows | Where-Object { $_.TableName -eq 'MyApp_CL' -and $_.Name -eq 'Inherited workbook' }) | Should -HaveCount 1
    }

    It 'reads with GET only, at the module''s api-versions' {
        $script:module.Requests | Should -Contain "/subscriptions/$($script:sub)/resourceGroups/rg-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-sentinel/tables 2022-10-01"
        $script:module.Requests | Should -Contain "/subscriptions/$($script:sub)/providers/Microsoft.Insights/dataCollectionRules 2023-03-11"
        $script:module.Requests | Should -Contain "/subscriptions/$($script:sub)/providers/Microsoft.Insights/workbooks?category=sentinel&canFetchContent=true 2022-04-01"
    }
}

Describe 'Get-iSOCTableMigrationImpact and Export-iSOCTableMigrationReport' {
    BeforeAll {
        $script:one = $script:standIn | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        $script:one.tables = @($script:one.tables | Where-Object { $_.name -ne 'MyApp_CL' -and $_.name -notlike 'Okta*' -and $_.name -notlike 'Tenable*' -and $_.name -notlike 'Lonely*' -and $_.name -ne 'MyApp_CL_v2' })
    }

    It 'returns a review with each list a list, even for one classic table' {
        $run = Invoke-ModuleReview -StandIn $script:one
        @($run.Review.ClassicTables) | Should -HaveCount 1
        $json = Get-Content -LiteralPath (Join-Path $run.Path 'report.json') -Raw
        $json | Should -Match '"solutionMatches":\s*\['
        $run.Review.PSObject.TypeNames | Should -Contain 'iSOCDeployments.TableMigrationReview'
        $run.Review.DirectCount | Should -BeGreaterThan 0
    }

    It 'writes nothing for a workspace with no classic tables' {
        $none = $script:standIn | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        $none.tables = @($none.tables | Where-Object { $_.properties.schema.tableSubType -ne 'Classic' })
        $path = Join-Path $TestDrive 'none'
        $run = Invoke-ModuleReview -StandIn $none -Path $path
        @($run.Review.ClassicTables) | Should -HaveCount 0
        $run.Files | Should -BeNullOrEmpty
        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It 'writes nothing under -WhatIf' {
        $run = Invoke-ModuleReview
        $path = Join-Path $TestDrive 'whatif'
        $run.Review | Export-iSOCTableMigrationReport -Path $path -WhatIf | Should -BeNullOrEmpty
        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It 'refuses anything but a review' {
        { [pscustomobject]@{ ClassicTables = @(1) } | Export-iSOCTableMigrationReport -Path (Join-Path $TestDrive 'x') } | Should -Throw '*Get-iSOCTableMigrationImpact*'
    }

    It 'counts an empty list as empty, where the script counted its response as one nameless item' {
        $empty = $script:standIn | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        $empty.logicApps = @()
        $empty.alertRules = @()
        $run = Invoke-ModuleReview -StandIn $empty
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Message -match 'Analytics Rules : 0$' } -Times 1 -Exactly
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Message -match 'Playbooks       : 0$' } -Times 1 -Exactly
        $office = $run.Review.Impacts | Where-Object TableName -eq 'OfficeActivity_CL'
        @($office.Playbooks) + @($office.IndirectPlaybooks) + @($office.AnalyticsRules) + @($office.IndirectAnalyticsRules) | Should -BeNullOrEmpty
    }
}

Describe 'The module''s report template' {
    BeforeAll {
        $script:tplPath = Join-Path $script:repoRoot 'Modules/iSOCDeployments/Resources/ClassicToDcr/report.html.template'
        $script:tplText = Get-Content -LiteralPath $script:tplPath -Raw
    }

    It 'offers the module''s commands, not the script' {
        $script:tplText | Should -Match ([regex]::Escape("'Invoke-iSOCClassicTableMigration -TableName '"))
        $script:tplText | Should -Match ([regex]::Escape("'Connect-iSOCWorkspace'"))
        $script:tplText | Should -Not -Match 'Invoke-ClassicTableMigration\.ps1'
        $script:tplText | Should -Not -Match 'Tools/ClassicToDcr'
    }

    It 'shows the module version in its badge' {
        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1')
        [regex]::Match($script:tplText, 'v([0-9]+\.[0-9]+\.[0-9]+) &middot; iSOCDeployments').Groups[1].Value | Should -BeExactly $manifest.ModuleVersion
    }

    It 'escapes every character that closes a PowerShell single-quoted string' {
        $script:tplText | Should -Match 'CMD_PS_QUOTES'
        foreach ($cp in '2018', '2019', '201a', '201b') { $script:tplText | Should -Match ('\\u' + $cp) }
    }

    It 'never offers -Force or -Confirm:$false' {
        $script:tplText | Should -Not -Match '-Force'
        $script:tplText | Should -Not -Match 'Confirm:\$false'
    }

    It 'offers a command only for a table name the migration accepts, and pins only a GUID subscription' {
        $script:tplText | Should -Match 'CMD_TABLE_NAME'
        $script:tplText | Should -Match '_CL'
        $script:tplText | Should -Match 'CMD_GUID'
    }

    It 'wires the copy button by delegation and reads the rendered text' {
        $copyMarkup = [regex]::Match($script:tplText, '<button[^>]*cmd-copy[^>]*>').Value
        $copyMarkup | Should -Not -BeNullOrEmpty
        $copyMarkup | Should -Not -Match 'onclick'
        $script:tplText | Should -Match 'addEventListener'
        $script:tplText | Should -Match 'textContent'
        $script:tplText | Should -Not -Match 'data-command'
    }

    It 'stays self-contained' {
        $script:tplText | Should -Not -Match '<script[^>]+src='
        $script:tplText | Should -Not -Match '<link[^>]+href="https?:'
        $script:tplText | Should -Not -Match 'fetch\('
        $script:tplText | Should -Not -Match 'XMLHttpRequest'
    }

    It 'counts chained dependents with direct ones and shows where the lists stop' {
        $script:tplText | Should -Match "ensureArray\(i\['Indirect' \+ k\]\)"
        $script:tplText | Should -Match 'var affectedCount = directCount \+ indirectCount'
        $script:tplText | Should -Match 'impact\.ChainTruncated'
        $script:tplText | Should -Match '(?m)^renderResolverCoverage\(\);'
        $script:tplText | Should -Match 'could not be followed'
        $script:tplText | Should -Match 'still reported in full'
    }
}
