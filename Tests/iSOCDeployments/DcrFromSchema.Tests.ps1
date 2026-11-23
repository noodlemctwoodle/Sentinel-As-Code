#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for New-iSOCDcrFromSchema.

.DESCRIPTION
    The schema reader, repairs, checks, stream and transform builders,
    templates and error flattener are held to explicit expected values for
    a handful of representative inputs, the shipped examples among them.

    The command runs through mocks of the module's REST client and
    deployment wrappers, over one stand-in workspace
    (Tests/iSOCDeployments/_helpers/DcrFromSchemaStandIn.psm1) whose tables
    and rules appear as they are deployed: each refusal must give its
    message and write nothing, and a run must validate, deploy and grant,
    name the module in its templates, write the same file each time, write
    nothing under -WhatIf and resolve a relative output folder.

    Parity with New-DcrFromSchema.ps1 was proven on release/26.11.0 before
    the script was removed.

.NOTES
    File:         Tests/iSOCDeployments/DcrFromSchema.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeDiscovery {
    $script:refusals = @(
        @{ Label = 'a classic table'; Schema = '{ "tableName": "Legacy_CL", "columns": [ { "name": "TimeGenerated", "type": "datetime" } ] }'; Parameters = @{}; Message = 'Legacy_CL is a classic (MMA / Data Collector API) table. A DCR cannot target one (InvalidOutputTable). Migrate it first with Invoke-iSOCClassicTableMigration.' }
        @{ Label = 'a column whose live type differs'; Schema = '{ "tableName": "Typed_CL", "columns": [ { "name": "TimeGenerated", "type": "datetime" }, { "name": "AlertId", "type": "string" } ] }'; Parameters = @{}; Message = 'The live table''s column types differ from the schema, and a column type cannot be changed after creation: AlertId: live table has ''int'', the schema says ''string''. Align the schema file with the live table, or use a new table name.' }
        @{ Label = 'an Auxiliary table with names that differ only by case'; Schema = '{ "tableName": "CaseAux_CL", "plan": "Auxiliary", "columns": [ { "name": "TimeGenerated", "type": "datetime" }, { "name": "Alert", "type": "string" }, { "name": "alert", "type": "string" } ] }'; Parameters = @{}; Message = 'An Auxiliary table drops rows when column names differ only by case, so this schema cannot use the Auxiliary plan: column names differ only by case: alert, Alert. Analytics and Basic tables treat these as separate columns; an Auxiliary table drops rows because of them. Rename the columns, or choose Analytics or Basic.' }
        @{ Label = 'a resource group that does not exist'; Example = 'minimal.json'; Parameters = @{ DcrResourceGroupName = 'rg-missing' }; Message = 'DCR resource group ''rg-missing'' does not exist in the workspace''s subscription. Re-run and supply an existing resource group, or pass -DcrResourceGroupName.' }
        @{ Label = 'a type that cannot be repaired'; Schema = '{ "tableName": "BadType_CL", "columns": [ { "name": "TimeGenerated", "type": "datetime" }, { "name": "Sketch", "type": "hyperloglog" } ] }'; Parameters = @{}; Message = 'Schema cannot be used and non-interactive mode cannot ask: Sketch: type ''hyperloglog'' is not a Log Analytics column type. Use one of: boolean, dateTime, dynamic, guid, int, long, real, string' }
        @{ Label = 'a table name that cannot be used'; Schema = '{ "tableName": "9bad_CL", "columns": [ { "name": "TimeGenerated", "type": "datetime" } ] }'; Parameters = @{}; Message = 'Table name is not usable: ''9bad_CL'' must start with a letter and contain only letters, digits and underscores, so KQL can reference it unquoted.' }
        @{ Label = 'retention out of range in the file'; Schema = '{ "tableName": "Kept_CL", "retentionInDays": 1000, "columns": [ { "name": "TimeGenerated", "type": "datetime" } ] }'; Parameters = @{}; Message = 'Interactive retention must be between 4 and 730 days, or -1 for the workspace default; got 1000.' }
        @{ Label = 'total retention shorter than interactive'; Schema = '{ "tableName": "Kept_CL", "retentionInDays": 90, "totalRetentionInDays": 30, "columns": [ { "name": "TimeGenerated", "type": "datetime" } ] }'; Parameters = @{}; Message = 'Total retention (30 days) cannot be shorter than interactive retention (90 days).' }
        @{ Label = 'a transform too long'; Example = 'minimal.json'; Parameters = @{ TransformKql = 'source | where ' + ('x' * 15400) }; Message = 'The transform is 15415 characters; a data collection rule allows 15360. Move the logic into a workspace function, or trim it.' }
        @{ Label = 'a sample of the data'; Schema = '[ { "user": "a", "count": 1 } ]'; Parameters = @{ TableName = 'Sample' }; Message = 'Schema file has no column list (<path>). Expected { "tableName": "MyTable_CL", "columns": [ { "name": "...", "type": "..." } ] }. This tool takes a schema, not a sample of the data.' }
        @{ Label = 'a file that is not JSON'; Schema = 'tableName: Yaml_CL'; Parameters = @{}; Like = 'Schema file is not valid JSON (<path>): *' }
        @{ Label = 'no table name'; Schema = '[ { "name": "TimeGenerated", "type": "datetime" }, { "name": "Value", "type": "string" } ]'; Parameters = @{}; Message = 'The schema file names no table, so -TableName is required.' }
        @{ Label = 'a plan in the file that is not one'; Schema = '{ "tableName": "Plan_CL", "plan": "Premium", "columns": [ { "name": "TimeGenerated", "type": "datetime" } ] }'; Parameters = @{}; Message = 'The schema file''s plan ''Premium'' is not one of Analytics, Basic and Auxiliary.' }
    )
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:examples = Join-Path $script:repoRoot 'Modules/iSOCDeployments/Resources/DcrFromSchema/Examples'
    $script:helperPath = Join-Path $PSScriptRoot '_helpers/DcrFromSchemaStandIn.psm1'
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module $script:helperPath -Force

    $script:roleIds = @{ 'Monitoring Metrics Publisher' = '3913510d-42f4-4e42-8a64-420c390055eb' }

    function Get-SchemaPath {
        <#
        .SYNOPSIS
            Return the path of an example schema, or write the given schema text to a new file.
        .PARAMETER Example
            Name of a shipped example schema.
        .PARAMETER Schema
            Schema text to write when no example is named.
        #>
        param([string] $Example, [string] $Schema)
        if ($Example) { return (Join-Path $script:examples $Example) }
        $path = Join-Path $TestDrive "$([guid]::NewGuid().ToString('N')).json"
        [System.IO.File]::WriteAllText($path, $Schema, [System.Text.UTF8Encoding]::new($false))
        $path
    }

    function Invoke-ModuleDcr {
        <#
        .SYNOPSIS
            Run New-iSOCDcrFromSchema with the Azure, REST and logging commands stood in, and return the result, error, writes and logs.
        .PARAMETER SchemaPath
            Path of the schema file.
        .PARAMETER Parameters
            Parameters splatted to the command.
        .PARAMETER NoEndpoint
            Make the stand-in report no data collection endpoint.
        #>
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
        <#
        .SYNOPSIS
            Normalise line endings and the generator name so generated text compares equal.
        .PARAMETER Text
            Text to process.
        #>
        param([string] $Text)
        ($Text -replace "`r`n", "`n" -replace 'generated by New-(iSOC)?DcrFromSchema(\.ps1)?\.', 'generated by X.').TrimEnd("`n")
    }

    function Get-ComparableTemplate {
        <#
        .SYNOPSIS
            Return each file in a folder as its name followed by its normalised content.
        .PARAMETER Folder
            Folder to read from.
        #>
        param([string] $Folder)
        if (-not (Test-Path -LiteralPath $Folder)) { return @() }
        @(Get-ChildItem -LiteralPath $Folder -File | Sort-Object Name | ForEach-Object { "$($_.Name)`n" + (ConvertTo-ComparableText (Get-Content -LiteralPath $_.FullName -Raw)) })
    }
}

