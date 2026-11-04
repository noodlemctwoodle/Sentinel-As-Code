#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for New-iSOCDcrFromSchema, against
    Tools/DcrFromSchema/New-DcrFromSchema.ps1.

.DESCRIPTION
    The schema reader, repairs, checks, stream and transform builders,
    templates and error flattener run beside the script's own and must
    answer the same.

    Then the script runs unchanged in a child pwsh with -NonInteractive,
    its Az cmdlets stood in for, and the command runs through mocks of the
    module's REST client and deployment wrappers; both over one stand-in
    workspace (Tests/iSOCDeployments/_helpers/DcrFromSchemaStandIn.psm1)
    whose tables and rules appear as they are deployed. For each run the two
    must validate and deploy the same templates in the same order, grant the
    same roles, write the same template files and return the same result,
    or refuse with the same message: the shipped examples, a schema that
    needs repair, a pasted one, a table that exists or cannot be read, every
    parameter given, -SkipTable, -WhatIf, a rule with no endpoint, a
    template that fails validation and a deployment that fails.

.NOTES
    File:         Tests/iSOCDeployments/DcrFromSchema.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeDiscovery {
    $lq = [string][char]0x201C
    $rq = [string][char]0x201D
    $ls = [string][char]0x2018
    $rs = [string][char]0x2019
    $nb = [string][char]0x00A0
    $zw = [string][char]0x200B

    $schema = @{
        Repair    = @'
{
  "tableName": "Repair_CL",
  "description": "Records that need repair.",
  "columns": [
    { "name": "Alert", "type": "string" },
    { "name": "alert", "type": "string" },
    { "name": "9Bad", "type": "string" },
    { "name": "Dup", "type": "integer" },
    { "name": "Dup", "type": "long" },
    { "name": "Src", "type": "string", "dataTypeHint": "ipv4" },
    { "name": "EventId", "type": "uuid", "note": "a key the Tables API does not define" },
    { "name": "TenantId", "type": "string" },
    { "name": "Count_d", "type": "double", "comment": "a classic suffix" },
    { "name": "Flag", "type": "bool", "displayName": "The flag" },
    { "name": "When", "type": "timestamp", "description": "line one\nline two" }
  ]
}
'@
        Pasted    = "{$nb`n  // pasted from a wiki`n  ${lq}tableName${rq}: ${lq}Pasted_CL${rq},`n  ${lq}columns${rq}: [`n    { ${lq}name${rq}: ${lq}TimeGenerated${rq}, ${lq}type${rq}: ${lq}datetime${rq} },`n    /* the id */ { ${lq}name${rq}: ${lq}Ref${rq}, ${lq}type${rq}: ${lq}guid${rq}, ${lq}description${rq}: ${lq}see http://wiki/x${zw}${rq} },`n  ],`n}"
        Existing  = @'
{
  "tableName": "Existing_CL",
  "description": "This description is far longer than a data collection rule allows, so it is cut to two hundred and fifty six characters before it is used: it goes on, and on, explaining what the table holds, who sends to it, how long it is kept, and why each of its columns is there at all, until it is too long.",
  "columns": [
    { "name": "TimeGenerated", "type": "datetime" },
    { "name": "AlertId", "type": "string" },
    { "name": "NewCol", "type": "dynamic" }
  ]
}
'@
        Broken    = '{ "tableName": "Broken_CL", "columns": [ { "name": "TimeGenerated", "type": "datetime" }, { "name": "Value", "type": "real" } ] }'
        Shapeless = '{ "tableName": "Shapeless_CL", "columns": [ { "name": "TimeGenerated", "type": "datetime" } ] }'
        Failing   = '{ "tableName": "Failing_CL", "dcrName": "dcr-failing", "columns": [ { "name": "TimeGenerated", "type": "datetime" } ] }'
        Rejected  = '{ "tableName": "Rejected_CL", "dcrName": "dcr-rejected", "columns": [ { "name": "TimeGenerated", "type": "datetime" } ] }'
        Tables    = '{ "properties": { "plan": "Basic", "totalRetentionInDays": 180, "schema": { "name": "Exported_CL", "description": "Read back from Azure.", "columns": [ { "name": "TimeGenerated", "type": "dateTime" }, { "name": "Host", "type": "string" } ] } } }'
        Single    = '[ { "name": "Only", "type": "string" } ]'
    }

    $script:runs = @(
        @{ Label = 'the threat intel example, templates only'; Example = 'threat-intel-alerts.json'; Parameters = @{} }
        @{ Label = 'the annotated example, deployed and granted'; Example = 'annotated.json'; Parameters = @{ Deploy = $true; GrantIngestionRoleTo = @('aaaaaaaa-1111-2222-3333-444444444444', 'user-object-1', 'held-object-1', 'deny-object-1') } }
        @{ Label = 'the Basic plan example, deployed'; Example = 'basic-plan.json'; Parameters = @{ Deploy = $true } }
        @{ Label = 'the Auxiliary plan example'; Example = 'auxiliary-plan.json'; Parameters = @{} }
        @{ Label = 'the minimal example'; Example = 'minimal.json'; Parameters = @{ Deploy = $true } }
        @{ Label = 'a schema that needs repair'; Schema = $schema.Repair; Parameters = @{ Deploy = $true } }
        @{ Label = 'a pasted schema'; Schema = $schema.Pasted; Parameters = @{} }
        @{ Label = 'a table as the Tables API returns it'; Schema = $schema.Tables; Parameters = @{ Deploy = $true } }
        @{ Label = 'a bare column list'; Schema = $schema.Single; Parameters = @{ TableName = 'Single' } }
        @{ Label = 'a table that exists, with a long description'; Schema = $schema.Existing; Parameters = @{ Deploy = $true } }
        @{ Label = 'a rule for a table that exists (-SkipTable)'; Schema = $schema.Existing; Parameters = @{ SkipTable = $true; Deploy = $true; GrantIngestionRoleTo = @('user-object-1') } }
        @{ Label = 'a live table that cannot be read'; Schema = $schema.Broken; Parameters = @{ Deploy = $true } }
        @{ Label = 'a live table answered without its schema'; Schema = $schema.Shapeless; Parameters = @{} }
        @{ Label = 'every parameter given'; Example = 'annotated.json'; Parameters = @{
                TableName = 'Param'; DcrName = 'dcr-param'; DcrResourceGroupName = 'rg-dcr'; Location = 'westeurope'
                DataCollectionEndpointResourceId = '/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-dcr/providers/Microsoft.Insights/dataCollectionEndpoints/dce-1'
                TransformKql = "source | extend Note = ${ls}x${rs}"; TablePlan = 'Basic'; RetentionInDays = 30; TotalRetentionInDays = 365
                Description = "Line one`nLine two"; IncludeDataTypeHint = $true; Deploy = $true; GrantIngestionRoleTo = @('user-object-1')
            }
        }
        @{ Label = '-WhatIf, with -Deploy'; Example = 'annotated.json'; Parameters = @{ Deploy = $true; WhatIf = $true; GrantIngestionRoleTo = @('user-object-1') } }
        @{ Label = 'a rule with no ingestion endpoint'; Example = 'minimal.json'; NoEndpoint = $true; Parameters = @{ Deploy = $true } }
        @{ Label = 'a template that fails validation'; Schema = $schema.Rejected; Parameters = @{ Deploy = $true }; ExpectError = 'Template validation failed \(<out>/dcr-rejected\.json\): \[InvalidTemplateDeployment\].+ -> \[InvalidProperty\] \(Properties\.Description\)' }
        @{ Label = 'a deployment that fails'; Schema = $schema.Failing; Parameters = @{ Deploy = $true }; ExpectError = '^Deployment failed: .+InvalidOutputTable' }
    )

    $script:refusals = @(
        @{ Label = 'a classic table'; Schema = '{ "tableName": "Legacy_CL", "columns": [ { "name": "TimeGenerated", "type": "datetime" } ] }'; Parameters = @{}; Replace = @{ 'Tools/ClassicToDcr/Invoke-ClassicTableMigration.ps1' = 'Invoke-iSOCClassicTableMigration' } }
        @{ Label = 'a column whose live type differs'; Schema = '{ "tableName": "Typed_CL", "columns": [ { "name": "TimeGenerated", "type": "datetime" }, { "name": "AlertId", "type": "string" } ] }'; Parameters = @{} }
        @{ Label = 'an Auxiliary table with names that differ only by case'; Schema = '{ "tableName": "CaseAux_CL", "plan": "Auxiliary", "columns": [ { "name": "TimeGenerated", "type": "datetime" }, { "name": "Alert", "type": "string" }, { "name": "alert", "type": "string" } ] }'; Parameters = @{} }
        @{ Label = 'a resource group that does not exist'; Example = 'minimal.json'; Parameters = @{ DcrResourceGroupName = 'rg-missing' }; Replace = @{ 'in subscription 11111111-2222-3333-4444-555555555555.' = "in the workspace's subscription." } }
        @{ Label = 'a type that cannot be repaired'; Schema = '{ "tableName": "BadType_CL", "columns": [ { "name": "TimeGenerated", "type": "datetime" }, { "name": "Sketch", "type": "hyperloglog" } ] }'; Parameters = @{} }
        @{ Label = 'a table name that cannot be used'; Schema = '{ "tableName": "9bad_CL", "columns": [ { "name": "TimeGenerated", "type": "datetime" } ] }'; Parameters = @{} }
        @{ Label = 'retention out of range in the file'; Schema = '{ "tableName": "Kept_CL", "retentionInDays": 1000, "columns": [ { "name": "TimeGenerated", "type": "datetime" } ] }'; Parameters = @{} }
        @{ Label = 'total retention shorter than interactive'; Schema = '{ "tableName": "Kept_CL", "retentionInDays": 90, "totalRetentionInDays": 30, "columns": [ { "name": "TimeGenerated", "type": "datetime" } ] }'; Parameters = @{} }
        @{ Label = 'a transform too long'; Example = 'minimal.json'; Parameters = @{ TransformKql = 'source | where ' + ('x' * 15400) } }
        @{ Label = 'a sample of the data'; Schema = '[ { "user": "a", "count": 1 } ]'; Parameters = @{ TableName = 'Sample' } }
        @{ Label = 'a file that is not JSON'; Schema = 'tableName: Yaml_CL'; Parameters = @{} }
        @{ Label = 'no table name'; Schema = '[ { "name": "TimeGenerated", "type": "datetime" }, { "name": "Value", "type": "string" } ]'; Parameters = @{}; Replace = @{ "'Table name (must end _CL)' is required in non-interactive mode. Supply it as a parameter." = 'The schema file names no table, so -TableName is required.' } }
        @{ Label = 'a plan in the file that is not one'; Schema = '{ "tableName": "Plan_CL", "plan": "Premium", "columns": [ { "name": "TimeGenerated", "type": "datetime" } ] }'; Parameters = @{}; LegacyMatch = 'Premium'; ModuleError = "The schema file's plan 'Premium' is not one of Analytics, Basic and Auxiliary." }
    )
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:scriptPath = Join-Path $script:repoRoot 'Tools/DcrFromSchema/New-DcrFromSchema.ps1'
    $script:examples = Join-Path $script:repoRoot 'Tools/DcrFromSchema/Examples'
    $script:helperPath = Join-Path $PSScriptRoot '_helpers/DcrFromSchemaStandIn.psm1'
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module $script:helperPath -Force
    Import-Module (Join-Path $script:repoRoot 'Tests/_helpers/Import-ScriptFunctions.psm1') -Force

    $text = Get-Content -LiteralPath $script:scriptPath -Raw
    $start = $text.IndexOf('#region -- Constants')
    $constants = $text.Substring($start, $text.IndexOf('#endregion', $start) - $start) -replace '-not \$NonInteractive', '$false'
    . ([scriptblock]::Create($constants))
    Import-ScriptFunctions -Path $script:scriptPath

    $script:roleIds = @{ 'Monitoring Metrics Publisher' = '3913510d-42f4-4e42-8a64-420c390055eb' }

    $script:wrapper = @'
param([string] $Script, [string] $Helper, [string] $Parameters, [string] $Out, [switch] $NoEndpoint)
$ErrorActionPreference = 'Stop'
Import-Module $Helper -Force
$global:DcrState = Get-DcrFromSchemaStandIn -NoEndpoint:$NoEndpoint
function Read-Host { throw 'The script prompted.' }
function Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = $global:DcrState.SubscriptionId }; Account = [pscustomobject]@{ Id = 'tester' } } }
function Set-AzContext { param($Subscription) Get-AzContext }
function Get-AzOperationalInsightsWorkspace { param($ResourceGroupName, $Name, $ErrorAction) [pscustomobject]@{ Name = $global:DcrState.WorkspaceName; ResourceGroupName = $global:DcrState.ResourceGroup; Location = $global:DcrState.Location; ResourceId = $global:DcrState.WorkspacePath } }
function Get-AzResourceGroup { param($Name, $ErrorAction) $a = Invoke-DcrFromSchemaArm -State $global:DcrState -Method GET -Path "/subscriptions/$($global:DcrState.SubscriptionId)/resourceGroups/$Name"; if ($a.Status -ne 200) { throw "Provided resource group does not exist." }; [pscustomobject]@{ ResourceGroupName = $Name } }
function Invoke-AzRestMethod {
    param($Path, $Uri, $Method = 'GET', $Payload)
    $target = if ($Path) { $Path } else { ([Uri]$Uri).PathAndQuery }
    $a = Invoke-DcrFromSchemaArm -State $global:DcrState -Method $Method -Path $target
    [pscustomobject]@{ StatusCode = $a.Status; Content = $(if ($null -ne $a.Body) { ConvertTo-Json -InputObject $a.Body -Depth 30 } else { '' }) }
}
function Test-AzResourceGroupDeployment { param($ResourceGroupName, $TemplateFile, $ErrorAction) Invoke-DcrFromSchemaValidate -State $global:DcrState -ResourceGroup $ResourceGroupName -TemplateFile $TemplateFile }
function New-AzResourceGroupDeployment { param($Name, $ResourceGroupName, $TemplateFile, [switch] $Force, $ErrorAction) Invoke-DcrFromSchemaDeploy -State $global:DcrState -Name $Name -ResourceGroup $ResourceGroupName -TemplateFile $TemplateFile }
function Get-AzResourceGroupDeploymentOperation {
    param($ResourceGroupName, $DeploymentName, $ErrorAction)
    foreach ($o in @(Get-DcrFromSchemaDeploymentOperation -State $global:DcrState -DeploymentName $DeploymentName)) {
        $m = $o.properties.statusMessage
        [pscustomobject]@{ ProvisioningState = $o.properties.provisioningState; StatusMessage = $(if ($m -is [string]) { $m } else { ConvertTo-Json -InputObject $m -Depth 8 -Compress }) }
    }
}
function Get-AzADServicePrincipal { param($ApplicationId, $ErrorAction) $id = Resolve-DcrFromSchemaApp -State $global:DcrState -AppId $ApplicationId; if (-not $id) { throw "Resource '$ApplicationId' does not exist." }; [pscustomobject]@{ Id = $id } }
function Get-AzRoleAssignment { param($ObjectId, $Scope, $RoleDefinitionName, $ErrorAction) @(Get-DcrFromSchemaAssignment -State $global:DcrState -PrincipalId $ObjectId -Scope $Scope | Where-Object { $_.Role -eq $RoleDefinitionName }) }
function New-AzRoleAssignment { param($ObjectId, $RoleDefinitionName, $Scope, $ErrorAction) Add-DcrFromSchemaAssignment -State $global:DcrState -PrincipalId $ObjectId -Role $RoleDefinitionName -Scope $Scope; [pscustomobject]@{ RoleAssignmentId = 'x' } }
$splat = Get-Content -LiteralPath $Parameters -Raw | ConvertFrom-Json -AsHashtable
$code = 0
$result = $null
try { $result = & $Script @splat }
catch { $code = 1; Set-Content -LiteralPath (Join-Path $Out 'error.txt') -Value $_.Exception.Message }
Set-Content -LiteralPath (Join-Path $Out 'results.json') -Value (ConvertTo-Json -InputObject @($result) -Depth 10)
Set-Content -LiteralPath (Join-Path $Out 'writes.json') -Value (ConvertTo-Json -InputObject @($global:DcrState.Writes) -Depth 10)
exit $code
'@

    function Get-SchemaPath {
        param([string] $Example, [string] $Schema)
        if ($Example) { return (Join-Path $script:examples $Example) }
        $path = Join-Path $TestDrive "$([guid]::NewGuid().ToString('N')).json"
        [System.IO.File]::WriteAllText($path, $Schema, [System.Text.UTF8Encoding]::new($false))
        $path
    }

    function Invoke-LegacyDcr {
        param([string] $SchemaPath, [hashtable] $Parameters, [switch] $NoEndpoint)
        $tree = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $out = Join-Path $tree 'out'
        $templates = Join-Path $tree 'templates'
        New-Item -ItemType Directory -Path $out -Force | Out-Null
        $copy = Join-Path $tree 'New-DcrFromSchema.ps1'
        Set-Content -LiteralPath $copy -Value ((Get-Content -LiteralPath $script:scriptPath -Raw) -replace '(?m)^#Requires -Modules[^\r\n]*\r?\n', '') -NoNewline
        Set-Content -LiteralPath (Join-Path $tree 'run.ps1') -Value $script:wrapper
        $splat = @{ SchemaPath = $SchemaPath; ResourceGroupName = 'rg-sentinel'; WorkspaceName = 'law-sentinel'; NonInteractive = $true; OutputDirectory = $templates } + $Parameters
        Set-Content -LiteralPath (Join-Path $tree 'parameters.json') -Value (ConvertTo-Json -InputObject $splat)
        $output = & pwsh -NoProfile -NonInteractive -File (Join-Path $tree 'run.ps1') -Script $copy -Helper $script:helperPath -Parameters (Join-Path $tree 'parameters.json') -Out $out -NoEndpoint:$NoEndpoint 2>&1 | Out-String
        $errorFile = Join-Path $out 'error.txt'
        [pscustomobject]@{
            ExitCode  = $LASTEXITCODE
            Output    = $output
            Error     = if (Test-Path -LiteralPath $errorFile) { (Get-Content -LiteralPath $errorFile -Raw).Trim().Replace($templates, '<out>') } else { $null }
            Result    = @(Get-Content -LiteralPath (Join-Path $out 'results.json') -Raw | ConvertFrom-Json -Depth 10 | Where-Object { $null -ne $_ }) | Select-Object -First 1
            Writes    = @(Get-Content -LiteralPath (Join-Path $out 'writes.json') -Raw | ConvertFrom-Json -Depth 10 | Where-Object { $null -ne $_ })
            Templates = $templates
        }
    }

    function Invoke-ModuleDcr {
        param([string] $SchemaPath, [hashtable] $Parameters, [switch] $NoEndpoint)
        $tree = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $templates = Join-Path $tree 'templates'
        $script:dcrState = Get-DcrFromSchemaStandIn -NoEndpoint:$NoEndpoint
        $script:logs = [System.Collections.Generic.List[string]]::new()
        $script:principalTypes = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName iSOCDeployments Write-iSOCLog { $script:logs.Add("$Level $Message") }
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
        Mock -ModuleName iSOCDeployments Test-iSOCAzResourceGroupDeployment { Invoke-DcrFromSchemaValidate -State $script:dcrState -ResourceGroup $Parameters.ResourceGroupName -TemplateFile $Parameters.TemplateFile }
        Mock -ModuleName iSOCDeployments New-iSOCAzResourceGroupDeployment { Invoke-DcrFromSchemaDeploy -State $script:dcrState -Name $Name -ResourceGroup $Parameters.ResourceGroupName -TemplateFile $Parameters.TemplateFile }
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
            $state = $script:dcrState
            if ($Api -eq 'Graph') {
                $q = [Uri]::UnescapeDataString($Path)
                if ($q -match "^/servicePrincipals\?\`$filter=appId eq '([^']+)'$") {
                    $id = Resolve-DcrFromSchemaApp -State $state -AppId $Matches[1]
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
                return @(Get-DcrFromSchemaAssignment -State $state -PrincipalId $Matches[1] | ForEach-Object {
                        [pscustomobject]@{ id = 'a'; name = 'a'; properties = [pscustomobject]@{ scope = $_.Scope; principalId = $_.PrincipalId; roleDefinitionId = "/subscriptions/$($state.SubscriptionId)/providers/Microsoft.Authorization/roleDefinitions/$($script:roleIds[$_.Role])" } }
                    })
            }
            if ($Method -eq 'PUT' -and $Path -match '^(.+)/providers/Microsoft\.Authorization/roleAssignments/[^/?]+') {
                $scope = $Matches[1]
                $roleId = ($Body.properties.roleDefinitionId -split '/')[-1]
                $role = @($script:roleIds.Keys | Where-Object { $script:roleIds[$_] -eq $roleId })[0]
                $script:principalTypes.Add([string]$Body.properties['principalType'])
                Add-DcrFromSchemaAssignment -State $state -PrincipalId $Body.properties.principalId -Role $role -Scope $scope
                return
            }
            $a = Invoke-DcrFromSchemaArm -State $state -Method $Method -Path $Path
            if ($a.Status -eq 404 -and $AllowNotFound) { return }
            if ($a.Status -ge 400) { throw [System.Net.Http.HttpRequestException]::new("HTTP $($a.Status) from $Method ${Path}: $($a.Body.error.message)", $null, [System.Net.HttpStatusCode]$a.Status) }
            if ($null -eq $a.Body) { return }
            $object = ConvertTo-Json -InputObject $a.Body -Depth 30 | ConvertFrom-Json -Depth 30
            if (@($object.PSObject.Properties.Name) -join ',' -eq 'value') { return $object.value }
            $object
        }
        $ctx = InModuleScope iSOCDeployments -Parameters @{ State = $script:dcrState } {
            param($State)
            New-iSOCContext -Value @{
                TenantId = 't'; SubscriptionId = $State.SubscriptionId; ResourceGroup = $State.ResourceGroup; WorkspaceName = $State.WorkspaceName
                WorkspaceResourceId = $State.WorkspacePath; WorkspaceId = $State.WorkspaceId; Region = $State.Location; PlaybookResourceGroup = 'rg-auto'
                Environment = 'AzureCloud'; IsGov = $false; ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'tester'
            }
        }
        $result = $null
        $failure = $null
        try { $result = New-iSOCDcrFromSchema -Context $ctx -SchemaPath $SchemaPath -OutputDirectory $templates @Parameters }
        catch { $failure = $_.Exception.Message.Replace($templates, '<out>') }
        [pscustomobject]@{ Result = $result; Error = $failure; Writes = @($script:dcrState.Writes); Templates = $templates; Logs = @($script:logs); PrincipalTypes = @($script:principalTypes) }
    }

    function ConvertTo-ComparableText {
        param([string] $Text)
        ($Text -replace "`r`n", "`n" -replace 'generated by New-(iSOC)?DcrFromSchema(\.ps1)?\.', 'generated by X.').TrimEnd("`n")
    }

    function ConvertTo-ComparableWrite {
        param($Writes)
        @($Writes | ForEach-Object {
                switch ($_.Kind) {
                    'Validate' { "Validate $($_.ResourceGroup) $($_.Resource)" }
                    'Deploy' { "Deploy $($_.ResourceGroup) $($_.Name)`n" + (ConvertTo-ComparableText $_.Template) }
                    'Grant' { "Grant $($_.PrincipalId) $($_.Role) $($_.Scope)" }
                }
            })
    }

    function Get-ComparableTemplate {
        param([string] $Folder)
        if (-not (Test-Path -LiteralPath $Folder)) { return @() }
        @(Get-ChildItem -LiteralPath $Folder -File | Sort-Object Name | ForEach-Object { "$($_.Name)`n" + (ConvertTo-ComparableText (Get-Content -LiteralPath $_.FullName -Raw)) })
    }

    function ConvertTo-ComparableResult {
        param($Result)
        if ($null -eq $Result) { return 'none' }
        $o = [ordered]@{}
        foreach ($n in @('TableName', 'ColumnCount', 'WorkspaceName', 'ResourceGroupName', 'DcrName', 'DcrResourceGroup', 'Location', 'StreamName', 'TransformKql', 'TableTemplatePath', 'DcrTemplatePath', 'Deployed', 'ImmutableId', 'Endpoint', 'Granted')) {
            $v = $Result.$n
            if ($n -like '*TemplatePath' -and $v) { $v = Split-Path -Leaf $v }
            if ($n -eq 'Granted') { $v = @($v) }
            $o[$n] = $v
        }
        ConvertTo-Json -InputObject $o -Depth 5 -Compress
    }
}

