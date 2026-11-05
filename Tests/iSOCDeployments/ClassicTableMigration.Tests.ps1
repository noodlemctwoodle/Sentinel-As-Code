#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for Invoke-iSOCClassicTableMigration.

.DESCRIPTION
    The stream, transform and template builders are held to explicit
    expected values over the stand-in workspace's schemas.

    The command runs through mocks of the module's REST client, log query
    and deployment wrapper, over one stand-in workspace
    (Tests/iSOCDeployments/_helpers/ClassicMigrationStandIn.psm1) whose
    tables turn DCR-based as they are migrated, and whose rules and role
    assignments appear as they are deployed and granted: listing only,
    refusals, grants, a run that migrates, deploys, grants and refuses, the
    counts it returns and the confirmation it asks for.

    Parity with Invoke-ClassicTableMigration.ps1 was proven on
    release/26.11.0 before the script was removed.

.NOTES
    File:         Tests/iSOCDeployments/ClassicTableMigration.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.2.0
    Last Updated: 2026-11-05
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:helperPath = Join-Path $PSScriptRoot '_helpers/ClassicMigrationStandIn.psm1'
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module $script:helperPath -Force

    $script:roleIds = @{ 'Monitoring Metrics Publisher' = '3913510d-42f4-4e42-8a64-420c390055eb' }

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
}

Describe 'The stream, transform and template builders' {
    BeforeAll {
        $state = Get-ClassicMigrationStandIn
        $script:tableNames = @($state.Tables.Keys)
        $script:schemas = @($state.Tables.Keys | ForEach-Object { , @($state.Tables[$_].columns | ForEach-Object { [pscustomobject]$_ }) })
    }

    It 'declares the stream columns and drops the reserved, hidden and underscore-led ones' {
        $expected = [ordered]@{
            'MyApp_CL'         = '{"Columns":[{"name":"TimeGenerated","type":"datetime"},{"name":"Message_s","type":"string"},{"name":"EventId_g","type":"string"},{"name":"Count_d","type":"real"},{"name":"Flag_b","type":"boolean"},{"name":"Props_d","type":"dynamic"},{"name":"Computer","type":"string"}],"Dropped":[{"Name":"_ResourceId_s","Reason":"stream column names must start with a letter"},{"Name":"TenantId","Reason":"reserved column name"},{"Name":"Secret_s","Reason":"hidden column"}]}'
            'Second_CL'        = '{"Columns":[{"name":"TimeGenerated","type":"datetime"},{"name":"Value_s","type":"string"}],"Dropped":[]}'
            'Ready_CL'         = '{"Columns":[{"name":"TimeGenerated","type":"datetime"},{"name":"RawData","type":"string"},{"name":"Id_g","type":"string"}],"Dropped":[]}'
            'Odd_CL'           = '{"Columns":[{"name":"TimeGenerated","type":"datetime"},{"name":"Weird_x","type":"string"},{"name":"Level_i","type":"int"},{"name":"Big_l","type":"long"}],"Dropped":[]}'
            'Unknown_CL'       = '{"Columns":[{"name":"TimeGenerated","type":"datetime"},{"name":"FilePath","type":"string"}],"Dropped":[]}'
            'Broken_CL'        = '{"Columns":[{"name":"TimeGenerated","type":"datetime"}],"Dropped":[]}'
            'AzureDiagnostics' = '{"Columns":[{"name":"TimeGenerated","type":"datetime"}],"Dropped":[]}'
            'SecurityEvent'    = '{"Columns":[{"name":"TimeGenerated","type":"datetime"}],"Dropped":[]}'
        }
        $new = InModuleScope iSOCDeployments -Parameters @{ Schemas = $script:schemas } { param($Schemas) foreach ($s in $Schemas) { ConvertTo-Json -InputObject (ConvertTo-iSOCDcrStreamColumn -SchemaColumn $s) -Depth 30 -Compress } }
        @($new).Count | Should -Be $expected.Count
        for ($i = 0; $i -lt $script:tableNames.Count; $i++) {
            @($new)[$i] | Should -BeExactly $expected[$script:tableNames[$i]] -Because $script:tableNames[$i]
        }
    }

    It 'casts back each column whose stream type is not the table''s' {
        $expected = [ordered]@{
            'MyApp_CL'         = 'source | extend EventId_g = toguid(EventId_g)'
            'Second_CL'        = 'source'
            'Ready_CL'         = 'source | extend Id_g = toguid(Id_g)'
            'Odd_CL'           = 'source'
            'Unknown_CL'       = 'source'
            'Broken_CL'        = 'source'
            'AzureDiagnostics' = 'source'
            'SecurityEvent'    = 'source'
        }
        $new = InModuleScope iSOCDeployments -Parameters @{ Schemas = $script:schemas } { param($Schemas) foreach ($s in $Schemas) { Get-iSOCDcrDefaultTransform -SchemaColumn $s -StreamColumn (ConvertTo-iSOCDcrStreamColumn -SchemaColumn $s).Columns } }
        $new | Should -Be @($script:tableNames | ForEach-Object { $expected[$_] })
    }

    It 'maps every column type onto a stream type' {
        $cases = [ordered]@{ 'String' = 'string'; 'int' = 'int'; 'long' = 'long'; 'real' = 'real'; 'bool' = 'boolean'; 'dateTime' = 'datetime'; 'dynamic' = 'dynamic'; 'guid' = 'string'; 'hyperloglog' = 'string'; '' = 'string' }
        $types = @($cases.Keys)
        $new = InModuleScope iSOCDeployments -Parameters @{ Types = $types } { param($Types) Mock Write-iSOCLog { }; foreach ($t in $Types) { Get-iSOCDcrColumnType -TableColumnType $t } }
        $new | Should -Be @($cases.Values)
    }

    It 'builds the template, with its keys in a fixed order' {
        $p = @{
            Name = 'dcr-x'; Region = 'uksouth'; Kind = 'Linux'; Stream = 'Custom-X_CL'; StreamColumn = @([pscustomobject]@{ name = 'TimeGenerated'; type = 'datetime' })
            WorkspaceResourceId = '/w'; OutputStream = 'Custom-X_CL'; Transform = 'source'; EndpointResourceId = '/dce'
            LogFilesDataSource = [ordered]@{ name = 'X-logfile'; streams = @('Custom-X_CL'); filePatterns = @('/x'); format = 'text' }; Description = 'd'
        }
        $expected = '{"$schema":"https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#","contentVersion":"1.0.0.0","metadata":{"description":"Data collection rule for Custom-X_CL, generated by Invoke-iSOCClassicTableMigration."},"resources":[{"type":"Microsoft.Insights/dataCollectionRules","apiVersion":"2023-03-11","name":"dcr-x","location":"uksouth","kind":"Linux","properties":{"description":"d","dataCollectionEndpointId":"/dce","streamDeclarations":{"Custom-X_CL":{"columns":[{"name":"TimeGenerated","type":"datetime"}]}},"dataSources":{"logFiles":[{"name":"X-logfile","streams":["Custom-X_CL"],"filePatterns":["/x"],"format":"text"}]},"destinations":{"logAnalytics":[{"workspaceResourceId":"/w","name":"workspaceDestination"}]},"dataFlows":[{"streams":["Custom-X_CL"],"destinations":["workspaceDestination"],"transformKql":"source","outputStream":"Custom-X_CL"}]}}]}'
        $new = InModuleScope iSOCDeployments -Parameters @{ P = $p } { param($P) ConvertTo-iSOCDcrArmTemplate @P } | ConvertTo-Json -Depth 30 -Compress
        $new | Should -BeExactly $expected
        @((ConvertFrom-Json $new -AsHashtable).Keys) | Should -Be @('$schema', 'contentVersion', 'metadata', 'resources')
    }
}

