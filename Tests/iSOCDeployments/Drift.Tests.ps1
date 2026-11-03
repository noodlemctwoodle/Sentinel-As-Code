#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for Compare-iSOCContent, Sync-iSOCContent and
    Export-iSOCDriftReport, and for parity with Tools/Test-SentinelRuleDrift.ps1.

.DESCRIPTION
    - The pieces, one case at a time, carried over from
      Tests/Test-SentinelRuleDrift.Tests.ps1 where the script had them: the
      field compare, the YAML rewrite, the line diff, the classification
      of a workspace rule, the file slug, the absorbed rule's YAML and its
      path, and the report.
    - The behaviour the module changes on purpose (MIGRATION.md edits E22
      to E24), each shown against the script: a query written back with its
      line breaks, case counted in a query and a name, excluded sources
      skipped instead of exported again as orphans, and a report that says
      what it did and carries no resource id.
    - Parity: the script's functions are lifted out by AST and its own
      Invoke-Main is run with its REST calls stood in for, against a
      workspace built from this repository's analytics rules as deploy
      would send them, some edited "in the portal", with Content Hub rules,
      orphans, a Microsoft-managed rule and a deprecated one beside them.
      The module's three commands run against the same workspace on
      another copy of the repository. Both must count the same, report the
      same rules and fields, and leave the same files behind.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Drift.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Drift.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml

    The parity block goes when Tools/Test-SentinelRuleDrift.ps1 is removed
    at cut-over.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '_helpers/Parity.psm1') -Force
    Import-Module powershell-yaml -ErrorAction Stop
    $script:workspacePath = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/ws'
    $script:fixtureRule = Join-Path $script:repoRoot 'Content/AnalyticalRules/AzureActivity/AzureVmRunCommandExecutionDetectionRule.yaml'

    $script:context = InModuleScope iSOCDeployments -Parameters @{ W = $script:workspacePath } {
        param($W)
        New-iSOCContext -Value @{
            TenantId = 't'; SubscriptionId = '00000000-0000-0000-0000-000000000000'; ResourceGroup = 'rg'; WorkspaceName = 'ws'
            WorkspaceResourceId = $W; WorkspaceId = 'c'; Region = 'uksouth'; PlaybookResourceGroup = 'rg'; Environment = 'AzureCloud'
            IsGov = $false; ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'a'
        }
    }

    function Invoke-InModule {
        param([scriptblock] $ScriptBlock, [hashtable] $Parameters = @{})
        InModuleScope iSOCDeployments -ScriptBlock $ScriptBlock -Parameters $Parameters
    }
    function Get-RuleType { Invoke-InModule { Get-iSOCContentTypeDefinition -Name AnalyticsRule } }

    # A workspace rule as the API returns it.
    function New-WorkspaceRule {
        param([string] $Name, [string] $Kind = 'Scheduled', [hashtable] $Properties = @{})
        $base = [ordered]@{
            displayName = "Rule $Name"; description = 'A portal rule.'; severity = 'Medium'; enabled = $true
            query = "SigninLogs`n| where ResultType != 0"
        }
        if ($Kind -eq 'Scheduled') {
            $base.queryFrequency = 'PT1H'; $base.queryPeriod = 'PT1H'; $base.triggerOperator = 'GreaterThan'; $base.triggerThreshold = 0
        }
        foreach ($key in $Properties.Keys) { $base[$key] = $Properties[$key] }
        [pscustomobject]@{
            id         = "$($script:workspacePath)/providers/Microsoft.SecurityInsights/alertRules/$Name"
            name       = $Name
            type       = 'Microsoft.SecurityInsights/alertRules'
            kind       = $Kind
            properties = [pscustomobject]$base
        } | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    }
    function Compare-Body {
        param([object] $Expected, [object] $Actual)
        @(Invoke-InModule { param($T, $E, $A) Compare-iSOCContentBody -ContentType $T -Expected $E -Actual $A } @{ T = (Get-RuleType); E = $Expected; A = $Actual })
    }
    function New-ExpectedBody {
        param([string] $Kind = 'Scheduled', [hashtable] $Properties = @{})
        $rule = New-WorkspaceRule -Name 'r' -Kind $Kind -Properties $Properties
        @{ kind = $Kind; properties = $rule.properties }
    }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Compare-iSOCContentBody on analytics rules' {
    It 'finds nothing when the workspace matches' {
        $actual = New-WorkspaceRule -Name 'r'
        Compare-Body (New-ExpectedBody) @{ kind = 'Scheduled'; properties = $actual.properties } | Should -BeNullOrEmpty
    }

    It 'finds a change to <Field>' -ForEach @(
        @{ Field = 'severity'; Change = @{ severity = 'High' } }
        @{ Field = 'query'; Change = @{ query = 'SigninLogs | take 5' } }
        @{ Field = 'triggerThreshold'; Change = @{ triggerThreshold = 5 } }
        @{ Field = 'displayName'; Change = @{ displayName = 'Renamed in the portal' } }
        @{ Field = 'queryFrequency'; Change = @{ queryFrequency = 'PT2H' } }
        @{ Field = 'triggerOperator'; Change = @{ triggerOperator = 'LessThan' } }
    ) {
        $actual = New-WorkspaceRule -Name 'r' -Properties $Change
        $diff = Compare-Body (New-ExpectedBody) @{ kind = 'Scheduled'; properties = $actual.properties }
        @($diff.Field) | Should -Be @($Field)
        $diff[0].Path | Should -BeExactly "properties.$Field"
    }

    It 'lists every changed field in the script''s order, with the values as each side has them' {
        $actual = New-WorkspaceRule -Name 'r' -Properties @{ severity = 'High'; query = "SigninLogs`n| take 5"; triggerThreshold = 5 }
        $diff = Compare-Body (New-ExpectedBody) @{ kind = 'Scheduled'; properties = $actual.properties }
        @($diff.Field) | Should -Be @('query', 'triggerThreshold', 'severity')
        $diff[0].Deployed | Should -BeExactly "SigninLogs`n| take 5"
        $diff[0].Expected | Should -BeExactly "SigninLogs`n| where ResultType != 0"
    }

    It 'does not compare enabled' {
        $actual = New-WorkspaceRule -Name 'r' -Properties @{ enabled = $false }
        Compare-Body (New-ExpectedBody) @{ kind = 'Scheduled'; properties = $actual.properties } | Should -BeNullOrEmpty
    }

    It 'ignores the case of <Field> and how a duration is spelt' -ForEach @(
        @{ Field = 'severity'; Change = @{ severity = 'medium' } }
        @{ Field = 'triggerOperator'; Change = @{ triggerOperator = 'greaterthan' } }
        @{ Field = 'queryFrequency'; Change = @{ queryFrequency = 'PT60M' } }
    ) {
        $actual = New-WorkspaceRule -Name 'r' -Properties $Change
        Compare-Body (New-ExpectedBody) @{ kind = 'Scheduled'; properties = $actual.properties } | Should -BeNullOrEmpty
    }

    It 'ignores whitespace in a query, but not case (MIGRATION.md edit E22)' {
        $spaced = New-WorkspaceRule -Name 'r' -Properties @{ query = "SigninLogs   | where ResultType  !=  0`n" }
        Compare-Body (New-ExpectedBody) @{ kind = 'Scheduled'; properties = $spaced.properties } | Should -BeNullOrEmpty
        $cased = New-WorkspaceRule -Name 'r' -Properties @{ query = "signinlogs`n| where ResultType != 0" }
        @((Compare-Body (New-ExpectedBody) @{ kind = 'Scheduled'; properties = $cased.properties }).Field) | Should -Be @('query')
        $renamed = New-WorkspaceRule -Name 'r' -Properties @{ displayName = 'rule x' }
        @((Compare-Body (New-ExpectedBody) @{ kind = 'Scheduled'; properties = $renamed.properties }).Field) | Should -Be @('displayName')
    }

    It 'compares only the query, severity and name of an NRT rule' {
        $actual = New-WorkspaceRule -Name 'r' -Kind NRT -Properties @{ queryFrequency = 'PT5M'; severity = 'Low' }
        $expected = New-ExpectedBody -Kind NRT
        $expected.properties | Add-Member -NotePropertyName queryFrequency -NotePropertyValue 'PT1H' -Force
        @((Compare-Body $expected @{ kind = 'NRT'; properties = $actual.properties }).Field) | Should -Be @('severity')
    }

    It 'does not compare a field the repository leaves unset' {
        $expected = New-ExpectedBody
        $expected.properties.PSObject.Properties.Remove('severity')
        $actual = New-WorkspaceRule -Name 'r' -Properties @{ severity = 'High' }
        Compare-Body $expected @{ kind = 'Scheduled'; properties = $actual.properties } | Should -BeNullOrEmpty
    }
}

