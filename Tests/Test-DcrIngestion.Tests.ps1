#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for the pure helpers in Tools/ClassicToDcr/Rehearsal/Test-DcrIngestion.ps1.

.DESCRIPTION
    Covers the functions a live stream depends on being correct before the
    first POST:

      Get-DcrIngestionTarget   immutable ID + endpoint, or a clear failure.
      Get-DcrStreamName        single vs multi stream resolution.
      Get-DestinationTableName outputStream -> table name.
      Get-IngestionUri         Logs Ingestion URI shape.
      New-StreamRecord         records that match the stream schema.
      New-TokenRequest         client-credentials request shape.
      ConvertFrom-SecureStringPlain  SecureString round-trip.

    Deliberately not covered: the token network call, the streaming loop,
    and the role assignment. Those need a real service principal and a
    deployed DCR, so they are verified live, not here.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-DcrIngestion.Tests.ps1

    Runs the helper unit tests. Needs no Azure auth.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-DcrIngestion.Tests.ps1 -Output Detailed

    Runs with per-assertion output, for diagnosing a stream-resolution
    or record-shape failure.

.NOTES
    File:         Tests/Test-DcrIngestion.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Created:      2026-07-28
    Version:      0.1.0
    Last Updated: 2026-09-01
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Tools/ClassicToDcr/Rehearsal/Test-DcrIngestion.ps1'

    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop

    $script:IngestionApiVersion = '2023-01-01'

    Import-ScriptFunctions -Path $scriptPath

    # A DCR shaped like one this repo's migration script deploys.
    $script:sampleDcr = [pscustomobject] @{
        properties = [pscustomobject] @{
            immutableId = 'dcr-000a00a000a00000a000000aa000a0aa'
            endpoints   = [pscustomobject] @{
                logsIngestion = 'https://dcr-x.uksouth-1.ingest.monitor.azure.com'
            }
            streamDeclarations = [pscustomobject] @{
                'Custom-MyApp_CL' = [pscustomobject] @{
                    columns = @(
                        [pscustomobject] @{ name = 'TimeGenerated'; type = 'datetime' }
                        [pscustomobject] @{ name = 'Message_s';     type = 'string'   }
                        [pscustomobject] @{ name = 'DurationMs_d';  type = 'real'     }
                        [pscustomobject] @{ name = 'Count_d';       type = 'long'     }
                        [pscustomobject] @{ name = 'Success_b';     type = 'boolean'  }
                    )
                }
            }
            dataFlows = @(
                [pscustomobject] @{
                    streams      = @('Custom-MyApp_CL')
                    outputStream = 'Custom-MyApp_CL'
                }
            )
        }
    }
}

Describe 'Test-DcrIngestion: script-level contract' {
    BeforeAll {
        $script:sourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools/ClassicToDcr/Rehearsal/Test-DcrIngestion.ps1'
        $script:sourceText = Get-Content -Path $script:sourcePath -Raw
    }

    It 'parses cleanly' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $script:sourcePath, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'accepts the client secret as a SecureString, not a plain string' {
        $script:sourceText | Should -Match '\[securestring\]\s*\$ClientSecret'
    }

    It 'never writes the secret or access token to output' {
        $script:sourceText | Should -Not -Match 'Write-.*secretPlain'
        $script:sourceText | Should -Not -Match 'Write-.*AccessToken'
    }

    It 'reads the client secret from an environment variable as a fallback' {
        $script:sourceText | Should -Match 'DCR_INGEST_CLIENT_SECRET'
    }

    It 'gates the role grant behind ShouldProcess and a switch' {
        $script:sourceText | Should -Match '\$GrantIngestionRole'
        $script:sourceText | Should -Match "ShouldProcess\([^)]*Grant"
    }

    It 'uses no em-dashes in prose' {
        $script:sourceText | Should -Not -Match ([char]0x2014)
    }

    It 'is standalone: does not import the Sentinel.Common module' {
        $script:sourceText | Should -Not -Match 'Import-Module[^\r\n]*Sentinel\.Common'
        $script:sourceText | Should -Not -Match 'Sentinel\.Common\.psd1'
        $script:sourceText | Should -Match 'function Write-PipelineMessage'
    }

    It 'has the correct repo-relative header path' {
        $script:sourceText | Should -Match 'File:\s+Tools/ClassicToDcr/Rehearsal/Test-DcrIngestion\.ps1'
        $script:sourceText | Should -Match 'Repository:\s+Sentinel-As-Code'
    }

    It 'resolves the -Follow workspace defensively, not by direct index' {
        # A DCR need not have a logAnalytics destination; a direct index
        # would throw under strict mode. Resolve via PSObject.Properties.
        $script:sourceText | Should -Not -Match 'destinations\.logAnalytics\[0\]\.workspaceResourceId'
        $script:sourceText | Should -Match "PSObject\.Properties\['logAnalytics'\]"
    }

    It 'acquires the SP token only after the ShouldProcess gate' {
        # -WhatIf must not perform a real OAuth token request or touch the
        # secret, so the initial token acquisition sits after the gate.
        $gate  = $script:sourceText.IndexOf('ShouldProcess($ingestUri')
        $token = $script:sourceText.IndexOf('$token = Get-ServicePrincipalToken')
        $gate  | Should -BeGreaterThan 0
        $token | Should -BeGreaterThan $gate
    }
}

