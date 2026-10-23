#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the KQL dependency helpers the module copied from
    Sentinel.Common.

.DESCRIPTION
    Three layers:

    - the KQL cases from Tests/Test-SentinelCommon.Tests.ps1, carried over
      against the module's helpers;
    - each copied function, token for token without comments, against its
      original, with only the helper names changed (and the YAML loader
      call Get-iSOCContentKqlQuery adds, MIGRATION.md edit E4);
    - every content file under Content/, read by both
      Get-ContentDependencies (Sentinel.Common) and
      Get-iSOCContentFileDependency, which must agree, with the parser
      aliases the dependency manifest builder uses.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Kql.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Kql.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml, Az.Accounts
                  (Sentinel.Common declares it)

    The parity layer goes when Sentinel.Common is retired at cut-over; the
    first two stay.
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $pairs = @(
        @{ Old = 'Remove-KqlComments'; New = 'Remove-iSOCKqlComment' }
        @{ Old = 'Get-KqlWatchlistReferences'; New = 'Get-iSOCKqlWatchlistReference' }
        @{ Old = 'Get-KqlExternalDataReferences'; New = 'Get-iSOCKqlExternalDataReference' }
        @{ Old = 'Get-KqlBareIdentifiers'; New = 'Get-iSOCKqlBareIdentifier' }
        @{ Old = 'Get-ContentKqlQuery'; New = 'Get-iSOCContentKqlQuery' }
        @{ Old = 'Get-ContentDependencies'; New = 'Get-iSOCContentFileDependency' }
    )
    $contentFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Content') -Recurse -File -Include '*.yaml', '*.yml', '*.json') |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '_helpers/Parity.psm1') -Force
    Import-Module powershell-yaml -ErrorAction Stop

    $script:renames = @{
        'Remove-KqlComments'            = 'Remove-iSOCKqlComment'
        'Get-KqlWatchlistReferences'    = 'Get-iSOCKqlWatchlistReference'
        'Get-KqlExternalDataReferences' = 'Get-iSOCKqlExternalDataReference'
        'Get-KqlBareIdentifiers'        = 'Get-iSOCKqlBareIdentifier'
        'Get-ContentKqlQuery'           = 'Get-iSOCContentKqlQuery'
        'Get-ContentDependencies'       = 'Get-iSOCContentFileDependency'
    }

    function Invoke-Kql {
        param([string] $Command, [hashtable] $Parameters)
        InModuleScope iSOCDeployments -Parameters @{ C = $Command; P = $Parameters } { param($C, $P) & $C @P }
    }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
    Remove-Module Sentinel.Common -ErrorAction SilentlyContinue
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

Describe 'Get-iSOCContentFileDependency' {
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
        $deps = Invoke-Kql Get-iSOCContentFileDependency @{ Path = (New-RuleFile 'a.yaml' 'SigninLogs | where ResultType != "0"'); KnownFunctions = $script:known }
        @($deps.tables) | Should -Contain 'SigninLogs'
        @($deps.functions) | Should -BeNullOrEmpty
    }

    It 'files a custom log table under tables' {
        @((Invoke-Kql Get-iSOCContentFileDependency @{ Path = (New-RuleFile 'b.yaml' 'MyCustomTable_CL | take 1'); KnownFunctions = $script:known }).tables) | Should -Contain 'MyCustomTable_CL'
    }

    It 'files a repository parser and an ASIM function under functions' {
        @((Invoke-Kql Get-iSOCContentFileDependency @{ Path = (New-RuleFile 'c.yaml' 'UnifiedSignInLogs | take 1'); KnownFunctions = $script:known }).functions) | Should -Contain 'UnifiedSignInLogs'
        @((Invoke-Kql Get-iSOCContentFileDependency @{ Path = (New-RuleFile 'd.yaml' 'ASimDnsActivityLogs | take 1'); KnownFunctions = $script:known }).functions) | Should -Contain 'ASimDnsActivityLogs'
    }

    It 'reads watchlists, external data and tables in one pass' {
        $query = "let bg = _GetWatchlist('breakGlassAccounts');`nlet azureRanges = externaldata(values: dynamic) [`"https://example.com/azureranges.json`"] with(format='multijson');`nSigninLogs | where UserPrincipalName in (bg) | take 1"
        $deps = Invoke-Kql Get-iSOCContentFileDependency @{ Path = (New-RuleFile 'e.yaml' $query); KnownFunctions = $script:known }
        @($deps.watchlists) | Should -Contain 'breakGlassAccounts'
        @($deps.externalData) | Should -Contain 'https://example.com/azureranges.json'
        @($deps.tables) | Should -Contain 'SigninLogs'
    }

    It 'returns empty buckets, and no unclassified bucket, for a file without a query' {
        $path = Join-Path $TestDrive 'no-query.yaml'
        Set-Content -LiteralPath $path -Value 'name: just metadata'
        $deps = Invoke-Kql Get-iSOCContentFileDependency @{ Path = $path; KnownFunctions = @{} }
        foreach ($bucket in 'tables', 'watchlists', 'functions', 'externalData') { @($deps[$bucket]).Count | Should -Be 0 }
        $deps.ContainsKey('unclassified') | Should -BeFalse
    }

    It 'reads the query of a Defender custom detection' {
        $path = Join-Path $TestDrive 'detection.yaml'
        Set-Content -LiteralPath $path -Value "displayName: x`nqueryCondition:`n  queryText: |`n    DeviceProcessEvents | take 1"
        @((Invoke-Kql Get-iSOCContentFileDependency @{ Path = $path; KnownFunctions = @{} }).tables) | Should -Contain 'DeviceProcessEvents'
    }
}

Describe '<New> keeps the code of <Old>' -ForEach $pairs {
    It 'has the same tokens once the helper names are mapped' {
        $old = Get-ParityTokenText -Path (Join-Path $script:repoRoot 'Modules/Sentinel.Common/Sentinel.Common.psm1') -Name $Old |
            ForEach-Object { if ($script:renames.ContainsKey($_)) { $script:renames[$_] } else { $_ } }
        $new = Get-ParityTokenText -Path (Join-Path $script:repoRoot "Modules/iSOCDeployments/Private/Kql/$New.ps1") -Name $New |
            Where-Object { $_ -ne 'Import-iSOCYamlModule' }
        @($new) | Should -Be @($old)
    }
}

Describe 'Dependencies of <Path>' -ForEach $contentFiles {
    BeforeAll {
        if (-not (Get-Module Sentinel.Common)) {
            Import-Module (Join-Path $script:repoRoot 'Modules/Sentinel.Common/Sentinel.Common.psd1') -Force
        }
        if (-not (Get-Variable -Name knownFunctions -Scope Script -ErrorAction SilentlyContinue)) {
            $script:knownFunctions = @{}
            Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'Content/Parsers') -Recurse -File -Include '*.yaml', '*.yml' | ForEach-Object {
                $y = ConvertFrom-Yaml (Get-Content -LiteralPath $_.FullName -Raw)
                if ($y -and $y.functionAlias) { $script:knownFunctions[[string]$y.functionAlias] = $_.FullName }
            }
        }
    }

    It 'are what Sentinel.Common finds' {
        $full = Join-Path $script:repoRoot $Path
        $old = Get-ContentDependencies -Path $full -KnownFunctions $script:knownFunctions
        $new = Invoke-Kql Get-iSOCContentFileDependency @{ Path = $full; KnownFunctions = $script:knownFunctions }
        ConvertTo-ParityJson $new | Should -BeExactly (ConvertTo-ParityJson $old)
    }
}