Describe 'Update-iSOCAnalyticsRuleYaml' {
    BeforeEach {
        $script:tmp = Join-Path $TestDrive "rule-$([guid]::NewGuid()).yaml"
        Copy-Item -LiteralPath $script:fixtureRule -Destination $script:tmp
        function Update-Rule { param([object[]] $Modification) Invoke-InModule { param($P, $M) Update-iSOCAnalyticsRuleYaml -Path $P -Modification $M } @{ P = $script:tmp; M = $Modification } }
    }

    It 'rewrites <Field> on its own line' -ForEach @(
        @{ Field = 'severity'; Value = 'High'; Line = 'severity: High' }
        @{ Field = 'triggerThreshold'; Value = 7; Line = 'triggerThreshold: 7' }
        @{ Field = 'triggerOperator'; Value = 'LessThan'; Line = 'triggerOperator: lt' }
        @{ Field = 'queryFrequency'; Value = 'PT2H'; Line = 'queryFrequency: PT2H' }
        @{ Field = 'queryPeriod'; Value = 'P1D'; Line = 'queryPeriod: P1D' }
        @{ Field = 'displayName'; Value = 'Renamed: in the portal'; Line = "name: 'Renamed: in the portal'" }
    ) {
        Update-Rule @([pscustomobject]@{ Field = $Field; Deployed = $Value; Expected = 'x' }) | Should -BeTrue
        (Get-Content -LiteralPath $script:tmp) | Should -Contain $Line
    }

    It 'replaces the query block with the workspace''s query, line breaks kept, and leaves what follows (MIGRATION.md edit E22)' {
        Update-Rule @([pscustomobject]@{ Field = 'query'; Deployed = "AzureActivity`n| where X has `"`$left`"`n| take 100`n"; Expected = 'x' }) | Should -BeTrue
        $text = Get-Content -LiteralPath $script:tmp -Raw
        $text | Should -BeLike "*query: |`n  AzureActivity`n  | where X has `"`$left`"`n  | take 100`nentityMappings:*"
        $text | Should -Not -Match 'runCommand'
        foreach ($key in 'entityMappings', 'eventGroupingSettings', 'incidentConfiguration', 'version', 'tags') { $text | Should -Match "(?m)^${key}:" }
        $text | Should -Match '(?m)^kind:\s+Scheduled'
        (ConvertFrom-Yaml $text)['query'] | Should -BeExactly "AzureActivity`n| where X has `"`$left`"`n| take 100`n"
    }

    It 'leaves every other field as it was and raises the patch version' {
        $before = Get-Content -LiteralPath $script:tmp -Raw
        Update-Rule @([pscustomobject]@{ Field = 'severity'; Deployed = 'High'; Expected = 'Medium' }) | Out-Null
        $after = Get-Content -LiteralPath $script:tmp -Raw
        $version = [regex]::Match($before, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)')
        $after | Should -Match "(?m)^version: $($version.Groups[1].Value)\.$($version.Groups[2].Value)\.$([int]$version.Groups[3].Value + 1)\b"
        ($after -replace '(?m)^(severity|version):.*$', '') | Should -BeExactly ($before -replace '(?m)^(severity|version):.*$', '')
    }

    It 'returns $false, and changes nothing, for a field the file has no line for' {
        $before = Get-Content -LiteralPath $script:tmp -Raw
        Update-Rule @([pscustomobject]@{ Field = 'kind'; Deployed = 'NRT'; Expected = 'Scheduled' }) | Should -BeFalse
        Get-Content -LiteralPath $script:tmp -Raw | Should -BeExactly $before
    }

    It 'keeps CRLF line endings, and writes no byte order mark' {
        $crlf = (Get-Content -LiteralPath $script:tmp -Raw) -replace "`r?`n", "`r`n"
        [System.IO.File]::WriteAllText($script:tmp, $crlf)
        Update-Rule @([pscustomobject]@{ Field = 'severity'; Deployed = 'Low'; Expected = 'Medium' }) | Should -BeTrue
        $bytes = [System.IO.File]::ReadAllBytes($script:tmp)
        $bytes[0] | Should -Not -Be 0xEF
        [System.Text.Encoding]::UTF8.GetString($bytes) | Should -BeLike "*`r`nseverity: Low`r`n*"
    }
}

Describe 'Get-iSOCLineDiff' {
    It '<Case>' -ForEach @(
        @{ Case = 'marks identical lines as context'; Before = "a`nb"; After = "a`nb"; Expected = "  a`n  b" }
        @{ Case = 'marks an added line +'; Before = "a"; After = "a`nb"; Expected = "  a`n+ b" }
        @{ Case = 'marks a removed line -'; Before = "a`nb"; After = "a"; Expected = "  a`n- b" }
        @{ Case = 'shows a changed line as an addition and a removal, in place'; Before = "a`nb`nc"; After = "a`nX`nc"; Expected = "  a`n+ X`n- b`n  c" }
        @{ Case = 'handles an empty before'; Before = ''; After = 'a'; Expected = "+ a`n- " }
        @{ Case = 'handles an empty after'; Before = 'a'; After = ''; Expected = "+ `n- a" }
        @{ Case = 'counts case'; Before = 'Take 1'; After = 'take 1'; Expected = "+ take 1`n- Take 1" }
    ) {
        Invoke-InModule { param($B, $A) Get-iSOCLineDiff -Before $B -After $A } @{ B = $Before; A = $After } | Should -BeExactly $Expected
    }
}

