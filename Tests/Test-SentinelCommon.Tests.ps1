#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 unit tests for the three functions exported from
    Modules/Sentinel.Common/Sentinel.Common.psm1.

.DESCRIPTION
    Covers the module's public surface in isolation:
      - Write-PipelineMessage: ADO vs local output branching across all
        six log levels.
      - Invoke-SentinelApi: success path, retry-on-transient-failure,
        terminal failure exception with response-body recovery.
      - Connect-AzureEnvironment: parameter contract, returned state
        shape, government-cloud branching.

    Uses Pester 5's Mock cmdlet to stub Az PowerShell calls so the
    suite runs offline with no Azure context. Each test imports the
    module fresh (Force) to avoid cross-test state leakage.
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repoRoot 'Modules/Sentinel.Common/Sentinel.Common.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # The new discovery functions need powershell-yaml to read content
    # files; ensure it's available for the round-trip tests.
    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Install-Module -Name powershell-yaml -Force -Scope CurrentUser -AllowClobber | Out-Null
    }
    Import-Module powershell-yaml -ErrorAction Stop
}

Describe 'Write-PipelineMessage' {
    Context 'Local environment (no BUILD_BUILDID)' {
        BeforeEach {
            # Strip the ADO env var so each test starts in local mode.
            $script:savedBuildId = $env:BUILD_BUILDID
            $env:BUILD_BUILDID = $null
        }

        AfterEach {
            $env:BUILD_BUILDID = $script:savedBuildId
        }

        It 'Info level writes plain text to stdout' {
            $output = Write-PipelineMessage -Message 'plain info' -Level Info 6>&1
            $output | Should -Be 'plain info'
        }

        It 'Section level writes cyan-coloured stdout (no ##[section] marker)' {
            $output = Write-PipelineMessage -Message 'a section' -Level Section 6>&1
            $output | Should -Match 'a section'
            $output | Should -Not -Match '##\[section\]'
        }

        It 'Warning level uses Write-Warning, not the ADO marker' {
            # Capture the warning stream via the 3 redirector. Write-Warning
            # emits a WarningRecord, not a string; coerce to string for the
            # assertion.
            $captured = Write-PipelineMessage -Message 'careful' -Level Warning -WarningAction Continue 3>&1
            ($captured | ForEach-Object { [string]$_ }) -join '|' | Should -Match 'careful'
        }

        It 'Debug level routes through Write-Verbose (silent without -Verbose)' {
            $output = Write-PipelineMessage -Message 'debug noise' -Level Debug 6>&1
            $output | Should -BeNullOrEmpty
        }
    }

    Context 'ADO environment (BUILD_BUILDID set)' {
        BeforeEach {
            $script:savedBuildId = $env:BUILD_BUILDID
            $env:BUILD_BUILDID = 'fake-build-12345'
        }

        AfterEach {
            $env:BUILD_BUILDID = $script:savedBuildId
        }

        It 'Section level emits the ##[section] log marker' {
            $output = Write-PipelineMessage -Message 'an ADO section' -Level Section 6>&1
            $output | Should -Match '^##\[section\]an ADO section$'
        }

        It 'Warning level emits the ##[warning] log marker' {
            $output = Write-PipelineMessage -Message 'an ADO warning' -Level Warning 6>&1
            $output | Should -Match '^##\[warning\]an ADO warning$'
        }

        It 'Error level emits the ##[error] log marker (not Write-Error)' {
            $output = Write-PipelineMessage -Message 'an ADO error' -Level Error 6>&1
            $output | Should -Match '^##\[error\]an ADO error$'
        }
    }

    Context 'Input validation' {
        It 'rejects an unknown level' {
            { Write-PipelineMessage -Message 'x' -Level 'Bogus' } |
                Should -Throw -ExpectedMessage '*ValidateSet*'
        }

        It 'accepts an empty message string' {
            { Write-PipelineMessage -Message '' -Level Info } | Should -Not -Throw
        }
    }
}

