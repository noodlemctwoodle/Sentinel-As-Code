#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for Get-iSOCTableMigrationImpact and Export-iSOCTableMigrationReport,
    against Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1.

.DESCRIPTION
    Three layers:

      - Each pure helper (the KQL readers, alias safety, connector kinds, the
        playbook and workbook query readers, the JavaScript literal) is run
        beside the script's own function over the same inputs, and must
        answer the same.
      - The impact analysis (alias index, direct and chained dependents,
        severed bridges, truncation, fan-out) is run beside the script's
        over one stand-in workspace, at three chain depths, and must agree
        to the last field.
      - The script itself runs unchanged in a child pwsh, its Az commands and
        Invoke-RestMethod stood in for over that workspace, and the module
        runs over the same workspace through a mocked REST client. The five
        files each writes must hold the same data.

    The module's report template is held to the contracts the script's is
    (tests/Test-InvokeTableMigrationReview.Tests.ps1), with the module's
    commands, and must differ from the script's only there.

.NOTES
    File:         Tests/iSOCDeployments/TableMigration.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:scriptPath = Join-Path $script:repoRoot 'Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1'
    $script:helperPath = Join-Path $PSScriptRoot '_helpers/TableMigrationStandIn.psm1'
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module $script:helperPath -Force
    Import-Module (Join-Path $script:repoRoot 'Tests/_helpers/Import-ScriptFunctions.psm1') -Force
    Import-ScriptFunctions -Path $script:scriptPath

    $script:standInPath = Join-Path $TestDrive 'standin.json'
    Set-Content -LiteralPath $script:standInPath -Value (ConvertTo-Json -InputObject (Get-TableMigrationStandIn) -Depth 30)
    $script:standIn = Get-Content -LiteralPath $script:standInPath -Raw | ConvertFrom-Json -Depth 30
    $script:sub = $script:standIn.subscriptionId

    $script:toJson = { param($Value) ConvertTo-Json -InputObject $Value -Depth 30 }

    $script:wrapper = @'