Describe 'ConvertTo-iSOCFileSlug' {
    It 'turns <Value> into <Expected>' -ForEach @(
        @{ Value = 'Brute force:  Entra ID (sign-ins)'; Max = 80; Expected = 'Brute-force-Entra-ID-sign-ins' }
        @{ Value = '--Leading and trailing--'; Max = 80; Expected = 'Leading-and-trailing' }
        @{ Value = 'abcdefgh ijkl'; Max = 9; Expected = 'abcdefgh' }
        @{ Value = '!!!'; Max = 80; Expected = 'rule' }
    ) {
        Invoke-InModule { param($V, $M) ConvertTo-iSOCFileSlug -Value $V -MaxLength $M } @{ V = $Value; M = $Max } | Should -BeExactly $Expected
    }
}

Describe 'Absorbed rule files' {
    BeforeAll {
        $script:orphan = New-WorkspaceRule -Name '6F1C2A3B-0000-4000-8000-000000000001' -Properties @{
            displayName = 'Portal: odd name'; techniques = @('T1078', 'T1110'); subTechniques = @('T1110.003', 'T1078.004')
            tactics = @('InitialAccess'); query = "SigninLogs`n| take 1`n"
            entityMappings = @(@{ entityType = 'Account'; fieldMappings = @(@{ identifier = 'FullName'; columnName = 'UserPrincipalName' }) })
            incidentConfiguration = @{ createIncident = $true; groupingConfiguration = @{ enabled = $false; lookbackDuration = 'PT5H' } }
        }
        $script:orphanYaml = Invoke-InModule { param($R) ConvertTo-iSOCAnalyticsRuleYaml -WorkspaceItem $R -Provenance Orphan } @{ R = $script:orphan }
        $script:orphanParsed = ConvertFrom-Yaml $script:orphanYaml
    }

    It 'keeps the rule''s name, in lower case, as the file''s id' {
        $script:orphanParsed['id'] | Should -BeExactly '6f1c2a3b-0000-4000-8000-000000000001'
    }

    It 'writes the short trigger operator and the schedule of a Scheduled rule only' {
        $script:orphanParsed['triggerOperator'] | Should -BeExactly 'gt'
        $nrt = Invoke-InModule { param($R) ConvertTo-iSOCAnalyticsRuleYaml -WorkspaceItem $R -Provenance Orphan } @{ R = (New-WorkspaceRule -Name 'n' -Kind NRT) }
        $nrt | Should -Not -Match '(?m)^(queryFrequency|queryPeriod|triggerOperator|triggerThreshold):'
    }

    It 'writes the query as a block, each line indented two spaces' {
        $script:orphanYaml | Should -BeLike "*query: |`n  SigninLogs`n  | take 1`n*"
    }

    It 'lists techniques and sub-techniques as relevantTechniques, each sub-technique after its parent' {
        @($script:orphanParsed['relevantTechniques']) | Should -Be @('T1078', 'T1078.004', 'T1110', 'T1110.003')
    }

    It 'tags where it came from, and starts at version 1.0.0' {
        @($script:orphanParsed['tags']) | Should -Be @('Sentinel-As-Code', 'Custom', 'AbsorbedFromPortal-Orphan')
        $script:orphanParsed['version'] | Should -BeExactly '1.0.0'
        $hub = ConvertFrom-Yaml (Invoke-InModule { param($R) ConvertTo-iSOCAnalyticsRuleYaml -WorkspaceItem $R -Provenance ContentHub -SolutionName 'Azure: Activity' } @{ R = $script:orphan })
        @($hub['tags'])[-1] | Should -BeExactly 'Azure: Activity'
    }

    It 'parses, and passes the module''s own rule validation' {
        $file = Join-Path $TestDrive 'Content/AnalyticalRules/Absorbed.yaml'
        New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force | Out-Null
        Set-Content -LiteralPath $file -Value $script:orphanYaml -NoNewline
        $issues = Invoke-InModule {
            param($R)
            $type = Get-iSOCContentTypeDefinition -Name AnalyticsRule
            $item = @(Read-iSOCAnalyticsRuleRepo -RepoPath $R -ContentType $type)[0]
            @(Test-iSOCAnalyticsRule -Item $item)
        } @{ R = $TestDrive }
        $issues | Should -BeNullOrEmpty
    }

    It 'goes to <Expected>' -ForEach @(
        @{ Provenance = 'ContentHub'; Solution = 'Microsoft Defender XDR'; Expected = 'Content/AnalyticalRules/AbsorbedFromPortal/ContentHub/Microsoft-Defender-XDR/Portal-odd-name.yaml' }
        @{ Provenance = 'ContentHub'; Solution = $null; Expected = 'Content/AnalyticalRules/AbsorbedFromPortal/ContentHub/Unattributed/Portal-odd-name.yaml' }
        @{ Provenance = 'Orphan'; Solution = $null; Expected = 'Content/AnalyticalRules/AbsorbedFromPortal/Orphans/Portal-odd-name.yaml' }
    ) {
        Invoke-InModule { param($R, $P, $S) Get-iSOCAnalyticsRuleRepoPath -WorkspaceItem $R -Provenance $P -SolutionName $S } @{ R = $script:orphan; P = $Provenance; S = $Solution } | Should -BeExactly $Expected
    }

    It 'is created, then left unchanged, then updated' {
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $save = { param($Text) Invoke-InModule { param($R, $T) Save-iSOCRepoFile -RepoPath $R -RelativePath 'Content/A/b.yaml' -Content $T } @{ R = $repo; T = $Text } }
        & $save "a`n" | Should -BeExactly 'Created'
        & $save "a`n" | Should -BeExactly 'Unchanged'
        & $save "A`n" | Should -BeExactly 'Updated'
    }
}