Describe 'The schema helpers, beside the script''s' {
    BeforeAll {
        Mock Write-PipelineMessage { }
        $script:inModule = { param([scriptblock] $Block, [hashtable] $With = @{}) InModuleScope iSOCDeployments -Parameters $With -ScriptBlock $Block }
        $script:canonical = { param($Value) ConvertTo-Json -InputObject $Value -Depth 30 -Compress }
    }

    It 'reads <Label> the same' -ForEach @(
        @{ Label = 'every shipped example'; Files = @('annotated.json', 'auxiliary-plan.json', 'basic-plan.json', 'minimal.json', 'threat-intel-alerts.json') }
    ) {
        foreach ($file in $Files) {
            $path = Join-Path $script:examples $file
            $old = Import-TableSpec -Path $path
            $new = & $script:inModule { param($P) Mock Write-iSOCLog { }; Import-iSOCTableSpec -Path $P } @{ P = $path }
            (& $script:canonical $new) | Should -BeExactly (& $script:canonical $old) -Because $file
        }
    }

    It 'reads and refuses every shape the same' {
        $texts = @(
            '{ "properties": { "plan": "Basic", "schema": { "name": "T_CL", "description": "d", "columns": [ { "name": "A", "type": "string" } ] } } }'
            '{ "properties": { "plan": "Basic" } }'
            '[ { "name": "A", "type": "string" }, { "name": "B" } ]'
            '{ "name": "Lone", "type": "string" }'
            '{ "table": "T_CL", "fields": [ { "name": "A" } ], "transformKql": "source", "location": "westeurope" }'
            '{ "tableName": "T_CL", "columns": [] }'
            '{ "tableName": "T_CL" }'
            '[ { "a": 1 } ]'
            ''
            '{ "tableName": "T_CL", "columns": [ { "name": "A", "type": "string" }, ], }'
            "{ $([char]0x201C)tableName$([char]0x201D): $([char]0x201C)T_CL$([char]0x201D), `"columns`": [ { `"name`": `"A`" } ] }"
            "$([char]0xFEFF){ `"tableName`": `"T_CL`", `"columns`": [ { `"name`": `"A`" } ] /* c */ }"
            '{ "tableName": nope }'
        )
        foreach ($t in $texts) {
            $path = Join-Path $TestDrive "$([guid]::NewGuid().ToString('N')).json"
            [System.IO.File]::WriteAllText($path, $t, [System.Text.UTF8Encoding]::new($false))
            $old = try { & $script:canonical (Import-TableSpec -Path $path) } catch { "error: $($_.Exception.Message)" }
            $new = & $script:inModule { param($P) Mock Write-iSOCLog { }; try { ConvertTo-Json -InputObject (Import-iSOCTableSpec -Path $P) -Depth 30 -Compress } catch { "error: $($_.Exception.Message)" } } @{ P = $path }
            $new | Should -BeExactly $old -Because $t
        }
    }

    It 'repairs text the same' {
        $q = [char]0x201C
        $texts = @('', '{"a": 1}', "$([char]0xFEFF){`"a`":1}", "{ ${q}a$([char]0x201D): 1 }", "{`"u`": `"http://x//y`", // c`n `"b`": [1, 2, ], /* d */ }", "{`"s`": `"a \`" , ]`"}", "$([char]0x00A0)[1,]")
        foreach ($t in $texts) {
            $old = Remove-JsonNoise -Text $t
            $new = & $script:inModule { param($T) Repair-iSOCJsonText -Text $T } @{ T = $t }
            (& $script:canonical $new) | Should -BeExactly (& $script:canonical $old)
            (& $script:inModule { param($T) ConvertTo-iSOCSafeText -Text $T -MaxLength 20 } @{ T = $t }) | Should -BeExactly (ConvertTo-SafeText -Text $t -MaxLength 20)
            (& $script:inModule { param($T) ConvertTo-iSOCStraightPunctuation -Text $T } @{ T = $t }) | Should -BeExactly (ConvertTo-StraightPunctuation -Text $t)
        }
        (& $script:inModule { ConvertTo-iSOCSafeText -Text "a`n`tb$([char]0x200B)c    d" }) | Should -BeExactly (ConvertTo-SafeText -Text "a`n`tb$([char]0x200B)c    d")
        (& $script:inModule { ConvertTo-iSOCSafeText -Text $null }) | Should -BeExactly (ConvertTo-SafeText -Text $null)
    }

    It 'names types, tables and column issues the same' {
        foreach ($type in @('string', 'STRING', ' bool ', 'integer', 'int64', 'double', 'decimal', 'datetime', 'timestamp', 'uuid', 'object', 'array', 'text', '', $null)) {
            (& $script:inModule { param($T) Get-iSOCTableColumnType -DeclaredType $T } @{ T = $type }) | Should -Be (Get-TableColumnType -DeclaredType $type)
        }
        foreach ($name in @('MyApp_CL', 'MyApp', '9app_CL', 'a-b_CL', 'A_CL', ('A' * 61) + '_CL', '')) {
            @(& $script:inModule { param($N) Get-iSOCTableNameProblem -Name $N } @{ N = $name }) | Should -Be @(Test-TableName -Name $name)
        }
        $cases = @(@('Message_s', 'string', ''), @('TenantId', 'string', ''), @('tenantid', 'bool', 'ip'), @('9x', 'text', 'ipv4'), @('a', 'string', ''), @(('A' * 46), 'guid', 'armPath'), @('', '', ''), @('Fine', 'dynamic', 'uri'))
        foreach ($c in $cases) {
            $old = @(Get-ColumnIssue -Name $c[0] -DeclaredType $c[1] -DataTypeHint $c[2])
            $new = @(& $script:inModule { param($C) Get-iSOCColumnIssue -Name $C[0] -DeclaredType $C[1] -DataTypeHint $C[2] } @{ C = $c })
            (& $script:canonical $new) | Should -BeExactly (& $script:canonical $old)
        }
    }

    It 'resolves and repairs a schema the same' {
        $columns = @(
            [pscustomobject]@{ name = ' Alert '; type = 'string'; desc = "two`nlines" }
            [pscustomobject]@{ name = 'alert'; columnType = 'bool' }
            [pscustomobject]@{ name = 'Dup'; dataType = 'integer' }
            [pscustomobject]@{ name = 'Dup'; type = 'long' }
            [pscustomobject]@{ name = '9Bad'; type = 'string' }
            [pscustomobject]@{ name = 'Src'; type = 'string'; dataTypeHint = 'ipv4'; displayName = ('D' * 200) }
            [pscustomobject]@{ name = 'TimeGenerated'; type = 'string' }
            [pscustomobject]@{ name = 'Sketch'; type = 'hyperloglog' }
        )
        $old = Resolve-TableSchema -Column $columns
        $new = & $script:inModule { param($C) Resolve-iSOCTableSchema -Column $C } @{ C = $columns }
        (& $script:canonical $new) | Should -BeExactly (& $script:canonical $old)

        $oldRepaired = @(Repair-TableSchema -Column (Resolve-TableSchema -Column $columns).Columns.ToArray())
        $newRepaired = @(& $script:inModule { param($C) Mock Write-iSOCLog { }; Repair-iSOCTableSchema -Column (Resolve-iSOCTableSchema -Column $C).Columns.ToArray() } @{ C = $columns })
        (& $script:canonical $newRepaired) | Should -BeExactly (& $script:canonical $oldRepaired)

        $noTime = @([pscustomobject]@{ name = 'A'; type = 'string' })
        $oldAdded = @(Invoke-SchemaEditor -Column (Resolve-TableSchema -Column $noTime).Columns.ToArray())
        $newAdded = @(& $script:inModule { param($C) Mock Write-iSOCLog { }; Invoke-iSOCSchemaRepair -Column (Resolve-iSOCTableSchema -Column $C).Columns.ToArray() } @{ C = $noTime })
        (& $script:canonical $newAdded) | Should -BeExactly (& $script:canonical $oldAdded)

        $oldError = try { Invoke-SchemaEditor -Column (Resolve-TableSchema -Column $columns).Columns.ToArray() } catch { $_.Exception.Message }
        $newError = & $script:inModule { param($C) Mock Write-iSOCLog { }; try { Invoke-iSOCSchemaRepair -Column (Resolve-iSOCTableSchema -Column $C).Columns.ToArray() } catch { $_.Exception.Message } } @{ C = $columns }
        $newError | Should -BeExactly $oldError
        $oldError | Should -Match 'Sketch'
    }

    It 'builds streams, transforms and diffs the same' {
        $columns = @(
            [pscustomobject]@{ Name = 'TimeGenerated'; Type = 'dateTime'; DataTypeHint = ''; Description = ''; DisplayName = '' }
            [pscustomobject]@{ Name = 'EventId'; Type = 'guid'; DataTypeHint = 'guid'; Description = 'An id.'; DisplayName = 'Event' }
            [pscustomobject]@{ Name = 'Case'; Type = 'string'; DataTypeHint = ''; Description = ''; DisplayName = '' }
            [pscustomobject]@{ Name = 'case'; Type = 'guid'; DataTypeHint = ''; Description = ''; DisplayName = '' }
            [pscustomobject]@{ Name = 'Count'; Type = 'long'; DataTypeHint = ''; Description = ''; DisplayName = '' }
        )
        $oldStream = @(ConvertTo-StreamColumn -Column $columns)
        $newStream = @(& $script:inModule { param($C) ConvertTo-iSOCSchemaStreamColumn -Column $C } @{ C = $columns })
        (& $script:canonical $newStream) | Should -BeExactly (& $script:canonical $oldStream)
        (& $script:inModule { param($C, $S) Get-iSOCSchemaTransform -Column $C -StreamColumn $S } @{ C = $columns; S = $oldStream }) | Should -BeExactly (Get-DefaultTransform -Column $columns -StreamColumn $oldStream)
        (& $script:inModule { param($C, $S) Get-iSOCSchemaTransform -Column $C -StreamColumn $S } @{ C = @($columns[0]); S = @($oldStream[0]) }) | Should -BeExactly 'source'

        $live = @([pscustomobject]@{ name = 'Count'; type = 'int' }, [pscustomobject]@{ name = 'case'; type = 'string' }, [pscustomobject]@{ name = 'Extra'; type = 'string' }, [pscustomobject]@{ name = '_Sys'; type = 'string' }, [pscustomobject]@{ name = 'TimeGenerated' })
        $oldDiff = Compare-TableSchema -DesiredColumn $columns -ExistingColumn $live
        $newDiff = & $script:inModule { param($C, $L) Compare-iSOCTableSchema -DesiredColumn $C -ExistingColumn $L } @{ C = $columns; L = $live }
        (& $script:canonical $newDiff) | Should -BeExactly (& $script:canonical $oldDiff)

        foreach ($t in @('source', "source | where A == $([char]0x2018)x$([char]0x2019)", ('x' * 15361))) {
            $old = try { & $script:canonical (Test-TransformKql -Transform $t) } catch { $_.Exception.Message }
            $new = & $script:inModule { param($T) try { ConvertTo-Json -InputObject (Repair-iSOCTransformKql -Transform $T) -Depth 5 -Compress } catch { $_.Exception.Message } } @{ T = $t }
            $new | Should -BeExactly $old
        }
    }

    It 'builds the same templates' {
        $columns = @(
            [pscustomobject]@{ Name = 'TimeGenerated'; Type = 'dateTime'; DataTypeHint = ''; Description = 'When.'; DisplayName = '' }
            [pscustomobject]@{ Name = 'Src'; Type = 'string'; DataTypeHint = 'ip'; Description = ''; DisplayName = 'Source' }
        )
        foreach ($c in @(
                @{ Plan = 'Analytics'; Retention = 90; Total = 365; Hint = $false; Description = 'A table.' }
                @{ Plan = 'Basic'; Retention = 30; Total = -1; Hint = $true; Description = '' }
                @{ Plan = ''; Retention = 0; Total = 0; Hint = $false; Description = 'x' }
            )) {
            $old = Build-TableArmTemplate -WorkspaceName law -Table T_CL -Column $columns -Plan $c.Plan -Retention $c.Retention -TotalRetention $c.Total -TableDescription $c.Description -IncludeDataTypeHint:$c.Hint
            $new = & $script:inModule { param($C, $Cols) Mock Write-iSOCLog { }; ConvertTo-iSOCTableArmTemplate -WorkspaceName law -Table T_CL -Column $Cols -Plan $C.Plan -Retention $C.Retention -TotalRetention $C.Total -TableDescription $C.Description -IncludeDataTypeHint:$C.Hint } @{ C = $c; Cols = $columns }
            (ConvertTo-ComparableText (ConvertTo-Json -InputObject $new -Depth 30)) | Should -BeExactly (ConvertTo-ComparableText (ConvertTo-Json -InputObject $old -Depth 30))
        }

        $stream = @([pscustomobject]@{ name = 'TimeGenerated'; type = 'datetime' }, [pscustomobject]@{ name = 'Src'; type = 'string' })
        foreach ($d in @('A rule.', ('Long ' * 80), '')) {
            foreach ($endpoint in @('', '/subscriptions/x/resourceGroups/y/providers/Microsoft.Insights/dataCollectionEndpoints/z')) {
                $old = Build-DcrArmTemplate -Name dcr-t -Region uksouth -Stream Custom-T_CL -StreamColumn $stream -WorkspaceResourceId /ws -OutputStream Custom-T_CL -Transform source -EndpointResourceId $endpoint -RuleDescription $d
                $new = & $script:inModule { param($D, $E, $S) $clean = ConvertTo-iSOCSafeText -Text $D -MaxLength 256; ConvertTo-iSOCDcrArmTemplate -Name dcr-t -Region uksouth -Kind Direct -Stream Custom-T_CL -StreamColumn $S -WorkspaceResourceId /ws -OutputStream Custom-T_CL -Transform source -EndpointResourceId $E -Description $clean -GeneratedBy 'New-iSOCDcrFromSchema' } @{ D = $d; E = $endpoint; S = $stream }
                (ConvertTo-ComparableText (ConvertTo-Json -InputObject $new -Depth 30)) | Should -BeExactly (ConvertTo-ComparableText (ConvertTo-Json -InputObject $old -Depth 30))
            }
        }
    }

    It 'flattens deployment errors the same' {
        $list = [System.Collections.Generic.List[object]]::new()
        $list.Add([pscustomobject]@{ Code = 'A'; Message = 'outer'; Target = 'T'; Details = @([pscustomobject]@{ code = 'B'; message = 'inner'; details = @([pscustomobject]@{ Code = 'C'; Message = 'deepest' }) }) })
        $list.Add([pscustomobject]@{ Code = 'D'; Message = 'second'; InnerError = 'as text' })
        $cases = @('plain text', [pscustomobject]@{ Foo = 1 }, [pscustomobject]@{ Message = 'only a message'; AdditionalInfo = @([pscustomobject]@{ Code = 'E'; Message = 'info' }) }, $null)
        foreach ($e in @($cases) + @(, $list)) {
            (& $script:inModule { param($E) Format-iSOCDeploymentError -ErrorObject $E } @{ E = $e }) | Should -BeExactly (Format-DeploymentError -ErrorObject $e)
        }
    }
}