Describe 'Listing only' {
    BeforeAll {
        $script:moduleList = Invoke-ModuleMigration -Parameters @{ AllClassicTables = $true; ListOnly = $true }
    }

    It 'changes nothing' {
        $script:moduleList.Writes | Should -BeNullOrEmpty
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
    It 'refuses a transform for more than one table' {
        $module = Invoke-ModuleMigration -Parameters @{ TableName = @('MyApp_CL', 'Odd_CL'); TransformKql = 'source' }
        $module.Error | Should -Be '-TransformKql applies to a single table only, because a transform is specific to one schema.'
    }

    It 'refuses a text log rule with no file pattern' {
        $module = Invoke-ModuleMigration -Parameters @{ TableName = @('MyApp_CL'); DcrKind = 'TextLog' }
        $module.Error | Should -Be '-FilePattern is required when -DcrKind is TextLog.'
    }

    It 'tells the role assignment what each principal is' {
        $run = Invoke-ModuleMigration -Parameters @{ TableName = @('MyApp_CL'); Deploy = $true; Force = $true; GrantIngestionRoleTo = @('aaaaaaaa-1111-2222-3333-444444444444', 'user-object-1', 'unknown-object-1') }
        $run.PrincipalTypes | Should -Be @('ServicePrincipal', 'User', '')
        ($run.Run.Results | Select-Object -First 1).Granted | Should -Be @('aaaaaaaa-1111-2222-3333-444444444444', 'user-object-1', 'unknown-object-1')
    }

    It 'migrates, deploys, grants and refuses in one run' {
        $module = Invoke-ModuleMigration -Parameters @{ AllClassicTables = $true; Deploy = $true; Force = $true; GrantIngestionRoleTo = @('aaaaaaaa-1111-2222-3333-444444444444', 'held-object-1', 'deny-object-1') }
        @($module.Writes.Kind | Sort-Object -Unique) | Should -Be @('Deploy', 'Grant', 'Migrate')
        @($module.Writes | Where-Object Kind -eq 'Grant').PrincipalId | Should -Be @('sp-object-1', 'sp-object-1')
        @(Get-ChildItem -LiteralPath $module.Templates).Count | Should -Be 3
        ($module.Run.Results | Where-Object TableName -eq 'Odd_CL').Error | Should -Match '^Deployment failed: .*InvalidOutputTable'
        ($module.Run.Results | Where-Object TableName -eq 'MyApp_CL').Granted | Should -Be @('aaaaaaaa-1111-2222-3333-444444444444', 'held-object-1')
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