Describe 'Get-iSOCAnalyticsRuleSource' {
    BeforeAll {
        $script:classifyRepo = Join-Path $TestDrive 'classify'
        New-Item -ItemType Directory -Path (Join-Path $script:classifyRepo 'Content/AnalyticalRules') -Force | Out-Null
        Copy-Item -LiteralPath $script:fixtureRule -Destination (Join-Path $script:classifyRepo 'Content/AnalyticalRules/Repo.yaml')
        Set-Content -LiteralPath (Join-Path $script:classifyRepo 'Content/AnalyticalRules/Invalid.yaml') -Value "id: 9d9d9d9d-0000-4000-8000-000000000009`nname: No kind`nseverity: Low`nquery: T"
        $script:repoRuleId = '303E7728-B654-467C-A509-00211879716C'
        function Get-Source {
            param([psobject] $Rule, [hashtable] $Options = @{})
            Invoke-InModule {
                param($C, $R, $O, $Rule)
                $run = New-iSOCDriftRun -Context $C -RepoPath $R -Options $O
                Get-iSOCAnalyticsRuleSource -Run $run -ContentType (Get-iSOCContentTypeDefinition -Name AnalyticsRule) -WorkspaceItem $Rule
            } @{ C = $script:context; R = $script:classifyRepo; O = $Options; Rule = $Rule }
        }
    }

    BeforeEach {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
            if ($Path -like '*/contentTemplates*') {
                return [pscustomobject]@{ name = 'tmpl-1'; properties = [pscustomobject]@{ contentId = 'tmpl-1'; packageId = 'pkg-1'; mainTemplate = [pscustomobject]@{ resources = @([pscustomobject]@{ type = 'Microsoft.OperationalInsights/workspaces/providers/alertRules'; kind = 'Scheduled'; properties = [pscustomobject]@{ displayName = 'T'; severity = 'High' } }) } } }
            }
            if ($Path -like '*/contentProductPackages') { return [pscustomobject]@{ name = 'p'; properties = [pscustomobject]@{ contentId = 'pkg-1'; displayName = 'Fixture Solution' } } }
        }
    }

    It 'is <Expected> for <Case>' -ForEach @(
        @{ Case = 'a rule linked to a known template'; Name = 'a'; Properties = @{ alertRuleTemplateName = 'tmpl-1' }; Options = @{}; Expected = 'ContentHub/' }
        @{ Case = 'a rule whose id is a repository rule''s, in any case'; Name = '303E7728-B654-467C-A509-00211879716C'; Properties = @{}; Options = @{}; Expected = 'Custom/' }
        @{ Case = 'a repository rule also linked to a template'; Name = '303e7728-b654-467c-a509-00211879716c'; Properties = @{ alertRuleTemplateName = 'tmpl-1' }; Options = @{}; Expected = 'Custom/' }
        @{ Case = 'a rule linked to nothing'; Name = 'b'; Properties = @{}; Options = @{}; Expected = 'Orphan/PortalOnly' }
        @{ Case = 'a rule with an empty template link'; Name = 'b'; Properties = @{ alertRuleTemplateName = '' }; Options = @{}; Expected = 'Orphan/PortalOnly' }
        @{ Case = 'a rule linked to a template the workspace does not have'; Name = 'b'; Properties = @{ alertRuleTemplateName = 'gone' }; Options = @{}; Expected = 'Orphan/PortalOnly' }
        @{ Case = 'a severity not asked for'; Name = 'b'; Properties = @{ severity = 'Low' }; Options = @{ Severity = @('High') }; Expected = '/Skipped' }
        @{ Case = 'a deprecated rule'; Name = 'b'; Properties = @{ displayName = '[Deprecated] Old' }; Options = @{}; Expected = '/Skipped' }
        @{ Case = 'a Content Hub rule of a solution not asked for'; Name = 'a'; Properties = @{ alertRuleTemplateName = 'tmpl-1' }; Options = @{ Solution = @('Other') }; Expected = 'ContentHub/Skipped' }
        @{ Case = 'excluded Content Hub rules (MIGRATION.md edit E23)'; Name = 'a'; Properties = @{ alertRuleTemplateName = 'tmpl-1' }; Options = @{ ExcludeSource = @('ContentHub') }; Expected = 'ContentHub/Skipped' }
        @{ Case = 'excluded Custom rules (MIGRATION.md edit E23)'; Name = '303e7728-b654-467c-a509-00211879716c'; Properties = @{}; Options = @{ ExcludeSource = @('Custom') }; Expected = 'Custom/Skipped' }
        @{ Case = 'excluded orphans'; Name = 'b'; Properties = @{}; Options = @{ ExcludeSource = @('Orphan') }; Expected = 'Orphan/Skipped' }
        @{ Case = 'a repository rule that does not validate'; Name = '9d9d9d9d-0000-4000-8000-000000000009'; Properties = @{}; Options = @{}; Expected = 'Custom/Skipped' }
    ) {
        $source = Get-Source -Rule (New-WorkspaceRule -Name $Name -Properties $Properties) -Options $Options
        "$($source.Source)/$($source.State)" | Should -BeExactly $Expected
    }

    It 'is Managed for a <Kind> rule' -ForEach @(@{ Kind = 'Fusion' }, @{ Kind = 'MLBehaviorAnalytics' }, @{ Kind = 'ThreatIntelligence' }, @{ Kind = 'MicrosoftSecurityIncidentCreation' }) {
        (Get-Source -Rule (New-WorkspaceRule -Name 'm' -Kind $Kind)).State | Should -BeExactly 'Managed'
    }

    It 'gives a Content Hub rule its template, solution and body' {
        $source = Get-Source -Rule (New-WorkspaceRule -Name 'a' -Properties @{ alertRuleTemplateName = 'tmpl-1' })
        $source.SourceRef | Should -BeExactly 'tmpl-1'
        $source.Solution | Should -BeExactly 'Fixture Solution'
        $source.Expected.properties.severity | Should -BeExactly 'High'
    }

    It 'gives a Custom rule its file and the body deploy would send' {
        $source = Get-Source -Rule (New-WorkspaceRule -Name $script:repoRuleId)
        $source.SourceRef | Should -BeExactly 'Content/AnalyticalRules/Repo.yaml'
        $source.SourcePath | Should -BeExactly (Join-Path $script:classifyRepo 'Content/AnalyticalRules/Repo.yaml')
        $source.Expected.properties.triggerOperator | Should -BeExactly 'GreaterThan'
    }

    It 'reads the alert rules with the preview api-version, which keeps sub-techniques' {
        Invoke-InModule { param($C) Read-iSOCAnalyticsRuleWorkspace -Context $C -ContentType (Get-iSOCContentTypeDefinition -Name AnalyticsRule) } @{ C = $script:context } | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Invoke-iSOCRestRequest -ParameterFilter { $Path -like '*/alertRules' -and $ApiVersion -eq '2025-07-01-preview' } -Times 1 -Exactly
    }
}