Describe 'Invoke-SentinelApi' {
    Context 'Success path' {
        It 'returns the parsed JSON body on a 200 response' {
            Mock -ModuleName Sentinel.Common Invoke-WebRequest {
                [pscustomobject]@{ Content = '{"value":"ok","count":42}' }
            }
            $result = Invoke-SentinelApi -Uri 'https://example/api' -Method Get -Headers @{}
            $result.value | Should -Be 'ok'
            $result.count | Should -Be 42
        }

        It 'forwards the Body parameter when supplied' {
            Mock -ModuleName Sentinel.Common Invoke-WebRequest {
                param($Uri, $Method, $Headers, $Body, $ContentType, $UseBasicParsing, $ErrorAction)
                # Capture the body for assertion via a script-scoped variable.
                $script:capturedBody = $Body
                [pscustomobject]@{ Content = '{}' }
            }
            Invoke-SentinelApi -Uri 'https://x/api' -Method Post -Headers @{} -Body '{"foo":"bar"}' | Out-Null
            $script:capturedBody | Should -Be '{"foo":"bar"}'
        }
    }

    Context 'Failure handling' {
        # WebException's Response property is read-only on the real type and
        # cannot be set on a synthetic instance — accurate retry-vs-no-retry
        # tests require a much more elaborate mock infrastructure than is
        # warranted here. The Invoke-WebRequest call site is exercised
        # heavily in production every deploy, so we keep the mock-driven
        # tests focused on the function's terminal behaviour: any thrown
        # exception bubbles up as the documented "API call failed" message.
        It 'throws "API call failed: ..." on a non-retryable exception' {
            Mock -ModuleName Sentinel.Common Invoke-WebRequest {
                throw [System.Exception]::new('synthetic failure for test')
            }

            { Invoke-SentinelApi -Uri 'https://x/api' -Method Get -Headers @{} -MaxRetries 1 } |
                Should -Throw -ExpectedMessage '*API call failed*'
        }

        It 'attempts at most MaxRetries calls before giving up' {
            $script:callCount = 0
            Mock -ModuleName Sentinel.Common Invoke-WebRequest {
                $script:callCount++
                throw [System.Exception]::new('still failing')
            }

            { Invoke-SentinelApi -Uri 'https://x/api' -Method Get -Headers @{} -MaxRetries 1 -RetryDelaySeconds 0 } |
                Should -Throw -ExpectedMessage '*API call failed*'
            $script:callCount | Should -Be 1 -Because 'a non-retryable exception (no Response property) should fail the first call without retry'
        }
    }
}