param([string] $Script, [string] $StandInPath, [string] $Parameters, [string] $Helper)
$ErrorActionPreference = 'Stop'
Import-Module $Helper -Force
$global:TableMigrationStandIn = Get-Content -LiteralPath $StandInPath -Raw | ConvertFrom-Json -Depth 30
function Import-Module { }
function Get-AzContext { [pscustomobject]@{ Account = [pscustomobject]@{ Id = 'tester' }; Subscription = [pscustomobject]@{ Id = $global:TableMigrationStandIn.subscriptionId; Name = 'Lab' } } }
function Set-AzContext { }
function Connect-AzAccount { }
function Get-AzAccessToken { [pscustomobject]@{ Token = 'token' } }
function Invoke-RestMethod {
param($Uri, $Headers, $Method)
if ($Method -ne 'Get') { throw "The review sent a $Method" }
$u = [Uri]$Uri
$query = @{}
foreach ($pair in $u.Query.TrimStart('?') -split '&') {
    if (-not $pair) { continue }
    $k, $v = $pair -split '=', 2
    $query[$k] = [Uri]::UnescapeDataString($v)
}
$answer = Get-TableMigrationStandInAnswer -StandIn $global:TableMigrationStandIn -Path $u.AbsolutePath -Query $query
if ($answer -is [System.Collections.IDictionary]) { return [pscustomobject]$answer }
$answer
}
$splat = Get-Content -LiteralPath $Parameters -Raw | ConvertFrom-Json -AsHashtable
& $Script @splat | Out-Null
exit $LASTEXITCODE
'@

    function Invoke-LegacyReview {
        param([scriptblock] $Edit)
        $tree = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $kit = Join-Path $tree 'kit'
        New-Item -ItemType Directory -Path $kit -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'Tools/ClassicToDcr/data') -Destination $kit -Recurse
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'Tools/ClassicToDcr/Templates') -Destination $kit -Recurse
        $text = (Get-Content -LiteralPath $script:scriptPath -Raw) -replace '(?m)^#Requires -Modules[^\r\n]*\r?\n', ''
        if ($Edit) { $text = & $Edit $text }
        $copy = Join-Path $kit 'Invoke-TableMigrationReview.ps1'
        Set-Content -LiteralPath $copy -Value $text -NoNewline
        Set-Content -LiteralPath (Join-Path $tree 'run.ps1') -Value $script:wrapper
        $out = Join-Path $tree 'out'
        Set-Content -LiteralPath (Join-Path $tree 'parameters.json') -Value (ConvertTo-Json -InputObject @{ SubscriptionId = $script:sub; ResourceGroupName = 'rg-sentinel'; WorkspaceName = 'law-sentinel'; OutputPath = $out; NonInteractive = $true })
        $output = & pwsh -NoProfile -NonInteractive -File (Join-Path $tree 'run.ps1') -Script $copy -StandInPath $script:standInPath -Parameters (Join-Path $tree 'parameters.json') -Helper $script:helperPath 2>&1 | Out-String
        [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE; Path = $out }
    }

    function Invoke-ModuleReview {
        param($StandIn = $script:standIn, [string] $Path = (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))))
        $script:moduleStandIn = $StandIn
        $script:moduleRequests = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
            if ($Method -ne 'GET') { throw "The review sent a $Method" }
            $script:moduleRequests.Add("$Path $ApiVersion")
            $parts = $Path -split '\?', 2
            $query = @{}
            if ($parts.Count -gt 1) {
                foreach ($pair in $parts[1] -split '&') { $k, $v = $pair -split '=', 2; $query[$k] = [Uri]::UnescapeDataString($v) }
            }
            $answer = Get-TableMigrationStandInAnswer -StandIn $script:moduleStandIn -Path $parts[0] -Query $query
            if ($answer -is [System.Collections.IDictionary]) { return $answer.value }
            $answer
        }
        $ctx = InModuleScope iSOCDeployments -Parameters @{ Sub = $StandIn.subscriptionId } {
            param($Sub)
            New-iSOCContext -Value @{
                TenantId = 't'; SubscriptionId = $Sub; ResourceGroup = 'rg-sentinel'; WorkspaceName = 'law-sentinel'
                WorkspaceResourceId = "/subscriptions/$Sub/resourceGroups/rg-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-sentinel"
                WorkspaceId = 'w'; Region = 'uksouth'; PlaybookResourceGroup = 'rg-auto'; Environment = 'AzureCloud'; IsGov = $false
                ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'tester'
            }
        }
        $review = Get-iSOCTableMigrationImpact -Context $ctx
        $files = @($review | Export-iSOCTableMigrationReport -Path $Path)
        [pscustomobject]@{ Review = $review; Files = $files; Path = $Path; Requests = @($script:moduleRequests) }
    }

    function Read-ReportData {
        param([string] $Path, [string] $File)
        $full = Join-Path $Path $File
        switch ($File) {
            'report.json' {
                $data = Get-Content -LiteralPath $full -Raw | ConvertFrom-Json -AsHashtable -Depth 40
                $data.Remove('generatedAt')
                return ConvertTo-Json -InputObject $data -Depth 40
            }
            'report.html' {
                $m = [regex]::Match((Get-Content -LiteralPath $full -Raw), 'JSON\.parse\("((?:[^"\\]|\\.)*)"\)')
                $data = ('"' + $m.Groups[1].Value + '"' | ConvertFrom-Json) | ConvertFrom-Json -AsHashtable -Depth 40
                $data.Remove('GeneratedAt')
                return ConvertTo-Json -InputObject $data -Depth 40
            }
            default { return ConvertTo-Json -InputObject @(Import-Csv -LiteralPath $full) -Depth 5 }
        }
    }
}