Describe 'Get-DcrIngestionTarget' {
    It 'extracts the immutable ID and endpoint' {
        $t = Get-DcrIngestionTarget -Dcr $script:sampleDcr
        $t.ImmutableId | Should -Be 'dcr-000a00a000a00000a000000aa000a0aa'
        $t.Endpoint    | Should -Be 'https://dcr-x.uksouth-1.ingest.monitor.azure.com'
    }

    It 'fails clearly when there is no logs ingestion endpoint' {
        $noEndpoint = [pscustomobject] @{
            properties = [pscustomobject] @{ immutableId = 'dcr-abc' }
        }
        { Get-DcrIngestionTarget -Dcr $noEndpoint } |
            Should -Throw -ExpectedMessage '*no logsIngestion endpoint*'
    }
}

Describe 'Get-DcrStreamName' {
    It 'uses the sole declared stream when none is requested' {
        Get-DcrStreamName -Dcr $script:sampleDcr | Should -Be 'Custom-MyApp_CL'
    }

    It 'accepts a valid explicit stream' {
        Get-DcrStreamName -Dcr $script:sampleDcr -Requested 'Custom-MyApp_CL' | Should -Be 'Custom-MyApp_CL'
    }

    It 'rejects a stream the DCR does not declare' {
        { Get-DcrStreamName -Dcr $script:sampleDcr -Requested 'Custom-Nope_CL' } |
            Should -Throw -ExpectedMessage '*not declared*'
    }

    It 'requires a choice when the DCR declares several streams' {
        $multi = [pscustomobject] @{
            properties = [pscustomobject] @{
                streamDeclarations = [pscustomobject] @{
                    'Custom-A_CL' = [pscustomobject] @{ columns = @() }
                    'Custom-B_CL' = [pscustomobject] @{ columns = @() }
                }
            }
        }
        { Get-DcrStreamName -Dcr $multi } | Should -Throw -ExpectedMessage '*Pass -StreamName*'
    }
}

Describe 'Get-DestinationTableName' {
    It 'strips the Custom- prefix from the output stream' {
        Get-DestinationTableName -Dcr $script:sampleDcr -Stream 'Custom-MyApp_CL' | Should -Be 'MyApp_CL'
    }

    It 'strips a Microsoft- prefix too' {
        $dcr = [pscustomobject] @{
            properties = [pscustomobject] @{
                dataFlows = @(
                    [pscustomobject] @{ streams = @('Microsoft-Event'); outputStream = 'Microsoft-Event' }
                )
            }
        }
        Get-DestinationTableName -Dcr $dcr -Stream 'Microsoft-Event' | Should -Be 'Event'
    }
}

Describe 'Get-IngestionUri' {
    It 'builds the documented Logs Ingestion URI' {
        $uri = Get-IngestionUri -Endpoint 'https://dcr-x.uksouth-1.ingest.monitor.azure.com' `
                                -ImmutableId 'dcr-abc' -Stream 'Custom-MyApp_CL'
        $uri | Should -Be 'https://dcr-x.uksouth-1.ingest.monitor.azure.com/dataCollectionRules/dcr-abc/streams/Custom-MyApp_CL?api-version=2023-01-01'
    }

    It 'does not double up the slash when the endpoint has a trailing slash' {
        $uri = Get-IngestionUri -Endpoint 'https://dcr-x.ingest.monitor.azure.com/' `
                                -ImmutableId 'dcr-abc' -Stream 'Custom-MyApp_CL'
        $uri | Should -Not -Match 'com//dataCollectionRules'
    }
}

Describe 'New-StreamRecord' {
    BeforeAll {
        $script:cols = @($script:sampleDcr.properties.streamDeclarations.'Custom-MyApp_CL'.columns)
        $script:ref  = [datetime]::new(2026, 7, 20, 12, 0, 0, [System.DateTimeKind]::Utc)
        $script:rec  = New-StreamRecord -StreamColumn $script:cols -Index 3 -RunId 'abc123' -ReferenceTime $script:ref
    }

    It 'produces a value for every declared column' {
        foreach ($c in $script:cols) {
            $script:rec.ContainsKey($c.name) | Should -BeTrue -Because "column $($c.name) must be present"
        }
    }

    It 'types each value to match the declared column type' {
        $script:rec['DurationMs_d'] | Should -BeOfType [double]
        $script:rec['Count_d']      | Should -BeOfType [long]
        $script:rec['Success_b']    | Should -BeOfType [bool]
        $script:rec['Message_s']    | Should -BeOfType [string]
    }

    It 'stamps the run marker into string columns so -Follow can isolate the run' {
        $script:rec['Message_s'] | Should -Match 'abc123'
    }

    It 'always includes TimeGenerated even if the stream omits it' {
        $cols = @([pscustomobject] @{ name = 'OnlyField_s'; type = 'string' })
        $rec  = New-StreamRecord -StreamColumn $cols -Index 0 -RunId 'x' -ReferenceTime $script:ref
        $rec.ContainsKey('TimeGenerated') | Should -BeTrue
    }

    It 'emits a body that serialises to a JSON array' {
        $batch = 1..3 | ForEach-Object {
            New-StreamRecord -StreamColumn $script:cols -Index $_ -RunId 'r' -ReferenceTime $script:ref
        }
        $parsed = (ConvertTo-Json -InputObject @($batch) -Depth 10) | ConvertFrom-Json
        @($parsed).Count | Should -Be 3
    }
}

