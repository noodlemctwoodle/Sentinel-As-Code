#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for Invoke-iSOCClassicTableMigration, against
    Tools/ClassicToDcr/Invoke-ClassicTableMigration.ps1.

.DESCRIPTION
    The stream, transform and template builders run beside the script's own
    over the same schemas and must answer the same.

    Then the script runs unchanged in a child pwsh, its Az cmdlets stood in
    for, and the command runs through mocks of the module's REST client,
    log query and deployment wrapper; both over one stand-in workspace
    (Tests/iSOCDeployments/_helpers/ClassicMigrationStandIn.psm1) whose
    tables turn DCR-based as they are migrated, and whose rules and role
    assignments appear as they are deployed and granted. For each run the
    two must make the same migrations, deployments (the same templates) and
    grants in the same order, write the same template files, and return the
    same result for every table: listing only, every classic table with
    deployment and grants, named tables, templates only, a deploy refused
    while a table is classic, text log rules, a transform given, -WhatIf,
    and Usage that cannot be read.

.NOTES
    File:         Tests/iSOCDeployments/ClassicTableMigration.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeDiscovery {
    $script:scenarios = @(
        @{ Label = 'every classic table, deployed and granted'; Parameters = @{ AllClassicTables = $true; Deploy = $true; Force = $true; GrantIngestionRoleTo = @('aaaaaaaa-1111-2222-3333-444444444444', 'user-object-1', 'held-object-1', 'deny-object-1') } }
        @{ Label = 'named tables, one already DCR-based, one without _CL'; Parameters = @{ TableName = @('Ready_CL', 'Second', 'Odd_CL'); Deploy = $true; Force = $true } }
        @{ Label = 'every classic table, empty ones included'; Parameters = @{ AllClassicTables = $true; IncludeEmptyTables = $true; Force = $true } }
        @{ Label = 'templates only, deploy refused while classic'; Parameters = @{ TableName = @('MyApp_CL'); SkipTableMigration = $true; Deploy = $true } }
        @{ Label = 'a Linux text log rule with an endpoint'; Parameters = @{ TableName = @('MyApp_CL'); DcrKind = 'TextLog'; Platform = 'Linux'; FilePattern = @('/var/log/app/*.log'); Deploy = $true; Force = $true; DcrNamePrefix = 'dcr-text-'; DcrResourceGroupName = 'rg-dcr'; Location = 'westeurope'; DataCollectionEndpointResourceId = '/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-dcr/providers/Microsoft.Insights/dataCollectionEndpoints/dce-1' } }
        @{ Label = 'a json text log rule, templates only'; Parameters = @{ TableName = @('Unknown_CL'); DcrKind = 'TextLog'; LogFormat = 'json'; FilePattern = @('C:\logs\*.json', 'D:\logs\*.json'); SkipTableMigration = $true } }
        @{ Label = 'a transform given'; Parameters = @{ TableName = @('MyApp_CL'); TransformKql = 'source | extend Extra_s = "x"'; Force = $true; Deploy = $true } }
        @{ Label = '-WhatIf'; Parameters = @{ AllClassicTables = $true; Deploy = $true; WhatIf = $true; GrantIngestionRoleTo = @('user-object-1') } }
        @{ Label = 'Usage that cannot be read'; UsageFails = $true; Parameters = @{ TableName = @('MyApp_CL', 'Unknown_CL'); Force = $true } }
    )
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:scriptPath = Join-Path $script:repoRoot 'Tools/ClassicToDcr/Invoke-ClassicTableMigration.ps1'
    $script:helperPath = Join-Path $PSScriptRoot '_helpers/ClassicMigrationStandIn.psm1'
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module $script:helperPath -Force
    Import-Module (Join-Path $script:repoRoot 'Tests/_helpers/Import-ScriptFunctions.psm1') -Force
    $script:DcrApiVersion = '2023-03-11'
    $script:ReservedColumns = @('TenantId', 'Type', 'UniqueId', 'Title', 'id', 'MG', 'ManagementGroupName', 'SourceSystem')
    $script:ColumnTypeMap = @{ 'string' = 'string'; 'int' = 'int'; 'long' = 'long'; 'real' = 'real'; 'boolean' = 'boolean'; 'bool' = 'boolean'; 'datetime' = 'datetime'; 'dynamic' = 'dynamic'; 'guid' = 'string' }
    $script:TextLogStreamColumns = @(
        [pscustomobject]@{ name = 'TimeGenerated'; type = 'datetime' }
        [pscustomobject]@{ name = 'RawData'; type = 'string' }
        [pscustomobject]@{ name = 'FilePath'; type = 'string' }
        [pscustomobject]@{ name = 'Computer'; type = 'string' }
    )
    Import-ScriptFunctions -Path $script:scriptPath

    $script:toJson = { param($Value) ConvertTo-Json -InputObject $Value -Depth 30 }
    $script:roleIds = @{ 'Monitoring Metrics Publisher' = '3913510d-42f4-4e42-8a64-420c390055eb' }

    $script:wrapper = @'
param([string] $Script, [string] $Helper, [string] $Parameters, [string] $Out, [switch] $UsageFails)
$ErrorActionPreference = 'Stop'
Import-Module $Helper -Force
$global:MigState = Get-ClassicMigrationStandIn -UsageFails:$UsageFails
function Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = $global:MigState.SubscriptionId }; Account = [pscustomobject]@{ Id = 'tester' } } }
function Set-AzContext { param($Subscription) Get-AzContext }
function Get-AzOperationalInsightsWorkspace { param($ResourceGroupName, $Name) [pscustomobject]@{ ResourceId = $global:MigState.WorkspacePath; Location = $global:MigState.Location; CustomerId = [guid]$global:MigState.WorkspaceId } }
function Invoke-AzOperationalInsightsQuery { param($WorkspaceId, $Query, $ErrorAction) Invoke-StandInLogQuery -State $global:MigState -Query $Query }
function Invoke-AzRestMethod {
    param($Path, $Uri, $Method = 'GET', $Payload)
    $target = if ($Path) { $Path } else { ([Uri]$Uri).PathAndQuery }
    $a = Invoke-StandInArm -State $global:MigState -Method $Method -Path $target
    [pscustomobject]@{ StatusCode = $a.Status; Content = $(if ($null -ne $a.Body) { ConvertTo-Json -InputObject $a.Body -Depth 30 } else { '' }) }
}
function Invoke-AzOperationalInsightsMigrateTable { param($ResourceGroupName, $WorkspaceName, $TableName, $Confirm) Invoke-StandInMigrate -State $global:MigState -Table $TableName }
function New-AzResourceGroupDeployment { param($Name, $ResourceGroupName, $TemplateFile, [switch] $Force, $ErrorAction) Invoke-StandInDeploy -State $global:MigState -Name $Name -ResourceGroup $ResourceGroupName -TemplateFile $TemplateFile }
function Get-AzResourceGroupDeploymentOperation {
    param($ResourceGroupName, $DeploymentName, $ErrorAction)
    foreach ($o in @(Get-StandInDeploymentOperation -State $global:MigState -DeploymentName $DeploymentName)) {
        $m = $o.properties.statusMessage
        [pscustomobject]@{ ProvisioningState = $o.properties.provisioningState; StatusMessage = $(if ($m -is [string]) { $m } else { ConvertTo-Json -InputObject $m -Depth 8 -Compress }) }
    }
}
function Get-AzADServicePrincipal { param($ApplicationId, $ErrorAction) $id = Resolve-StandInApp -State $global:MigState -AppId $ApplicationId; if (-not $id) { throw "Resource '$ApplicationId' does not exist." }; [pscustomobject]@{ Id = $id } }
function Get-AzRoleAssignment { param($ObjectId, $Scope, $RoleDefinitionName, $ErrorAction) @(Get-StandInAssignment -State $global:MigState -PrincipalId $ObjectId -Scope $Scope | Where-Object { $_.Role -eq $RoleDefinitionName }) }
function New-AzRoleAssignment { param($ObjectId, $RoleDefinitionName, $Scope, $ErrorAction) Add-StandInAssignment -State $global:MigState -PrincipalId $ObjectId -Role $RoleDefinitionName -Scope $Scope; [pscustomobject]@{ RoleAssignmentId = 'x' } }
$splat = Get-Content -LiteralPath $Parameters -Raw | ConvertFrom-Json -AsHashtable
$code = 0
$result = $null
try { $result = & $Script @splat }
catch { $code = 1; Set-Content -LiteralPath (Join-Path $Out 'error.txt') -Value $_.Exception.Message }
Set-Content -LiteralPath (Join-Path $Out 'results.json') -Value (ConvertTo-Json -InputObject @($result) -Depth 10)
Set-Content -LiteralPath (Join-Path $Out 'writes.json') -Value (ConvertTo-Json -InputObject @($global:MigState.Writes) -Depth 10)
exit $code
'@

    function Invoke-LegacyMigration {
        param([hashtable] $Parameters, [switch] $UsageFails)
        $tree = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $out = Join-Path $tree 'out'
        $templates = Join-Path $tree 'templates'
        New-Item -ItemType Directory -Path $out, $templates -Force | Out-Null
        $copy = Join-Path $tree 'Invoke-ClassicTableMigration.ps1'
        Set-Content -LiteralPath $copy -Value ((Get-Content -LiteralPath $script:scriptPath -Raw) -replace '(?m)^#Requires -Modules[^\r\n]*\r?\n', '') -NoNewline
        Set-Content -LiteralPath (Join-Path $tree 'run.ps1') -Value $script:wrapper
        $splat = @{ ResourceGroupName = 'rg-sentinel'; WorkspaceName = 'law-sentinel'; OutputDirectory = $templates } + $Parameters
        Set-Content -LiteralPath (Join-Path $tree 'parameters.json') -Value (ConvertTo-Json -InputObject $splat)
        $output = & pwsh -NoProfile -NonInteractive -File (Join-Path $tree 'run.ps1') -Script $copy -Helper $script:helperPath -Parameters (Join-Path $tree 'parameters.json') -Out $out -UsageFails:$UsageFails 2>&1 | Out-String
        $errorFile = Join-Path $out 'error.txt'
        [pscustomobject]@{
            ExitCode  = $LASTEXITCODE
            Output    = $output
            Error     = if (Test-Path -LiteralPath $errorFile) { (Get-Content -LiteralPath $errorFile -Raw).Trim() } else { $null }
            Results   = @(Get-Content -LiteralPath (Join-Path $out 'results.json') -Raw | ConvertFrom-Json -Depth 10 | Where-Object { $null -ne $_ })
            Writes    = @(Get-Content -LiteralPath (Join-Path $out 'writes.json') -Raw | ConvertFrom-Json -Depth 10 | Where-Object { $null -ne $_ })
            Templates = $templates
        }
    }

    function Invoke-ModuleMigration {
        param([hashtable] $Parameters, [switch] $UsageFails)
        $tree = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $templates = Join-Path $tree 'templates'
        New-Item -ItemType Directory -Path $templates -Force | Out-Null
        $script:migState = Get-ClassicMigrationStandIn -UsageFails:$UsageFails
        $script:principalTypes = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
        Mock -ModuleName iSOCDeployments Invoke-iSOCAzLogQuery { Invoke-StandInLogQuery -State $script:migState -Query $Query }
        Mock -ModuleName iSOCDeployments New-iSOCAzResourceGroupDeployment {
            Invoke-StandInDeploy -State $script:migState -Name $Name -ResourceGroup $Parameters.ResourceGroupName -TemplateFile $Parameters.TemplateFile
        }
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
            $state = $script:migState
            if ($Api -eq 'Graph') {
                $q = [Uri]::UnescapeDataString($Path)
                if ($q -match "^/servicePrincipals\?\`$filter=appId eq '([^']+)'$") {
                    $id = Resolve-StandInApp -State $state -AppId $Matches[1]
                    if ($id) { return [pscustomobject]@{ id = $id; appId = $Matches[1] } }
                    return
                }
                if ($q -match '^/directoryObjects/(.+)$') {
                    if ($state.Users -contains $Matches[1]) { return [pscustomobject]@{ '@odata.type' = '#microsoft.graph.user'; id = $Matches[1] } }
                    return
                }
                throw "unexpected Graph $Method $Path"
            }
            if ($Path -match "/providers/Microsoft\.Authorization/roleAssignments\?\`$filter=assignedTo\('([^']+)'\)$") {
                return @(Get-StandInAssignment -State $state -PrincipalId $Matches[1] | ForEach-Object {
                        [pscustomobject]@{ id = 'a'; name = 'a'; properties = [pscustomobject]@{ scope = $_.Scope; principalId = $_.PrincipalId; roleDefinitionId = "/subscriptions/$($state.SubscriptionId)/providers/Microsoft.Authorization/roleDefinitions/$($script:roleIds[$_.Role])" } }
                    })
            }
            if ($Method -eq 'PUT' -and $Path -match '^(.+)/providers/Microsoft\.Authorization/roleAssignments/[^/?]+') {
                $scope = $Matches[1]
                $roleId = ($Body.properties.roleDefinitionId -split '/')[-1]
                $role = @($script:roleIds.Keys | Where-Object { $script:roleIds[$_] -eq $roleId })[0]
                $script:principalTypes.Add([string]$Body.properties['principalType'])
                Add-StandInAssignment -State $state -PrincipalId $Body.properties.principalId -Role $role -Scope $scope
                return
            }
            $a = Invoke-StandInArm -State $state -Method $Method -Path $Path
            if ($a.Status -ge 400) { throw [System.Net.Http.HttpRequestException]::new("HTTP $($a.Status) from $Method $Path", $null, [System.Net.HttpStatusCode]$a.Status) }
            if ($null -eq $a.Body) { return }
            $object = ConvertTo-Json -InputObject $a.Body -Depth 30 | ConvertFrom-Json -Depth 30
            if (@($object.PSObject.Properties.Name) -join ',' -eq 'value') { return $object.value }
            $object
        }
        $ctx = InModuleScope iSOCDeployments -Parameters @{ State = $script:migState } {
            param($State)
            New-iSOCContext -Value @{
                TenantId = 't'; SubscriptionId = $State.SubscriptionId; ResourceGroup = $State.ResourceGroup; WorkspaceName = $State.WorkspaceName
                WorkspaceResourceId = $State.WorkspacePath; WorkspaceId = $State.WorkspaceId; Region = $State.Location; PlaybookResourceGroup = 'rg-auto'
                Environment = 'AzureCloud'; IsGov = $false; ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'tester'
            }
        }
        $run = $null
        $failure = $null
        try { $run = Invoke-iSOCClassicTableMigration -Context $ctx -Path $templates @Parameters }
        catch { $failure = $_.Exception.Message }
        [pscustomobject]@{ Run = $run; Error = $failure; Writes = @($script:migState.Writes); Templates = $templates; PrincipalTypes = @($script:principalTypes) }
    }

    function ConvertTo-ComparableWrite {
        param($Writes)
        @($Writes | ForEach-Object {
                switch ($_.Kind) {
                    'Migrate' { "Migrate $($_.Table)" }
                    'Deploy' { "Deploy $($_.ResourceGroup) $($_.Name)`n" + ($_.Template -replace 'generated by Invoke-(iSOC)?ClassicTableMigration(\.ps1)?\.', 'generated by X.') }
                    'Grant' { "Grant $($_.PrincipalId) $($_.Role) $($_.Scope)" }
                }
            })
    }

    function Get-ComparableTemplate {
        param([string] $Folder)
        @(Get-ChildItem -LiteralPath $Folder -File | Sort-Object Name | ForEach-Object {
                "$($_.Name)`n" + ((Get-Content -LiteralPath $_.FullName -Raw) -replace 'generated by Invoke-(iSOC)?ClassicTableMigration(\.ps1)?\.', 'generated by X.')
            })
    }

    function ConvertTo-ComparableResult {
        param($Results)
        @($Results | ForEach-Object {
                [ordered]@{
                    TableName    = $_.TableName
                    SubTypeAfter = $_.SubTypeAfter
                    Migrated     = [bool]$_.Migrated
                    RowCount     = $_.RowCount
                    GB90d        = $_.GB90d
                    DcrName      = $_.DcrName
                    Template     = if ($_.TemplatePath) { Split-Path -Leaf $_.TemplatePath } else { $null }
                    Deployed     = [bool]$_.Deployed
                    ImmutableId  = $_.ImmutableId
                    Endpoint     = $_.Endpoint
                    Granted      = @($_.Granted)
                    Error        = $_.Error
                }
            })
    }

    function ConvertTo-ComparableTable {
        param($Tables)
        @($Tables | ForEach-Object {
                [ordered]@{ Name = $_.Name; SubType = $_.SubType; Plan = $_.Plan; ColumnCount = $_.ColumnCount; RowCount = $_.RowCount; GB90d = $_.GB90d; Unreadable = [bool]$_.Error }
            })
    }

}