Describe 'The KQL readers, beside the script''s' {
    BeforeAll {
        $script:corpus = @(
            $null, '', 'T', 'OfficeParser | where x == 1',
            "T | where Name == 'OfficeParser'", 'T | where Name == "Office\"Parser" | OfficeParser',
            "@'C:\path\' | OfficeParser", '@"a""b" OfficeParser', "T // OfficeParser`nX",
            "h'secret' OfficeParser", "`````` multi`nOfficeParser `````` Tail", "``````never closed OfficeParser",
            "['OfficeParser'] | take 1", "[`"OfficeParser`"]", 'parse_json(x)["OfficeParser"]', "Properties['OfficeParser']",
            'cluster("c").database("d").OfficeParser | take 1', 'workspace("w").OfficeParser', 'app ( "a" ) . OfficeParser',
            'T | extend OfficeParser = 1', 'T | where OfficeParser == 1', 'T | where OfficeParser =~ "x"', 'x.OfficeParser',
            'let OfficeParser = T; OfficeParser', 'let a=1; a | union OfficeParser', "'unterminated`nOfficeParser",
            'T | where a != b and c <= d', 'officeparser | take 1', 'OfficeParser_v2 | take 1', "x`r`n// c`r`nOfficeParser"
        )
    }

    It 'reads each query to the same code, names and references' {
        $old = foreach ($t in $script:corpus) {
            [ordered]@{
                Code     = Get-KqlCodeText -Text $t
                Expanded = Expand-KqlQuotedIdentifier -Text $t
                Search   = ConvertTo-KqlNameSearchText -Text (Get-KqlCodeText -Text $t)
                Let      = @((Get-KqlLetBoundName -Text $t) | Sort-Object -CaseSensitive)
                Refs     = @((Get-KqlReferenceIdentifierSet -Text @($t)) | Sort-Object -CaseSensitive)
                Names    = Test-KqlReferencesTable -Query $t -TableName 'OfficeParser'
            }
        }
        $new = InModuleScope iSOCDeployments -Parameters @{ Corpus = $script:corpus } {
            param($Corpus)
            foreach ($t in $Corpus) {
                [ordered]@{
                    Code     = Get-iSOCKqlCodeText -Text $t
                    Expanded = Expand-iSOCKqlQuotedIdentifier -Text $t
                    Search   = ConvertTo-iSOCKqlNameSearchText -Text (Get-iSOCKqlCodeText -Text $t)
                    Let      = @((Get-iSOCKqlLetBoundName -Text $t) | Sort-Object -CaseSensitive)
                    Refs     = @((Get-iSOCKqlReferenceIdentifierSet -Text @($t)) | Sort-Object -CaseSensitive)
                    Names    = Test-iSOCKqlTableReference -Query $t -TableName 'OfficeParser'
                }
            }
        }
        (& $script:toJson @($new)) | Should -BeExactly (& $script:toJson @($old))
    }

    It 'judges each alias as the script does' {
        $aliases = @($null, '', '  ', 'abc', 'abcd', 'OfficeParser', ' OfficeParser ', 'where', 'Where', 'TimeGenerated', 'my-parser', '1abc', 'Update', 'update', 'Location', 'Good_Name1')
        $old = foreach ($a in $aliases) { foreach ($min in 3, 4) { Get-FunctionAliasSafety -Alias $a -MinimumLength $min -WorkspaceTableName 'Update', 'SecurityEvent' -WorkspaceColumnName 'Location', 'Message' } }
        $new = InModuleScope iSOCDeployments -Parameters @{ Aliases = $aliases } {
            param($Aliases)
            foreach ($a in $Aliases) { foreach ($min in 3, 4) { Get-iSOCFunctionAliasSafety -Alias $a -MinimumLength $min -WorkspaceTableName 'Update', 'SecurityEvent' -WorkspaceColumnName 'Location', 'Message' } }
        }
        (& $script:toJson @($new)) | Should -BeExactly (& $script:toJson @($old))
        (& $script:toJson @(InModuleScope iSOCDeployments { Get-iSOCReservedAliasName })) | Should -BeExactly (& $script:toJson @(Get-ReservedAliasName))
    }

    It 'classifies each connector as the script does' {
        $ids = @($null, '', 'OktaSSOv2', 'OktaSSO_Polling', 'FooCCP', 'FooCCPDefinition', 'BarDefinition', 'X_Ccf_', 'AzureActiveDirectory', 'Office365', 'CEF', 'Syslog', 'CefAma', 'WindowsForwardedEventsAma', 'SomethingServerless', 'MyFunc', 'Vendor_API_FunctionApp', 'Random')
        $old = foreach ($id in $ids) { Resolve-ConnectorKind -ConnectorId $id -SolutionName 'S' }
        $new = InModuleScope iSOCDeployments -Parameters @{ Ids = $ids } { param($Ids) foreach ($id in $Ids) { Resolve-iSOCConnectorKind -ConnectorId $id -SolutionName 'S' } }
        $new | Should -Be $old
        $old | Should -Contain 'CCF'
        $old | Should -Contain 'AzureFunctions'
        $old | Should -Contain 'Legacy'
    }

    It 'reads the same queries from each playbook and workbook' {
        $definitions = @($script:standIn.logicApps | ForEach-Object { $_.properties.PSObject.Properties['definition'] ? $_.properties.definition : $null })
        $data = @($script:standIn.workbooks.properties.serializedData) + @($null, '', '[]', '{"query":"a","items":[{"query":"b"},{"x":{"query":5}}]}')
        $old = [ordered]@{
            Playbooks = @($definitions | ForEach-Object { , @(Get-PlaybookKqlText -Definition $_ | Sort-Object -CaseSensitive) })
            Workbooks = @($data | ForEach-Object { , @(Get-WorkbookQueryText -SerializedData $_) })
        }
        $new = InModuleScope iSOCDeployments -Parameters @{ Definitions = $definitions; Data = $data } {
            param($Definitions, $Data)
            [ordered]@{
                Playbooks = @($Definitions | ForEach-Object { , @(Get-iSOCPlaybookKqlText -Definition $_ | Sort-Object -CaseSensitive) })
                Workbooks = @($Data | ForEach-Object { , @(Get-iSOCWorkbookQueryText -SerializedData $_) })
            }
        }
        (& $script:toJson $new) | Should -BeExactly (& $script:toJson $old)
    }

    It 'escapes each string for the page as the script does' {
        $values = @('', 'plain', '</script><b>', "line$([char]0x2028)sep$([char]0x2029)end", 'quote " back \ end', "tab`tnew`nend")
        $old = foreach ($v in $values) { ConvertTo-JsStringLiteral -Value $v }
        $new = InModuleScope iSOCDeployments -Parameters @{ Values = $values } { param($Values) foreach ($v in $Values) { ConvertTo-iSOCJsStringLiteral -Value $v } }
        $new | Should -Be $old
    }
}

