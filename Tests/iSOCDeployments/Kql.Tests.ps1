#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the KQL dependency helpers the module copied from
    Sentinel.Common.

.DESCRIPTION
    Two layers:

    - the KQL cases from Tests/Test-SentinelCommon.Tests.ps1, carried over
      against the module's helpers;
    - Get-iSOCContentKqlQuery with Get-iSOCQueryDependency over one file
      of each content shape (YAML rules, a parser, a JSON summary rule, a
      Defender detection and files with no readable query), held to
      explicit buckets.

    Parity with Sentinel.Common, function by function and over every file
    under Content/, was proven on release/26.11.0 before it was removed.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Kql.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Kql.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.3.0
    Last Updated: 2026-11-05
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module powershell-yaml -ErrorAction Stop

    function Get-FileDependency {
        param([string] $Path, [hashtable] $KnownFunctions)
        InModuleScope iSOCDeployments -Parameters @{ P = $Path; K = $KnownFunctions } {
            param($P, $K)
            Get-iSOCQueryDependency -Query (Get-iSOCContentKqlQuery -Path $P) -KnownFunctions $K
        }
    }

    function Invoke-Kql {
        param([string] $Command, [hashtable] $Parameters)
        InModuleScope iSOCDeployments -Parameters @{ C = $Command; P = $Parameters } { param($C, $P) & $C @P }
    }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Remove-iSOCKqlComment' {
    It 'strips // line comments to end of line' {
        Invoke-Kql Remove-iSOCKqlComment @{ Query = "SecurityAlert`n| where x == 1 // ignore me`n| take 1" } | Should -Not -Match 'ignore me'
    }

    It 'preserves URLs containing ://' {
        Invoke-Kql Remove-iSOCKqlComment @{ Query = 'let url = "https://foo.com/path"; print url' } | Should -Match 'https://foo.com/path'
    }

    It 'strips /* block */ comments including across newlines' {
        $result = Invoke-Kql Remove-iSOCKqlComment @{ Query = "SecurityAlert`n/* multi-line`n   block comment */`n| take 1" }
        $result | Should -Not -Match 'block comment'
        $result | Should -Match 'SecurityAlert'
        $result | Should -Match 'take 1'
    }

    It 'returns the input unchanged when no comments are present' {
        $kql = 'SecurityAlert | where Severity == "High" | take 1'
        Invoke-Kql Remove-iSOCKqlComment @{ Query = $kql } | Should -Be $kql
    }
}

Describe 'Get-iSOCKqlWatchlistReference' {
    It "extracts a single _GetWatchlist('alias') reference" {
        @(Invoke-Kql Get-iSOCKqlWatchlistReference @{ Query = "let bg = _GetWatchlist('breakGlassAccounts'); SigninLogs | where x in (bg)" }) | Should -Be @('breakGlassAccounts')
    }

    It 'extracts double-quoted alias forms' {
        @(Invoke-Kql Get-iSOCKqlWatchlistReference @{ Query = '_GetWatchlist("DoubleQuoted")' }) | Should -Be @('DoubleQuoted')
    }

    It 'deduplicates aliases referenced multiple times' {
        @(Invoke-Kql Get-iSOCKqlWatchlistReference @{ Query = "_GetWatchlist('Foo') | union (_GetWatchlist('Foo'))" }).Count | Should -Be 1
    }

    It 'returns multiple aliases sorted' {
        @(Invoke-Kql Get-iSOCKqlWatchlistReference @{ Query = "_GetWatchlist('Zoo') | union (_GetWatchlist('Apple'), _GetWatchlist('Mango'))" }) | Should -Be @('Apple', 'Mango', 'Zoo')
    }

    It 'returns nothing for queries with no _GetWatchlist calls, or only commented ones' {
        @(Invoke-Kql Get-iSOCKqlWatchlistReference @{ Query = 'SecurityAlert | take 1' }).Count | Should -Be 0
        @(Invoke-Kql Get-iSOCKqlWatchlistReference @{ Query = "// _GetWatchlist('Commented') is ignored`nSecurityAlert" }).Count | Should -Be 0
    }
}

