#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Unit tests for the helper functions in
    Tools/ClassicToDcr/Invoke-ClassicTableMigration.ps1.

.DESCRIPTION
    Covers the two pure functions the script's correctness rests on:

      Get-DcrColumnType    Tables API column type -> DCR stream type.
      ConvertTo-StreamColumn  Table schema -> stream declaration columns,
                              with reserved, system and hidden columns
                              removed and TimeGenerated guaranteed.
      Build-DcrArmTemplate    The emitted ARM template shape.

    Deliberately not covered: the migration call itself
    (Invoke-AzOperationalInsightsMigrateTable), the ARM reads, and the
    deployment. Those need a live workspace and a table that can only be
    migrated once, so they are not unit-testable. The script gates all
    three behind ShouldProcess for that reason.
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Tools/ClassicToDcr/Invoke-ClassicTableMigration.ps1'

    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop

    # Script-scoped constants the extracted functions reference. The AST
    # extractor deliberately skips top-level statements, so the caller
    # restates them (documented pattern in Import-ScriptFunctions.psm1).
    $script:DcrApiVersion = '2023-03-11'

    $script:ReservedColumns = @(
        'TenantId'
        'Type'
        'UniqueId'
        'Title'
        'id'
        'MG'
        'ManagementGroupName'
        'SourceSystem'
    )

    $script:ColumnTypeMap = @{
        'string'   = 'string'
        'int'      = 'int'
        'long'     = 'long'
        'real'     = 'real'
        'boolean'  = 'boolean'
        'bool'     = 'boolean'
        'datetime' = 'datetime'
        'dynamic'  = 'dynamic'
        'guid'     = 'string'
    }

    Import-ScriptFunctions -Path $scriptPath
}