Describe 'Parity with Tools/Test-SentinelRuleDrift.ps1' {
    BeforeAll {
        Import-Module (Join-Path $script:repoRoot 'Tests/_helpers/Import-ScriptFunctions.psm1') -Force
        Import-ScriptFunctions -Path (Join-Path $script:repoRoot 'Tools/Test-SentinelRuleDrift.ps1')
        function Write-PipelineMessage { param($Message, $Level) }
        function Connect-AzureEnvironment {
            param($ResourceGroup, $Workspace, $Region, $SubscriptionId, [switch] $IsGov)
            @{ SubscriptionId = '00000000-0000-0000-0000-000000000000'; ServerUrl = 'https://management.azure.com'; BaseUri = "https://management.azure.com$($script:workspacePath)"; WorkspaceResourceId = $script:workspacePath; WorkspaceId = 'c'; AuthHeader = @{} }
        }
        function Invoke-SentinelApi {
            param($Uri, $Method, $Headers, $Body)
            [pscustomobject]@{ value = @(Get-StandInAnswer -Path $Uri) }
        }
        $script:SentinelApiVersion = '2025-09-01'
        $script:AlertRuleApiVersion = '2025-07-01-preview'
        $script:ManagedRuleKinds = @('Fusion', 'MicrosoftSecurityIncidentCreation', 'MLBehaviorAnalytics', 'ThreatIntelligence')
        $script:ResourceGroup = 'rg'
        $script:Workspace = 'ws'
        $script:Region = 'uksouth'

        # The stand-in workspace: every repository rule as deploy sends it,
        # with the API's spelling of its durations; some edited in the
        # portal; and the rules the repository does not have.
        $script:mutated = [ordered]@{}
        $repoItems = @(Invoke-InModule {
                param($R)
                $type = Get-iSOCContentTypeDefinition -Name AnalyticsRule
                foreach ($item in Read-iSOCAnalyticsRuleRepo -RepoPath $R -ContentType $type) {
                    if (-not $item.ParseError -and @(Test-iSOCAnalyticsRule -Item $item).Count -eq 0) {
                        [pscustomobject]@{ Item = $item; Body = (ConvertTo-iSOCAnalyticsRuleRequest -Item $item).Body }
                    }
                }
            } @{ R = $script:repoRoot })
        $deployed = [System.Collections.Generic.List[object]]::new()
        $scheduledIndex = 0
        $edits = @(
            @{ severity = 'Informational' }
            @{ query = 'APPEND' }
            @{ triggerThreshold = 'PLUS5' }
            @{ displayName = 'APPEND' }
            @{ queryFrequency = 'P2D' }
            @{ triggerOperator = 'LessThan' }
            @{ severity = 'Low'; query = 'APPEND' }
        )
        foreach ($entry in $repoItems) {
            $props = [ordered]@{}
            foreach ($key in $entry.Body.properties.Keys) { $props[$key] = $entry.Body.properties[$key] }
            foreach ($duration in 'queryFrequency', 'queryPeriod', 'suppressionDuration') {
                if ($props.Contains($duration) -and $props[$duration]) {
                    try { $props[$duration] = [System.Xml.XmlConvert]::ToString([System.Xml.XmlConvert]::ToTimeSpan([string]$props[$duration])) }
                    catch { Write-Verbose "Left $duration of $($entry.Item.RelativePath) as the file spells it: $($_.Exception.Message)" }
                }
            }
            $isCommunity = $entry.Item.Source -eq 'Community'
            $edit = $null
            if ($entry.Body.kind -eq 'Scheduled' -and -not $isCommunity -and $scheduledIndex -lt $edits.Count -and $entry.Item.RelativePath -notlike '*AzureVmRunCommand*') {
                $edit = $edits[$scheduledIndex]; $scheduledIndex++
            }
            elseif ($entry.Body.kind -eq 'NRT' -and -not $script:mutated.Contains('nrt')) { $edit = @{ query = 'APPEND' }; $script:mutated['nrt'] = $entry.Item.RelativePath }
            elseif ($isCommunity -and -not $script:mutated.Contains('community')) { $edit = @{ severity = 'High' }; $script:mutated['community'] = $entry.Item.RelativePath }
            if ($edit) {
                foreach ($key in $edit.Keys) {
                    $props[$key] = switch ($edit[$key]) {
                        'APPEND' { if ($key -eq 'query') { "$($props.query)`n| where TimeGenerated > ago(1d)" } else { "$($props[$key]) (edited in the portal)" } }
                        'PLUS5' { [int]$props[$key] + 5 }
                        default {
                            $alternative = @{ severity = 'Medium'; triggerOperator = 'GreaterThan'; queryFrequency = 'P3D' }
                            if ([string]$props[$key] -eq $_) { $alternative[$key] } else { $_ }
                        }
                    }
                }
                $script:mutated[$entry.Item.RelativePath] = @($edit.Keys)
            }
            $deployed.Add([ordered]@{ id = "$($script:workspacePath)/providers/Microsoft.SecurityInsights/alertRules/$($entry.Item.Data['id'])"; name = [string]$entry.Item.Data['id']; kind = $entry.Body.kind; properties = $props })
        }
        $absorbed = $deployed | Where-Object { $_.properties.displayName -like 'Azure VM Run Command*' } | Select-Object -First 1
        $absorbed.properties.alertRuleTemplateName = 'tmpl-a1'

        $templateRule = { param($Display, $Severity, $Query, [string] $Kind = 'Scheduled', [hashtable] $Extra = @{})
            $p = [ordered]@{ displayName = $Display; description = 'From Content Hub.'; severity = $Severity; query = $Query; enabled = $true; tactics = @('Execution'); techniques = @('T1059'); subTechniques = @('T1059.001') }
            if ($Kind -eq 'Scheduled') { $p.queryFrequency = 'PT24H'; $p.queryPeriod = 'PT24H'; $p.triggerOperator = 'GreaterThan'; $p.triggerThreshold = 0 }
            foreach ($k in $Extra.Keys) { $p[$k] = $Extra[$k] }
            $p
        }
        $templates = @(
            @{ id = 'tmpl-a1'; pkg = 'pkg.alpha'; type = 'Microsoft.OperationalInsights/workspaces/providers/alertRules'; kind = 'Scheduled'; props = (& $templateRule 'Alpha clean' 'High' "SecurityEvent`n| where EventID == 4625") }
            @{ id = 'tmpl-a2'; pkg = 'pkg.alpha'; type = 'Microsoft.SecurityInsights/AlertRuleTemplates'; kind = 'Scheduled'; props = (& $templateRule 'Alpha query edited' 'Medium' "SecurityEvent`n| where EventID == 4720") }
            @{ id = 'tmpl-b1'; pkg = 'pkg.bravo'; type = 'Microsoft.OperationalInsights/workspaces/providers/alertRules'; kind = 'Scheduled'; props = (& $templateRule 'Bravo severity edited' 'Low' 'AuditLogs | take 1') }
            @{ id = 'tmpl-b2'; pkg = 'pkg.bravo'; type = 'Microsoft.OperationalInsights/workspaces/providers/alertRules'; kind = 'NRT'; props = (& $templateRule 'Bravo NRT clean' 'Medium' 'AuditLogs | take 2' 'NRT') }
            @{ id = 'tmpl-c1'; pkg = 'pkg.unknown'; type = 'Microsoft.OperationalInsights/workspaces/providers/alertRules'; kind = 'Scheduled'; props = (& $templateRule 'Unattributed threshold edited' 'High' 'Syslog | take 1') }
            @{ id = 'tmpl-x'; pkg = 'pkg.alpha'; type = $null; kind = $null; props = $null }
        )
        $script:standIn = @{
            Templates = @(foreach ($t in $templates) {
                    $main = if ($t.props) { [ordered]@{ resources = @([ordered]@{ type = $t.type; name = $t.id; kind = $t.kind; properties = $t.props }, [ordered]@{ type = 'Microsoft.OperationalInsights/workspaces/providers/metadata'; properties = [ordered]@{ version = '1.0.0' } }) } } else { $null }
                    [ordered]@{ name = $t.id; properties = [ordered]@{ contentId = $t.id; contentKind = 'AnalyticsRule'; packageId = $t.pkg; mainTemplate = $main } }
                })
            Catalogue = @([ordered]@{ name = 'pkg.alpha'; properties = [ordered]@{ contentId = 'pkg.alpha'; displayName = 'Fixture Alpha' } }, [ordered]@{ name = 'pkg.bravo'; properties = [ordered]@{ contentId = 'pkg.bravo'; displayName = 'Fixture Bravo' } })
        }
        $hubRule = { param($Name, $Template, [hashtable] $Change = @{})
            $source = ($templates | Where-Object { $_.id -eq $Template }).props
            $p = [ordered]@{}
            if ($source) { foreach ($k in $source.Keys) { $p[$k] = $source[$k] } } else { $p = & $templateRule "Linked $Name" 'Medium' 'T | take 1' }
            foreach ($k in 'queryFrequency', 'queryPeriod') { if ($p.Contains($k)) { $p[$k] = 'P1D' } }
            foreach ($k in $Change.Keys) { $p[$k] = $Change[$k] }
            $p.alertRuleTemplateName = $Template
            $kind = if ($p.Contains('queryFrequency')) { 'Scheduled' } else { 'NRT' }
            [ordered]@{ id = "$($script:workspacePath)/providers/Microsoft.SecurityInsights/alertRules/$Name"; name = $Name; kind = $kind; properties = $p }
        }
        $deployed.Add((& $hubRule 'a1a1a1a1-0000-4000-8000-000000000001' 'tmpl-a1'))
        $deployed.Add((& $hubRule 'a2a2a2a2-0000-4000-8000-000000000002' 'tmpl-a2' @{ query = "SecurityEvent`n| where EventID in (4720, 4722)" }))
        $deployed.Add((& $hubRule 'b1b1b1b1-0000-4000-8000-000000000003' 'tmpl-b1' @{ severity = 'High' }))
        $deployed.Add((& $hubRule 'b2b2b2b2-0000-4000-8000-000000000004' 'tmpl-b2'))
        $deployed.Add((& $hubRule 'c1c1c1c1-0000-4000-8000-000000000005' 'tmpl-c1' @{ triggerThreshold = 3 }))
        $deployed.Add((& $hubRule 'd1d1d1d1-0000-4000-8000-000000000006' 'tmpl-x'))
        $deployed.Add((& $hubRule 'e1e1e1e1-0000-4000-8000-000000000007' 'tmpl-gone'))
        $orphanProps = & $templateRule 'Portal orphan: brute force' 'High' "SigninLogs`n| where ResultType == 50126`n| summarize count() by UserPrincipalName" 'Scheduled' @{
            entityMappings = @([ordered]@{ entityType = 'Account'; fieldMappings = @([ordered]@{ identifier = 'FullName'; columnName = 'UserPrincipalName' }) })
            incidentConfiguration = [ordered]@{ createIncident = $true; groupingConfiguration = [ordered]@{ enabled = $false; lookbackDuration = 'PT5H'; matchingMethod = 'AllEntities' } }
            eventGroupingSettings = [ordered]@{ aggregationKind = 'SingleAlert' }
        }
        $deployed.Add([ordered]@{ id = "$($script:workspacePath)/providers/Microsoft.SecurityInsights/alertRules/0a0a0a0a-0000-4000-8000-000000000008"; name = '0a0a0a0a-0000-4000-8000-000000000008'; kind = 'Scheduled'; properties = $orphanProps })
        $deployed.Add([ordered]@{ id = "$($script:workspacePath)/providers/Microsoft.SecurityInsights/alertRules/0b0b0b0b-0000-4000-8000-000000000009"; name = '0b0b0b0b-0000-4000-8000-000000000009'; kind = 'NRT'; properties = (& $templateRule 'Portal NRT orphan' 'Low' 'OfficeActivity | take 1' 'NRT') })
        $deployed.Add([ordered]@{ id = "$($script:workspacePath)/providers/Microsoft.SecurityInsights/alertRules/BuiltInFusion"; name = 'BuiltInFusion'; kind = 'Fusion'; properties = [ordered]@{ displayName = 'Advanced Multistage Attack Detection'; enabled = $true; alertRuleTemplateName = 'f71aba3d' } })
        $deployed.Add([ordered]@{ id = "$($script:workspacePath)/providers/Microsoft.SecurityInsights/alertRules/0c0c0c0c-0000-4000-8000-000000000010"; name = '0c0c0c0c-0000-4000-8000-000000000010'; kind = 'Scheduled'; properties = (& $templateRule '[Deprecated] Portal old rule' 'Medium' 'T | take 1') })
        $script:standIn.Rules = @($deployed)
        $script:standInJson = $script:standIn | ConvertTo-Json -Depth 30

        function Get-StandInAnswer {
            param([string] $Path)
            $data = $script:standInJson | ConvertFrom-Json -Depth 30
            if ($Path -like '*/alertRules*') { return $data.Rules }
            if ($Path -like '*/contentTemplates*') { return $data.Templates }
            if ($Path -like '*/contentProductPackages*') { return $data.Catalogue }
        }

        function New-RepoCopy {
            $copy = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path (Join-Path $copy 'Content') -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:repoRoot 'Content/AnalyticalRules') -Destination (Join-Path $copy 'Content') -Recurse
            $copy
        }

        function Invoke-LegacyDrift {
            param([hashtable] $Setting = @{})
            $copy = New-RepoCopy
            $script:RepoPath = $copy
            $script:Solutions = if ($Setting.ContainsKey('Solution')) { $Setting.Solution } else { @() }
            $script:SeveritiesToInclude = if ($Setting.ContainsKey('Severity')) { $Setting.Severity } else { @('High', 'Medium', 'Low', 'Informational') }
            foreach ($name in 'SkipContentHub', 'SkipCustom', 'SkipOrphans', 'ReportOnly', 'FailOnDrift', 'IsGov', 'WhatIf') { Set-Variable -Scope Script -Name $name -Value ([bool]$Setting[$name]) }
            $script:SubscriptionId = $null
            Invoke-Main
            $copy
        }

        function Invoke-ModuleDrift {
            param([hashtable] $Setting = @{}, [switch] $NoSync)
            $copy = New-RepoCopy
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
            Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { Get-StandInAnswer -Path $Path }
            $parameters = @{ Context = $script:context; RepoPath = $copy }
            if ($Setting.ContainsKey('Solution')) { $parameters.Solution = $Setting.Solution }
            if ($Setting.ContainsKey('Severity')) { $parameters.Severity = $Setting.Severity }
            $exclude = @(foreach ($pair in @(@('SkipContentHub', 'ContentHub'), @('SkipCustom', 'Custom'), @('SkipOrphans', 'Orphan'))) { if ($Setting[$pair[0]]) { $pair[1] } })
            if ($exclude.Count -gt 0) { $parameters.ExcludeSource = $exclude }
            $drift = Compare-iSOCContent @parameters
            if (-not $NoSync) { $drift = $drift | Sync-iSOCContent }
            $drift | Export-iSOCDriftReport | Out-Null
            [pscustomobject]@{ Repo = $copy; Drift = $drift }
        }

        function Read-Report {
            param([string] $Repo)
            $file = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'reports') -Filter 'sentinel-drift-*.json' -ErrorAction SilentlyContinue)
            if ($file.Count -eq 0) { return $null }
            Get-Content -LiteralPath $file[0].FullName -Raw | ConvertFrom-Json -AsHashtable -Depth 30
        }

        # The forms the script compared and reported: the module reports
        # values as each side has them (MIGRATION.md edit E22).
        function ConvertTo-LegacyValue {
            param([string] $Field, $Value)
            if ($null -eq $Value) { return $null }
            switch ($Field) {
                'query' { return (Convert-QueryWhitespace ([string]$Value)) }
                { $_ -in 'queryFrequency', 'queryPeriod' } { return (ConvertTo-NormalisedDuration ([string]$Value)) }
                'triggerOperator' { return (Convert-TriggerOperator ([string]$Value)) }
                'severity' { return (Convert-Severity ([string]$Value)) }
                'triggerThreshold' { return [int]$Value }
            }
            [string]$Value
        }
        function Get-ComparableReport {
            param([System.Collections.IDictionary] $Report, [switch] $Module)
            $shape = {
                param($Entry)
                $copy = [ordered]@{}
                foreach ($key in $Entry.Keys) { if ($key -ne 'ruleId') { $copy[$key] = $Entry[$key] } }
                if ($copy.Contains('modifiedFields')) {
                    $copy.modifiedFields = @(foreach ($m in $copy.modifiedFields) {
                            [ordered]@{
                                field    = $m.field
                                deployed = if ($Module) { ConvertTo-LegacyValue $m.field $m.deployed } else { $m.deployed }
                                expected = if ($Module) { ConvertTo-LegacyValue $m.field $m.expected } else { $m.expected }
                            }
                        })
                }
                $copy
            }
            [ordered]@{
                summary = $Report.summary
                drifted = @($Report.drifted | Sort-Object { $_.ruleName } | ForEach-Object { & $shape $_ })
                orphans = @($Report.orphans | Sort-Object { $_.ruleName } | ForEach-Object { & $shape $_ })
            }
        }

        # Every file under Content/ that differs between a copy and the
        # repository, as relative path to text.
        function Get-ChangedFile {
            param([string] $Repo)
            $changed = [ordered]@{}
            foreach ($file in Get-ChildItem -LiteralPath (Join-Path $Repo 'Content') -Recurse -File | Sort-Object FullName) {
                $relative = [System.IO.Path]::GetRelativePath($Repo, $file.FullName).Replace('\', '/')
                $original = Join-Path $script:repoRoot $relative
                $text = Get-Content -LiteralPath $file.FullName -Raw
                if (-not (Test-Path -LiteralPath $original) -or (Get-Content -LiteralPath $original -Raw) -cne $text) { $changed[$relative] = $text }
            }
            $changed
        }
        function Remove-QueryBlock {
            param([string] $Text)
            [regex]::Replace($Text, '(?m)^query:[ \t]*\|[^\r\n]*\r?\n(?:[ \t][^\r\n]*\r?\n?)*?(?=^[A-Za-z][\w-]*:)', "query: QUERY`n")
        }
        function Assert-SameFile {
            param([string] $LegacyRepo, [string] $ModuleRepo)
            $old = Get-ChangedFile $LegacyRepo
            $new = Get-ChangedFile $ModuleRepo
            @($new.Keys) | Should -Be @($old.Keys)
            foreach ($path in $old.Keys) {
                if ($new[$path] -ceq $old[$path]) { continue }
                # Only the query may differ: the script wrote it collapsed.
                (Remove-QueryBlock $new[$path]) | Should -BeExactly (Remove-QueryBlock $old[$path]) -Because $path
                $newQuery = (ConvertFrom-Yaml $new[$path])['query']
                Convert-QueryWhitespace $newQuery | Should -BeExactly (Convert-QueryWhitespace (ConvertFrom-Yaml $old[$path])['query']) -Because $path
            }
        }
    }

    Context 'the defaults: compare, absorb and report' {
        BeforeAll {
            $script:legacyA = Invoke-LegacyDrift
            $script:moduleA = Invoke-ModuleDrift
            $script:legacyReportA = Read-Report $script:legacyA
            $script:moduleReportA = Read-Report $script:moduleA.Repo
        }

        It 'exercises every bucket' {
            $s = $script:legacyReportA.summary
            foreach ($bucket in 'contentHubClean', 'contentHubDrift', 'customClean', 'customDrift', 'orphan', 'managed', 'skipped') { $s[$bucket] | Should -BeGreaterThan 0 -Because $bucket }
            $s.customDrift | Should -Be (@($script:mutated.Keys | Where-Object { $_ -like 'Content/*' }).Count)
        }

        It 'counts the same' {
            ConvertTo-ParityJson $script:moduleReportA.summary | Should -BeExactly (ConvertTo-ParityJson $script:legacyReportA.summary)
        }

        It 'reports the same rules and changed fields' {
            $old = Get-ComparableReport $script:legacyReportA
            $new = Get-ComparableReport $script:moduleReportA -Module
            ConvertTo-ParityJson $new.drifted | Should -BeExactly (ConvertTo-ParityJson $old.drifted)
            ConvertTo-ParityJson $new.orphans | Should -BeExactly (ConvertTo-ParityJson $old.orphans)
        }

        It 'leaves the same files, the query written with its line breaks (MIGRATION.md edit E22)' {
            Assert-SameFile $script:legacyA $script:moduleA.Repo
            $queryEdited = @($script:moduleA.Drift.Items | Where-Object { $_.State -eq 'PortalEdit' -and $_.Modifications.Field -contains 'query' })[0]
            $legacyText = Get-Content -LiteralPath (Join-Path $script:legacyA $queryEdited.SourceRef) -Raw
            $moduleText = Get-Content -LiteralPath (Join-Path $script:moduleA.Repo $queryEdited.SourceRef) -Raw
            @((ConvertFrom-Yaml $legacyText)['query'].Trim() -split "`n").Count | Should -Be 1
            (ConvertFrom-Yaml $moduleText)['query'].TrimEnd() | Should -BeExactly ([string]$queryEdited.WorkspaceItem.properties.query).TrimEnd()
        }

        It 'writes no resource id, so no subscription id, into the report (MIGRATION.md edit E24)' {
            @($script:legacyReportA.drifted)[0].Contains('ruleId') | Should -BeTrue
            $files = Get-ChildItem -LiteralPath (Join-Path $script:moduleA.Repo 'reports') -File
            $files.Count | Should -Be 2
            foreach ($file in $files) { Get-Content -LiteralPath $file.FullName -Raw | Should -Not -Match '00000000-0000-0000-0000-000000000000' }
        }

        It 'says in the Markdown where each absorbed rule went (MIGRATION.md edit E24)' {
            $md = Get-Content -LiteralPath (Get-ChildItem -LiteralPath (Join-Path $script:moduleA.Repo 'reports') -Filter '*.md').FullName -Raw
            # Contains, not -BeLike: a backtick escapes in a wildcard.
            foreach ($text in @(
                    '## Custom Rule Drift (auto-synced into repo)'
                    '## Content Hub Drift (promoted to Custom rules)'
                    '- Absorbed as: `Content/AnalyticalRules/AbsorbedFromPortal/ContentHub/Fixture-Alpha/Alpha-query-edited.yaml` (created)'
                    '## Orphan Rules (absorbed into the repo)'
                    '`Content/AnalyticalRules/AbsorbedFromPortal/Orphans/Portal-orphan-brute-force.yaml` (created)'
                    "``````diff`n"
                    '+ | where TimeGenerated > ago(1d)'
                )) { $md.Contains($text) | Should -BeTrue -Because $text }
        }

        It 'finds nothing more when it runs again on what it absorbed' {
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
            Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { Get-StandInAnswer -Path $Path }
            $again = Compare-iSOCContent -Context $script:context -RepoPath $script:moduleA.Repo
            @($again.Items | Where-Object { $_.State -in 'PortalEdit', 'ContentHubCustomised', 'PortalOnly' }) | Should -BeNullOrEmpty
            $again.HasDrift | Should -BeFalse
        }
    }

    Context 'report only' {
        BeforeAll {
            $script:legacyB = Invoke-LegacyDrift -Setting @{ ReportOnly = $true }
            $script:moduleB = Invoke-ModuleDrift -NoSync
        }

        It 'changes no rule file' {
            (Get-ChangedFile $script:legacyB).Count | Should -Be 0
            (Get-ChangedFile $script:moduleB.Repo).Count | Should -Be 0
        }

        It 'reports the same' {
            $old = Get-ComparableReport (Read-Report $script:legacyB)
            $new = Get-ComparableReport (Read-Report $script:moduleB.Repo) -Module
            ConvertTo-ParityJson $new | Should -BeExactly (ConvertTo-ParityJson $old)
        }

        It 'says in the Markdown that nothing was written (MIGRATION.md edit E24)' {
            $md = Get-Content -LiteralPath (Get-ChildItem -LiteralPath (Join-Path $script:moduleB.Repo 'reports') -Filter '*.md').FullName -Raw
            $md | Should -BeLike '*## Custom Rule Drift (report only)*'
            $md | Should -BeLike '*## Content Hub Drift (report only)*'
            $md | Should -BeLike '*## Orphan Rules (report only; manual triage required)*'
        }
    }

    Context 'one solution and two severities' {
        BeforeAll {
            $setting = @{ Solution = @('Fixture Alpha'); Severity = @('High', 'Medium') }
            $script:legacyC = Invoke-LegacyDrift -Setting $setting
            $script:moduleC = Invoke-ModuleDrift -Setting $setting
        }

        It 'reports the same' {
            $old = Get-ComparableReport (Read-Report $script:legacyC)
            $new = Get-ComparableReport (Read-Report $script:moduleC.Repo) -Module
            ConvertTo-ParityJson $new | Should -BeExactly (ConvertTo-ParityJson $old)
        }

        It 'leaves the same files' { Assert-SameFile $script:legacyC $script:moduleC.Repo }
    }

    Context 'a source left out (MIGRATION.md edit E23)' {
        It 'skips Content Hub rules, where the script exported them again as orphans' {
            $legacy = Read-Report (Invoke-LegacyDrift -Setting @{ SkipContentHub = $true })
            $module = Invoke-ModuleDrift -Setting @{ SkipContentHub = $true }
            $linked = @($module.Drift.Items | Where-Object { $_.Source -eq 'ContentHub' })
            $linked.Count | Should -BeGreaterThan 0
            @($linked.State | Select-Object -Unique) | Should -Be @('Skipped')
            $legacy.summary.orphan | Should -Be ($module.Drift.Summary.orphan + $linked.Count)
            @($legacy.orphans.ruleName) | Should -Contain 'a2a2a2a2-0000-4000-8000-000000000002'
        }

        It 'skips repository rules, where the script exported every one of them again as an orphan' {
            $legacyRepo = Invoke-LegacyDrift -Setting @{ SkipCustom = $true }
            $module = Invoke-ModuleDrift -Setting @{ SkipCustom = $true }
            $governed = @($module.Drift.Items | Where-Object { $_.Source -eq 'Custom' })
            @($governed.State | Select-Object -Unique) | Should -Be @('Skipped')
            $legacyOrphanFiles = @((Get-ChangedFile $legacyRepo).Keys | Where-Object { $_ -like '*/Orphans/*' })
            $legacyOrphanFiles.Count | Should -BeGreaterThan 100
            @((Get-ChangedFile $module.Repo).Keys | Where-Object { $_ -like '*/Orphans/*' }).Count | Should -Be 3
        }
    }
}