Describe 'Making a table and rule as New-DcrFromSchema.ps1 does: <Label>' -ForEach $script:runs {
    It 'validates, deploys and grants the same, writes the same templates and returns the same result' {
        $path = Get-SchemaPath -Example $Example -Schema $Schema
        $legacy = Invoke-LegacyDcr -SchemaPath $path -Parameters $Parameters -NoEndpoint:([bool]$NoEndpoint)
        $module = Invoke-ModuleDcr -SchemaPath $path -Parameters $Parameters -NoEndpoint:([bool]$NoEndpoint)

        $legacy.Output | Should -Not -Match 'The script prompted'
        if (-not $Parameters.WhatIf) { @(Get-ComparableTemplate $legacy.Templates).Count | Should -BeGreaterThan 0 }
        if ($Parameters.Deploy -and -not $Parameters.WhatIf) { @($legacy.Writes | Where-Object { $_.Kind -eq 'Deploy' }).Count | Should -BeGreaterThan 0 }
        if (-not $legacy.Error) { $legacy.Result.TableName | Should -Not -BeNullOrEmpty }
        if ($ExpectError) { $legacy.Error | Should -Match $ExpectError } else { $legacy.Error | Should -BeNullOrEmpty }
        $module.Error | Should -BeExactly $legacy.Error
        @(ConvertTo-ComparableWrite $module.Writes) | Should -Be @(ConvertTo-ComparableWrite $legacy.Writes)
        @(Get-ComparableTemplate $module.Templates) | Should -Be @(Get-ComparableTemplate $legacy.Templates)
        if (-not $legacy.Error) {
            $legacy.ExitCode | Should -Be 0
            (ConvertTo-ComparableResult $module.Result) | Should -BeExactly (ConvertTo-ComparableResult $legacy.Result)
        }
        else {
            $legacy.ExitCode | Should -Be 1
        }
    }
}