Describe 'Get-iSOCKqlExternalDataReference' {
    It 'extracts a URL from a single externaldata block' {
        $kql = "externaldata(col1: string)`n    [`"https://example.com/feed.json`"] with(format='multijson')"
        @(Invoke-Kql Get-iSOCKqlExternalDataReference @{ Query = $kql }) | Should -Be @('https://example.com/feed.json')
    }

    It 'extracts multiple URLs from a single bracket list' {
        $kql = "externaldata(col1: string)`n    [`"https://a.example/feed`", `"https://b.example/feed`"] with(format='multijson')"
        @(Invoke-Kql Get-iSOCKqlExternalDataReference @{ Query = $kql }) | Should -Be @('https://a.example/feed', 'https://b.example/feed')
    }

    It 'returns nothing when no externaldata block is present' {
        @(Invoke-Kql Get-iSOCKqlExternalDataReference @{ Query = 'SecurityAlert | take 1' }).Count | Should -Be 0
    }
}

Describe 'Get-iSOCKqlBareIdentifier' {
    It 'finds <Expected> in: <Query>' -ForEach @(
        @{ Query = 'SecurityAlert | where Severity == "High"'; Expected = 'SecurityAlert' }
        @{ Query = 'let recent = SigninLogs | where TimeGenerated > ago(1h); recent'; Expected = 'SigninLogs' }
        @{ Query = 'SigninLogs | union kind=outer AADNonInteractiveUserSignInLogs | take 1'; Expected = 'AADNonInteractiveUserSignInLogs' }
        @{ Query = 'union isfuzzy=true SigninLogs, AuditLogs'; Expected = 'SigninLogs' }
        @{ Query = 'SigninLogs | join kind=inner (AADRiskyUsers | where State == "atRisk") on UserId'; Expected = 'AADRiskyUsers' }
        @{ Query = "let cached = materialize (`n    MicrosoftGraphActivityLogs`n    | take 1`n);`ncached"; Expected = 'MicrosoftGraphActivityLogs' }
        @{ Query = 'let total = toscalar(SecurityAlert | count); print total'; Expected = 'SecurityAlert' }
        @{ Query = "table('SigninLogs') | take 1"; Expected = 'SigninLogs' }
    ) {
        @(Invoke-Kql Get-iSOCKqlBareIdentifier @{ Query = $Query }) | Should -Contain $Expected
    }

    It 'leaves out <Excluded> in: <Query>' -ForEach @(
        @{ Query = "SecurityAlert`n| project Timestamp,`n    AlertName,`n    Severity`n| take 10"; Excluded = 'AlertName' }
        @{ Query = "let legacyClients = dynamic([`n    `"IMAP`", `"POP`", `"SMTP`", `"Other clients; POP`"`n]);`nSigninLogs | where ClientAppUsed in (legacyClients)"; Excluded = 'POP' }
        @{ Query = 'let myLocal = SigninLogs | take 1; myLocal | project Time = TimeGenerated'; Excluded = 'myLocal' }
        @{ Query = 'let aadFunc = (tableName: string, start: datetime) { table(tableName) | where TimeGenerated > start }; aadFunc("SigninLogs", ago(1h))'; Excluded = 'tableName' }
        @{ Query = 'union isfuzzy=true kind=outer SigninLogs, AuditLogs'; Excluded = 'isfuzzy' }
        @{ Query = 'let count = toscalar(SigninLogs | count); print count'; Excluded = 'toscalar' }
    ) {
        @(Invoke-Kql Get-iSOCKqlBareIdentifier @{ Query = $Query }) | Should -Not -Contain $Excluded
    }

    It 'finds tables passed as strings to a lambda that calls table()' {
        $kql = "let aadFunc = (tableName: string) {`n    table(tableName)`n    | take 1`n};`nlet aadSignin = aadFunc(`"SigninLogs`");`nlet aadNonInt = aadFunc(`"AADNonInteractiveUserSignInLogs`");`nunion isfuzzy=true aadSignin, aadNonInt"
        $ids = @(Invoke-Kql Get-iSOCKqlBareIdentifier @{ Query = $kql })
        $ids | Should -Contain 'SigninLogs'
        $ids | Should -Contain 'AADNonInteractiveUserSignInLogs'
    }
}

Describe 'Get-iSOCQueryDependency' {
    BeforeAll {
        $script:known = @{ UnifiedSignInLogs = $true }
        function New-RuleFile {
            param([string] $Name, [string] $Query)
            $path = Join-Path $TestDrive $Name
            Set-Content -LiteralPath $path -Value "id: aaaa1111-2222-3333-4444-555555555555`nname: Test rule`nquery: |`n$((($Query -split "`n") | ForEach-Object { "    $_" }) -join "`n")"
            $path
        }
    }

    It 'files a table at a data-source position under tables' {
        $deps = Get-FileDependency (New-RuleFile 'a.yaml' 'SigninLogs | where ResultType != "0"') $script:known
        @($deps.tables) | Should -Contain 'SigninLogs'
        @($deps.functions) | Should -BeNullOrEmpty
    }

    It 'files a custom log table under tables' {
        @((Get-FileDependency (New-RuleFile 'b.yaml' 'MyCustomTable_CL | take 1') $script:known).tables) | Should -Contain 'MyCustomTable_CL'
    }

    It 'files a repository parser and an ASIM function under functions' {
        @((Get-FileDependency (New-RuleFile 'c.yaml' 'UnifiedSignInLogs | take 1') $script:known).functions) | Should -Contain 'UnifiedSignInLogs'
        @((Get-FileDependency (New-RuleFile 'd.yaml' 'ASimDnsActivityLogs | take 1') $script:known).functions) | Should -Contain 'ASimDnsActivityLogs'
    }

    It 'reads watchlists, external data and tables in one pass' {
        $query = "let bg = _GetWatchlist('breakGlassAccounts');`nlet azureRanges = externaldata(values: dynamic) [`"https://example.com/azureranges.json`"] with(format='multijson');`nSigninLogs | where UserPrincipalName in (bg) | take 1"
        $deps = Get-FileDependency (New-RuleFile 'e.yaml' $query) $script:known
        @($deps.watchlists) | Should -Contain 'breakGlassAccounts'
        @($deps.externalData) | Should -Contain 'https://example.com/azureranges.json'
        @($deps.tables) | Should -Contain 'SigninLogs'
    }

    It 'returns empty buckets, and no unclassified bucket, for a file without a query' {
        $path = Join-Path $TestDrive 'no-query.yaml'
        Set-Content -LiteralPath $path -Value 'name: just metadata'
        $deps = Get-FileDependency $path @{}
        foreach ($bucket in 'tables', 'watchlists', 'functions', 'externalData') { @($deps[$bucket]).Count | Should -Be 0 }
        $deps.ContainsKey('unclassified') | Should -BeFalse
    }

    It 'reads the query of a Defender custom detection' {
        $path = Join-Path $TestDrive 'detection.yaml'
        Set-Content -LiteralPath $path -Value "displayName: x`nqueryCondition:`n  queryText: |`n    DeviceProcessEvents | take 1"
        @((Get-FileDependency $path @{}).tables) | Should -Contain 'DeviceProcessEvents'
    }
}