Describe 'Invoke-ClassicTableMigration: script-level contract' {
    BeforeAll {
        $script:sourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools/ClassicToDcr/Invoke-ClassicTableMigration.ps1'
        $script:sourceText = Get-Content -Path $script:sourcePath -Raw
    }

    It 'parses cleanly' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $script:sourcePath, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'gates the irreversible migration behind ShouldProcess' {
        $script:sourceText | Should -Match 'SupportsShouldProcess'
        $script:sourceText | Should -Match 'Invoke-AzOperationalInsightsMigrateTable'
    }

    It 'adds a ShouldContinue gate on the migration' {
        # ShouldProcess alone only honours -WhatIf. The extra ShouldContinue
        # is what makes the irreversible step prompt on its own.
        $script:sourceText | Should -Match 'ShouldContinue'
    }

    It 'does not raise ConfirmImpact for the whole script' {
        # ConfirmImpact = 'High' would prompt on every ShouldProcess call,
        # including the harmless template write, and would throw outright
        # under -NonInteractive. The migration is gated individually instead.
        $script:sourceText | Should -Not -Match "ConfirmImpact\s*=\s*'High'"
    }

    It 'exposes -SkipTableMigration and -Force' {
        $params = (Get-Command $script:sourcePath).Parameters
        $params.Keys | Should -Contain 'SkipTableMigration'
        $params.Keys | Should -Contain 'Force'
    }

    It 'short-circuits the migration block when -SkipTableMigration is set' {
        # Inside the per-table loop the skip branch must be evaluated before
        # anything can call the migration helper, so a skipped run never
        # reaches ShouldContinue.
        $skipIndex    = $script:sourceText.IndexOf('if ($SkipTableMigration)')
        $migrateIndex = $script:sourceText.IndexOf('$migrated = Invoke-ClassicTableMigration')

        $skipIndex    | Should -BeGreaterThan 0
        $migrateIndex | Should -BeGreaterThan 0
        $skipIndex    | Should -BeLessThan $migrateIndex
    }

    It 'authors the DCR at an API version that carries the endpoints property' {
        # 'endpoints' (which exposes logsIngestion on a Direct DCR) was added
        # to DataCollectionRuleResourceProperties in 2023-03-11. Authoring at
        # anything older produces a DCR with no built-in ingestion endpoint,
        # which then needs a Data Collection Endpoint and cannot be retrofitted.
        $script:sourceText | Should -Match "DcrApiVersion\s*=\s*'(\d{4})-(\d{2})-(\d{2})'"

        $matched = [regex]::Match($script:sourceText, "DcrApiVersion\s*=\s*'(?<v>\d{4}-\d{2}-\d{2})'")
        $matched.Success | Should -BeTrue
        ([datetime]$matched.Groups['v'].Value) |
            Should -BeGreaterOrEqual ([datetime]'2023-03-11')
    }

    It 'refuses to deploy against a table that is still Classic' {
        # ARM returns InvalidOutputTable, which reads like a template fault.
        # The script must pre-empt that with the real cause.
        $script:sourceText | Should -Match 'Cannot deploy:.*still'
        $script:sourceText | Should -Match 'DataCollectionRuleBased'
    }

    It 'excludes non-custom tables that merely report Classic' {
        # tableSubType Classic also covers platform tables like
        # AzureDiagnostics when Custom Fields were created against them.
        # Migrating those would be wrong, so the _CL suffix is the gate.
        $script:sourceText | Should -Match "notlike '\*_CL'"
    }

    It 'judges emptiness by actual rows, not by billable GB' {
        # A table with live data reports 0 GB in Usage for hours (billing
        # lag), so the empty decision must key on a direct row count. Keying
        # it on GB90d would brand a populated table abandoned.
        $script:sourceText | Should -Match 'function Get-TableRowCount'
        $script:sourceText | Should -Match '\$_\.RowCount -eq 0'
        # The empty-table filter must not be driven by GB90d any more.
        $script:sourceText | Should -Not -Match '\$_\.GB90d -le 0'
    }

    It 'treats an unknown row count as not-empty, not empty' {
        # RowCount -eq $null means the count query could not run. The empty
        # filter uses -eq 0, so $null does not match and the table is not
        # skipped as empty.
        $script:sourceText | Should -Match '\$_\.RowCount -eq 0 -and -not \$_\.Error'
    }

    It 'uses no em-dashes in prose' {
        $script:sourceText | Should -Not -Match ([char]0x2014)
    }

    It 'has the correct repo-relative header path' {
        $script:sourceText | Should -Match 'Sentinel-As-Code/Tools/ClassicToDcr/Invoke-ClassicTableMigration\.ps1'
    }

    It 'is standalone: does not import the Sentinel.Common module' {
        # The ClassicToDcr kit must run on a jump box where the repo module
        # is absent. It defines its own Write-PipelineMessage instead.
        $script:sourceText | Should -Not -Match 'Import-Module[^\r\n]*Sentinel\.Common'
        $script:sourceText | Should -Not -Match 'Sentinel\.Common\.psd1'
        $script:sourceText | Should -Match 'function Write-PipelineMessage'
    }

    It 'exposes -GrantIngestionRoleTo and grants only the ingestion role' {
        $params = (Get-Command $script:sourcePath).Parameters
        $params.Keys | Should -Contain 'GrantIngestionRoleTo'
        # It grants Monitoring Metrics Publisher, scoped to the DCR, gated by
        # ShouldProcess, and only when a grant identity was supplied.
        $script:sourceText | Should -Match "Monitoring Metrics Publisher"
        $script:sourceText | Should -Match 'if \(\$GrantIngestionRoleTo\)'
        $script:sourceText | Should -Match "ShouldProcess\([^)]*Grant"
        $script:sourceText | Should -Match 'New-AzRoleAssignment -ObjectId \$objectId'
    }

    It 'does not send any test data itself (POST stays in the test tool)' {
        # The production migration tool must never inject rows into a real
        # table. No ingestion POST or synthetic record generation here.
        $script:sourceText | Should -Not -Match 'streams/Custom-.*api-version=2023-01-01.*Invoke'
        $script:sourceText | Should -Not -Match 'Invoke-RestMethod'
        $script:sourceText | Should -Not -Match 'Invoke-WebRequest'
    }

    It 'grants only inside the deploy path' {
        # The grant needs a deployed DCR; it must sit after the deploy, not
        # run when -Deploy is absent.
        $deployIdx = $script:sourceText.IndexOf("ShouldProcess(`"`$DcrResourceGroupName/`$dcrName`", 'Deploy data collection rule')")
        $grantIdx  = $script:sourceText.IndexOf('if ($GrantIngestionRoleTo)')
        $deployIdx | Should -BeGreaterThan 0
        $grantIdx  | Should -BeGreaterThan $deployIdx
    }

    It 'does not unwrap a .Context property from Set-AzContext' {
        # Set-AzContext returns PSAzureContext directly. Only the
        # PSAzureProfile from Connect-AzAccount has .Context, so unwrapping
        # here yields $null and throws on the next property access.
        $script:sourceText | Should -Not -Match 'Set-AzContext[^\r\n]*\)\.Context'
    }
}

Describe 'Invoke-ArmRequest: relative vs absolute routing' {
    BeforeAll {
        # Stand in for the real cmdlet, reproducing its two parameter sets
        # and its refusal to accept a relative -Uri. The stub must mirror the
        # real signature, so some parameters are declared without being read.
        function Invoke-AzRestMethod {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
                Justification = 'Test double mirroring the real cmdlet signature.')]
            [CmdletBinding(DefaultParameterSetName = 'ByPath')]
            param(
                [Parameter(ParameterSetName = 'ByPath', Mandatory)] [string] $Path,
                [Parameter(ParameterSetName = 'ByURI',  Mandatory)] [string] $Uri,
                [string] $Method
            )

            if ($PSCmdlet.ParameterSetName -eq 'ByURI' -and
                -not [System.Uri]::IsWellFormedUriString($Uri, [System.UriKind]::Absolute)) {
                throw 'This operation is not supported for a relative URI.'
            }

            $script:usedParameterSet = $PSCmdlet.ParameterSetName
            [pscustomobject] @{ StatusCode = 200; Content = '{}' }
        }

        $script:subId = '00000000-0000-0000-0000-000000000000'
    }

    It 'routes an ARM-relative table path to -Path' {
        $script:usedParameterSet = $null
        $uri = "/subscriptions/$script:subId/resourceGroups/rg/providers" +
               '/Microsoft.OperationalInsights/workspaces/law/tables/MyApp_CL?api-version=2023-09-01'

        { Invoke-ArmRequest -Uri $uri -SuccessCodes @(200) } | Should -Not -Throw
        $script:usedParameterSet | Should -Be 'ByPath'
    }

    It 'routes an ARM-relative DCR path to -Path' {
        $script:usedParameterSet = $null
        $uri = "/subscriptions/$script:subId/resourceGroups/rg/providers" +
               '/Microsoft.Insights/dataCollectionRules/dcr-myapp?api-version=2024-03-11'

        { Invoke-ArmRequest -Uri $uri -SuccessCodes @(200) } | Should -Not -Throw
        $script:usedParameterSet | Should -Be 'ByPath'
    }

    It 'routes a fully qualified URL to -Uri' {
        $script:usedParameterSet = $null
        $uri = "https://management.azure.com/subscriptions/$script:subId/resourceGroups/rg?api-version=2021-04-01"

        { Invoke-ArmRequest -Uri $uri -SuccessCodes @(200) } | Should -Not -Throw
        $script:usedParameterSet | Should -Be 'ByURI'
    }

    It 'routes a sovereign-cloud URL to -Uri' {
        $script:usedParameterSet = $null
        $uri = "https://management.usgovcloudapi.net/subscriptions/$script:subId/resourceGroups/rg?api-version=2021-04-01"

        { Invoke-ArmRequest -Uri $uri -SuccessCodes @(200) } | Should -Not -Throw
        $script:usedParameterSet | Should -Be 'ByURI'
    }

    It 'throws with the status code and body on a failed request' {
        function Invoke-AzRestMethod {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
                Justification = 'Test double mirroring the real cmdlet signature.')]
            [CmdletBinding()]
            param([string] $Path, [string] $Uri, [string] $Method)
            [pscustomobject] @{ StatusCode = 404; Content = '{"error":"TableNotFound"}' }
        }

        { Invoke-ArmRequest -Uri '/subscriptions/x/tables/Nope_CL?api-version=2023-09-01' -SuccessCodes @(200) } |
            Should -Throw -ExpectedMessage '*404*TableNotFound*'
    }
}

Describe 'Get-DcrColumnType' {
    It 'maps <TableType> to <Expected>' -ForEach @(
        @{ TableType = 'string';   Expected = 'string'   }
        @{ TableType = 'int';      Expected = 'int'      }
        @{ TableType = 'long';     Expected = 'long'     }
        @{ TableType = 'real';     Expected = 'real'     }
        @{ TableType = 'boolean';  Expected = 'boolean'  }
        @{ TableType = 'dynamic';  Expected = 'dynamic'  }
    ) {
        Get-DcrColumnType -TableColumnType $TableType | Should -Be $Expected
    }

    It 'normalises the Tables API camelCase dateTime to the DCR datetime' {
        # The Tables API returns 'dateTime'; stream declarations only
        # accept 'datetime'. Getting this wrong fails DCR creation.
        Get-DcrColumnType -TableColumnType 'dateTime' | Should -Be 'datetime'
    }

    It 'declares guid columns as string' {
        # 'guid' has no stream-declaration equivalent. Azure Monitor
        # stores GUIDs as strings, so the stream must say string.
        Get-DcrColumnType -TableColumnType 'guid' | Should -Be 'string'
    }

    It 'falls back to string for an unknown type' {
        Get-DcrColumnType -TableColumnType 'notARealType' -WarningAction SilentlyContinue |
            Should -Be 'string'
    }
}

Describe 'ConvertTo-StreamColumn' {
    BeforeAll {
        # Shape of a classic MMA / Data Collector API custom log table.
        $script:classicSchema = @(
            [pscustomobject] @{ name = 'TimeGenerated';   type = 'dateTime'; isHidden = $false }
            [pscustomobject] @{ name = 'Computer';        type = 'string';   isHidden = $false }
            [pscustomobject] @{ name = 'RawData';         type = 'string';   isHidden = $false }
            [pscustomobject] @{ name = 'SourceIp_s';      type = 'string';   isHidden = $false }
            [pscustomobject] @{ name = 'Duration_d';      type = 'real';     isHidden = $false }
            [pscustomobject] @{ name = 'CorrelationId_g'; type = 'guid';     isHidden = $false }
            [pscustomobject] @{ name = 'TenantId';        type = 'guid';     isHidden = $false }
            [pscustomobject] @{ name = '_ResourceId';     type = 'string';   isHidden = $false }
            [pscustomobject] @{ name = 'Legacy_s';        type = 'string';   isHidden = $true  }
        )

        $script:result    = ConvertTo-StreamColumn -SchemaColumn $script:classicSchema
        $script:converted = @($script:result.Columns)
        $script:names     = @($script:converted | ForEach-Object { $_.name })
        $script:dropped   = @($script:result.Dropped)
    }

    It 'keeps the custom columns' {
        $script:names | Should -Contain 'SourceIp_s'
        $script:names | Should -Contain 'Duration_d'
    }

    It 'drops reserved column <_>' -ForEach @('TenantId') {
        $script:names | Should -Not -Contain $_
    }

    It 'drops system columns prefixed with an underscore' {
        $script:names | Should -Not -Contain '_ResourceId'
    }

    It 'drops hidden columns' {
        $script:names | Should -Not -Contain 'Legacy_s'
    }

    It 'maps column types through Get-DcrColumnType' {
        ($script:converted | Where-Object name -EQ 'CorrelationId_g').type | Should -Be 'string'
        ($script:converted | Where-Object name -EQ 'Duration_d').type      | Should -Be 'real'
    }

    It 'guarantees TimeGenerated even when the schema omits it' {
        $withoutTime = @(
            [pscustomobject] @{ name = 'SourceIp_s'; type = 'string'; isHidden = $false }
        )

        $columns = @((ConvertTo-StreamColumn -SchemaColumn $withoutTime).Columns)
        $names   = @($columns | ForEach-Object { $_.name })

        $names | Should -Contain 'TimeGenerated'
        ($columns | Where-Object name -EQ 'TimeGenerated').type | Should -Be 'datetime'
    }

    It 'does not duplicate TimeGenerated when the schema already has it' {
        @($script:names | Where-Object { $_ -eq 'TimeGenerated' }).Count | Should -Be 1
    }

    It 'tolerates a schema with no custom columns' {
        $columns = @((ConvertTo-StreamColumn -SchemaColumn @()).Columns)
        $columns.Count  | Should -Be 1
        $columns[0].name | Should -Be 'TimeGenerated'
    }

    It 'reports every dropped column with a reason' {
        # Silent drops are how you lose a column without noticing. Each one
        # must surface so the operator can be told it stops receiving data.
        $script:dropped.Count | Should -BeGreaterThan 0
        $script:dropped | ForEach-Object {
            $_.Name   | Should -Not -BeNullOrEmpty
            $_.Reason | Should -Not -BeNullOrEmpty
        }
    }

    It 'reports underscore-prefixed classic artefacts as undroppable, not silently' {
        # Real-world case: AzureActivity_CL carried _table_s and
        # _ResourceId_s. Stream column names must start with a letter, so
        # these can never be carried across.
        $schema = @(
            [pscustomobject] @{ name = '_table_s';      type = 'string'; isHidden = $false }
            [pscustomobject] @{ name = '_ResourceId_s'; type = 'string'; isHidden = $false }
            [pscustomobject] @{ name = 'Good_s';        type = 'string'; isHidden = $false }
        )

        $result  = ConvertTo-StreamColumn -SchemaColumn $schema
        $names   = @($result.Columns | ForEach-Object { $_.name })
        $dropped = @($result.Dropped | ForEach-Object { $_.Name })

        $names   | Should -Contain 'Good_s'
        $names   | Should -Not -Contain '_table_s'
        $dropped | Should -Contain '_table_s'
        $dropped | Should -Contain '_ResourceId_s'

        ($result.Dropped | Where-Object Name -EQ '_table_s').Reason |
            Should -Match 'start with a letter'
    }
}

Describe 'Build-DcrArmTemplate' {
    BeforeAll {
        $script:columns = @(
            [pscustomobject] @{ name = 'TimeGenerated'; type = 'datetime' }
            [pscustomobject] @{ name = 'SourceIp_s';    type = 'string'   }
        )

        $script:workspaceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sentinel' +
                              '/providers/Microsoft.OperationalInsights/workspaces/law-sentinel'

        $script:directTemplate = Build-DcrArmTemplate -Name 'dcr-myapp' `
                                                      -Region 'uksouth' `
                                                      -Kind 'Direct' `
                                                      -Stream 'Custom-MyApp_CL' `
                                                      -StreamColumn $script:columns `
                                                      -WorkspaceResourceId $script:workspaceId `
                                                      -OutputStream 'Custom-MyApp_CL' `
                                                      -Transform 'source'

        $script:directResource = $script:directTemplate.resources[0]
    }

    It 'emits a single dataCollectionRules resource' {
        @($script:directTemplate.resources).Count | Should -Be 1
        $script:directResource.type | Should -Be 'Microsoft.Insights/dataCollectionRules'
    }

    It 'sets kind Direct so the DCR gets its own logs ingestion endpoint' {
        $script:directResource.kind | Should -Be 'Direct'
    }

    It 'omits dataCollectionEndpointId when no DCE is supplied' {
        $script:directResource.properties.Contains('dataCollectionEndpointId') | Should -BeFalse
    }

    It 'omits the dataSources section for a Direct DCR' {
        $script:directResource.properties.Contains('dataSources') | Should -BeFalse
    }

    It 'declares the stream with the supplied columns' {
        $declaration = $script:directResource.properties.streamDeclarations['Custom-MyApp_CL']
        @($declaration.columns).Count | Should -Be 2
    }

    It 'wires the data flow to the workspace destination and output stream' {
        $flow = $script:directResource.properties.dataFlows[0]
        $flow.streams      | Should -Contain 'Custom-MyApp_CL'
        $flow.destinations | Should -Contain 'workspaceDestination'
        $flow.outputStream | Should -Be 'Custom-MyApp_CL'
        $flow.transformKql | Should -Be 'source'
    }

    It 'points the destination at the supplied workspace' {
        $script:directResource.properties.destinations.logAnalytics[0].workspaceResourceId |
            Should -Be $script:workspaceId
    }

    It 'includes the DCE when one is supplied' {
        $dceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sentinel' +
                 '/providers/Microsoft.Insights/dataCollectionEndpoints/dce-sentinel'

        $template = Build-DcrArmTemplate -Name 'dcr-myapp' -Region 'uksouth' -Kind 'Direct' `
                                         -Stream 'Custom-MyApp_CL' -StreamColumn $script:columns `
                                         -WorkspaceResourceId $script:workspaceId `
                                         -OutputStream 'Custom-MyApp_CL' -Transform 'source' `
                                         -EndpointResourceId $dceId

        $template.resources[0].properties.dataCollectionEndpointId | Should -Be $dceId
    }

    It 'includes the logFiles data source for an agent text-log DCR' {
        $dataSource = [ordered] @{
            name         = 'myapp-logfile'
            streams      = @('Custom-MyApp_CL')
            filePatterns = @('C:\logs\*.txt')
            format       = 'text'
        }

        $template = Build-DcrArmTemplate -Name 'dcr-myapp' -Region 'uksouth' -Kind 'Windows' `
                                         -Stream 'Custom-MyApp_CL' -StreamColumn $script:columns `
                                         -WorkspaceResourceId $script:workspaceId `
                                         -OutputStream 'Custom-MyApp_CL' -Transform 'source' `
                                         -LogFilesDataSource $dataSource

        $resource = $template.resources[0]
        $resource.kind | Should -Be 'Windows'
        $resource.properties.dataSources.logFiles[0].filePatterns | Should -Contain 'C:\logs\*.txt'
    }

    It 'round-trips through ConvertTo-Json as a valid ARM template' {
        $json  = $script:directTemplate | ConvertTo-Json -Depth 30
        $parsed = $json | ConvertFrom-Json

        $parsed.'$schema'      | Should -Match 'deploymentTemplate\.json'
        $parsed.contentVersion | Should -Be '1.0.0.0'
        $parsed.resources[0].apiVersion | Should -Be '2023-03-11'
    }
}

Describe 'Get-DefaultTransform' {
    BeforeAll {
        # Build a (schema column, stream column) pair for a Tables API type,
        # where the stream type is whatever ConvertTo-StreamColumn produces.
        function Get-TypePair {
            param([string] $ApiType)
            $streamType = Get-DcrColumnType -TableColumnType $ApiType
            [pscustomobject] @{
                Schema = @([pscustomobject] @{ name = 'Col1'; type = $ApiType })
                Stream = @([pscustomobject] @{ name = 'Col1'; type = $streamType })
            }
        }
    }

    It 'passes <ApiType> through unchanged (no cast needed)' -ForEach @(
        @{ ApiType = 'string'   }
        @{ ApiType = 'int'      }
        @{ ApiType = 'long'     }
        @{ ApiType = 'real'     }
        @{ ApiType = 'boolean'  }
        @{ ApiType = 'dateTime' }
        @{ ApiType = 'dynamic'  }
    ) {
        $p = Get-TypePair -ApiType $ApiType
        Get-DefaultTransform -SchemaColumn $p.Schema -StreamColumn $p.Stream | Should -Be 'source'
    }

    It 'casts a guid column back to guid, because the stream declares it string' {
        $p = Get-TypePair -ApiType 'guid'
        Get-DefaultTransform -SchemaColumn $p.Schema -StreamColumn $p.Stream |
            Should -Be 'source | extend Col1 = toguid(Col1)'
    }

    It 'casts every mismatched column, not just the first' {
        # Defensive: if the stream ever declares a type different from the
        # table for several columns, each must be reconciled.
        $schema = @(
            [pscustomobject] @{ name = 'A'; type = 'guid' }
            [pscustomobject] @{ name = 'B'; type = 'int'  }
            [pscustomobject] @{ name = 'C'; type = 'guid' }
        )
        $stream = @(
            [pscustomobject] @{ name = 'A'; type = 'string' }   # mismatch -> toguid
            [pscustomobject] @{ name = 'B'; type = 'int'    }   # match    -> none
            [pscustomobject] @{ name = 'C'; type = 'string' }   # mismatch -> toguid
        )
        $t = Get-DefaultTransform -SchemaColumn $schema -StreamColumn $stream
        $t | Should -Match 'A = toguid\(A\)'
        $t | Should -Match 'C = toguid\(C\)'
        $t | Should -Not -Match '\bB\b'
    }

    It 'does not cast a column that was dropped from the stream' {
        $schema = @([pscustomobject] @{ name = 'Dropped_g'; type = 'guid' })
        $stream = @()   # dropped
        Get-DefaultTransform -SchemaColumn $schema -StreamColumn $stream | Should -Be 'source'
    }

    It 'surfaces the deployment error detail instead of the generic summary' {
        # Regression guard for the opaque failure: the deploy path must pull
        # the operation StatusMessage, not just the first line of the throw.
        $src = Get-Content -Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools/ClassicToDcr/Invoke-ClassicTableMigration.ps1') -Raw
        $src | Should -Match 'Get-AzResourceGroupDeploymentOperation'
        $src | Should -Match 'throw "Deployment failed:'
    }
}