Describe 'The stream, transform and template builders, beside the script''s' {
    BeforeAll {
        $state = Get-ClassicMigrationStandIn
        $script:schemas = @($state.Tables.Keys | ForEach-Object { , @($state.Tables[$_].columns | ForEach-Object { [pscustomobject]$_ }) })
    }

    It 'declares the same stream columns and drops the same ones' {
        $old = foreach ($s in $script:schemas) { ConvertTo-StreamColumn -SchemaColumn $s }
        $new = InModuleScope iSOCDeployments -Parameters @{ Schemas = $script:schemas } { param($Schemas) foreach ($s in $Schemas) { ConvertTo-iSOCDcrStreamColumn -SchemaColumn $s } }
        (& $script:toJson @($new)) | Should -BeExactly (& $script:toJson @($old))
    }

    It 'builds the same transform' {
        $old = foreach ($s in $script:schemas) { Get-DefaultTransform -SchemaColumn $s -StreamColumn (ConvertTo-StreamColumn -SchemaColumn $s).Columns }
        $new = InModuleScope iSOCDeployments -Parameters @{ Schemas = $script:schemas } { param($Schemas) foreach ($s in $Schemas) { Get-iSOCDcrDefaultTransform -SchemaColumn $s -StreamColumn (ConvertTo-iSOCDcrStreamColumn -SchemaColumn $s).Columns } }
        $new | Should -Be $old
        $old | Should -Contain 'source | extend EventId_g = toguid(EventId_g)'
    }

    It 'maps every column type the same' {
        $types = 'string', 'String', 'int', 'long', 'real', 'boolean', 'bool', 'datetime', 'dateTime', 'dynamic', 'guid', 'hyperloglog', ''
        $old = foreach ($t in $types) { Get-DcrColumnType -TableColumnType $t 3>$null }
        $new = InModuleScope iSOCDeployments -Parameters @{ Types = $types } { param($Types) Mock Write-iSOCLog { }; foreach ($t in $Types) { Get-iSOCDcrColumnType -TableColumnType $t } }
        $new | Should -Be $old
    }

    It 'builds the same template, with its keys in a fixed order' {
        $p = @{
            Name = 'dcr-x'; Region = 'uksouth'; Kind = 'Linux'; Stream = 'Custom-X_CL'; StreamColumn = @([pscustomobject]@{ name = 'TimeGenerated'; type = 'datetime' })
            WorkspaceResourceId = '/w'; OutputStream = 'Custom-X_CL'; Transform = 'source'; EndpointResourceId = '/dce'
            LogFilesDataSource = [ordered]@{ name = 'X-logfile'; streams = @('Custom-X_CL'); filePatterns = @('/x'); format = 'text' }; Description = 'd'
        }
        $old = (Build-DcrArmTemplate @p | ConvertTo-Json -Depth 30) -replace 'Invoke-ClassicTableMigration\.ps1', 'X'
        $new = (InModuleScope iSOCDeployments -Parameters @{ P = $p } { param($P) ConvertTo-iSOCDcrArmTemplate @P } | ConvertTo-Json -Depth 30) -replace 'Invoke-iSOCClassicTableMigration', 'X'
        $new | Should -BeExactly $old
        @((ConvertFrom-Json $new -AsHashtable).Keys) | Should -Be @('$schema', 'contentVersion', 'metadata', 'resources')
    }
}