Describe 'Refusing as New-DcrFromSchema.ps1 does: <Label>' -ForEach $script:refusals {
    It 'refuses with the same message and writes nothing' {
        $path = Get-SchemaPath -Example $Example -Schema $Schema
        $legacy = Invoke-LegacyDcr -SchemaPath $path -Parameters $Parameters
        $module = Invoke-ModuleDcr -SchemaPath $path -Parameters $Parameters
        $legacy.ExitCode | Should -Be 1
        if ($ModuleError) {
            $legacy.Error | Should -Match $LegacyMatch
            $module.Error | Should -BeExactly $ModuleError
        }
        else {
            $expected = $legacy.Error
            if ($Replace) { foreach ($k in $Replace.Keys) { $expected = $expected.Replace($k, $Replace[$k]) } }
            $module.Error | Should -BeExactly $expected
        }
        @($legacy.Writes | Where-Object { $_.Kind -ne 'Validate' }) | Should -BeNullOrEmpty
        @($module.Writes | Where-Object { $_.Kind -ne 'Validate' }) | Should -BeNullOrEmpty
        Test-Path -LiteralPath $module.Templates | Should -BeFalse
    }
}

Describe 'New-iSOCDcrFromSchema' {
    It 'has something to compare: a deployed run validates, deploys and grants' {
        $module = Invoke-ModuleDcr -SchemaPath (Get-SchemaPath -Example 'annotated.json') -Parameters @{ Deploy = $true; GrantIngestionRoleTo = @('aaaaaaaa-1111-2222-3333-444444444444', 'user-object-1') }
        @($module.Writes.Kind) | Should -Be @('Validate', 'Deploy', 'Validate', 'Deploy', 'Grant', 'Grant')
        $module.Result.PSObject.TypeNames[0] | Should -Be 'iSOCDeployments.DcrFromSchemaRun'
        $module.Result.Endpoint | Should -Match '^https://dcr-payment-audit-'
        @($module.PrincipalTypes) | Should -Be @('ServicePrincipal', 'User')
    }

    It 'names itself in the templates, with LF line endings and one final newline' {
        $module = Invoke-ModuleDcr -SchemaPath (Get-SchemaPath -Example 'minimal.json') -Parameters @{}
        foreach ($file in Get-ChildItem -LiteralPath $module.Templates -File) {
            $bytes = [System.IO.File]::ReadAllText($file.FullName)
            $bytes | Should -Match 'generated by New-iSOCDcrFromSchema\.'
            $bytes | Should -Not -Match "`r"
            $bytes.EndsWith("}`n") | Should -BeTrue
        }
    }

    It 'writes the same file each time' {
        $path = Get-SchemaPath -Example 'threat-intel-alerts.json'
        $first = Invoke-ModuleDcr -SchemaPath $path -Parameters @{}
        $second = Invoke-ModuleDcr -SchemaPath $path -Parameters @{}
        @(Get-ComparableTemplate $second.Templates) | Should -Be @(Get-ComparableTemplate $first.Templates)
        (Get-Content -LiteralPath (Join-Path $first.Templates 'table-threatintelalert.json') -Raw) | Should -Match '^\{\s+"\$schema"'
    }

    It 'writes and deploys nothing under -WhatIf, and logs no subscription id' {
        $module = Invoke-ModuleDcr -SchemaPath (Get-SchemaPath -Example 'annotated.json') -Parameters @{ Deploy = $true; WhatIf = $true }
        $module.Writes | Should -BeNullOrEmpty
        Test-Path -LiteralPath $module.Templates | Should -BeFalse
        $module.Result.Deployed | Should -BeFalse
        ($module.Logs -join "`n") | Should -Not -Match '11111111-2222-3333-4444-555555555555'
    }

    It 'names the module''s commands in what it tells you to run' {
        $module = Invoke-ModuleDcr -SchemaPath (Get-SchemaPath -Example 'minimal.json') -Parameters @{ Deploy = $true }
        ($module.Logs -join "`n") | Should -Match 'Test-iSOCDcrIngestion -DcrName dcr-myapp -DcrResourceGroupName rg-sentinel -Follow'
        ($module.Logs -join "`n") | Should -Not -Match 'Test-DcrIngestion\.ps1'
    }

    It 'resolves a relative output folder against the current location' {
        $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $folder | Out-Null
        Push-Location $folder
        try {
            $module = Invoke-ModuleDcr -SchemaPath (Get-SchemaPath -Example 'minimal.json') -Parameters @{}
            $script:dcrState = Get-DcrFromSchemaStandIn
            $ctx = InModuleScope iSOCDeployments -Parameters @{ State = $script:dcrState } { param($State) New-iSOCContext -Value @{ TenantId = 't'; SubscriptionId = $State.SubscriptionId; ResourceGroup = $State.ResourceGroup; WorkspaceName = $State.WorkspaceName; WorkspaceResourceId = $State.WorkspacePath; WorkspaceId = $State.WorkspaceId; Region = $State.Location; PlaybookResourceGroup = 'rg-auto'; Environment = 'AzureCloud'; IsGov = $false; ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'tester' } }
            $run = New-iSOCDcrFromSchema -Context $ctx -SchemaPath (Join-Path $script:examples 'minimal.json') -OutputDirectory 'relative'
            $run.DcrTemplatePath | Should -Be (Join-Path (Join-Path (Get-Location).ProviderPath 'relative') 'dcr-myapp.json')
            Test-Path -LiteralPath $run.DcrTemplatePath | Should -BeTrue
            $module.Error | Should -BeNullOrEmpty
        }
        finally { Pop-Location }
    }
}
