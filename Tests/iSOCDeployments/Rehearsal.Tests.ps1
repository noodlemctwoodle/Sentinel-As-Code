#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for New-iSOCClassicTableFixture, Remove-iSOCClassicTableFixture and
    Test-iSOCDcrIngestion.

.DESCRIPTION
    The pure helpers (the Data Collector signature, the fixture and stream
    records, the token request, the dotenv reader, the DCR readers) are held
    to explicit expected values for a handful of representative inputs.

    Each command runs through mocks of the module's REST client, HTTP client
    and log query, over one stand-in
    (Tests/iSOCDeployments/_helpers/RehearsalStandIn.psm1) that checks every
    Data Collector signature against the workspace key, issues and checks
    tokens, and checks every ingested record against the stream: the posts,
    tokens, ingestion and grants a run makes, the refusals, the environment
    it leaves, and what a removal and a stream return.

    Parity with New-ClassicTableFixture.ps1 and Test-DcrIngestion.ps1 was
    proven on release/26.11.0 before the scripts were removed.

.NOTES
    File:         Tests/iSOCDeployments/Rehearsal.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:helperPath = Join-Path $PSScriptRoot '_helpers/RehearsalStandIn.psm1'
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module $script:helperPath -Force
    $script:tenant = '22222222-3333-4444-5555-666666666666'
    $script:roleIds = @{ 'Monitoring Metrics Publisher' = '3913510d-42f4-4e42-8a64-420c390055eb' }
    $script:settingNames = 'DCR_INGEST_TENANT_ID', 'AZURE_TENANT_ID', 'DCR_INGEST_CLIENT_ID', 'AZURE_CLIENT_ID', 'DCR_INGEST_CLIENT_SECRET', 'AZURE_CLIENT_SECRET'
    $script:savedSettings = @{}
    foreach ($n in $script:settingNames) { $script:savedSettings[$n] = [System.Environment]::GetEnvironmentVariable($n); [System.Environment]::SetEnvironmentVariable($n, $null) }

    function Invoke-ModuleRehearsal {
        param([string] $Command, [hashtable] $Parameters, [string] $FailBatch = '', [switch] $FailCollector)
        $script:rehState = Get-RehearsalStandIn -FailBatch @($FailBatch -split ',' | Where-Object { $_ } | ForEach-Object { [int]$_ }) -FailCollector:$FailCollector
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
        Mock -ModuleName iSOCDeployments Start-Sleep { }
        Mock -ModuleName iSOCDeployments Invoke-iSOCAzLogQuery { Invoke-RehearsalQuery -State $script:rehState -Query $Query }
        Mock -ModuleName iSOCDeployments Invoke-iSOCHttpRequest {
            $s = $script:rehState
            if ($Uri -like '*ods.opinsights*') { return [pscustomobject]@{ StatusCode = (Invoke-RehearsalCollector -State $s -Uri $Uri -Headers $Headers -Body $Body); Content = '' } }
            if ($Uri -like 'https://login.*') {
                $t = Invoke-RehearsalToken -State $s -Uri $Uri -Form $Body
                return [pscustomobject]@{ StatusCode = $t.Status; Content = (ConvertTo-Json -InputObject $t.Body) }
            }
            $r = Invoke-RehearsalIngest -State $s -Uri $Uri -Headers $Headers -Body $Body
            [pscustomobject]@{ StatusCode = $r.Status; Content = $r.Content }
        }
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
            $s = $script:rehState
            if ($Api -eq 'Graph') {
                $q = [Uri]::UnescapeDataString($Path)
                if ($q -match "appId eq '([^']+)'") { if ($s.Apps.Contains($Matches[1])) { return [pscustomobject]@{ id = $s.Apps[$Matches[1]] } }; return }
                if ($q -match '^/directoryObjects/') { return }
                throw "unexpected Graph $Path"
            }
            if ($Path -match "/providers/Microsoft\.Authorization/roleAssignments\?\`$filter=assignedTo\('([^']+)'\)$") {
                return @(Get-RehearsalAssignment -State $s -PrincipalId $Matches[1] | ForEach-Object {
                        [pscustomobject]@{ id = 'a'; name = 'a'; properties = [pscustomobject]@{ scope = $_.Scope; principalId = $_.PrincipalId; roleDefinitionId = "/x/roleDefinitions/$($script:roleIds[$_.Role])" } }
                    })
            }
            if ($Method -eq 'PUT' -and $Path -match '^(.+)/providers/Microsoft\.Authorization/roleAssignments/') {
                $roleId = ($Body.properties.roleDefinitionId -split '/')[-1]
                $role = @($script:roleIds.Keys | Where-Object { $script:roleIds[$_] -eq $roleId })[0]
                Add-RehearsalAssignment -State $s -PrincipalId $Body.properties.principalId -Role $role -Scope $Matches[1]
                return
            }
            $a = Invoke-RehearsalArm -State $s -Method $Method -Path $Path
            if ($a.Status -eq 404 -and $AllowNotFound) { return }
            if ($a.Status -ge 400) { throw [System.Net.Http.HttpRequestException]::new("HTTP $($a.Status) from $Method $Path", $null, [System.Net.HttpStatusCode]$a.Status) }
            if ($null -eq $a.Body) { return }
            ConvertTo-Json -InputObject $a.Body -Depth 30 | ConvertFrom-Json -Depth 30
        }
        $ctx = InModuleScope iSOCDeployments -Parameters @{ State = $script:rehState } {
            param($State)
            New-iSOCContext -Value @{
                TenantId = 't'; SubscriptionId = $State.SubscriptionId; ResourceGroup = 'rg-scratch'; WorkspaceName = $State.WorkspaceName
                WorkspaceResourceId = $State.WorkspacePath; WorkspaceId = $State.WorkspaceId; Region = 'uksouth'; PlaybookResourceGroup = 'rg-scratch'
                Environment = 'AzureCloud'; IsGov = $false; ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'tester'
            }
        }
        $p = @{} + $Parameters
        if ($p.ContainsKey('ClientSecret')) { $p.ClientSecret = ConvertTo-SecureString $p.ClientSecret -AsPlainText -Force }
        $result = $null
        $failure = $null
        try { $result = & $Command -Context $ctx @p }
        catch { $failure = $_.Exception.Message }
        [pscustomobject]@{ Result = $result; Error = $failure; Writes = @($script:rehState.Writes) }
    }

    function Use-RehearsalFolder {
        param([switch] $EnvFile)
        $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $folder | Out-Null
        if ($EnvFile) {
            Set-Content -LiteralPath (Join-Path $folder '.env') -Value @(
                '# rehearsal service principal'
                "export DCR_INGEST_TENANT_ID=`"$script:tenant`""
                "DCR_INGEST_CLIENT_ID='aaaaaaaa-1111-2222-3333-444444444444'"
                'DCR_INGEST_CLIENT_SECRET=secret-a'
                ''
            )
        }
        $folder
    }
}

AfterAll {
    foreach ($n in $script:settingNames) { [System.Environment]::SetEnvironmentVariable($n, $script:savedSettings[$n]) }
}

Describe 'The rehearsal helpers' {
    BeforeAll {
        $script:dcr = (Get-RehearsalStandIn).Dcrs['dcr-myapp'] | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
    }

    It 'signs a Data Collector request' {
        $key = [Convert]::ToBase64String([byte[]](1..64))
        $expected = @{ 0 = 'SharedKey w:ZqpO8uO8Bv8ECop6LH2TtIeXC6tko6BfnzrU9PDO0x8='; 17 = 'SharedKey w:gND5swjDHrbvWi45mH9IqInLNv/BN37x90JnPLRJemQ='; 4096 = 'SharedKey w:QHyIbtbdovyOcIHGjsFq1CMdGiYEUmCIpyXiaqHMjCQ=' }
        foreach ($len in 0, 17, 4096) {
            $new = InModuleScope iSOCDeployments -Parameters @{ Key = $key; Len = $len } { param($Key, $Len) New-iSOCDataCollectorSignature -WorkspaceId 'w' -SharedKey $Key -ContentLength $Len -Rfc1123Date 'Wed, 04 Nov 2026 10:00:00 GMT' }
            $new | Should -BeExactly $expected[$len] -Because "a body of $len bytes"
        }
    }

    It 'makes the fixture records' {
        $at = [datetime]::new(2026, 11, 4, 10, 0, 0, [System.DateTimeKind]::Utc)
        $new = InModuleScope iSOCDeployments -Parameters @{ At = $at } { param($At) New-iSOCFixtureRecord -Count 9 -ReferenceTime $At -SeedGuid '0a1b2c3d-0000-0000-0000-000000000001' }
        $expected = '[{"DurationMs":1.5,"EventId":"0a1b2c3d-0000-0000-0000-000000000001","Message":"Synthetic fixture record 0 for classic-table migration testing.","Severity":"Information","SourceHost":"web-01","SourceIp":"10.0.0.0","Success":false,"Timestamp":"2026-11-04T10:00:00.0000000Z"},' +
        '{"DurationMs":15.2,"EventId":"0a1b2c3d-0000-0000-0000-000000000001","Message":"Synthetic fixture record 1 for classic-table migration testing.","Severity":"Warning","SourceHost":"web-02","SourceIp":"10.0.1.7","Success":true,"Timestamp":"2026-11-04T09:59:59.0000000Z"},' +
        '{"DurationMs":28.9,"EventId":"0a1b2c3d-0000-0000-0000-000000000001","Message":"Synthetic fixture record 2 for classic-table migration testing.","Severity":"Error","SourceHost":"db-01","SourceIp":"10.0.2.14","Success":true,"Timestamp":"2026-11-04T09:59:58.0000000Z"},' +
        '{"DurationMs":42.6,"EventId":"0a1b2c3d-0000-0000-0000-000000000001","Message":"Synthetic fixture record 3 for classic-table migration testing.","Severity":"Information","SourceHost":"app-01","SourceIp":"10.0.3.21","Success":true,"Timestamp":"2026-11-04T09:59:57.0000000Z"},' +
        '{"DurationMs":56.3,"EventId":"0a1b2c3d-0000-0000-0000-000000000001","Message":"Synthetic fixture record 4 for classic-table migration testing.","Severity":"Warning","SourceHost":"web-01","SourceIp":"10.0.4.28","Success":true,"Timestamp":"2026-11-04T09:59:56.0000000Z"},' +
        '{"DurationMs":70.0,"EventId":"0a1b2c3d-0000-0000-0000-000000000001","Message":"Synthetic fixture record 5 for classic-table migration testing.","Severity":"Error","SourceHost":"web-02","SourceIp":"10.0.5.35","Success":false,"Timestamp":"2026-11-04T09:59:55.0000000Z"},' +
        '{"DurationMs":83.7,"EventId":"0a1b2c3d-0000-0000-0000-000000000001","Message":"Synthetic fixture record 6 for classic-table migration testing.","Severity":"Information","SourceHost":"db-01","SourceIp":"10.0.6.42","Success":true,"Timestamp":"2026-11-04T09:59:54.0000000Z"},' +
        '{"DurationMs":97.4,"EventId":"0a1b2c3d-0000-0000-0000-000000000001","Message":"Synthetic fixture record 7 for classic-table migration testing.","Severity":"Warning","SourceHost":"app-01","SourceIp":"10.0.7.49","Success":true,"Timestamp":"2026-11-04T09:59:53.0000000Z"},' +
        '{"DurationMs":111.1,"EventId":"0a1b2c3d-0000-0000-0000-000000000001","Message":"Synthetic fixture record 8 for classic-table migration testing.","Severity":"Error","SourceHost":"web-01","SourceIp":"10.0.8.56","Success":true,"Timestamp":"2026-11-04T09:59:52.0000000Z"}]'
        (ConvertTo-RehearsalCanonical @($new)) | Should -BeExactly $expected
    }

    It 'makes the stream records' {
        $at = [datetime]::new(2026, 11, 4, 10, 0, 0, [System.DateTimeKind]::Utc)
        $columns = @($script:dcr.properties.streamDeclarations.'Custom-MyApp_CL'.columns) + @([pscustomobject]@{ name = 'Other'; type = 'guid' })
        (ConvertTo-Json -InputObject $columns -Compress) | Should -BeExactly '[{"name":"TimeGenerated","type":"datetime"},{"name":"Message_s","type":"string"},{"name":"Count_d","type":"real"},{"name":"Flag_b","type":"boolean"},{"name":"Level_i","type":"int"},{"name":"Big_l","type":"long"},{"name":"Props_d","type":"dynamic"},{"name":"Other","type":"guid"}]'
        $new = InModuleScope iSOCDeployments -Parameters @{ At = $at; Columns = $columns } { param($At, $Columns) foreach ($i in 0..4) { New-iSOCStreamRecord -StreamColumn $Columns -Index $i -RunId 'abcdef123456' -ReferenceTime $At } }
        $expected = '[{"Big_l":0,"Count_d":0.5,"Flag_b":true,"Level_i":0,"Message_s":"dcr-test abcdef123456 #0","Other":"dcr-test abcdef123456 #0","Props_d":{"index":0,"runId":"abcdef123456"},"TimeGenerated":"2026-11-04T10:00:00.0000000Z"},' +
        '{"Big_l":1,"Count_d":2.0,"Flag_b":false,"Level_i":1,"Message_s":"dcr-test abcdef123456 #1","Other":"dcr-test abcdef123456 #1","Props_d":{"index":1,"runId":"abcdef123456"},"TimeGenerated":"2026-11-04T10:00:00.0000000Z"},' +
        '{"Big_l":2,"Count_d":3.5,"Flag_b":true,"Level_i":2,"Message_s":"dcr-test abcdef123456 #2","Other":"dcr-test abcdef123456 #2","Props_d":{"index":2,"runId":"abcdef123456"},"TimeGenerated":"2026-11-04T10:00:00.0000000Z"},' +
        '{"Big_l":3,"Count_d":5.0,"Flag_b":false,"Level_i":3,"Message_s":"dcr-test abcdef123456 #3","Other":"dcr-test abcdef123456 #3","Props_d":{"index":3,"runId":"abcdef123456"},"TimeGenerated":"2026-11-04T10:00:00.0000000Z"},' +
        '{"Big_l":4,"Count_d":6.5,"Flag_b":true,"Level_i":4,"Message_s":"dcr-test abcdef123456 #4","Other":"dcr-test abcdef123456 #4","Props_d":{"index":4,"runId":"abcdef123456"},"TimeGenerated":"2026-11-04T10:00:00.0000000Z"}]'
        (ConvertTo-RehearsalCanonical @($new)) | Should -BeExactly $expected
    }

    It 'builds the token request' {
        $new = InModuleScope iSOCDeployments { New-iSOCTokenRequest -AuthorityHost 'https://login.microsoftonline.com/' -TenantId 't' -ClientId 'c' -Audience 'https://monitor.azure.com/' -ClientSecretPlain 's' }
        (ConvertTo-RehearsalCanonical $new) | Should -BeExactly '{"Body":{"client_id":"c","client_secret":"s","grant_type":"client_credentials","scope":"https://monitor.azure.com/.default"},"Uri":"https://login.microsoftonline.com/t/oauth2/v2.0/token"}'
    }

    It 'reads a dotenv file' {
        $file = Join-Path $TestDrive 'sample.env'
        Set-Content -LiteralPath $file -Value @('# c', '', 'A=1', 'export B = "two words" ', "C='3'", 'D=', 'bad line', '9X=no', 'E="unclosed')
        (ConvertTo-RehearsalCanonical (InModuleScope iSOCDeployments -Parameters @{ F = $file } { param($F) Import-iSOCDotEnv -Path $F })) | Should -BeExactly '{"A":"1","B":"two words","C":"3","D":"","E":"\"unclosed"}'
        (InModuleScope iSOCDeployments { Import-iSOCDotEnv -Path '/no/such/file' }).Count | Should -Be 0
    }

    It 'reads a rule''s target, stream, columns and destination' {
        $two = (Get-RehearsalStandIn).Dcrs['dcr-two'] | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        $new = InModuleScope iSOCDeployments -Parameters @{ Dcr = $script:dcr; Two = $two } { param($Dcr, $Two) [ordered]@{ Target = Get-iSOCDcrIngestionTarget -Dcr $Dcr; Stream = Get-iSOCDcrStreamName -Dcr $Dcr; Columns = @(Get-iSOCDcrStreamColumn -Dcr $Dcr -Stream 'Custom-MyApp_CL'); Destination = Get-iSOCDcrDestinationTable -Dcr $Two -Stream 'Custom-Two_CL' } }
        $expected = '{"Columns":[{"name":"TimeGenerated","type":"datetime"},{"name":"Message_s","type":"string"},{"name":"Count_d","type":"real"},{"name":"Flag_b","type":"boolean"},{"name":"Level_i","type":"int"},{"name":"Big_l","type":"long"},{"name":"Props_d","type":"dynamic"}],' +
        '"Destination":"Two_CL",' +
        '"Stream":"Custom-MyApp_CL",' +
        '"Target":{"Endpoint":"https://dcr-myapp-x1y2.uksouth-1.ingest.monitor.azure.com","ImmutableId":"dcr-dcrmyapp000000000000000000000000"}}'
        (ConvertTo-RehearsalCanonical $new) | Should -BeExactly $expected
    }
}

Describe 'The rehearsal commands' {
    It 'have something to compare: posts, tokens, ingestion and grants' {
        $run = Invoke-ModuleRehearsal -Command 'Test-iSOCDcrIngestion' -Parameters @{ DcrName = 'dcr-myapp'; DcrResourceGroupName = 'rg-scratch'; TenantId = $script:tenant; ClientId = 'aaaaaaaa-1111-2222-3333-444444444444'; ClientSecret = 'secret-a'; BatchCount = 2; BatchSize = 3; Follow = $true; GrantIngestionRole = $true }
        @($run.Writes.Kind) | Should -Be @('Grant', 'Token', 'Ingest', 'Ingest')
        $run.Result.Arrived | Should -Be 6
        $fixture = Invoke-ModuleRehearsal -Command 'New-iSOCClassicTableFixture' -Parameters @{ TableName = 'Check'; RecordCount = 3 }
        @($fixture.Writes.Kind) | Should -Be @('Post')
        $fixture.Result.SubType | Should -Be 'Classic'
    }

    It 'refuses: <Label>' -ForEach @(
        @{ Label = 'a wrong secret'; Parameters = @{ DcrName = 'dcr-myapp'; ClientId = 'aaaaaaaa-1111-2222-3333-444444444444'; ClientSecret = 'wrong'; BatchCount = 1 }; Like = 'Token request failed:*Check the tenant, client ID and secret.' }
        @{ Label = 'a rule with no endpoint'; Parameters = @{ DcrName = 'dcr-bare'; ClientId = 'aaaaaaaa-1111-2222-3333-444444444444'; ClientSecret = 'secret-a'; BatchCount = 1 }; Message = 'This DCR has no logsIngestion endpoint. Endpoints exist only on DCRs created with kind Direct on api-version 2023-03-11 or later, and cannot be added afterwards. Recreate the DCR, or use a Data Collection Endpoint.' }
        @{ Label = 'two streams and no choice'; Parameters = @{ DcrName = 'dcr-two'; ClientId = 'aaaaaaaa-1111-2222-3333-444444444444'; ClientSecret = 'secret-a'; BatchCount = 1 }; Message = 'This DCR declares 2 streams (Custom-One_CL, Custom-Two_CL). Pass -StreamName to choose one.' }
        @{ Label = 'an unknown client'; Parameters = @{ DcrName = 'dcr-myapp'; ClientId = 'cccccccc-1111-2222-3333-444444444444'; ClientSecret = 'x'; BatchCount = 1 }; Message = 'No service principal found for client ID cccccccc-1111-2222-3333-444444444444 in this tenant.' }
        @{ Label = 'no tenant'; NoTenant = $true; Parameters = @{ DcrName = 'dcr-myapp'; BatchCount = 1 }; Message = 'No tenant ID. Pass -TenantId, or set DCR_INGEST_TENANT_ID / AZURE_TENANT_ID (e.g. in .env).' }
    ) {
        $folder = Use-RehearsalFolder
        $p = @{ DcrResourceGroupName = 'rg-scratch' } + $Parameters
        if (-not $NoTenant) { $p.TenantId = $script:tenant }
        Push-Location -LiteralPath $folder
        try { $module = Invoke-ModuleRehearsal -Command 'Test-iSOCDcrIngestion' -Parameters $p }
        finally { Pop-Location }
        $module.Error | Should -Not -BeNullOrEmpty
        if ($Message) { $module.Error | Should -BeExactly $Message }
        else { $module.Error | Should -BeLike $Like }
        @($module.Writes | Where-Object Kind -EQ 'Ingest') | Should -BeNullOrEmpty
    }

    It 'leaves the environment as it found it' {
        $folder = Use-RehearsalFolder -EnvFile
        Push-Location -LiteralPath $folder
        try { Invoke-ModuleRehearsal -Command 'Test-iSOCDcrIngestion' -Parameters @{ DcrName = 'dcr-myapp'; DcrResourceGroupName = 'rg-scratch'; BatchCount = 1 } | Out-Null }
        finally { Pop-Location }
        [System.Environment]::GetEnvironmentVariable('DCR_INGEST_TENANT_ID') | Should -BeNullOrEmpty
        [System.Environment]::GetEnvironmentVariable('DCR_INGEST_CLIENT_SECRET') | Should -BeNullOrEmpty
    }

    It 'reports what a removal did' {
        (Invoke-ModuleRehearsal -Command 'Remove-iSOCClassicTableFixture' -Parameters @{ TableName = 'Old_CL'; Confirm = $false }).Result.Outcome | Should -Be 'StillClassic'
        (Invoke-ModuleRehearsal -Command 'Remove-iSOCClassicTableFixture' -Parameters @{ TableName = 'Old_CL'; MigrateBeforeRemove = $true; Confirm = $false }).Result.Outcome | Should -Be 'Removed'
        (Invoke-ModuleRehearsal -Command 'Remove-iSOCClassicTableFixture' -Parameters @{ TableName = 'Gone'; Confirm = $false }).Result.Outcome | Should -Be 'NotFound'
        (Invoke-ModuleRehearsal -Command 'Remove-iSOCClassicTableFixture' -Parameters @{ TableName = 'Done_CL'; WhatIf = $true }).Result.Outcome | Should -Be 'Skipped'
    }

    It 'returns what a stream sent' {
        $run = Invoke-ModuleRehearsal -Command 'New-iSOCClassicTableFixture' -Parameters @{ TableName = 'Stream2'; Stream = $true; RecordCount = 4; BatchCount = 2; IntervalSeconds = 1 }
        $run.Result.BatchesSent | Should -Be 2
        $run.Result.BatchesFailed | Should -Be 0
        $run.Result.RecordsSent | Should -Be 8
    }

    It 'ends a stream whose every post fails after -BatchCount, as 1.0.2 does' {
        $run = Invoke-ModuleRehearsal -Command 'New-iSOCClassicTableFixture' -FailCollector -Parameters @{ TableName = 'Stream4'; Stream = $true; RecordCount = 2; BatchCount = 3; IntervalSeconds = 1 }
        $run.Result.BatchesSent | Should -Be 3
        $run.Result.BatchesFailed | Should -Be 3
        $run.Result.RecordsSent | Should -Be 0
    }
}