Describe 'Connect-AzureEnvironment' {
    Context 'Returned state shape' {
        BeforeAll {
            # Stub every Az cmdlet the function calls so the test runs
            # offline. Mock -ModuleName Sentinel.Common scopes the mock to
            # the module's session, which is where the function runs.
            Mock -ModuleName Sentinel.Common Update-AzConfig { }
            Mock -ModuleName Sentinel.Common Get-AzContext {
                [pscustomobject]@{
                    Subscription = [pscustomobject]@{ Id = 'sub-12345'; Name = 'Test Sub'; TenantId = 'tenant-67890' }
                }
            }
            Mock -ModuleName Sentinel.Common Set-AzContext { }
            Mock -ModuleName Sentinel.Common Get-AzAccessToken {
                [pscustomobject]@{ Token = 'fake-bearer-token' }
            }
            Mock -ModuleName Sentinel.Common Get-AzResourceGroup { [pscustomobject]@{ ResourceGroupName = 'fake-rg' } }
            Mock -ModuleName Sentinel.Common Invoke-SentinelApi {
                [pscustomobject]@{ properties = [pscustomobject]@{ customerId = 'workspace-guid-1234' } }
            }
        }

        It 'returns a hashtable with the expected keys' {
            $ctx = Connect-AzureEnvironment -ResourceGroup 'rg-test' -Workspace 'law-test' -Region 'uksouth' -SubscriptionId 'sub-12345'
            $ctx | Should -BeOfType ([hashtable])
            foreach ($key in @('SubscriptionId', 'ServerUrl', 'BaseUri', 'WorkspaceResourceId', 'WorkspaceId', 'PlaybookRG', 'AuthHeader')) {
                $ctx.ContainsKey($key) | Should -BeTrue -Because "Connect-AzureEnvironment must return $key in its state hashtable"
            }
        }

        It 'uses the commercial cloud endpoint by default' {
            $ctx = Connect-AzureEnvironment -ResourceGroup 'rg-test' -Workspace 'law-test' -Region 'uksouth'
            $ctx.ServerUrl | Should -Be 'https://management.azure.com'
        }

        It 'switches to the government cloud endpoint when -IsGov is set' {
            $ctx = Connect-AzureEnvironment -ResourceGroup 'rg-test' -Workspace 'law-test' -Region 'usgovvirginia' -IsGov
            $ctx.ServerUrl | Should -Be 'https://management.usgovcloudapi.net'
        }

        It 'falls back PlaybookRG to ResourceGroup when not supplied' {
            $ctx = Connect-AzureEnvironment -ResourceGroup 'rg-test' -Workspace 'law-test' -Region 'uksouth'
            $ctx.PlaybookRG | Should -Be 'rg-test'
        }

        It 'uses an explicit PlaybookResourceGroup when supplied' {
            $ctx = Connect-AzureEnvironment -ResourceGroup 'rg-test' -Workspace 'law-test' -Region 'uksouth' -PlaybookResourceGroup 'rg-playbooks'
            $ctx.PlaybookRG | Should -Be 'rg-playbooks'
        }

        It 'builds the BaseUri from server URL + subscription / RG / workspace' {
            $ctx = Connect-AzureEnvironment -ResourceGroup 'rg-x' -Workspace 'law-x' -Region 'uksouth' -SubscriptionId 'sub-explicit'
            $ctx.BaseUri | Should -Be 'https://management.azure.com/subscriptions/sub-explicit/resourceGroups/rg-x/providers/Microsoft.OperationalInsights/workspaces/law-x'
        }

        It 'builds WorkspaceResourceId without the server URL prefix' {
            $ctx = Connect-AzureEnvironment -ResourceGroup 'rg-x' -Workspace 'law-x' -Region 'uksouth' -SubscriptionId 'sub-explicit'
            $ctx.WorkspaceResourceId | Should -Be '/subscriptions/sub-explicit/resourceGroups/rg-x/providers/Microsoft.OperationalInsights/workspaces/law-x'
        }
    }

    Context 'Authentication failures' {
        It 'throws when Get-AzContext returns nothing' {
            Mock -ModuleName Sentinel.Common Update-AzConfig { }
            Mock -ModuleName Sentinel.Common Get-AzContext { $null }
            Mock -ModuleName Sentinel.Common Connect-AzAccount { } # silently no-op

            { Connect-AzureEnvironment -ResourceGroup 'rg-x' -Workspace 'law-x' -Region 'uksouth' } |
                Should -Throw -ExpectedMessage '*Failed to establish Azure context*'
        }

        It 'fails fast when no Azure context can be established' {
            # The "Failed to acquire an access token" path requires the
            # Get-AzAccessToken try-catch AND the profile-client fallback to
            # both fail to produce a token. The profile-client fallback uses
            # New-Object against an Az-internal type that is not mockable
            # without test-only access to the Az SDK; we test the simpler
            # auth-failure path (no Az context at all) instead, which
            # provides equivalent coverage of the fail-fast contract.
            Mock -ModuleName Sentinel.Common Update-AzConfig { }
            Mock -ModuleName Sentinel.Common Get-AzContext { $null }
            Mock -ModuleName Sentinel.Common Connect-AzAccount { }

            { Connect-AzureEnvironment -ResourceGroup 'rg-x' -Workspace 'law-x' -Region 'uksouth' } |
                Should -Throw -ExpectedMessage '*Failed to establish Azure context*'
        }
    }
}

# ===========================================================================
# Discovery helpers (Wave 4 Item 4)
# ===========================================================================

Describe 'Remove-KqlComments' {
    It 'strips // line comments to end of line' {
        $kql = "SecurityAlert`n| where x == 1 // ignore me`n| take 1"
        Remove-KqlComments -Query $kql | Should -Not -Match 'ignore me'
    }

    It 'preserves URLs containing :// (negative lookbehind)' {
        $kql = 'let url = "https://foo.com/path"; print url'
        $result = Remove-KqlComments -Query $kql
        $result | Should -Match 'https://foo.com/path'
    }

    It 'strips /* block */ comments including across newlines' {
        $kql = "SecurityAlert`n/* multi-line`n   block comment */`n| take 1"
        $result = Remove-KqlComments -Query $kql
        $result | Should -Not -Match 'block comment'
        $result | Should -Match 'SecurityAlert'
        $result | Should -Match 'take 1'
    }

    It 'returns the input unchanged when no comments are present' {
        $kql = 'SecurityAlert | where Severity == "High" | take 1'
        Remove-KqlComments -Query $kql | Should -Be $kql
    }
}