Describe 'Parity with Invoke-ClassicTableMigration.ps1: <Label>' -ForEach $script:scenarios {
    BeforeAll {
        $script:legacy = Invoke-LegacyMigration -Parameters $Parameters -UsageFails:([bool]$UsageFails)
        $script:module = Invoke-ModuleMigration -Parameters $Parameters -UsageFails:([bool]$UsageFails)
    }

    It 'runs the script to the end' {
        $script:legacy.ExitCode | Should -Be 0 -Because $script:legacy.Output
        $script:module.Error | Should -BeNullOrEmpty
    }

    It 'makes the same migrations, deployments and grants, in order' {
        (& $script:toJson (ConvertTo-ComparableWrite $script:module.Writes)) | Should -BeExactly (& $script:toJson (ConvertTo-ComparableWrite $script:legacy.Writes))
    }

    It 'writes the same template files' {
        (& $script:toJson (Get-ComparableTemplate $script:module.Templates)) | Should -BeExactly (& $script:toJson (Get-ComparableTemplate $script:legacy.Templates))
    }

    It 'returns the same result for each table' {
        (& $script:toJson (ConvertTo-ComparableResult $script:module.Run.Results)) | Should -BeExactly (& $script:toJson (ConvertTo-ComparableResult $script:legacy.Results))
        $script:module.Run.ExitCode | Should -Be ([int](@($script:legacy.Results | Where-Object { $_.Error }).Count -gt 0))
    }
}