Describe 'Dependencies of a content file' {
    BeforeAll {
        $script:knownParsers = @{ UnifiedSignInLogs = 'Parsers/UnifiedSignInLogs.yaml'; MyParser = 'Parsers/MyParser.yaml' }
    }

    It 'are what <Name> reads from' -ForEach @(
        @{
            Name = 'rule.yaml'; Tables = @('AuditLogs'); Watchlists = @('breakGlassAccounts'); Functions = @('UnifiedSignInLogs'); ExternalData = @()
            Lines = @(
                'id: 11111111-2222-3333-4444-555555555555'
                'name: Sign-in from a break-glass account'
                'query: |'
                '  let breakGlass = _GetWatchlist(''breakGlassAccounts'') | project UPN = SearchKey;'
                '  UnifiedSignInLogs'
                '  | where UserPrincipalName in (breakGlass)'
                '  | join kind=leftouter (AuditLogs | where OperationName == "Add member to role") on $left.UserId == $right.InitiatedBy'
                '  | project TimeGenerated, UserPrincipalName, IPAddress'
            )
        }
        @{
            Name = 'hunting.yml'; Tables = @('AADNonInteractiveUserSignInLogs', 'SigninLogs'); Watchlists = @(); Functions = @(); ExternalData = @('https://example.com/ranges.csv')
            Lines = @(
                'id: 22222222-3333-4444-5555-666666666666'
                'name: Sign-ins from listed ranges'
                'query: |'
                '  let ranges = externaldata(network: string) ["https://example.com/ranges.csv"] with(format=''csv'');'
                '  let cached = materialize(SigninLogs | where TimeGenerated > ago(1d));'
                '  let total = toscalar(AADNonInteractiveUserSignInLogs | count);'
                '  cached'
                '  | evaluate ipv4_lookup(ranges, IPAddress, network)'
                '  | extend Total = total'
            )
        }
        @{
            Name = 'parser.yaml'; Tables = @('SecurityEvent'); Watchlists = @(); Functions = @('_ASim_ProcessEvent', 'imAuthentication'); ExternalData = @()
            Lines = @(
                'id: MyParser'
                'functionAlias: MyParser'
                'query: |'
                '  let readTable = (tableName: string) { table(tableName) | take 1 };'
                '  union isfuzzy=true imAuthentication, readTable("SecurityEvent")'
                '  | join kind=inner (_ASim_ProcessEvent | take 1) on EventID'
            )
        }
        @{
            Name = 'summary.json'; Tables = @('SecurityAlert'); Watchlists = @(); Functions = @('MyParser'); ExternalData = @()
            Lines = @(
                '{'
                '  "name": "AlertSummary",'
                '  "query": "SecurityAlert\n| summarize Alerts = count() by AlertName, bin(TimeGenerated, 1h)\n| join kind=inner (MyParser | take 1) on AlertName",'
                '  "binSize": 60,'
                '  "destinationTable": "AlertSummary_CL"'
                '}'
            )
        }
        @{
            Name = 'detection.yaml'; Tables = @('DeviceNetworkEvents', 'DeviceProcessEvents'); Watchlists = @(); Functions = @(); ExternalData = @()
            Lines = @(
                'displayName: Encoded PowerShell with a network connection'
                'queryCondition:'
                '  queryText: |'
                '    DeviceProcessEvents'
                '    | where FileName =~ "powershell.exe" and ProcessCommandLine has "-enc"'
                '    | join kind=inner (DeviceNetworkEvents | where RemotePort == 443) on DeviceId'
            )
        }
        @{
            Name = 'workbook.json'; Tables = @(); Watchlists = @(); Functions = @(); ExternalData = @()
            Lines = @(
                '{'
                '  "version": "Notebook/1.0",'
                '  "items": [ { "type": 3, "content": { "query": "SigninLogs | take 1" } } ]'
                '}'
            )
        }
        @{
            Name = 'broken.yaml'; Tables = @(); Watchlists = @(); Functions = @(); ExternalData = @()
            Lines = @('id: [unclosed', 'query: SigninLogs | take 1')
        }
        @{
            Name = 'list.yaml'; Tables = @(); Watchlists = @(); Functions = @(); ExternalData = @()
            Lines = @('- query: SigninLogs | take 1')
        }
    ) {
        $path = Join-Path $TestDrive $Name
        Set-Content -LiteralPath $path -Value ($Lines -join "`n")
        $deps = Get-FileDependency $path $script:knownParsers
        @($deps.Keys | Sort-Object) | Should -Be @('externalData', 'functions', 'tables', 'watchlists')
        (@($deps.tables) -join ',') | Should -BeExactly ($Tables -join ',')
        (@($deps.watchlists) -join ',') | Should -BeExactly ($Watchlists -join ',')
        (@($deps.functions) -join ',') | Should -BeExactly ($Functions -join ',')
        (@($deps.externalData) -join ',') | Should -BeExactly ($ExternalData -join ',')
    }
}