Describe 'The impact analysis, beside the script''s' {
    BeforeAll {
        $script:content = ConvertTo-TableMigrationContent -StandIn $script:standIn
        $script:tableNames = @($script:standIn.tables.name)
        $script:columnNames = @($script:standIn.tables | ForEach-Object { if ($_.properties.schema.PSObject.Properties['columns']) { $_.properties.schema.columns.name } } | Sort-Object -Unique)
        $script:classic = @('OfficeActivity_CL', 'MyApp_CL', 'MyApp_CL_v2', 'Okta_CL', 'Tenable_IE_CL', 'Lonely_CL')

        $script:analyseOld = {
            param($Content, [int] $Depth)
            $index = Get-ParserAliasIndex -Content $Content -WorkspaceTableName $script:tableNames -WorkspaceColumnName $script:columnNames
            [ordered]@{
                Index   = $index
                Impacts = @(foreach ($t in $script:classic) { Get-TableImpactAnalysis -TableName $t -Content $Content -AliasIndex $index -MaxDepth $Depth })
            }
        }
        $script:analyseNew = {
            param($Content, [int] $Depth)
            InModuleScope iSOCDeployments -Parameters @{ Content = $Content; Depth = $Depth; Tables = $script:tableNames; Columns = $script:columnNames; Classic = $script:classic } {
                param($Content, $Depth, $Tables, $Columns, $Classic)
                $index = Get-iSOCParserAliasIndex -Content $Content -WorkspaceTableName $Tables -WorkspaceColumnName $Columns
                [ordered]@{
                    Index   = $index
                    Impacts = @(foreach ($t in $Classic) { Get-iSOCTableImpactAnalysis -TableName $t -Content $Content -AliasIndex $index -MaxDepth $Depth })
                }
            }
        }
    }

    It 'finds the same dependents of every classic table, <Depth> hop(s) deep' -ForEach @(@{ Depth = 1 }, @{ Depth = 2 }, @{ Depth = 10 }) {
        $old = & $script:analyseOld $script:content $Depth
        $new = & $script:analyseNew $script:content $Depth
        (& $script:toJson $new.Impacts) | Should -BeExactly (& $script:toJson $old.Impacts)
        (& $script:toJson $new.Index) | Should -BeExactly (& $script:toJson $old.Index)
    }

    It 'has a workspace that reaches every case the analysis handles' {
        $result = & $script:analyseNew $script:content 10
        $office = $result.Impacts | Where-Object TableName -eq 'OfficeActivity_CL'
        ($office.IndirectAnalyticsRules.Name) | Should -Contain 'Rule via wrapper'
        ($office.IndirectAnalyticsRules.Name) | Should -Contain 'Rule quoted'
        ($office.IndirectAnalyticsRules.Name) | Should -Not -Contain 'Rule with comment'
        ($office.IndirectAnalyticsRules.Name) | Should -Not -Contain 'Rule cross workspace'
        ($office.IndirectAnalyticsRules.Name) | Should -Not -Contain 'Rule both'
        ($office.AnalyticsRules.Name) | Should -Contain 'Rule both'
        ($office.IndirectHuntingQueries.Name) | Should -Contain 'Hunt deeper'
        ($office.IndirectHuntingQueries.Name) | Should -Not -Contain 'Hunt case'
        ($office.IndirectSavedSearches.Name) | Should -Not -Contain 'Shadowed'
        ($office.IndirectWorkbooks.Name) | Should -Contain 'Office workbook'
        ($office.IndirectPlaybooks.Name) | Should -Contain 'pb-query'
        ($office.IndirectPlaybooks.Name) | Should -Not -Contain 'pb-key'
        @($office.IndirectDcrs).Count | Should -Be 0
        ($office.UnresolvedBridges.Alias) | Should -Contain 'abc'
        ($result.Impacts | Where-Object TableName -eq 'MyApp_CL').UnresolvedBridges.Alias | Should -Contain 'Update'
        ($result.Impacts | Where-Object TableName -eq 'MyApp_CL_v2').UnresolvedBridges.Alias | Should -Contain 'Location'
        ($result.Impacts | Where-Object TableName -eq 'MyApp_CL').Dcrs.Name | Should -Contain 'dcr-myapp'
        (& $script:analyseNew $script:content 1).Impacts | Where-Object ChainTruncated | Should -Not -BeNullOrEmpty
    }

    It 'warns of an alias most of the workspace names, as the script does' {
        $hub = [pscustomobject]@{ id = '/x/savedSearches/hub'; name = 'hub'; properties = [pscustomobject]@{ displayName = 'Hub'; category = 'Parsers'; functionAlias = 'HubParser'; query = 'OfficeActivity_CL' } }
        $rules = @(foreach ($n in 1..60) {
                $q = if ($n -le 25) { 'HubParser | take 1' } else { 'SecurityEvent | take 1' }
                [pscustomobject]@{ id = "/x/alertRules/r$n"; name = "r$n"; properties = [pscustomobject]@{ displayName = "Rule $n"; query = $q; enabled = $true; severity = 'Low' } }
            })
        $fan = [pscustomobject]@{ AlertRules = $rules; SavedSearches = @($hub); HuntingQueries = @(); Parsers = @($hub); Workbooks = @(); Dcrs = @(); Playbooks = @() }
        $old = & $script:analyseOld $fan 10
        $new = & $script:analyseNew $fan 10
        @($new.Index.Warnings) | Should -HaveCount 1
        (& $script:toJson $new) | Should -BeExactly (& $script:toJson $old)
    }

    It 'agrees when the workspace has no parsers at all' {
        $none = [pscustomobject]@{ AlertRules = $script:content.AlertRules; SavedSearches = @(); HuntingQueries = @(); Parsers = @(); Workbooks = $script:content.Workbooks; Dcrs = $script:content.Dcrs; Playbooks = $script:content.Playbooks }
        (& $script:toJson (& $script:analyseNew $none 10)) | Should -BeExactly (& $script:toJson (& $script:analyseOld $none 10))
    }

    It 'maps each table to the same solutions and connector kinds' {
        $packages = @($script:standIn.contentProductPackages | ForEach-Object { $_ | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20 })
        $script:MappingPath = Join-Path $script:repoRoot 'Tools/ClassicToDcr/data/solution-mapping.json'
        $mapping = Get-SolutionMapping
        $old = foreach ($t in $script:classic) { [ordered]@{ Match = Get-SolutionMatchForTable -TableName $t -StaticMapping $mapping -Packages $packages; Kinds = @(Get-ConnectorClassification -TableName $t -StaticMapping $mapping -Packages $packages) } }
        $new = InModuleScope iSOCDeployments -Parameters @{ Packages = $packages; Classic = $script:classic } {
            param($Packages, $Classic)
            $mapping = Get-iSOCSolutionMapping
            foreach ($t in $Classic) { [ordered]@{ Match = Get-iSOCSolutionMatch -TableName $t -StaticMapping $mapping -Packages $Packages; Kinds = @(Get-iSOCConnectorClassification -TableName $t -StaticMapping $mapping -Packages $Packages) } }
        }
        (& $script:toJson @($new)) | Should -BeExactly (& $script:toJson @($old))
        @($new | ForEach-Object { $_.Kinds.ConnectorKind }) | Should -Contain 'CCF'
        @($new | ForEach-Object { $_.Kinds.ConnectorKind }) | Should -Contain 'Platform'
        @($new | ForEach-Object { $_.Kinds.ConnectorKind }) | Should -Contain 'AzureFunctions'
    }
}

