#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for New-iSOCClassicTableFixture, Remove-iSOCClassicTableFixture and
    Test-iSOCDcrIngestion, against the scripts under Tools/ClassicToDcr/Rehearsal/.

.DESCRIPTION
    The pure helpers (the Data Collector signature, the fixture and stream
    records, the token request, the dotenv reader, the DCR readers) run
    beside the scripts' own and must answer the same.

    Then each script runs unchanged in a child pwsh, its Az cmdlets,
    Invoke-RestMethod, Invoke-WebRequest and Start-Sleep stood in for, and
    each command runs through mocks of the module's REST client, HTTP
    client and log query, over one stand-in
    (Tests/iSOCDeployments/_helpers/RehearsalStandIn.psm1) that checks every
    Data Collector signature against the workspace key, issues and checks
    tokens, and checks every ingested record against the stream. Both must
    make the same posts, migrations, deletions, token requests, ingestion
    posts and grants, in order, and return the same result.

.NOTES
    File:         Tests/iSOCDeployments/Rehearsal.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeDiscovery {
    $script:fixtureRuns = @(
        @{ Label = 'a fixture seeded once'; Parameters = @{ TableName = 'SacMigrationTest'; RecordCount = 7 } }
        @{ Label = 'a fixture named with _CL'; Parameters = @{ TableName = 'Sac_CL'; RecordCount = 1 } }
        @{ Label = 'a fixture streamed in batches'; Parameters = @{ TableName = 'Stream1'; Stream = $true; RecordCount = 2; BatchCount = 3; IntervalSeconds = 1 } }
        @{ Label = 'a fixture under -WhatIf'; Parameters = @{ TableName = 'SacMigrationTest'; WhatIf = $true } }
        @{ Label = 'a stream whose every post fails'; FailCollector = $true; Parameters = @{ TableName = 'Stream3'; Stream = $true; RecordCount = 2; BatchCount = 3; IntervalSeconds = 1 } }
        @{ Label = 'a classic table left'; Remove = $true; Parameters = @{ TableName = 'Old_CL'; Confirm = $false } }
        @{ Label = 'a classic table migrated, then deleted'; Remove = $true; Parameters = @{ TableName = 'Old'; MigrateBeforeRemove = $true; Confirm = $false } }
        @{ Label = 'a DCR-based table deleted'; Remove = $true; Parameters = @{ TableName = 'Done_CL'; Confirm = $false } }
        @{ Label = 'a table already gone'; Remove = $true; Parameters = @{ TableName = 'Gone_CL'; Confirm = $false } }
        @{ Label = 'a removal under -WhatIf'; Remove = $true; Parameters = @{ TableName = 'Old_CL'; MigrateBeforeRemove = $true; WhatIf = $true } }
    )
    $script:ingestionRuns = @(
        @{ Label = 'three batches, granted and followed'; Parameters = @{ DcrName = 'dcr-myapp'; ClientId = 'aaaaaaaa-1111-2222-3333-444444444444'; ClientSecret = 'secret-a'; BatchCount = 3; BatchSize = 4; Follow = $true; GrantIngestionRole = $true } }
        @{ Label = 'a principal that already holds the role'; Parameters = @{ DcrName = 'dcr-myapp'; ClientId = 'bbbbbbbb-1111-2222-3333-444444444444'; ClientSecret = 'secret-b'; BatchCount = 2; BatchSize = 1; GrantIngestionRole = $true } }
        @{ Label = 'a principal without the role, not granted'; Parameters = @{ DcrName = 'dcr-myapp'; ClientId = 'aaaaaaaa-1111-2222-3333-444444444444'; ClientSecret = 'secret-a'; BatchCount = 1; BatchSize = 2 } }
        @{ Label = 'a batch the service refuses'; FailBatch = '2'; Parameters = @{ DcrName = 'dcr-myapp'; ClientId = 'aaaaaaaa-1111-2222-3333-444444444444'; ClientSecret = 'secret-a'; BatchCount = 3; BatchSize = 2; Follow = $true; ArrivalTimeoutSeconds = 20 } }
        @{ Label = 'a stream chosen from two'; Parameters = @{ DcrName = 'dcr-two'; StreamName = 'Custom-Two_CL'; ClientId = 'aaaaaaaa-1111-2222-3333-444444444444'; ClientSecret = 'secret-a'; BatchCount = 1; BatchSize = 3 } }
        @{ Label = 'the settings from .env'; EnvFile = $true; Parameters = @{ DcrName = 'dcr-myapp'; BatchCount = 1; BatchSize = 1 } }
        @{ Label = '-WhatIf'; Parameters = @{ DcrName = 'dcr-myapp'; ClientId = 'aaaaaaaa-1111-2222-3333-444444444444'; ClientSecret = 'secret-a'; BatchCount = 2; WhatIf = $true; GrantIngestionRole = $true } }
    )
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:fixtureScript = Join-Path $script:repoRoot 'Tools/ClassicToDcr/Rehearsal/New-ClassicTableFixture.ps1'
    $script:ingestScript = Join-Path $script:repoRoot 'Tools/ClassicToDcr/Rehearsal/Test-DcrIngestion.ps1'
    $script:helperPath = Join-Path $PSScriptRoot '_helpers/RehearsalStandIn.psm1'
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module $script:helperPath -Force
    $script:tenant = '22222222-3333-4444-5555-666666666666'
    $script:roleIds = @{ 'Monitoring Metrics Publisher' = '3913510d-42f4-4e42-8a64-420c390055eb' }
    $script:settingNames = 'DCR_INGEST_TENANT_ID', 'AZURE_TENANT_ID', 'DCR_INGEST_CLIENT_ID', 'AZURE_CLIENT_ID', 'DCR_INGEST_CLIENT_SECRET', 'AZURE_CLIENT_SECRET'
    $script:savedSettings = @{}
    foreach ($n in $script:settingNames) { $script:savedSettings[$n] = [System.Environment]::GetEnvironmentVariable($n); [System.Environment]::SetEnvironmentVariable($n, $null) }

    $script:wrapper = @'
param([string] $Script, [string] $Helper, [string] $Parameters, [string] $Out, [string] $FailBatch = '', [switch] $FailCollector)
$ErrorActionPreference = 'Stop'
Import-Module $Helper -Force
$global:RehState = Get-RehearsalStandIn -FailBatch @($FailBatch -split ',' | Where-Object { $_ } | ForEach-Object { [int]$_ }) -FailCollector:$FailCollector
function Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = $global:RehState.SubscriptionId }; Account = [pscustomobject]@{ Id = 'tester' } } }
function Set-AzContext { param($Subscription) Get-AzContext }
function Get-AzOperationalInsightsWorkspace { param($ResourceGroupName, $Name) [pscustomobject]@{ CustomerId = [guid]$global:RehState.WorkspaceId; ResourceId = $global:RehState.WorkspacePath; Location = 'uksouth' } }
function Get-AzOperationalInsightsWorkspaceSharedKey { param($ResourceGroupName, $Name) [pscustomobject]@{ PrimarySharedKey = $global:RehState.SharedKey; SecondarySharedKey = 'second' } }
function Invoke-AzRestMethod {
    param($Path, $Uri, $Method = 'GET', $Payload)
    $t = if ($Path) { $Path } else { ([Uri]$Uri).PathAndQuery }
    $a = Invoke-RehearsalArm -State $global:RehState -Method $Method -Path $t
    [pscustomobject]@{ StatusCode = $a.Status; Content = $(if ($null -ne $a.Body) { ConvertTo-Json -InputObject $a.Body -Depth 30 } else { '' }) }
}
function Invoke-AzOperationalInsightsMigrateTable { param($ResourceGroupName, $WorkspaceName, $TableName, $Confirm) $null = Invoke-RehearsalArm -State $global:RehState -Method POST -Path "$($global:RehState.WorkspacePath)/tables/$TableName/migrate" }
function Invoke-RestMethod {
    param($Uri, $Method, $ContentType, $Headers, $Body)
    if ($Uri -like '*ods.opinsights*') {
        $s = Invoke-RehearsalCollector -State $global:RehState -Uri $Uri -Headers $Headers -Body $Body
        if ($s -ne 200) { throw "Response status code does not indicate success: $s." }
        return
    }
    $t = Invoke-RehearsalToken -State $global:RehState -Uri $Uri -Form $Body
    if ($t.Status -ne 200) { throw "Response status code does not indicate success: $($t.Status) (Unauthorized)." }
    [pscustomobject]$t.Body
}
function Invoke-WebRequest {
    param($Uri, $Method, $Headers, $ContentType, $Body, [switch] $SkipHttpErrorCheck)
    $r = Invoke-RehearsalIngest -State $global:RehState -Uri $Uri -Headers $Headers -Body $Body
    [pscustomobject]@{ StatusCode = $r.Status; Content = $r.Content }
}
function Get-AzADServicePrincipal { param($ApplicationId, $ErrorAction) if ($global:RehState.Apps.Contains($ApplicationId)) { [pscustomobject]@{ Id = $global:RehState.Apps[$ApplicationId] } } }
function Get-AzRoleAssignment { param($ObjectId, $Scope, $RoleDefinitionName, $ErrorAction) @(Get-RehearsalAssignment -State $global:RehState -PrincipalId $ObjectId -Scope $Scope | Where-Object { $_.Role -eq $RoleDefinitionName }) }
function New-AzRoleAssignment { param($ObjectId, $RoleDefinitionName, $Scope) Add-RehearsalAssignment -State $global:RehState -PrincipalId $ObjectId -Role $RoleDefinitionName -Scope $Scope; [pscustomobject]@{ RoleAssignmentId = 'x' } }
function Invoke-AzOperationalInsightsQuery { param($WorkspaceId, $Query, $ErrorAction) Invoke-RehearsalQuery -State $global:RehState -Query $Query }
function Start-Sleep { param($Seconds) }
$splat = Get-Content -LiteralPath $Parameters -Raw | ConvertFrom-Json -AsHashtable
if ($splat.Contains('ClientSecret')) { $splat.ClientSecret = ConvertTo-SecureString $splat.ClientSecret -AsPlainText -Force }
$code = 0
$result = $null
try { $result = & $Script @splat }
catch { $code = 1; Set-Content -LiteralPath (Join-Path $Out 'error.txt') -Value $_.Exception.Message }
Set-Content -LiteralPath (Join-Path $Out 'results.json') -Value (ConvertTo-Json -InputObject @($result) -Depth 10)
Set-Content -LiteralPath (Join-Path $Out 'writes.json') -Value (ConvertTo-Json -InputObject @($global:RehState.Writes) -Depth 10)
exit $code
'@

    function Invoke-LegacyRehearsal {
        param([string] $Script, [hashtable] $Parameters, [string] $FailBatch = '', [switch] $FailCollector)
        $tree = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $out = Join-Path $tree 'out'
        New-Item -ItemType Directory -Path $out -Force | Out-Null
        $copy = Join-Path $tree (Split-Path -Leaf $Script)
        Set-Content -LiteralPath $copy -Value ((Get-Content -LiteralPath $Script -Raw) -replace '(?m)^#Requires -Modules[^\r\n]*\r?\n', '') -NoNewline
        Set-Content -LiteralPath (Join-Path $tree 'run.ps1') -Value $script:wrapper
        Set-Content -LiteralPath (Join-Path $tree 'parameters.json') -Value (ConvertTo-Json -InputObject $Parameters)
        $output = & pwsh -NoProfile -NonInteractive -File (Join-Path $tree 'run.ps1') -Script $copy -Helper $script:helperPath -Parameters (Join-Path $tree 'parameters.json') -Out $out -FailBatch $FailBatch -FailCollector:$FailCollector 2>&1 | Out-String
        $errorFile = Join-Path $out 'error.txt'
        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output   = $output
            Error    = if (Test-Path -LiteralPath $errorFile) { (Get-Content -LiteralPath $errorFile -Raw).Trim() } else { $null }
            Results  = @(Get-Content -LiteralPath (Join-Path $out 'results.json') -Raw | ConvertFrom-Json -Depth 10 | Where-Object { $null -ne $_ })
            Writes   = @(Get-Content -LiteralPath (Join-Path $out 'writes.json') -Raw | ConvertFrom-Json -Depth 10 | Where-Object { $null -ne $_ })
        }
    }

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

    function ConvertTo-ComparableWrite {
        param($Writes)
        @($Writes | ForEach-Object { ConvertTo-RehearsalCanonical $_ })
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

Describe 'The rehearsal helpers, beside the scripts''' {
    BeforeAll {
        Import-Module (Join-Path $script:repoRoot 'Tests/_helpers/Import-ScriptFunctions.psm1') -Force
        Import-ScriptFunctions -Path $script:fixtureScript
        Import-ScriptFunctions -Path $script:ingestScript
        $script:dcr = (Get-RehearsalStandIn).Dcrs['dcr-myapp'] | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
    }

    It 'signs a Data Collector request the same' {
        $key = [Convert]::ToBase64String([byte[]](1..64))
        foreach ($len in 0, 17, 4096) {
            $old = New-DataCollectorSignature -WorkspaceId 'w' -SharedKey $key -ContentLength $len -Rfc1123Date 'Wed, 04 Nov 2026 10:00:00 GMT'
            $new = InModuleScope iSOCDeployments -Parameters @{ Key = $key; Len = $len } { param($Key, $Len) New-iSOCDataCollectorSignature -WorkspaceId 'w' -SharedKey $Key -ContentLength $Len -Rfc1123Date 'Wed, 04 Nov 2026 10:00:00 GMT' }
            $new | Should -BeExactly $old
        }
    }

    It 'makes the same fixture records' {
        $at = [datetime]::new(2026, 11, 4, 10, 0, 0, [System.DateTimeKind]::Utc)
        $old = New-FixtureRecord -Count 9 -ReferenceTime $at -SeedGuid '0a1b2c3d-0000-0000-0000-000000000001'
        $new = InModuleScope iSOCDeployments -Parameters @{ At = $at } { param($At) New-iSOCFixtureRecord -Count 9 -ReferenceTime $At -SeedGuid '0a1b2c3d-0000-0000-0000-000000000001' }
        (ConvertTo-RehearsalCanonical @($new)) | Should -BeExactly (ConvertTo-RehearsalCanonical @($old))
    }

    It 'makes the same stream records' {
        $at = [datetime]::new(2026, 11, 4, 10, 0, 0, [System.DateTimeKind]::Utc)
        $columns = @($script:dcr.properties.streamDeclarations.'Custom-MyApp_CL'.columns) + @([pscustomobject]@{ name = 'Other'; type = 'guid' })
        $old = foreach ($i in 0..4) { New-StreamRecord -StreamColumn $columns -Index $i -RunId 'abcdef123456' -ReferenceTime $at }
        $new = InModuleScope iSOCDeployments -Parameters @{ At = $at; Columns = $columns } { param($At, $Columns) foreach ($i in 0..4) { New-iSOCStreamRecord -StreamColumn $Columns -Index $i -RunId 'abcdef123456' -ReferenceTime $At } }
        (ConvertTo-RehearsalCanonical @($new)) | Should -BeExactly (ConvertTo-RehearsalCanonical @($old))
    }

    It 'builds the same token request' {
        $old = New-TokenRequest -AuthorityHost 'https://login.microsoftonline.com/' -TenantId 't' -ClientId 'c' -Audience 'https://monitor.azure.com/' -ClientSecretPlain 's'
        $new = InModuleScope iSOCDeployments { New-iSOCTokenRequest -AuthorityHost 'https://login.microsoftonline.com/' -TenantId 't' -ClientId 'c' -Audience 'https://monitor.azure.com/' -ClientSecretPlain 's' }
        (ConvertTo-RehearsalCanonical $new) | Should -BeExactly (ConvertTo-RehearsalCanonical $old)
    }

    It 'reads a dotenv file the same' {
        $file = Join-Path $TestDrive 'sample.env'
        Set-Content -LiteralPath $file -Value @('# c', '', 'A=1', 'export B = "two words" ', "C='3'", 'D=', 'bad line', '9X=no', 'E="unclosed')
        (ConvertTo-RehearsalCanonical (InModuleScope iSOCDeployments -Parameters @{ F = $file } { param($F) Import-iSOCDotEnv -Path $F })) | Should -BeExactly (ConvertTo-RehearsalCanonical (Import-DotEnv -Path $file))
        (InModuleScope iSOCDeployments { Import-iSOCDotEnv -Path '/no/such/file' }).Count | Should -Be 0
    }

    It 'reads a rule''s target, stream, columns and destination the same' {
        $two = (Get-RehearsalStandIn).Dcrs['dcr-two'] | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        $old = [ordered]@{ Target = Get-DcrIngestionTarget -Dcr $script:dcr; Stream = Get-DcrStreamName -Dcr $script:dcr; Columns = @(Get-DcrStreamColumn -Dcr $script:dcr -Stream 'Custom-MyApp_CL'); Destination = Get-DestinationTableName -Dcr $two -Stream 'Custom-Two_CL' }
        $new = InModuleScope iSOCDeployments -Parameters @{ Dcr = $script:dcr; Two = $two } { param($Dcr, $Two) [ordered]@{ Target = Get-iSOCDcrIngestionTarget -Dcr $Dcr; Stream = Get-iSOCDcrStreamName -Dcr $Dcr; Columns = @(Get-iSOCDcrStreamColumn -Dcr $Dcr -Stream 'Custom-MyApp_CL'); Destination = Get-iSOCDcrDestinationTable -Dcr $Two -Stream 'Custom-Two_CL' } }
        (ConvertTo-RehearsalCanonical $new) | Should -BeExactly (ConvertTo-RehearsalCanonical $old)
    }
}

Describe 'Parity with New-ClassicTableFixture.ps1: <Label>' -ForEach $script:fixtureRuns {
    BeforeAll {
        $base = @{ ResourceGroupName = 'rg-scratch'; WorkspaceName = 'law-scratch' }
        $legacyParameters = $base + $Parameters
        if ($Remove) { $legacyParameters.Remove = $true }
        $script:legacy = Invoke-LegacyRehearsal -Script $script:fixtureScript -Parameters $legacyParameters -FailCollector:([bool]$FailCollector)
        $command = if ($Remove) { 'Remove-iSOCClassicTableFixture' } else { 'New-iSOCClassicTableFixture' }
        $script:module = Invoke-ModuleRehearsal -Command $command -Parameters $Parameters -FailCollector:([bool]$FailCollector)
    }

    It 'runs the script and the command to the end' {
        $script:legacy.ExitCode | Should -Be 0 -Because $script:legacy.Output
        $script:module.Error | Should -BeNullOrEmpty
    }

    It 'makes the same posts, migrations and deletions, in order' {
        (ConvertTo-ComparableWrite $script:module.Writes) | Should -Be (ConvertTo-ComparableWrite $script:legacy.Writes)
    }

    It 'returns the same fixture' {
        if ($Remove -or $Parameters.ContainsKey('Stream') -or $Parameters.ContainsKey('WhatIf')) {
            $script:legacy.Results | Should -BeNullOrEmpty
            return
        }
        (ConvertTo-RehearsalCanonical $script:module.Result) | Should -BeExactly (ConvertTo-RehearsalCanonical ($script:legacy.Results | Select-Object -First 1))
    }
}

Describe 'Parity with Test-DcrIngestion.ps1: <Label>' -ForEach $script:ingestionRuns {
    BeforeAll {
        $folder = Use-RehearsalFolder -EnvFile:([bool]$EnvFile)
        $p = @{ DcrResourceGroupName = 'rg-scratch' } + $Parameters
        if (-not $EnvFile) { $p.TenantId = $script:tenant }
        Push-Location -LiteralPath $folder
        try {
            $script:legacy = Invoke-LegacyRehearsal -Script $script:ingestScript -Parameters $p -FailBatch ([string]$FailBatch)
            $script:module = Invoke-ModuleRehearsal -Command 'Test-iSOCDcrIngestion' -Parameters $p -FailBatch ([string]$FailBatch)
        }
        finally { Pop-Location }
    }

    It 'runs the script and the command to the end' {
        $script:legacy.ExitCode | Should -Be 0 -Because $script:legacy.Output
        $script:module.Error | Should -BeNullOrEmpty
    }

    It 'makes the same token requests, ingestion posts and grants, in order' {
        (ConvertTo-ComparableWrite $script:module.Writes) | Should -Be (ConvertTo-ComparableWrite $script:legacy.Writes)
    }

    It 'returns the same result' {
        if ($Parameters.ContainsKey('WhatIf')) {
            $script:legacy.Results | Should -BeNullOrEmpty
            $script:module.Result | Should -BeNullOrEmpty
            return
        }
        $strip = { param($r) $o = [ordered]@{}; foreach ($n in $r.PSObject.Properties.Name) { if ($n -ne 'RunId') { $o[$n] = $r.$n } }; ConvertTo-RehearsalCanonical $o }
        (& $strip $script:module.Result) | Should -BeExactly (& $strip ($script:legacy.Results | Select-Object -First 1))
        $script:module.Result.RunId | Should -Match '^[0-9a-f]{12}$'
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

    It 'refuses as the script does: <Label>' -ForEach @(
        @{ Label = 'a wrong secret'; Parameters = @{ DcrName = 'dcr-myapp'; ClientId = 'aaaaaaaa-1111-2222-3333-444444444444'; ClientSecret = 'wrong'; BatchCount = 1 }; Like = 'Token request failed:*Check the tenant, client ID and secret.' }
        @{ Label = 'a rule with no endpoint'; Parameters = @{ DcrName = 'dcr-bare'; ClientId = 'aaaaaaaa-1111-2222-3333-444444444444'; ClientSecret = 'secret-a'; BatchCount = 1 }; Same = $true }
        @{ Label = 'two streams and no choice'; Parameters = @{ DcrName = 'dcr-two'; ClientId = 'aaaaaaaa-1111-2222-3333-444444444444'; ClientSecret = 'secret-a'; BatchCount = 1 }; Same = $true }
        @{ Label = 'an unknown client'; Parameters = @{ DcrName = 'dcr-myapp'; ClientId = 'cccccccc-1111-2222-3333-444444444444'; ClientSecret = 'x'; BatchCount = 1 }; Same = $true }
        @{ Label = 'no tenant'; NoTenant = $true; Parameters = @{ DcrName = 'dcr-myapp'; BatchCount = 1 }; Same = $true }
    ) {
        $folder = Use-RehearsalFolder
        $p = @{ DcrResourceGroupName = 'rg-scratch' } + $Parameters
        if (-not $NoTenant) { $p.TenantId = $script:tenant }
        Push-Location -LiteralPath $folder
        try {
            $legacy = Invoke-LegacyRehearsal -Script $script:ingestScript -Parameters $p
            $module = Invoke-ModuleRehearsal -Command 'Test-iSOCDcrIngestion' -Parameters $p
        }
        finally { Pop-Location }
        $legacy.ExitCode | Should -Be 1
        $module.Error | Should -Not -BeNullOrEmpty
        if ($Same) { $module.Error | Should -BeExactly $legacy.Error }
        else { $legacy.Error | Should -BeLike $Like; $module.Error | Should -BeLike $Like }
        @($module.Writes | Where-Object Kind -eq 'Ingest') | Should -BeNullOrEmpty
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