Describe 'The schema helpers' {
    BeforeAll {
        $script:inModule = { param([scriptblock] $Block, [hashtable] $With = @{}) InModuleScope iSOCDeployments -Parameters $With $Block }
        $script:canonical = { param($Value) ConvertTo-Json -InputObject $Value -Depth 30 -Compress }
    }

    It 'reads every shipped example' {
        $expected = [ordered]@{
            'annotated.json'           = '{"TableName":"PaymentAudit_CL",' +
            '"Columns":[{"name":"TimeGenerated","type":"datetime","description":"When the gateway recorded the event."},' +
            '{"name":"TransactionId","type":"guid","description":"Gateway transaction identifier. Declared string in the DCR stream and cast back by the transform, because a stream declaration cannot express guid."},' +
            '{"name":"MerchantName","type":"string","displayName":"Merchant","description":"Trading name of the merchant."},' +
            '{"name":"SourceIp","type":"string","dataTypeHint":"ip","description":"Caller address. The ip hint lets the portal and Sentinel entity mapping treat it as an address rather than text."},' +
            '{"name":"GatewayResourceId","type":"string","dataTypeHint":"armPath","description":"Resource ID of the gateway instance."},' +
            '{"name":"CallbackUrl","type":"string","dataTypeHint":"uri","description":"Merchant callback endpoint."},' +
            '{"name":"AmountMinorUnits","type":"long","description":"Amount in minor units. Integral on purpose: a real would introduce floating-point error into money."},' +
            '{"name":"Succeeded","type":"boolean","description":"Whether the gateway authorised the payment."},' +
            '{"name":"RiskScore","type":"real","description":"Fraud score between 0 and 1."},' +
            '{"name":"GatewayResponse","type":"dynamic","description":"Full gateway response body, kept as an object so it stays queryable."}],' +
            '"Extra":{"description":"Payment gateway audit events, pushed over the Logs Ingestion API.",' +
            '"dcrName":"dcr-payment-audit",' +
            '"plan":"Analytics",' +
            '"retentionInDays":30,' +
            '"totalRetentionInDays":730,' +
            '"transformKql":"source | where isnotempty(TransactionId) | extend TransactionId = toguid(TransactionId)"}}'
            'auxiliary-plan.json'      = '{"TableName":"NetFlowArchive_CL",' +
            '"Columns":[{"name":"TimeGenerated","type":"datetime","description":"Flow timestamp. An Auxiliary table only accepts ISO 8601 with six decimal places, for example 2026-07-30T09:15:22.123456Z."},' +
            '{"name":"SourceIp","type":"string","dataTypeHint":"ip","description":"Flow source address."},' +
            '{"name":"DestinationIp","type":"string","dataTypeHint":"ip","description":"Flow destination address."},' +
            '{"name":"DestinationPort","type":"int","description":"Destination port."},' +
            '{"name":"Protocol","type":"string","description":"Transport protocol."},' +
            '{"name":"BytesSent","type":"long","description":"Bytes sent. Long rather than int, because a flow archive overflows a 32-bit counter."},' +
            '{"name":"BytesReceived","type":"long","description":"Bytes received."},' +
            '{"name":"Action","type":"string","description":"Whether the flow was allowed or denied."}],' +
            '"Extra":{"description":"Verbose network flow records kept for compliance. Auxiliary plan: cheapest ingestion, 30-day fixed interactive retention, low-fidelity query only. TimeGenerated must be sent as ISO 8601 with six decimal places.",' +
            '"dcrName":"dcr-netflow-archive",' +
            '"plan":"Auxiliary",' +
            '"totalRetentionInDays":365}}'
            'basic-plan.json'          = '{"TableName":"AppTrace_CL",' +
            '"Columns":[{"name":"TimeGenerated","type":"datetime","description":"When the application emitted the trace."},' +
            '{"name":"Component","type":"string","description":"Emitting component. Keep the filterable fields as real columns, because Basic tables support a reduced KQL surface."},' +
            '{"name":"Level","type":"string","description":"Trace level, for example Information or Warning."},' +
            '{"name":"CorrelationId","type":"string","description":"Request correlation identifier."},' +
            '{"name":"Message","type":"string","description":"Trace message."},' +
            '{"name":"Properties","type":"dynamic","description":"Structured trace properties."}],' +
            '"Extra":{"description":"High-volume application traces. Basic plan: cheap to ingest, 30-day fixed interactive retention, no alerting.",' +
            '"dcrName":"dcr-app-trace",' +
            '"plan":"Basic",' +
            '"totalRetentionInDays":365}}'
            'minimal.json'             = '{"TableName":"MyApp_CL",' +
            '"Columns":[{"name":"TimeGenerated","type":"datetime"},' +
            '{"name":"Message","type":"string"}],' +
            '"Extra":{}}'
            'threat-intel-alerts.json' = '{"TableName":"ThreatIntelAlert_CL",' +
            '"Columns":[{"name":"TimeGenerated","type":"datetime","description":"When the record was ingested."},' +
            '{"name":"AlertCreated","type":"datetime","description":"When the feed raised the alert. Kept separate from TimeGenerated so feed latency stays measurable."},' +
            '{"name":"AlertId","type":"string","description":"Feed identifier for the alert."},' +
            '{"name":"AlertType","type":"string","description":"Feed classification of the alert."},' +
            '{"name":"AlertName","type":"string","description":"Human-readable alert title."},' +
            '{"name":"AlertQuery","type":"string","description":"Query or rule the feed matched on."},' +
            '{"name":"AlertSource","type":"string","description":"Which feed or collection the alert came from."},' +
            '{"name":"Resource","type":"dynamic","description":"Affected resource, as an object."},' +
            '{"name":"HighlightText","type":"string","description":"Matched excerpt, flattened for full-text search."},' +
            '{"name":"Highlights","type":"dynamic","description":"Matched excerpts with their offsets."},' +
            '{"name":"Tags","type":"dynamic","description":"Feed tags. Dynamic rather than a delimited string, so tags stay individually queryable."},' +
            '{"name":"RawData","type":"dynamic","description":"Full original payload, retained for reprocessing."}],' +
            '"Extra":{"description":"Alerts pushed from a threat intelligence feed over the Logs Ingestion API.",' +
            '"dcrName":"dcr-threat-intel-alert",' +
            '"plan":"Analytics",' +
            '"retentionInDays":90,' +
            '"totalRetentionInDays":365}}'
        }
        foreach ($file in $expected.Keys) {
            $path = Join-Path $script:examples $file
            $new = & $script:inModule { param($P) Mock Write-iSOCLog { }; Import-iSOCTableSpec -Path $P } @{ P = $path }
            (& $script:canonical $new) | Should -BeExactly $expected[$file] -Because $file
        }
    }

    It 'reads and refuses every shape' {
        $cases = @(
            @{ Text = '{ "properties": { "plan": "Basic", "schema": { "name": "T_CL", "description": "d", "columns": [ { "name": "A", "type": "string" } ] } } }'; Expected = '{"TableName":"T_CL","Columns":[{"name":"A","type":"string"}],"Extra":{"description":"d","plan":"Basic"}}' }
            @{ Text = '{ "properties": { "plan": "Basic" } }'; Expected = 'error: Schema file has a ''properties'' block but no ''properties.schema'' (<path>).' }
            @{ Text = '[ { "name": "A", "type": "string" }, { "name": "B" } ]'; Expected = '{"TableName":null,"Columns":[{"name":"A","type":"string"},{"name":"B"}],"Extra":{}}' }
            @{ Text = '{ "name": "Lone", "type": "string" }'; Expected = '{"TableName":null,"Columns":[{"name":"Lone","type":"string"}],"Extra":{}}' }
            @{ Text = '{ "table": "T_CL", "fields": [ { "name": "A" } ], "transformKql": "source", "location": "westeurope" }'; Expected = '{"TableName":"T_CL","Columns":[{"name":"A"}],"Extra":{"location":"westeurope","transformKql":"source"}}' }
            @{ Text = '{ "tableName": "T_CL", "columns": [] }'; Expected = 'error: Schema file declares an empty column list (<path>).' }
            @{ Text = '{ "tableName": "T_CL" }'; Expected = 'error: Schema file has no column list (<path>). Expected { "tableName": "MyTable_CL", "columns": [ { "name": "...", "type": "..." } ] }. This tool takes a schema, not a sample of the data.' }
            @{ Text = ''; Expected = 'error: Schema file is empty: <path>' }
            @{ Text = '{ "tableName": "T_CL", "columns": [ { "name": "A", "type": "string" }, ], }'; Expected = '{"TableName":"T_CL","Columns":[{"name":"A","type":"string"}],"Extra":{}}' }
            @{ Text = "$([char]0xFEFF){ `"tableName`": `"T_CL`", `"columns`": [ { `"name`": `"A`" } ] /* c */ }"; Expected = '{"TableName":"T_CL","Columns":[{"name":"A"}],"Extra":{}}' }
        )
        foreach ($c in $cases) {
            $path = Join-Path $TestDrive "$([guid]::NewGuid().ToString('N')).json"
            [System.IO.File]::WriteAllText($path, $c.Text, [System.Text.UTF8Encoding]::new($false))
            $new = & $script:inModule { param($P) Mock Write-iSOCLog { }; try { ConvertTo-Json -InputObject (Import-iSOCTableSpec -Path $P) -Depth 30 -Compress } catch { "error: $($_.Exception.Message)" } } @{ P = $path }
            $new | Should -BeExactly $c.Expected.Replace('<path>', $path) -Because $c.Text
        }
    }

    It 'repairs text' {
        $q = [char]0x201C
        $cases = @(
            @{ Text = ''; Noise = '{"Text":"","Applied":[]}'; Safe = ''; Straight = '' }
            @{ Text = '{"a": 1}'; Noise = '{"Text":"{\"a\": 1}","Applied":[]}'; Safe = '{"a": 1}'; Straight = '{"a": 1}' }
            @{ Text = "$([char]0xFEFF){`"a`":1}"; Noise = '{"Text":"{\"a\":1}","Applied":["byte order mark"]}'; Safe = '{"a":1}'; Straight = ([string][char]0xFEFF + '{"a":1}') }
            @{ Text = "{ ${q}a$([char]0x201D): 1 }"; Noise = '{"Text":"{ \"a\": 1 }","Applied":["curly quotes or no-break spaces"]}'; Safe = ('{ ' + [string][char]0x201C + 'a' + [string][char]0x201D + ': 1 }'); Straight = '{ "a": 1 }' }
            @{ Text = "{`"u`": `"http://x//y`", // c`n `"b`": [1, 2, ], /* d */ }"; Noise = '{"Text":"{\"u\": \"http://x//y\", \n \"b\": [1, 2 ],  }","Applied":["JSON comments","trailing commas"]}'; Safe = '{"u": "http://x//...'; Straight = ('{"u": "http://x//y", // c' + [string][char]0x000A + ' "b": [1, 2, ], /* d */ }') }
            @{ Text = "{`"s`": `"a \`" , ]`"}"; Noise = '{"Text":"{\"s\": \"a \\\" , ]\"}","Applied":[]}'; Safe = '{"s": "a \" , ]"}'; Straight = '{"s": "a \" , ]"}' }
            @{ Text = "$([char]0x00A0)[1,]"; Noise = ('{"Text":"' + [string][char]0x00A0 + '[1]","Applied":["trailing commas"]}'); Safe = '[1,]'; Straight = ' [1,]' }
        )
        foreach ($c in $cases) {
            (& $script:canonical (& $script:inModule { param($T) Repair-iSOCJsonText -Text $T } @{ T = $c.Text })) | Should -BeExactly $c.Noise
            (& $script:inModule { param($T) ConvertTo-iSOCSafeText -Text $T -MaxLength 20 } @{ T = $c.Text }) | Should -BeExactly $c.Safe
            (& $script:inModule { param($T) ConvertTo-iSOCStraightPunctuation -Text $T } @{ T = $c.Text }) | Should -BeExactly $c.Straight
        }
        (& $script:inModule { ConvertTo-iSOCSafeText -Text "a`n`tb$([char]0x200B)c    d" }) | Should -BeExactly 'a b c d'
        (& $script:inModule { ConvertTo-iSOCSafeText -Text $null }) | Should -BeExactly ''
    }

    It 'names types, tables and column issues' {
        $types = [ordered]@{ 'STRING' = 'string'; ' bool ' = 'boolean'; 'integer' = 'int'; 'int64' = 'long'; 'double' = 'real'; 'timestamp' = 'dateTime'; 'uuid' = 'guid'; 'array' = 'dynamic'; 'text' = $null; '' = $null }
        foreach ($type in $types.Keys) {
            (& $script:inModule { param($T) Get-iSOCTableColumnType -DeclaredType $T } @{ T = $type }) | Should -Be $types[$type] -Because "type '$type'"
        }
        (& $script:inModule { Get-iSOCTableColumnType -DeclaredType $null }) | Should -BeNullOrEmpty
        $names = @(
            @{ Name = 'MyApp_CL'; Problems = @() }
            @{ Name = 'MyApp'; Problems = @('''MyApp'' does not end with ''_CL'', which every custom log table name must') }
            @{ Name = '9app_CL'; Problems = @('''9app_CL'' must start with a letter and contain only letters, digits and underscores, so KQL can reference it unquoted') }
            @{ Name = 'a-b_CL'; Problems = @('''a-b_CL'' must start with a letter and contain only letters, digits and underscores, so KQL can reference it unquoted') }
            @{ Name = 'A_CL'; Problems = @() }
            @{ Name = ('A' * 61); Problems = @('''<long>'' does not end with ''_CL'', which every custom log table name must') }
            @{ Name = '_CL'; Problems = @('''_CL'' must start with a letter and contain only letters, digits and underscores, so KQL can reference it unquoted', '''_CL'' is 3 characters; the minimum is 4') }
            @{ Name = ''; Problems = @('the table name is empty') }
        )
        foreach ($n in $names) {
            $problems = @($n.Problems | ForEach-Object { $_.Replace('<long>', ('A' * 61)) })
            @(& $script:inModule { param($N) Get-iSOCTableNameProblem -Name $N } @{ N = $n.Name }) | Should -BeExactly $problems -Because "table '$($n.Name)'"
        }
        $cases = @(
            @{ Column = @('Message_s', 'string', ''); Expected = '[{"Severity":"Warning","Message":"''_s'' is a classic Custom Log Wizard type suffix; a DCR-based table carries real types and does not need it"}]' }
            @{ Column = @('TenantId', 'string', ''); Expected = '[{"Severity":"Error","Message":"''TenantId'' conflicts with a system or reserved column name"}]' }
            @{ Column = @('tenantid', 'bool', 'ip'); Expected = '[{"Severity":"Error","Message":"''tenantid'' conflicts with a system or reserved column name"}]' }
            @{ Column = @('9x', 'text', 'ipv4'); Expected = '[{"Severity":"Error","Message":"must start with an ASCII letter and then contain only letters, digits and underscores"},{"Severity":"Error","Message":"type ''text'' is not a Log Analytics column type. Use one of: boolean, dateTime, dynamic, guid, int, long, real, string"},{"Severity":"Error","Message":"dataTypeHint ''ipv4'' is not valid. Use one of: armPath, guid, ip, uri"}]' }
            @{ Column = @('a', 'string', ''); Expected = '[{"Severity":"Error","Message":"is 1 character; column names must be 2 to 45 characters"}]' }
            @{ Column = @(('A' * 46), 'guid', 'armPath'); Expected = '[{"Severity":"Error","Message":"is 46 characters; the limit is 45"}]' }
            @{ Column = @('', '', ''); Expected = '[{"Severity":"Error","Message":"the column name is empty"},{"Severity":"Error","Message":"type ''(none)'' is not a Log Analytics column type. Use one of: boolean, dateTime, dynamic, guid, int, long, real, string"}]' }
            @{ Column = @('Fine', 'dynamic', 'uri'); Expected = '[]' }
        )
        foreach ($c in $cases) {
            $new = @(& $script:inModule { param($C) Get-iSOCColumnIssue -Name $C[0] -DeclaredType $C[1] -DataTypeHint $C[2] } @{ C = $c.Column })
            (& $script:canonical $new) | Should -BeExactly $c.Expected -Because "column '$($c.Column[0])'"
        }
    }

    It 'resolves and repairs a schema' {
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
        $display = ('D' * 125) + '...'
        $new = & $script:inModule { param($C) Resolve-iSOCTableSchema -Column $C } @{ C = $columns }
        $expected = '{"Columns":[{"Name":"Alert",' +
        '"Type":"string",' +
        '"DeclaredType":"string",' +
        '"Description":"two lines",' +
        '"DisplayName":"",' +
        '"DataTypeHint":"",' +
        '"Issues":[{"Severity":"Error","Message":"must start with an ASCII letter and then contain only letters, digits and underscores"}]},' +
        '{"Name":"alert",' +
        '"Type":"boolean",' +
        '"DeclaredType":"bool",' +
        '"Description":"",' +
        '"DisplayName":"",' +
        '"DataTypeHint":"",' +
        '"Issues":[]},' +
        '{"Name":"Dup",' +
        '"Type":"int",' +
        '"DeclaredType":"integer",' +
        '"Description":"",' +
        '"DisplayName":"",' +
        '"DataTypeHint":"",' +
        '"Issues":[]},' +
        '{"Name":"Dup",' +
        '"Type":"long",' +
        '"DeclaredType":"long",' +
        '"Description":"",' +
        '"DisplayName":"",' +
        '"DataTypeHint":"",' +
        '"Issues":[]},' +
        '{"Name":"9Bad",' +
        '"Type":"string",' +
        '"DeclaredType":"string",' +
        '"Description":"",' +
        '"DisplayName":"",' +
        '"DataTypeHint":"",' +
        '"Issues":[{"Severity":"Error","Message":"must start with an ASCII letter and then contain only letters, digits and underscores"}]},' +
        '{"Name":"Src",' +
        '"Type":"string",' +
        '"DeclaredType":"string",' +
        '"Description":"",' +
        '"DisplayName":"<display>",' +
        '"DataTypeHint":"ipv4",' +
        '"Issues":[{"Severity":"Error","Message":"dataTypeHint ''ipv4'' is not valid. Use one of: armPath, guid, ip, uri"}]},' +
        '{"Name":"TimeGenerated",' +
        '"Type":"string",' +
        '"DeclaredType":"string",' +
        '"Description":"",' +
        '"DisplayName":"",' +
        '"DataTypeHint":"",' +
        '"Issues":[]},' +
        '{"Name":"Sketch",' +
        '"Type":"hyperloglog",' +
        '"DeclaredType":"hyperloglog",' +
        '"Description":"",' +
        '"DisplayName":"",' +
        '"DataTypeHint":"",' +
        '"Issues":[{"Severity":"Error","Message":"type ''hyperloglog'' is not a Log Analytics column type. Use one of: boolean, dateTime, dynamic, guid, int, long, real, string"}]}],' +
        '"SchemaIssues":[{"Severity":"Error",' +
        '"Message":"duplicate column name ''Dup'' appears 2 times."},' +
        '{"Severity":"Warning",' +
        '"Message":"column names differ only by case: alert, Alert. Analytics and Basic tables treat these as separate columns; an Auxiliary table drops rows because of them.",' +
        '"Kind":"CaseCollision"},' +
        '{"Severity":"Error",' +
        '"Message":"TimeGenerated is declared ''string''. It must be datetime.",' +
        '"Fix":"FixTimeGeneratedType"}]}'
        (& $script:canonical $new) | Should -BeExactly $expected.Replace('<display>', $display)

        $newRepaired = @(& $script:inModule { param($C) Mock Write-iSOCLog { }; Repair-iSOCTableSchema -Column (Resolve-iSOCTableSchema -Column $C).Columns.ToArray() } @{ C = $columns })
        $expectedRepaired = '[{"Name":"alert",' +
        '"Type":"boolean",' +
        '"DeclaredType":"bool",' +
        '"Description":"",' +
        '"DisplayName":"",' +
        '"DataTypeHint":"",' +
        '"Issues":[]},' +
        '{"Name":"Dup",' +
        '"Type":"int",' +
        '"DeclaredType":"integer",' +
        '"Description":"",' +
        '"DisplayName":"",' +
        '"DataTypeHint":"",' +
        '"Issues":[]},' +
        '{"Name":"Src",' +
        '"Type":"string",' +
        '"DeclaredType":"string",' +
        '"Description":"",' +
        '"DisplayName":"<display>",' +
        '"DataTypeHint":"",' +
        '"Issues":[{"Severity":"Error","Message":"dataTypeHint ''ipv4'' is not valid. Use one of: armPath, guid, ip, uri"}]},' +
        '{"Name":"TimeGenerated",' +
        '"Type":"dateTime",' +
        '"DeclaredType":"datetime",' +
        '"Description":"",' +
        '"DisplayName":"",' +
        '"DataTypeHint":"",' +
        '"Issues":[]},' +
        '{"Name":"Sketch",' +
        '"Type":"hyperloglog",' +
        '"DeclaredType":"hyperloglog",' +
        '"Description":"",' +
        '"DisplayName":"",' +
        '"DataTypeHint":"",' +
        '"Issues":[{"Severity":"Error","Message":"type ''hyperloglog'' is not a Log Analytics column type. Use one of: boolean, dateTime, dynamic, guid, int, long, real, string"}]}]'
        (& $script:canonical $newRepaired) | Should -BeExactly $expectedRepaired.Replace('<display>', $display)

        $noTime = @([pscustomobject]@{ name = 'A'; type = 'string' })
        $newAdded = @(& $script:inModule { param($C) Mock Write-iSOCLog { }; Invoke-iSOCSchemaRepair -Column (Resolve-iSOCTableSchema -Column $C).Columns.ToArray() } @{ C = $noTime })
        (& $script:canonical $newAdded) | Should -BeExactly '[{"Name":"TimeGenerated","Type":"dateTime","DeclaredType":"dateTime","Description":"","DisplayName":"","DataTypeHint":"","Issues":[]}]'

        $newError = & $script:inModule { param($C) Mock Write-iSOCLog { }; try { Invoke-iSOCSchemaRepair -Column (Resolve-iSOCTableSchema -Column $C).Columns.ToArray() } catch { $_.Exception.Message } } @{ C = $columns }
        $newError | Should -BeExactly 'Schema cannot be used and non-interactive mode cannot ask: Sketch: type ''hyperloglog'' is not a Log Analytics column type. Use one of: boolean, dateTime, dynamic, guid, int, long, real, string'
        $newError | Should -Match 'Sketch'
    }

    It 'builds streams, transforms and diffs' {
        $columns = @(
            [pscustomobject]@{ Name = 'TimeGenerated'; Type = 'dateTime'; DataTypeHint = ''; Description = ''; DisplayName = '' }
            [pscustomobject]@{ Name = 'EventId'; Type = 'guid'; DataTypeHint = 'guid'; Description = 'An id.'; DisplayName = 'Event' }
            [pscustomobject]@{ Name = 'Case'; Type = 'string'; DataTypeHint = ''; Description = ''; DisplayName = '' }
            [pscustomobject]@{ Name = 'case'; Type = 'guid'; DataTypeHint = ''; Description = ''; DisplayName = '' }
            [pscustomobject]@{ Name = 'Count'; Type = 'long'; DataTypeHint = ''; Description = ''; DisplayName = '' }
        )
        $newStream = @(& $script:inModule { param($C) ConvertTo-iSOCSchemaStreamColumn -Column $C } @{ C = $columns })
        (& $script:canonical $newStream) | Should -BeExactly '[{"name":"TimeGenerated","type":"datetime"},{"name":"EventId","type":"string"},{"name":"Case","type":"string"},{"name":"case","type":"string"},{"name":"Count","type":"long"}]'
        (& $script:inModule { param($C, $S) Get-iSOCSchemaTransform -Column $C -StreamColumn $S } @{ C = $columns; S = $newStream }) | Should -BeExactly 'source | extend EventId = toguid(EventId), case = toguid(case)'
        (& $script:inModule { param($C, $S) Get-iSOCSchemaTransform -Column $C -StreamColumn $S } @{ C = @($columns[0]); S = @($newStream[0]) }) | Should -BeExactly 'source'

        $live = @([pscustomobject]@{ name = 'Count'; type = 'int' }, [pscustomobject]@{ name = 'case'; type = 'string' }, [pscustomobject]@{ name = 'Extra'; type = 'string' }, [pscustomobject]@{ name = '_Sys'; type = 'string' }, [pscustomobject]@{ name = 'TimeGenerated' })
        $newDiff = & $script:inModule { param($C, $L) Compare-iSOCTableSchema -DesiredColumn $C -ExistingColumn $L } @{ C = $columns; L = $live }
        (& $script:canonical $newDiff) | Should -BeExactly '{"Added":["EventId","Case"],"Conflicts":["TimeGenerated: live table has ''string'', the schema says ''dateTime''","case: live table has ''string'', the schema says ''guid''","Count: live table has ''int'', the schema says ''long''"],"OnlyLive":["Extra"]}'

        $transforms = @(
            @{ Text = 'source'; Expected = '{"Text":"source","Applied":[]}' }
            @{ Text = "source | where A == $([char]0x2018)x$([char]0x2019)"; Expected = '{"Text":"source | where A == ''x''","Applied":["curly quotes or no-break spaces"]}' }
            @{ Text = ('x' * 15361); Expected = 'The transform is 15361 characters; a data collection rule allows 15360. Move the logic into a workspace function, or trim it.' }
        )
        foreach ($t in $transforms) {
            $new = & $script:inModule { param($T) try { ConvertTo-Json -InputObject (Repair-iSOCTransformKql -Transform $T) -Depth 5 -Compress } catch { $_.Exception.Message } } @{ T = $t.Text }
            $new | Should -BeExactly $t.Expected
        }
    }

    It 'builds the templates' {
        $columns = @(
            [pscustomobject]@{ Name = 'TimeGenerated'; Type = 'dateTime'; DataTypeHint = ''; Description = 'When.'; DisplayName = '' }
            [pscustomobject]@{ Name = 'Src'; Type = 'string'; DataTypeHint = 'ip'; Description = ''; DisplayName = 'Source' }
        )
        $tables = @(
            @{ Plan = 'Analytics'; Retention = 90; Total = 365; Hint = $false; Description = 'A table.'
                Expected = '{"$schema":"https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",' +
                '"contentVersion":"1.0.0.0",' +
                '"metadata":{"description":"Custom log table T_CL, generated by New-iSOCDcrFromSchema."},' +
                '"resources":[{"type":"Microsoft.OperationalInsights/workspaces/tables",' +
                '"apiVersion":"2025-07-01",' +
                '"name":"law/T_CL",' +
                '"properties":{"schema":{"name":"T_CL","columns":[{"name":"TimeGenerated","type":"dateTime","description":"When."},{"name":"Src","type":"string","displayName":"Source"}],"description":"A table."},"plan":"Analytics","retentionInDays":90,"totalRetentionInDays":365}}]}'
            }
            @{ Plan = 'Basic'; Retention = 30; Total = -1; Hint = $true; Description = ''
                Expected = '{"$schema":"https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",' +
                '"contentVersion":"1.0.0.0",' +
                '"metadata":{"description":"Custom log table T_CL, generated by New-iSOCDcrFromSchema."},' +
                '"resources":[{"type":"Microsoft.OperationalInsights/workspaces/tables",' +
                '"apiVersion":"2025-07-01",' +
                '"name":"law/T_CL",' +
                '"properties":{"schema":{"name":"T_CL","columns":[{"name":"TimeGenerated","type":"dateTime","description":"When."},{"name":"Src","type":"string","dataTypeHint":"ip","displayName":"Source"}]},"plan":"Basic","totalRetentionInDays":-1}}]}'
            }
            @{ Plan = ''; Retention = 0; Total = 0; Hint = $false; Description = 'x'
                Expected = '{"$schema":"https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",' +
                '"contentVersion":"1.0.0.0",' +
                '"metadata":{"description":"Custom log table T_CL, generated by New-iSOCDcrFromSchema."},' +
                '"resources":[{"type":"Microsoft.OperationalInsights/workspaces/tables",' +
                '"apiVersion":"2025-07-01",' +
                '"name":"law/T_CL",' +
                '"properties":{"schema":{"name":"T_CL","columns":[{"name":"TimeGenerated","type":"dateTime","description":"When."},{"name":"Src","type":"string","displayName":"Source"}],"description":"x"}}}]}'
            }
        )
        foreach ($c in $tables) {
            $new = & $script:inModule { param($C, $Cols) Mock Write-iSOCLog { }; ConvertTo-iSOCTableArmTemplate -WorkspaceName law -Table T_CL -Column $Cols -Plan $C.Plan -Retention $C.Retention -TotalRetention $C.Total -TableDescription $C.Description -IncludeDataTypeHint:$C.Hint } @{ C = $c; Cols = $columns }
            (ConvertTo-Json -InputObject $new -Depth 30 -Compress) | Should -BeExactly $c.Expected -Because "a '$($c.Plan)' table"
        }

        $stream = @([pscustomobject]@{ name = 'TimeGenerated'; type = 'datetime' }, [pscustomobject]@{ name = 'Src'; type = 'string' })
        $endpoint = '/subscriptions/x/resourceGroups/y/providers/Microsoft.Insights/dataCollectionEndpoints/z'
        $rules = @(
            @{ Description = 'A rule.'; Endpoint = ''
                Expected = '{"$schema":"https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",' +
                '"contentVersion":"1.0.0.0",' +
                '"metadata":{"description":"Data collection rule for Custom-T_CL, generated by New-iSOCDcrFromSchema."},' +
                '"resources":[{"type":"Microsoft.Insights/dataCollectionRules",' +
                '"apiVersion":"2023-03-11",' +
                '"name":"dcr-t",' +
                '"location":"uksouth",' +
                '"kind":"Direct",' +
                '"properties":{"description":"A rule.","streamDeclarations":{"Custom-T_CL":{"columns":[{"name":"TimeGenerated","type":"datetime"},{"name":"Src","type":"string"}]}},"destinations":{"logAnalytics":[{"workspaceResourceId":"/ws","name":"workspaceDestination"}]},"dataFlows":[{"streams":["Custom-T_CL"],"destinations":["workspaceDestination"],"transformKql":"source","outputStream":"Custom-T_CL"}]}}]}'
            }
            @{ Description = 'A rule.'; Endpoint = $endpoint
                Expected = '{"$schema":"https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",' +
                '"contentVersion":"1.0.0.0",' +
                '"metadata":{"description":"Data collection rule for Custom-T_CL, generated by New-iSOCDcrFromSchema."},' +
                '"resources":[{"type":"Microsoft.Insights/dataCollectionRules",' +
                '"apiVersion":"2023-03-11",' +
                '"name":"dcr-t",' +
                '"location":"uksouth",' +
                '"kind":"Direct",' +
                '"properties":{"description":"A rule.","dataCollectionEndpointId":"/subscriptions/x/resourceGroups/y/providers/Microsoft.Insights/dataCollectionEndpoints/z","streamDeclarations":{"Custom-T_CL":{"columns":[{"name":"TimeGenerated","type":"datetime"},{"name":"Src","type":"string"}]}},"destinations":{"logAnalytics":[{"workspaceResourceId":"/ws","name":"workspaceDestination"}]},"dataFlows":[{"streams":["Custom-T_CL"],"destinations":["workspaceDestination"],"transformKql":"source","outputStream":"Custom-T_CL"}]}}]}'
            }
            @{ Description = ('Long ' * 80); Endpoint = ''
                Expected = '{"$schema":"https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",' +
                '"contentVersion":"1.0.0.0",' +
                '"metadata":{"description":"Data collection rule for Custom-T_CL, generated by New-iSOCDcrFromSchema."},' +
                '"resources":[{"type":"Microsoft.Insights/dataCollectionRules",' +
                '"apiVersion":"2023-03-11",' +
                '"name":"dcr-t",' +
                '"location":"uksouth",' +
                '"kind":"Direct",' +
                '"properties":{"description":"Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Lon...","streamDeclarations":{"Custom-T_CL":{"columns":[{"name":"TimeGenerated","type":"datetime"},{"name":"Src","type":"string"}]}},"destinations":{"logAnalytics":[{"workspaceResourceId":"/ws","name":"workspaceDestination"}]},"dataFlows":[{"streams":["Custom-T_CL"],"destinations":["workspaceDestination"],"transformKql":"source","outputStream":"Custom-T_CL"}]}}]}'
            }
            @{ Description = ('Long ' * 80); Endpoint = $endpoint
                Expected = '{"$schema":"https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",' +
                '"contentVersion":"1.0.0.0",' +
                '"metadata":{"description":"Data collection rule for Custom-T_CL, generated by New-iSOCDcrFromSchema."},' +
                '"resources":[{"type":"Microsoft.Insights/dataCollectionRules",' +
                '"apiVersion":"2023-03-11",' +
                '"name":"dcr-t",' +
                '"location":"uksouth",' +
                '"kind":"Direct",' +
                '"properties":{"description":"Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Long Lon...","dataCollectionEndpointId":"/subscriptions/x/resourceGroups/y/providers/Microsoft.Insights/dataCollectionEndpoints/z","streamDeclarations":{"Custom-T_CL":{"columns":[{"name":"TimeGenerated","type":"datetime"},{"name":"Src","type":"string"}]}},"destinations":{"logAnalytics":[{"workspaceResourceId":"/ws","name":"workspaceDestination"}]},"dataFlows":[{"streams":["Custom-T_CL"],"destinations":["workspaceDestination"],"transformKql":"source","outputStream":"Custom-T_CL"}]}}]}'
            }
            @{ Description = ''; Endpoint = ''
                Expected = '{"$schema":"https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",' +
                '"contentVersion":"1.0.0.0",' +
                '"metadata":{"description":"Data collection rule for Custom-T_CL, generated by New-iSOCDcrFromSchema."},' +
                '"resources":[{"type":"Microsoft.Insights/dataCollectionRules",' +
                '"apiVersion":"2023-03-11",' +
                '"name":"dcr-t",' +
                '"location":"uksouth",' +
                '"kind":"Direct",' +
                '"properties":{"streamDeclarations":{"Custom-T_CL":{"columns":[{"name":"TimeGenerated","type":"datetime"},{"name":"Src","type":"string"}]}},"destinations":{"logAnalytics":[{"workspaceResourceId":"/ws","name":"workspaceDestination"}]},"dataFlows":[{"streams":["Custom-T_CL"],"destinations":["workspaceDestination"],"transformKql":"source","outputStream":"Custom-T_CL"}]}}]}'
            }
            @{ Description = ''; Endpoint = $endpoint
                Expected = '{"$schema":"https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",' +
                '"contentVersion":"1.0.0.0",' +
                '"metadata":{"description":"Data collection rule for Custom-T_CL, generated by New-iSOCDcrFromSchema."},' +
                '"resources":[{"type":"Microsoft.Insights/dataCollectionRules",' +
                '"apiVersion":"2023-03-11",' +
                '"name":"dcr-t",' +
                '"location":"uksouth",' +
                '"kind":"Direct",' +
                '"properties":{"dataCollectionEndpointId":"/subscriptions/x/resourceGroups/y/providers/Microsoft.Insights/dataCollectionEndpoints/z","streamDeclarations":{"Custom-T_CL":{"columns":[{"name":"TimeGenerated","type":"datetime"},{"name":"Src","type":"string"}]}},"destinations":{"logAnalytics":[{"workspaceResourceId":"/ws","name":"workspaceDestination"}]},"dataFlows":[{"streams":["Custom-T_CL"],"destinations":["workspaceDestination"],"transformKql":"source","outputStream":"Custom-T_CL"}]}}]}'
            }
        )
        foreach ($r in $rules) {
            $new = & $script:inModule { param($D, $E, $S) $clean = ConvertTo-iSOCSafeText -Text $D -MaxLength 256; ConvertTo-iSOCDcrArmTemplate -Name dcr-t -Region uksouth -Kind Direct -Stream Custom-T_CL -StreamColumn $S -WorkspaceResourceId /ws -OutputStream Custom-T_CL -Transform source -EndpointResourceId $E -Description $clean -GeneratedBy 'New-iSOCDcrFromSchema' } @{ D = $r.Description; E = $r.Endpoint; S = $stream }
            (ConvertTo-Json -InputObject $new -Depth 30 -Compress) | Should -BeExactly $r.Expected -Because "description '$($r.Description)', endpoint '$($r.Endpoint)'"
        }
    }

    It 'flattens deployment errors' {
        $list = [System.Collections.Generic.List[object]]::new()
        $list.Add([pscustomobject]@{ Code = 'A'; Message = 'outer'; Target = 'T'; Details = @([pscustomobject]@{ code = 'B'; message = 'inner'; details = @([pscustomobject]@{ Code = 'C'; Message = 'deepest' }) }) })
        $list.Add([pscustomobject]@{ Code = 'D'; Message = 'second'; InnerError = 'as text' })
        $cases = @('plain text', [pscustomobject]@{ Foo = 1 }, [pscustomobject]@{ Message = 'only a message'; AdditionalInfo = @([pscustomobject]@{ Code = 'E'; Message = 'info' }) }, $null)
        $expected = @('plain text', 'unrecognised error shape (PSCustomObject): {"Foo":1}', 'only a message -> [E] info', '', '[A] (T) outer -> [B] inner -> [C] deepest | [D] second -> as text')
        $all = @($cases) + @(, $list)
        $all.Count | Should -Be $expected.Count
        for ($i = 0; $i -lt $all.Count; $i++) {
            (& $script:inModule { param($E) Format-iSOCDeploymentError -ErrorObject $E } @{ E = $all[$i] }) | Should -BeExactly $expected[$i]
        }
    }
}

Describe 'Refusing: <Label>' -ForEach $script:refusals {
    It 'refuses with its message and writes nothing' {
        $path = Get-SchemaPath -Example $Example -Schema $Schema
        $module = Invoke-ModuleDcr -SchemaPath $path -Parameters $Parameters
        if ($Message) { $module.Error | Should -BeExactly $Message.Replace('<path>', $path) }
        else { $module.Error | Should -BeLike $Like.Replace('<path>', $path) }
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
        } finally { Pop-Location }
    }
}