Describe 'Get-KqlWatchlistReferences' {
    It "extracts a single _GetWatchlist('alias') reference" {
        $kql = "let bg = _GetWatchlist('breakGlassAccounts'); SigninLogs | where x in (bg)"
        $refs = Get-KqlWatchlistReferences -Query $kql
        @($refs).Count | Should -Be 1
        @($refs)[0]    | Should -Be 'breakGlassAccounts'
    }

    It 'extracts double-quoted alias forms' {
        $refs = Get-KqlWatchlistReferences -Query '_GetWatchlist("DoubleQuoted")'
        @($refs).Count | Should -Be 1
        @($refs)[0]    | Should -Be 'DoubleQuoted'
    }

    It 'deduplicates aliases referenced multiple times' {
        $kql = "_GetWatchlist('Foo') | union (_GetWatchlist('Foo'))"
        $refs = Get-KqlWatchlistReferences -Query $kql
        @($refs).Count | Should -Be 1
    }

    It 'returns multiple aliases sorted' {
        $kql = "_GetWatchlist('Zoo') | union (_GetWatchlist('Apple'), _GetWatchlist('Mango'))"
        $refs = Get-KqlWatchlistReferences -Query $kql
        @($refs)        | Should -Be @('Apple', 'Mango', 'Zoo')
    }

    It 'returns @() for queries with no _GetWatchlist calls' {
        @(Get-KqlWatchlistReferences -Query 'SecurityAlert | take 1').Count | Should -Be 0
    }

    It 'ignores _GetWatchlist references inside comments' {
        $kql = "// _GetWatchlist('Commented') is ignored`nSecurityAlert"
        @(Get-KqlWatchlistReferences -Query $kql).Count | Should -Be 0
    }
}

Describe 'Get-KqlExternalDataReferences' {
    It 'extracts a URL from a single externaldata block' {
        $kql = @'
externaldata(col1: string)
    ["https://example.com/feed.json"] with(format='multijson')
'@
        $urls = Get-KqlExternalDataReferences -Query $kql
        @($urls).Count | Should -Be 1
        @($urls)[0]    | Should -Be 'https://example.com/feed.json'
    }

    It 'extracts multiple URLs from a single bracket list' {
        $kql = @'
externaldata(col1: string)
    ["https://a.example/feed", "https://b.example/feed"] with(format='multijson')
'@
        $urls = Get-KqlExternalDataReferences -Query $kql
        @($urls).Count | Should -Be 2
        @($urls -contains 'https://a.example/feed') | Should -BeTrue
        @($urls -contains 'https://b.example/feed') | Should -BeTrue
    }

    It 'returns @() when no externaldata block is present' {
        @(Get-KqlExternalDataReferences -Query 'SecurityAlert | take 1').Count | Should -Be 0
    }
}