Describe 'Parity with Invoke-TableMigrationReview.ps1' {
    BeforeAll {
        $script:legacy = Invoke-LegacyReview
        $script:module = Invoke-ModuleReview
    }

    It 'runs the script to the end' {
        $script:legacy.ExitCode | Should -Be 0 -Because $script:legacy.Output
        Test-Path -LiteralPath (Join-Path $script:legacy.Path 'report.html') | Should -BeTrue
    }

    It 'writes the same <File>' -ForEach @(@{ File = 'tables.csv' }, @{ File = 'impact.csv' }, @{ File = 'solution-matches.csv' }, @{ File = 'report.json' }, @{ File = 'report.html' }) {
        Read-ReportData -Path $script:module.Path -File $File | Should -BeExactly (Read-ReportData -Path $script:legacy.Path -File $File)
    }

    It 'returns the five files it wrote' {
        @($script:module.Files.Name) | Should -Be @('tables.csv', 'impact.csv', 'solution-matches.csv', 'report.json', 'report.html')
    }

    It 'finds dependents of every kind, direct and through parsers' {
        $rows = @(Import-Csv -LiteralPath (Join-Path $script:module.Path 'impact.csv'))
        foreach ($type in 'AnalyticsRules', 'HuntingQueries', 'Parsers', 'SavedSearches', 'Workbooks', 'Playbooks', 'Dcrs') {
            @($rows | Where-Object ContentType -eq $type) | Should -Not -BeNullOrEmpty -Because "a $type dependent is in the workspace"
        }
        @($rows | Where-Object DependencyKind -eq 'Indirect') | Should -Not -BeNullOrEmpty
        ($rows | Where-Object { $_.Name -eq 'Rule via wrapper' }).ViaChain | Should -Be 'OfficeWrapper -> OfficeActivityParser -> OfficeActivity_CL'
    }

    It 'reads a workbook the list returns without content on its own, and finds what it names' {
        $script:module.Requests | Should -Contain "/subscriptions/$($script:sub)/resourceGroups/rg-sentinel/providers/Microsoft.Insights/workbooks/wb-inherited?canFetchContent=true 2022-04-01"
        $rows = @(Import-Csv -LiteralPath (Join-Path $script:module.Path 'impact.csv'))
        @($rows | Where-Object { $_.TableName -eq 'MyApp_CL' -and $_.Name -eq 'Inherited workbook' }) | Should -HaveCount 1
    }

    It 'found no workbook before 0.2.2, which listed them without canFetchContent' {
        $old = Invoke-LegacyReview -Edit { param($Text) $Text -replace "\s*;?\s*'canFetchContent'\s*=\s*'true'", '' }
        $old.ExitCode | Should -Be 0 -Because $old.Output
        @(Import-Csv -LiteralPath (Join-Path $old.Path 'impact.csv') | Where-Object ContentType -eq 'Workbooks') | Should -BeNullOrEmpty
        @(Import-Csv -LiteralPath (Join-Path $script:legacy.Path 'impact.csv') | Where-Object ContentType -eq 'Workbooks') | Should -Not -BeNullOrEmpty
    }

    It 'reads with GET only, at the module''s api-versions' {
        $script:module.Requests | Should -Contain "/subscriptions/$($script:sub)/resourceGroups/rg-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-sentinel/tables 2022-10-01"
        $script:module.Requests | Should -Contain "/subscriptions/$($script:sub)/providers/Microsoft.Insights/dataCollectionRules 2023-03-11"
        $script:module.Requests | Should -Contain "/subscriptions/$($script:sub)/providers/Microsoft.Insights/workbooks?category=sentinel&canFetchContent=true 2022-04-01"
    }
}