Describe 'Sync-iSOCContent and Export-iSOCDriftReport under -WhatIf, and with no drift' {
    BeforeAll {
        $script:quietRepo = Join-Path $TestDrive 'quiet'
        New-Item -ItemType Directory -Path (Join-Path $script:quietRepo 'Content/AnalyticalRules') -Force | Out-Null
        Copy-Item -LiteralPath $script:fixtureRule -Destination (Join-Path $script:quietRepo 'Content/AnalyticalRules/Repo.yaml')
        function Invoke-Compare {
            param([object[]] $Rules)
            $script:quietRules = $Rules
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
            Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { if ($Path -like '*/alertRules') { $script:quietRules } }
            Compare-iSOCContent -Context $script:context -RepoPath $script:quietRepo
        }
    }

    It 'writes nothing with -WhatIf' {
        $before = Get-Content -LiteralPath (Join-Path $script:quietRepo 'Content/AnalyticalRules/Repo.yaml') -Raw
        $drift = Invoke-Compare @((New-WorkspaceRule -Name 'orphan-1'), (New-WorkspaceRule -Name '303e7728-b654-467c-a509-00211879716c' -Properties @{ displayName = 'Azure VM Run Command or Custom Script execution detected'; severity = 'High'; query = 'AzureActivity | take 1'; queryFrequency = 'PT30M'; queryPeriod = 'PT35M' }))
        $drift.HasDrift | Should -BeTrue
        $drift | Sync-iSOCContent -WhatIf | Export-iSOCDriftReport -WhatIf | Should -BeNullOrEmpty
        Get-Content -LiteralPath (Join-Path $script:quietRepo 'Content/AnalyticalRules/Repo.yaml') -Raw | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $script:quietRepo 'reports') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:quietRepo 'Content/AnalyticalRules/AbsorbedFromPortal') | Should -BeFalse
        @($drift.Items.SyncAction | Where-Object { $_ }) | Should -BeNullOrEmpty
    }

    It 'writes no report when nothing drifted, so the drift pipeline has nothing to commit' {
        $drift = Invoke-Compare @((New-WorkspaceRule -Name 'fusion' -Kind Fusion))
        $drift.HasDrift | Should -BeFalse
        $drift | Export-iSOCDriftReport | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $script:quietRepo 'reports') | Should -BeFalse
    }

    It 'refuses a content type it cannot compare' {
        { Compare-iSOCContent -Context $script:context -RepoPath $script:quietRepo -ContentType Parser } | Should -Throw -ExpectedMessage '*cannot compare Parser*'
    }
}