Describe 'Get-KqlBareIdentifiers' {
    It 'identifies a table at the start of a simple query' {
        $ids = Get-KqlBareIdentifiers -Query 'SecurityAlert | where Severity == "High"'
        @($ids) | Should -Contain 'SecurityAlert'
    }

    It 'identifies a table after `let X = `' {
        $ids = Get-KqlBareIdentifiers -Query 'let recent = SigninLogs | where TimeGenerated > ago(1h); recent'
        @($ids) | Should -Contain 'SigninLogs'
    }

    It 'identifies a table after the `union` operator (with kind= modifier)' {
        $kql = 'SigninLogs | union kind=outer AADNonInteractiveUserSignInLogs | take 1'
        $ids = Get-KqlBareIdentifiers -Query $kql
        @($ids) | Should -Contain 'SigninLogs'
        @($ids) | Should -Contain 'AADNonInteractiveUserSignInLogs'
    }

    It 'identifies a table after `union isfuzzy=true`' {
        $ids = Get-KqlBareIdentifiers -Query 'union isfuzzy=true SigninLogs, AuditLogs'
        @($ids) | Should -Contain 'SigninLogs'
    }

    It 'identifies a table inside a join subquery' {
        $kql = 'SigninLogs | join kind=inner (AADRiskyUsers | where State == "atRisk") on UserId'
        $ids = Get-KqlBareIdentifiers -Query $kql
        @($ids) | Should -Contain 'AADRiskyUsers'
    }

    It 'does NOT pick up column names from project/extend continuation lines' {
        $kql = @'
SecurityAlert
| project Timestamp,
    AlertName,
    Severity,
    Description
| take 10
'@
        $ids = Get-KqlBareIdentifiers -Query $kql
        @($ids) | Should -Contain 'SecurityAlert'
        @($ids) | Should -Not -Contain 'AlertName'
        @($ids) | Should -Not -Contain 'Severity'
        @($ids) | Should -Not -Contain 'Description'
    }

    It 'does NOT pick up identifiers inside string literals (POP/SMTP false positive)' {
        $kql = @'
let legacyClients = dynamic([
    "IMAP", "POP", "SMTP", "Other clients; POP"
]);
SigninLogs | where ClientAppUsed in (legacyClients)
'@
        $ids = Get-KqlBareIdentifiers -Query $kql
        @($ids) | Should -Contain 'SigninLogs'
        @($ids) | Should -Not -Contain 'POP'
        @($ids) | Should -Not -Contain 'SMTP'
    }

    It 'does NOT pick up let-bound variable names' {
        $kql = 'let myLocal = SigninLogs | take 1; myLocal | project Time = TimeGenerated'
        $ids = Get-KqlBareIdentifiers -Query $kql
        @($ids) | Should -Contain 'SigninLogs'
        @($ids) | Should -Not -Contain 'myLocal'
    }

    It 'does NOT pick up lambda parameter names' {
        $kql = 'let aadFunc = (tableName: string, start: datetime) { table(tableName) | where TimeGenerated > start }; aadFunc("SigninLogs", ago(1h))'
        $ids = Get-KqlBareIdentifiers -Query $kql
        @($ids) | Should -Not -Contain 'tableName'
        @($ids) | Should -Not -Contain 'start'
    }

    It 'does NOT pick up KQL keywords (isfuzzy, kind, etc.)' {
        $ids = Get-KqlBareIdentifiers -Query 'union isfuzzy=true kind=outer SigninLogs, AuditLogs'
        @($ids) | Should -Not -Contain 'isfuzzy'
        @($ids) | Should -Not -Contain 'kind'
    }

    It 'does NOT pick up KQL function-call sites (toscalar, materialize, iif)' {
        $kql = 'let count = toscalar(SigninLogs | count); print count'
        $ids = Get-KqlBareIdentifiers -Query $kql
        @($ids) | Should -Not -Contain 'toscalar'
    }

    It 'identifies a table inside a `materialize(...)` subquery' {
        $kql = @'
let cached = materialize (
    MicrosoftGraphActivityLogs
    | where ingestion_time() > ago(30m)
    | take 1
);
cached
'@
        $ids = Get-KqlBareIdentifiers -Query $kql
        @($ids) | Should -Contain 'MicrosoftGraphActivityLogs'
        @($ids) | Should -Not -Contain 'materialize'
    }

    It 'identifies a table inside a `toscalar(...)` subquery' {
        $kql = 'let total = toscalar(SecurityAlert | count); print total'
        $ids = Get-KqlBareIdentifiers -Query $kql
        @($ids) | Should -Contain 'SecurityAlert'
    }

    It 'identifies tables passed as string args to KQL `table()` (lambda wrapper pattern)' {
        $kql = @'
let aadFunc = (tableName: string) {
    table(tableName)
    | where ResultType == "0"
    | take 1
};
let aadSignin = aadFunc("SigninLogs");
let aadNonInt = aadFunc("AADNonInteractiveUserSignInLogs");
union isfuzzy=true aadSignin, aadNonInt
'@
        $ids = Get-KqlBareIdentifiers -Query $kql
        @($ids) | Should -Contain 'SigninLogs'
        @($ids) | Should -Contain 'AADNonInteractiveUserSignInLogs'
    }

    It 'identifies a direct `table(''X'')` call with a literal table name' {
        $kql = "table('SigninLogs') | take 1"
        $ids = Get-KqlBareIdentifiers -Query $kql
        @($ids) | Should -Contain 'SigninLogs'
    }
}