Describe 'Get-iSOCTableMigrationImpact and Export-iSOCTableMigrationReport' {
    BeforeAll {
        $script:one = $script:standIn | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        $script:one.tables = @($script:one.tables | Where-Object { $_.name -ne 'MyApp_CL' -and $_.name -notlike 'Okta*' -and $_.name -notlike 'Tenable*' -and $_.name -notlike 'Lonely*' -and $_.name -ne 'MyApp_CL_v2' })
    }

    It 'returns a review with each list a list, even for one classic table' {
        $run = Invoke-ModuleReview -StandIn $script:one
        @($run.Review.ClassicTables) | Should -HaveCount 1
        $json = Get-Content -LiteralPath (Join-Path $run.Path 'report.json') -Raw
        $json | Should -Match '"solutionMatches":\s*\['
        $run.Review.PSObject.TypeNames | Should -Contain 'iSOCDeployments.TableMigrationReview'
        $run.Review.DirectCount | Should -BeGreaterThan 0
    }

    It 'writes nothing for a workspace with no classic tables' {
        $none = $script:standIn | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        $none.tables = @($none.tables | Where-Object { $_.properties.schema.tableSubType -ne 'Classic' })
        $path = Join-Path $TestDrive 'none'
        $run = Invoke-ModuleReview -StandIn $none -Path $path
        @($run.Review.ClassicTables) | Should -HaveCount 0
        $run.Files | Should -BeNullOrEmpty
        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It 'writes nothing under -WhatIf' {
        $run = Invoke-ModuleReview
        $path = Join-Path $TestDrive 'whatif'
        $run.Review | Export-iSOCTableMigrationReport -Path $path -WhatIf | Should -BeNullOrEmpty
        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It 'refuses anything but a review' {
        { [pscustomobject]@{ ClassicTables = @(1) } | Export-iSOCTableMigrationReport -Path (Join-Path $TestDrive 'x') } | Should -Throw '*Get-iSOCTableMigrationImpact*'
    }

    It 'counts an empty list as empty, where the script counted its response as one nameless item' {
        $empty = $script:standIn | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
        $empty.logicApps = @()
        $empty.alertRules = @()
        $run = Invoke-ModuleReview -StandIn $empty
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Message -match 'Analytics Rules : 0$' } -Times 1 -Exactly
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Message -match 'Playbooks       : 0$' } -Times 1 -Exactly
        $office = $run.Review.Impacts | Where-Object TableName -eq 'OfficeActivity_CL'
        @($office.Playbooks) + @($office.IndirectPlaybooks) + @($office.AnalyticsRules) + @($office.IndirectAnalyticsRules) | Should -BeNullOrEmpty
    }
}