Describe 'Parity with Invoke-ClassicTableMigration.ps1: listing only' {
    BeforeAll {
        $script:legacyList = Invoke-LegacyMigration -Parameters @{ AllClassicTables = $true; ListOnly = $true }
        $script:moduleList = Invoke-ModuleMigration -Parameters @{ AllClassicTables = $true; ListOnly = $true }
    }

    It 'lists the same tables, and changes nothing' {
        $script:legacyList.ExitCode | Should -Be 0 -Because $script:legacyList.Output
        (& $script:toJson (ConvertTo-ComparableTable $script:moduleList.Run.Tables)) | Should -BeExactly (& $script:toJson (ConvertTo-ComparableTable $script:legacyList.Results))
        $script:moduleList.Writes | Should -BeNullOrEmpty
        $script:legacyList.Writes | Should -BeNullOrEmpty
        Get-ChildItem -LiteralPath $script:moduleList.Templates | Should -BeNullOrEmpty
        $script:moduleList.Run.Results | Should -BeNullOrEmpty
    }

    It 'leaves out AzureDiagnostics, and reads the table it cannot as unreadable' {
        @($script:moduleList.Run.Tables.Name) | Should -Not -Contain 'AzureDiagnostics'
        ($script:moduleList.Run.Tables | Where-Object Name -eq 'Broken_CL').SubType | Should -Be 'Unreadable'
        ($script:moduleList.Run.Tables | Where-Object Name -eq 'Unknown_CL').RowCount | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-iSOCClassicTableMigration' {
    It 'refuses a transform for more than one table, as the script does' {
        $p = @{ TableName = @('MyApp_CL', 'Odd_CL'); TransformKql = 'source' }
        $legacy = Invoke-LegacyMigration -Parameters $p
        $module = Invoke-ModuleMigration -Parameters $p
        $legacy.ExitCode | Should -Be 1
        $module.Error | Should -Be $legacy.Error
    }

    It 'refuses a text log rule with no file pattern, as the script does' {
        $p = @{ TableName = @('MyApp_CL'); DcrKind = 'TextLog' }
        $legacy = Invoke-LegacyMigration -Parameters $p
        $module = Invoke-ModuleMigration -Parameters $p
        $module.Error | Should -Be $legacy.Error
    }

    It 'tells the role assignment what each principal is' {
        $run = Invoke-ModuleMigration -Parameters @{ TableName = @('MyApp_CL'); Deploy = $true; Force = $true; GrantIngestionRoleTo = @('aaaaaaaa-1111-2222-3333-444444444444', 'user-object-1', 'unknown-object-1') }
        $run.PrincipalTypes | Should -Be @('ServicePrincipal', 'User', '')
        ($run.Run.Results | Select-Object -First 1).Granted | Should -Be @('aaaaaaaa-1111-2222-3333-444444444444', 'user-object-1', 'unknown-object-1')
    }

    It 'compares runs that migrate, deploy, grant and refuse' {
        $legacy = Invoke-LegacyMigration -Parameters @{ AllClassicTables = $true; Deploy = $true; Force = $true; GrantIngestionRoleTo = @('aaaaaaaa-1111-2222-3333-444444444444', 'held-object-1', 'deny-object-1') }
        @($legacy.Writes.Kind | Sort-Object -Unique) | Should -Be @('Deploy', 'Grant', 'Migrate')
        @($legacy.Writes | Where-Object Kind -eq 'Grant').PrincipalId | Should -Be @('sp-object-1', 'sp-object-1')
        @(Get-ChildItem -LiteralPath $legacy.Templates).Count | Should -Be 3
        ($legacy.Results | Where-Object TableName -eq 'Odd_CL').Error | Should -Match '^Deployment failed: .*InvalidOutputTable'
        ($legacy.Results | Where-Object TableName -eq 'MyApp_CL').Granted | Should -Be @('aaaaaaaa-1111-2222-3333-444444444444', 'held-object-1')
    }

    It 'returns a run with the counts and an exit code' {
        $run = (Invoke-ModuleMigration -Parameters @{ AllClassicTables = $true; Deploy = $true; Force = $true }).Run
        $run.PSObject.TypeNames | Should -Contain 'iSOCDeployments.TableMigrationRun'
        $run.Migrated | Should -BeGreaterThan 0
        $run.Deployed | Should -BeGreaterThan 0
        $run.Failed | Should -Be 1
        $run.ExitCode | Should -Be 1
    }

    It 'asks before migrating unless -Force' {
        $run = Invoke-ModuleMigration -Parameters @{ TableName = @('MyApp_CL'); Confirm = $false }
        ($run.Run.Results | Select-Object -First 1).Migrated | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $script:repoRoot 'Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Convert-iSOCClassicTable.ps1') -Raw) | Should -Match 'ShouldContinue'
    }
}