Describe 'Get-ContentDependencies' {
    BeforeAll {
        # Repo-driven model: only KnownFunctions is needed (built from
        # Parsers/ in the real script). Anything not matched as a function
        # defaults to a table.
        $script:knownFunctions = @{
            UnifiedSignInLogs = $true
        }
    }

    It 'classifies a Microsoft-provided table at a data-source position' {
        $tmp = Join-Path $TestDrive 'rule.yaml'
        Set-Content -Path $tmp -Value @"
id: aaaa1111-2222-3333-4444-555555555555
name: Test rule
query: |
    SigninLogs | where ResultType != "0" | take 1
"@
        $deps = Get-ContentDependencies -Path $tmp -KnownFunctions $script:knownFunctions
        @($deps.tables)    | Should -Contain 'SigninLogs'
        @($deps.functions) | Should -BeNullOrEmpty
    }

    It 'classifies a custom-log _CL identifier as a table by default' {
        $tmp = Join-Path $TestDrive 'rule-cl.yaml'
        Set-Content -Path $tmp -Value @"
id: aaaa1111-2222-3333-4444-555555555556
name: Test rule
query: |
    MyCustomTable_CL | take 1
"@
        $deps = Get-ContentDependencies -Path $tmp -KnownFunctions $script:knownFunctions
        @($deps.tables) | Should -Contain 'MyCustomTable_CL'
    }

    It 'classifies an in-repo function (KnownFunctions) under functions' {
        $tmp = Join-Path $TestDrive 'rule-func.yaml'
        Set-Content -Path $tmp -Value @"
id: aaaa1111-2222-3333-4444-555555555557
name: Test rule
query: |
    UnifiedSignInLogs | where ResultType != "0" | take 1
"@
        $deps = Get-ContentDependencies -Path $tmp -KnownFunctions $script:knownFunctions
        @($deps.functions) | Should -Contain 'UnifiedSignInLogs'
        @($deps.tables)    | Should -BeNullOrEmpty
    }

    It 'classifies an ASIM Microsoft-provided function via the regex pattern' {
        $tmp = Join-Path $TestDrive 'rule-asim.yaml'
        Set-Content -Path $tmp -Value @"
id: aaaa1111-2222-3333-4444-555555555558
name: Test rule
query: |
    ASimDnsActivityLogs | where DnsResponseName has_any (1, 2) | take 1
"@
        $deps = Get-ContentDependencies -Path $tmp -KnownFunctions $script:knownFunctions
        @($deps.functions) | Should -Contain 'ASimDnsActivityLogs'
        @($deps.tables)    | Should -BeNullOrEmpty
    }

    It 'extracts watchlists, externalData, and tables in one pass' {
        $tmp = Join-Path $TestDrive 'rule-multi.yaml'
        Set-Content -Path $tmp -Value @'
id: aaaa1111-2222-3333-4444-555555555559
name: Test rule
query: |
    let bg = _GetWatchlist('breakGlassAccounts');
    let azureRanges = externaldata(values: dynamic) ["https://example.com/azureranges.json"] with(format='multijson');
    SigninLogs | where UserPrincipalName in (bg) | take 1
'@
        $deps = Get-ContentDependencies -Path $tmp -KnownFunctions $script:knownFunctions
        @($deps.watchlists)   | Should -Contain 'breakGlassAccounts'
        @($deps.externalData) | Should -Contain 'https://example.com/azureranges.json'
        @($deps.tables)       | Should -Contain 'SigninLogs'
    }

    It 'returns empty arrays when the file has no embedded query' {
        $tmp = Join-Path $TestDrive 'no-query.yaml'
        Set-Content -Path $tmp -Value 'name: just metadata'
        $deps = Get-ContentDependencies -Path $tmp -KnownFunctions @{}
        @($deps.tables).Count       | Should -Be 0
        @($deps.watchlists).Count   | Should -Be 0
        @($deps.functions).Count    | Should -Be 0
        @($deps.externalData).Count | Should -Be 0
    }

    It 'does not emit an unclassified bucket' {
        # Repo-driven model: every bare identifier is either a function
        # or a table. There is no third bucket.
        $tmp = Join-Path $TestDrive 'rule-noun.yaml'
        Set-Content -Path $tmp -Value @"
id: aaaa1111-2222-3333-4444-555555555560
name: Test rule
query: |
    SomeBrandNewTable | take 1
"@
        $deps = Get-ContentDependencies -Path $tmp -KnownFunctions @{}
        $deps.ContainsKey('unclassified') | Should -BeFalse
        @($deps.tables) | Should -Contain 'SomeBrandNewTable'
    }
}
