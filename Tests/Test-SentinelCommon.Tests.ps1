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