Describe 'New-TokenRequest' {
    BeforeAll {
        $script:req = New-TokenRequest -AuthorityHost 'https://login.microsoftonline.com' `
                                       -TenantId 'tid' -ClientId 'cid' `
                                       -Audience 'https://monitor.azure.com' -ClientSecretPlain 'shh'
    }

    It 'targets the v2 token endpoint for the tenant' {
        $script:req.Uri | Should -Be 'https://login.microsoftonline.com/tid/oauth2/v2.0/token'
    }

    It 'requests the .default scope for the ingestion audience' {
        $script:req.Body.scope | Should -Be 'https://monitor.azure.com/.default'
    }

    It 'uses the client-credentials grant' {
        $script:req.Body.grant_type | Should -Be 'client_credentials'
        $script:req.Body.client_id  | Should -Be 'cid'
    }

    It 'builds a Government-cloud request when pointed at the .us hosts' {
        $gov = New-TokenRequest -AuthorityHost 'https://login.microsoftonline.us' `
                                -TenantId 'tid' -ClientId 'cid' `
                                -Audience 'https://monitor.azure.us' -ClientSecretPlain 'shh'
        $gov.Uri        | Should -Match '^https://login\.microsoftonline\.us/'
        $gov.Body.scope | Should -Be 'https://monitor.azure.us/.default'
    }
}

Describe 'SecureString round-trip' {
    It 'ConvertTo-SecureStringFromPlain then ConvertFrom-SecureStringPlain returns the original' {
        $secure = ConvertTo-SecureStringFromPlain -Plain 'p@ss word 123'
        ConvertFrom-SecureStringPlain -Secure $secure | Should -Be 'p@ss word 123'
    }
}

Describe 'Import-DotEnv' {
    BeforeAll {
        $script:envFile = Join-Path $TestDrive 'sample.env'
        @(
            '# a comment'
            ''
            'DCR_INGEST_TENANT_ID=11111111-1111-1111-1111-111111111111'
            'export DCR_INGEST_CLIENT_ID = 22222222-2222-2222-2222-222222222222'
            'DCR_INGEST_CLIENT_SECRET="s3cr3t with spaces"'
            "SINGLE='single quoted'"
            'EQUALS_IN_VALUE=a=b=c'
        ) | Set-Content -Path $script:envFile -Encoding utf8
        $script:parsed = Import-DotEnv -Path $script:envFile
    }

    It 'parses plain KEY=VALUE pairs' {
        $script:parsed['DCR_INGEST_TENANT_ID'] | Should -Be '11111111-1111-1111-1111-111111111111'
    }

    It 'tolerates an export prefix and whitespace around the equals' {
        $script:parsed['DCR_INGEST_CLIENT_ID'] | Should -Be '22222222-2222-2222-2222-222222222222'
    }

    It 'strips surrounding double and single quotes' {
        $script:parsed['DCR_INGEST_CLIENT_SECRET'] | Should -Be 's3cr3t with spaces'
        $script:parsed['SINGLE']                   | Should -Be 'single quoted'
    }

    It 'keeps equals signs that appear inside the value' {
        $script:parsed['EQUALS_IN_VALUE'] | Should -Be 'a=b=c'
    }

    It 'ignores comments and blank lines' {
        $script:parsed.Keys | Should -Not -Contain '# a comment'
        $script:parsed.Count | Should -Be 5
    }

    It 'returns an empty hashtable when the file is absent' {
        $result = Import-DotEnv -Path (Join-Path $TestDrive 'does-not-exist.env')
        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 0
    }
}

Describe 'Resolve-Setting' {
    It 'prefers the explicit value over the environment' {
        $env:SAC_TEST_RESOLVE = 'from-env'
        try {
            Resolve-Setting -Explicit 'from-param' -EnvName 'SAC_TEST_RESOLVE' | Should -Be 'from-param'
        }
        finally { Remove-Item Env:SAC_TEST_RESOLVE -ErrorAction SilentlyContinue }
    }

    It 'falls back to the first set environment variable' {
        $env:SAC_TEST_RESOLVE_2 = 'from-env-2'
        try {
            Resolve-Setting -EnvName 'SAC_TEST_MISSING', 'SAC_TEST_RESOLVE_2' | Should -Be 'from-env-2'
        }
        finally { Remove-Item Env:SAC_TEST_RESOLVE_2 -ErrorAction SilentlyContinue }
    }

    It 'returns null when nothing is set' {
        Resolve-Setting -EnvName 'SAC_DEFINITELY_NOT_SET_XYZ' | Should -BeNullOrEmpty
    }
}