Describe 'The module''s report template' {
    BeforeAll {
        $script:tplPath = Join-Path $script:repoRoot 'Modules/iSOCDeployments/Resources/ClassicToDcr/report.html.template'
        $script:tplText = Get-Content -LiteralPath $script:tplPath -Raw
        $script:scriptTpl = Get-Content -LiteralPath (Join-Path $script:repoRoot 'Tools/ClassicToDcr/Templates/report.html.template') -Raw
    }

    It 'differs from the script''s only in the commands it offers and the names it gives' {
        $normalise = {
            param($Text)
            $t = $Text.Replace([string][char]0x2500, '-').Replace([string][char]0x2550, '=')
            $t = [regex]::Replace($t, '(?s)// -- Migration command --.*?// -- Render table card --', '')
            $t = [regex]::Replace($t, 'v[0-9.]+ (&middot;|\u00b7) [A-Za-z]+', 'BADGE')
            [regex]::Replace($t, 'Generated by <strong[^>]*>[^<]+</strong>', 'GENERATED')
        }
        (& $normalise $script:tplText) | Should -BeExactly (& $normalise $script:scriptTpl)
    }

    It 'offers the module''s commands, not the script' {
        $script:tplText | Should -Match ([regex]::Escape("'Invoke-iSOCClassicTableMigration -TableName '"))
        $script:tplText | Should -Match ([regex]::Escape("'Connect-iSOCWorkspace'"))
        $script:tplText | Should -Not -Match 'Invoke-ClassicTableMigration\.ps1'
        $script:tplText | Should -Not -Match 'Tools/ClassicToDcr'
    }

    It 'shows the module version in its badge' {
        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1')
        [regex]::Match($script:tplText, 'v([0-9]+\.[0-9]+\.[0-9]+) &middot; iSOCDeployments').Groups[1].Value | Should -BeExactly $manifest.ModuleVersion
    }

    It 'escapes every character that closes a PowerShell single-quoted string' {
        $script:tplText | Should -Match 'CMD_PS_QUOTES'
        foreach ($cp in '2018', '2019', '201a', '201b') { $script:tplText | Should -Match ('\\u' + $cp) }
    }

    It 'never offers -Force or -Confirm:$false' {
        $script:tplText | Should -Not -Match '-Force'
        $script:tplText | Should -Not -Match 'Confirm:\$false'
    }

    It 'offers a command only for a table name the migration accepts, and pins only a GUID subscription' {
        $script:tplText | Should -Match 'CMD_TABLE_NAME'
        $script:tplText | Should -Match '_CL'
        $script:tplText | Should -Match 'CMD_GUID'
    }

    It 'wires the copy button by delegation and reads the rendered text' {
        $copyMarkup = [regex]::Match($script:tplText, '<button[^>]*cmd-copy[^>]*>').Value
        $copyMarkup | Should -Not -BeNullOrEmpty
        $copyMarkup | Should -Not -Match 'onclick'
        $script:tplText | Should -Match 'addEventListener'
        $script:tplText | Should -Match 'textContent'
        $script:tplText | Should -Not -Match 'data-command'
    }

    It 'stays self-contained' {
        $script:tplText | Should -Not -Match '<script[^>]+src='
        $script:tplText | Should -Not -Match '<link[^>]+href="https?:'
        $script:tplText | Should -Not -Match 'fetch\('
        $script:tplText | Should -Not -Match 'XMLHttpRequest'
    }

    It 'counts chained dependents with direct ones and shows where the lists stop' {
        $script:tplText | Should -Match "ensureArray\(i\['Indirect' \+ k\]\)"
        $script:tplText | Should -Match 'var affectedCount = directCount \+ indirectCount'
        $script:tplText | Should -Match 'impact\.ChainTruncated'
        $script:tplText | Should -Match '(?m)^renderResolverCoverage\(\);'
        $script:tplText | Should -Match 'could not be followed'
        $script:tplText | Should -Match 'still reported in full'
    }
}

Describe 'The solution mapping' {
    It 'is the script''s, until the weekly refresh moves to the module at cut-over' {
        $module = [System.IO.File]::ReadAllBytes((Join-Path $script:repoRoot 'Modules/iSOCDeployments/Resources/ClassicToDcr/solution-mapping.json'))
        $tools = [System.IO.File]::ReadAllBytes((Join-Path $script:repoRoot 'Tools/ClassicToDcr/data/solution-mapping.json'))
        [Convert]::ToBase64String($module) | Should -BeExactly ([Convert]::ToBase64String($tools)) -Because 'a refresh of Tools/ClassicToDcr/data/solution-mapping.json is copied to the module until the workflow writes the module''s'
    }
}
