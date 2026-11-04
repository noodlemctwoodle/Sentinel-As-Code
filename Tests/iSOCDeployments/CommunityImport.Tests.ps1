#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 tests for Import-iSOCCommunityRule and the community import
    helpers.

.DESCRIPTION
    Covers:
      - The helpers, with the cases of Tests/Test-ImportCommunityRules.Tests.ps1
        carried over: the hash, the trigger operator, tags, durations,
        validation and normalisation, ARM conversion, reading YAML in order,
        version 5 ids, id lines, settling ids, and a re-import of the
        repository's own Dalonso rules keeping every id.
      - The source definition, the README (MIGRATION.md edit E30), the git
        requirement and the checkout.
      - Parity: a synthetic upstream git repository, cloned over file://
        both by Tools/Import-CommunityRules.ps1, run unchanged in a child
        pwsh from a copy of the repository, and by the module on another
        copy: the same rules, ids, manifest and README, and the differences
        MIGRATION.md edits E28 to E31 describe, shown.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/CommunityImport.Tests.ps1

    Runs the whole suite. Needs git on the PATH.

.NOTES
    File:         Tests/iSOCDeployments/CommunityImport.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml, git

    The parity block goes when Tools/Import-CommunityRules.ps1 is removed
    at cut-over.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '_helpers/Parity.psm1') -Force
    Import-Module powershell-yaml -ErrorAction Stop

    function Invoke-Private {
        param([string] $Command, [hashtable] $Arguments = @{})
        InModuleScope iSOCDeployments -Parameters @{ C = $Command; A = $Arguments } { param($C, $A) Mock Write-iSOCLog { }; & $C @A }
    }
    $script:dalonsoSource = Invoke-Private Get-iSOCCommunitySource @{ Name = 'Dalonso' }
    $script:attribution = $script:dalonsoSource.Attribution
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Helpers (carried over from Test-ImportCommunityRules.Tests.ps1)' {
    It 'hashes text as 64 upper-case hex digits, the same for the same text and not for one character more' {
        $hash = Invoke-Private Get-iSOCTextHash @{ Content = 'abc' }
        $hash | Should -MatchExactly '^[0-9A-F]{64}$'
        Invoke-Private Get-iSOCTextHash @{ Content = 'abc' } | Should -BeExactly $hash
        Invoke-Private Get-iSOCTextHash @{ Content = 'abcd' } | Should -Not -Be $hash
        Invoke-Private Get-iSOCTextHash @{ Content = 'abc ' } | Should -Not -Be $hash
    }

    It 'adds the required tags to <Case>, once each in any case, sorted' -ForEach @(
        @{ Case = 'a list'; Existing = @('UserTag', 'community'); Expected = @('community', 'Dalonso', 'ThreatHunting', 'UserTag') }
        @{ Case = 'one string'; Existing = 'Identity'; Expected = @('Community', 'Dalonso', 'Identity', 'ThreatHunting') }
        @{ Case = 'nothing'; Existing = $null; Expected = @('Community', 'Dalonso', 'ThreatHunting') }
    ) {
        @(Invoke-Private Merge-iSOCCommunityTag @{ Existing = $Existing; Required = $script:dalonsoSource.Tags }) | Should -Be $Expected
    }

    It 'turns <Value> into <Expected>' -ForEach @(
        @{ Value = '5m'; Expected = 'PT5M' }
        @{ Value = '1h'; Expected = 'PT1H' }
        @{ Value = '14d'; Expected = 'P14D' }
        @{ Value = 'PT1H'; Expected = 'PT1H' }
        @{ Value = 'every hour'; Expected = 'every hour' }
    ) {
        Invoke-Private ConvertTo-iSOCIsoDuration @{ Value = $Value } | Should -BeExactly $Expected
    }

    Context 'normalising a rule' {
        BeforeAll {
            function ConvertTo-Rule {
                param([System.Collections.IDictionary] $Rule)
                Invoke-Private ConvertTo-iSOCCommunityRuleYaml @{ Rule = $Rule; SourceFile = 'fake.yaml'; Source = $script:dalonsoSource }
            }
            function New-Rule { [ordered]@{ id = 'x'; name = 'Sample'; kind = 'Scheduled'; severity = 'Medium'; query = 'T | take 1' } }
        }

        It 'refuses a rule without its required fields' {
            { ConvertTo-Rule @{ id = 'x' } } | Should -Throw -ExpectedMessage '*missing required fields: name, kind, severity, query*'
        }

        It 'disables the rule, puts the attribution first and adds the tags' {
            $rule = New-Rule
            $rule.enabled = $true
            $rule.description = 'Original description'
            $rule.tags = @('UserTag')
            $parsed = ConvertFrom-Yaml (ConvertTo-Rule $rule)
            $parsed.enabled | Should -BeFalse
            $parsed.description | Should -BeExactly ($script:attribution + 'Original description')
            @($parsed.tags) | Should -Be @('Community', 'Dalonso', 'ThreatHunting', 'UserTag')
        }

        It 'spells a trigger operator as the API does, a long one in another case too (MIGRATION.md edit E28)' {
            $rule = New-Rule
            $rule.triggerOperator = 'gt'
            (ConvertFrom-Yaml (ConvertTo-Rule $rule)).triggerOperator | Should -BeExactly 'GreaterThan'
            $rule = New-Rule
            $rule.triggerOperator = 'greaterthan'
            (ConvertFrom-Yaml (ConvertTo-Rule $rule)).triggerOperator | Should -BeExactly 'GreaterThan'
        }

        It 'keeps the order of an ordered rule' {
            $rule = [ordered]@{ id = 'x'; name = 'Sample'; zeta = 1; kind = 'Scheduled'; severity = 'Medium'; alpha = 2; query = 'T' }
            $keys = @((ConvertTo-Rule $rule) -split "`r?`n" | Where-Object { $_ -match '^[A-Za-z]+:' } | ForEach-Object { ($_ -split ':')[0] })
            $keys[0..6] | Should -Be @('id', 'name', 'zeta', 'kind', 'severity', 'alpha', 'query')
        }
    }

    Context 'an ARM rule' {
        BeforeAll {
            function New-ArmResource {
                param([hashtable] $Override = @{}, [string[]] $Remove = @())
                $base = [ordered]@{
                    displayName = 'Sample ARM rule'; description = 'ARM description'; severity = 'High'; query = 'AuditLogs | take 1'
                    queryFrequency = '1h'; queryPeriod = '1d'; triggerOperator = 'gt'; triggerThreshold = 0
                    tactics = @('InitialAccess'); techniques = @('T1078')
                }
                foreach ($key in $Override.Keys) { $base[$key] = $Override[$key] }
                foreach ($key in $Remove) { $base.Remove($key) }
                [ordered]@{ kind = 'Scheduled'; properties = $base } | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
            }
            function ConvertFrom-Arm { param($Resource, [string] $Fallback = 'fallback-id') ConvertFrom-Yaml (Invoke-Private ConvertFrom-iSOCArmAlertRule @{ Resource = $Resource; SourceFile = 'fake-arm.json'; Source = $script:dalonsoSource; FallbackId = $Fallback }) }
        }

        It 'maps every standard field' {
            $parsed = ConvertFrom-Arm (New-ArmResource -Override @{ alertRuleTemplateName = 'tmpl-1' })
            $parsed.id | Should -Be 'tmpl-1'
            $parsed.name | Should -Be 'Sample ARM rule'
            $parsed.severity | Should -Be 'High'
            $parsed.query | Should -Be 'AuditLogs | take 1'
            $parsed.queryFrequency | Should -Be 'PT1H'
            $parsed.queryPeriod | Should -Be 'P1D'
            $parsed.triggerOperator | Should -Be 'GreaterThan'
            $parsed.triggerThreshold | Should -Be 0
            @($parsed.tactics) | Should -Contain 'InitialAccess'
            @($parsed.techniques) | Should -Contain 'T1078'
            $parsed.enabled | Should -BeFalse
        }

        It 'names a rule without a display name by its template name' {
            (ConvertFrom-Arm (New-ArmResource -Override @{ alertRuleTemplateName = 'TemplateGuidName' } -Remove 'displayName')).name | Should -Be 'TemplateGuidName'
        }

        It 'gives a rule without a template name the id it is given, not a random one (MIGRATION.md edit E31)' {
            (ConvertFrom-Arm (New-ArmResource) -Fallback 'stable-id').id | Should -Be 'stable-id'
        }

        It 'keeps entity mappings' {
            $parsed = ConvertFrom-Arm (New-ArmResource -Override @{ alertRuleTemplateName = 't'; entityMappings = @(@{ entityType = 'Account'; fieldMappings = @(@{ identifier = 'AadUserId'; columnName = 'Caller' }) }) })
            $parsed.Contains('entityMappings') | Should -BeTrue
        }
    }

    Context 'reading a YAML rule file' {
        BeforeAll {
            $script:sourcePath = Join-Path $TestDrive 'source-rule.yaml'
            Set-Content -LiteralPath $script:sourcePath -Encoding utf8 -Value @'
id: 11111111-2222-4333-8444-555555555555
name: Sample upstream rule
description: |
  Upstream text.
severity: High
queryFrequency: PT1H
queryPeriod: PT1H
triggerOperator: gt
triggerThreshold: 0
enabled: true
query: |
  SigninLogs
  | take 1
version: 1.0.0
kind: Scheduled
'@
        }

        It 'imports it, in its own key order' {
            $rule = Invoke-Private Read-iSOCCommunityYamlRule @{ Path = $script:sourcePath; Source = $script:dalonsoSource }
            $rule.Error | Should -BeNullOrEmpty
            $parsed = ConvertFrom-Yaml $rule.YamlContent
            $parsed.id | Should -Be '11111111-2222-4333-8444-555555555555'
            $parsed.enabled | Should -BeFalse
            $parsed.triggerOperator | Should -Be 'GreaterThan'
            $keys = @($rule.YamlContent -split "`r?`n" | Where-Object { $_ -match '^[A-Za-z]+:' } | ForEach-Object { ($_ -split ':')[0] })
            $keys[0..3] | Should -Be @('id', 'name', 'description', 'severity')
        }

        It 'leaves out a file that is not a mapping, saying why' {
            $list = Join-Path $TestDrive 'list.yaml'
            Set-Content -LiteralPath $list -Value "- a`n- b"
            (Invoke-Private Read-iSOCCommunityYamlRule @{ Path = $list; Source = $script:dalonsoSource }).Error | Should -Be 'the YAML is not a mapping'
        }
    }

    It 'makes the RFC 4122 version 5 GUID of <Name>' -ForEach @(
        @{ Name = 'example'; Expected = 'f8b72323-0e40-5a08-bd7f-039dfb85a9b2' }
        @{ Name = 'https://github.com/davidalonsod/Dalonso-Security-Repo#CommonSecurityLog/01-CSL-Beaconing-Detection.yaml'; Expected = '27601f16-757a-51d0-8d83-290d329141fc' }
    ) {
        Invoke-Private New-iSOCCommunityRuleId @{ Name = $Name } | Should -BeExactly $Expected
    }

    It 'reads a bare or quoted top-level id, and nothing for a missing file or a nested id' {
        $bare = Join-Path $TestDrive 'bare.yaml'
        Set-Content -LiteralPath $bare -Value "id: 6F1C2A3B-0D4E-4F5A-9B8C-7D6E5F4A3B2C`nname: x"
        Invoke-Private Get-iSOCRuleFileId @{ Path = $bare } | Should -BeExactly '6F1C2A3B-0D4E-4F5A-9B8C-7D6E5F4A3B2C'
        $quoted = Join-Path $TestDrive 'quoted.yaml'
        Set-Content -LiteralPath $quoted -Value "name: x`nid: 'abc-123'"
        Invoke-Private Get-iSOCRuleFileId @{ Path = $quoted } | Should -BeExactly 'abc-123'
        Invoke-Private Get-iSOCRuleFileId @{ Path = (Join-Path $TestDrive 'absent.yaml') } | Should -BeNullOrEmpty
        $none = Join-Path $TestDrive 'none.yaml'
        Set-Content -LiteralPath $none -Value "name: x`n  id: nested"
        Invoke-Private Get-iSOCRuleFileId @{ Path = $none } | Should -BeNullOrEmpty
    }

    Context 'settling ids' {
        BeforeAll {
            $script:source = 'https://github.com/example-org/rules.git'
            function New-Pending { param([string] $RelativePath, [string] $Id) @{ RelativePath = $RelativePath; YamlContent = "id: $Id`nname: $RelativePath`nquery: |`n  T`n"; Category = 'X' } }
            function Get-PendingId { param($Rule) ([regex]::Match($Rule.YamlContent, '(?m)^id: (.+)$')).Groups[1].Value }
            function Resolve-Id {
                param([System.Collections.IList] $Pending, [hashtable] $Reserved = @{}, [string] $Repo = $script:source)
                @(Invoke-Private Resolve-iSOCCommunityRuleId @{ PendingRules = $Pending; OutputPath = $script:out; SourceRepo = $Repo; ReservedIds = $Reserved })
            }
            function Get-DerivedId { param([string] $Path) Invoke-Private New-iSOCCommunityRuleId @{ Name = "https://github.com/example-org/rules#$Path" } }
        }

        BeforeEach {
            $script:out = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $script:out | Out-Null
        }

        It 'leaves unique upstream ids alone' {
            $pending = [System.Collections.ArrayList]@((New-Pending 'A/one.yaml' 'id-1'), (New-Pending 'B/two.yaml' 'id-2'))
            (Resolve-Id $pending).Count | Should -Be 0
            Get-PendingId $pending[1] | Should -Be 'id-2'
        }

        It 'keeps the first rule in path order on a shared id and derives one for the next' {
            $pending = [System.Collections.ArrayList]@((New-Pending 'SigninLogs/x.yaml' 'shared'), (New-Pending 'CommonSecurityLog/y.yaml' 'SHARED'))
            $changes = Resolve-Id $pending
            Get-PendingId $pending[1] | Should -Be 'SHARED'
            Get-PendingId $pending[0] | Should -Be (Get-DerivedId 'SigninLogs/x.yaml')
            $changes[0].Reason | Should -Match 'already used by CommonSecurityLog/y.yaml'
        }

        It 'keeps the id a repository file has, over the upstream''s and over a new rule bringing it' {
            New-Item -ItemType Directory -Path (Join-Path $script:out 'Z') | Out-Null
            Set-Content -LiteralPath (Join-Path $script:out 'Z/existing.yaml') -Value "id: taken`nname: existing"
            $pending = [System.Collections.ArrayList]@((New-Pending 'A/new.yaml' 'taken'), (New-Pending 'Z/existing.yaml' 'upstream'))
            $changes = Resolve-Id $pending
            Get-PendingId $pending[1] | Should -Be 'taken'
            Get-PendingId $pending[0] | Should -Be (Get-DerivedId 'A/new.yaml')
            ($changes | Where-Object RelativePath -eq 'Z/existing.yaml').Reason | Should -Be 'kept the id the repository file has'
        }

        It 'derives an id when an in-house rule has the upstream one, changing only the id line' {
            $pending = [System.Collections.ArrayList]@((New-Pending 'A/one.yaml' 'In-House-Id'))
            $before = $pending[0].YamlContent
            Resolve-Id $pending -Reserved @{ 'in-house-id' = 'Identity/Rule.yaml' } | Out-Null
            Get-PendingId $pending[0] | Should -Not -Be 'In-House-Id'
            ($pending[0].YamlContent -split "`n")[1..9] | Should -Be (($before -split "`n")[1..9])
        }

        It 'gives the same ids on every run, whatever the order or a trailing slash' {
            $first = [System.Collections.ArrayList]@((New-Pending 'B/b.yaml' 'same'), (New-Pending 'A/a.yaml' 'same'))
            $second = [System.Collections.ArrayList]@((New-Pending 'A/a.yaml' 'same'), (New-Pending 'B/b.yaml' 'same'))
            Resolve-Id $first | Out-Null
            Resolve-Id $second -Repo "$($script:source)/" | Out-Null
            Get-PendingId $first[0] | Should -Be (Get-PendingId $second[1])
        }

        It 'refuses a rule with no top-level id line' {
            { Resolve-Id ([System.Collections.ArrayList]@(@{ RelativePath = 'A/x.yaml'; YamlContent = "name: x`n" })) } | Should -Throw -ExpectedMessage '*no top-level id line*'
        }
    }

    Context 'a re-import of the repository''s Dalonso rules' {
        BeforeAll {
            $script:dalonso = Join-Path $script:repoRoot 'Content/AnalyticalRules/Community/Dalonso'
            $script:reserved = Invoke-Private Get-iSOCReservedRuleId @{ RulesRoot = (Join-Path $script:repoRoot 'Content/AnalyticalRules'); ExcludePath = $script:dalonso }
        }

        It 'keeps every id the repository has, even when the upstream reuses one across categories' {
            $shared = Invoke-Private Get-iSOCRuleFileId @{ Path = (Join-Path $script:dalonso 'SigninLogs/11-SIGNIN-SlowLowPasswordSpray.yaml') }
            $pending = [System.Collections.ArrayList]::new()
            foreach ($file in Get-ChildItem -LiteralPath $script:dalonso -Recurse -File -Include '*.yaml', '*.yml') {
                $relative = [System.IO.Path]::GetRelativePath($script:dalonso, $file.FullName).Replace('\', '/')
                $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8
                if ($relative -like 'CommonSecurityLog*') { $content = [regex]::new('(?m)^id:[^\r\n]*').Replace($content, "id: $shared", 1) }
                [void]$pending.Add(@{ RelativePath = $relative; YamlContent = $content; Category = 'x' })
            }
            Invoke-Private Resolve-iSOCCommunityRuleId @{ PendingRules = $pending; OutputPath = $script:dalonso; SourceRepo = 'https://github.com/davidalonsod/Dalonso-Security-Repo.git'; ReservedIds = $script:reserved } | Out-Null
            $ids = @($pending | ForEach-Object { ([regex]::Match($_.YamlContent, '(?m)^id:[ \t]*(\S+)')).Groups[1].Value })
            @($ids | Group-Object | Where-Object Count -gt 1).Name | Should -BeNullOrEmpty
            for ($i = 0; $i -lt $pending.Count; $i++) {
                $ids[$i] | Should -Be (Invoke-Private Get-iSOCRuleFileId @{ Path = (Join-Path $script:dalonso $pending[$i].RelativePath) }) -Because $pending[$i].RelativePath
            }
        }

        It 'reserves the in-house ids and none of the community folder''s' {
            $script:reserved.Count | Should -BeGreaterThan 50
            @($script:reserved.Values | Where-Object { $_ -like 'Community/Dalonso/*' }) | Should -BeNullOrEmpty
        }
    }
}

Describe 'Sources, the README, git and the checkout' {
    It 'knows the Dalonso source, in any case, and names the sources when asked for one it does not have' {
        (Invoke-Private Get-iSOCCommunitySource @{ Name = 'dalonso' }).Repository | Should -Be 'https://github.com/davidalonsod/Dalonso-Security-Repo.git'
        { Invoke-Private Get-iSOCCommunitySource @{ Name = 'Nobody' } } | Should -Throw -ExpectedMessage "*no community source 'Nobody'*Dalonso*"
    }

    It 'shows each rule''s own first line in the README, not the attribution, and how to re-import (MIGRATION.md edit E30)' {
        $details = @{ SigninLogs = @(@{ Name = 'Spray | wide'; Severity = 'High'; Description = $script:attribution + "First line.`nSecond line." }) }
        $readme = Invoke-Private ConvertTo-iSOCCommunityReadme @{ Source = $script:dalonsoSource; CategoryStats = @{ SigninLogs = 1 }; RuleDetails = $details; ImportDate = 'today' }
        $readme | Should -Match ([regex]::Escape('| Spray \| wide | High | First line. |'))
        $readme | Should -Match 'Import-iSOCCommunityRule -Source Dalonso'
        $readme | Should -Not -Match "`r"
        $readme.EndsWith("```n") | Should -BeTrue
    }

    It 'checks git as a command, with its version' {
        $git = Invoke-Private Test-iSOCRequirement @{ Requirement = (InModuleScope iSOCDeployments { Get-iSOCRequirement | Where-Object Name -eq 'git' }) }
        $git.Found | Should -BeTrue
        $git.Version | Should -Match '^\d+\.\d+'
        $missing = Invoke-Private Test-iSOCRequirement @{ Requirement = [pscustomobject]@{ Name = 'no-such-command-isoc'; Kind = 'Command'; Step = @('Import'); Required = $true; MinimumVersion = '1.0'; Hint = 'Install it.' } }
        $missing.Found | Should -BeFalse
        $missing.Detail | Should -Be 'Install it.'
        @(Test-iSOCDeploymentPrerequisite -Step Import | ForEach-Object { $_.Name }) | Should -Contain 'git 2.0.0+'
    }

    It 'reads a folder on disk without cloning, its commit unknown when it is not a checkout' {
        $folder = Join-Path $TestDrive 'plain-source'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $checkout = Invoke-Private Get-iSOCCommunityCheckout @{ SourceRepo = 'https://example.invalid/x.git'; SourceBranch = 'main'; SourcePath = $folder }
        $checkout.Commit | Should -Be 'unknown'
        { Invoke-Private Get-iSOCCommunityCheckout @{ SourceRepo = 'x'; SourceBranch = 'main'; SourcePath = (Join-Path $TestDrive 'nowhere') } } | Should -Throw -ExpectedMessage '*does not exist*'
    }
}

Describe 'Parity with Tools/Import-CommunityRules.ps1' {
    BeforeAll {
        $script:legacyScript = Join-Path $script:repoRoot 'Tools/Import-CommunityRules.ps1'
        $script:inHouseId = Invoke-Private Get-iSOCRuleFileId @{ Path = (Join-Path $script:repoRoot 'Content/AnalyticalRules/AzureActivity/AzureVmRunCommandExecutionDetectionRule.yaml') }
        $script:existingFile = 'SigninLogs/11-SIGNIN-SlowLowPasswordSpray.yaml'
        $script:existingId = Invoke-Private Get-iSOCRuleFileId @{ Path = (Join-Path $script:repoRoot "Content/AnalyticalRules/Community/Dalonso/$($script:existingFile)") }

        function Invoke-Git { param([string] $Folder, [string[]] $Arguments) & git -C $Folder -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false @Arguments 2>&1 | Out-Null }

        # A synthetic upstream in the Dalonso layout: a rule the repository
        # has (under a new upstream id), two rules sharing an id across
        # categories, one with an in-house id, one without a severity, a
        # list, files the import ignores, and ARM templates with rules, with
        # none, and that do not parse.
        function New-Upstream {
            param([string] $Name, [switch] $NoTemplateName)
            $root = Join-Path $TestDrive $Name
            $write = {
                param([string] $Path, [string] $Text)
                $full = Join-Path $root $Path
                New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
                Set-Content -LiteralPath $full -Value $Text -NoNewline
            }
            $rule = {
                param([string] $Id, [string] $RuleName, [string] $Extra = '')
                "id: $Id`nname: $RuleName`ndescription: |`n  $RuleName does things.`n  A second line.`nseverity: High`nqueryFrequency: PT1H`nqueryPeriod: PT1H`ntriggerOperator: gt`ntriggerThreshold: 0`nenabled: true`n$($Extra)query: |`n  SigninLogs`n  | where ResultType != 0`nkind: Scheduled`n"
            }
            $signin = 'Use Cases Threat Hunting/SigninLogs-ThreatHunting'
            & $write "$signin/11-SIGNIN-SlowLowPasswordSpray.yaml" (& $rule 'aaaaaaaa-1111-4111-8111-000000000001' 'Slow and low password spray' "tags: Identity`n")
            & $write "$signin/A-new-rule.yaml" (& $rule 'aaaaaaaa-1111-4111-8111-000000000002' 'New sign-in rule | with a pipe')
            & $write "$signin/B-no-severity.yaml" "id: aaaaaaaa-1111-4111-8111-000000000003`nname: No severity`nkind: Scheduled`nquery: T`n"
            & $write "$signin/C-list.yaml" "- a`n- b`n"
            & $write "$signin/D-ignored.yml" (& $rule 'aaaaaaaa-1111-4111-8111-000000000004' 'Ignored yml')
            & $write "$signin/E-ignored.kql" 'SigninLogs | take 1'
            $csl = 'Use Cases Threat Hunting/CommonSecurityLog-ThreatHunting'
            & $write "$csl/csl-shared.yaml" (& $rule 'aaaaaaaa-1111-4111-8111-000000000002' 'Shared id rule')
            & $write "$csl/csl-inhouse.yaml" (& $rule $script:inHouseId 'In-house id rule')
            & $write 'Use Cases Threat Hunting/DNSEvents/Analytic-Rules/rules/dns.yaml' ((& $rule 'aaaaaaaa-1111-4111-8111-000000000005' 'DNS rule').Replace('triggerOperator: gt', 'triggerOperator: GreaterThan'))

            $armRule = {
                param([string] $Template, [string] $DisplayName, [string] $Frequency)
                $properties = [ordered]@{ displayName = $DisplayName; description = "$DisplayName from ARM."; severity = 'Medium'; query = 'AzureActivity | take 1'; queryFrequency = $Frequency; queryPeriod = '1d'; triggerOperator = 'gt'; triggerThreshold = 1; tactics = @('Persistence'); techniques = @('T1098'); entityMappings = @([ordered]@{ entityType = 'Account'; fieldMappings = @([ordered]@{ identifier = 'Name'; columnName = 'Caller' }) }) }
                if ($Template) { $properties.alertRuleTemplateName = $Template }
                [ordered]@{ type = 'Microsoft.OperationalInsights/workspaces/providers/alertRules'; kind = 'Scheduled'; name = 'x'; properties = $properties }
            }
            $first = if ($NoTemplateName) { '' } else { 'bbbbbbbb-2222-4222-8222-000000000001' }
            $template = [ordered]@{ '$schema' = 'x'; resources = @((& $armRule $first 'Azure: role assigned / then used' '5m'), (& $armRule 'bbbbbbbb-2222-4222-8222-000000000002' 'Azure run command' '1h'), [ordered]@{ type = 'Microsoft.Insights/workbooks'; name = 'w' }) }
            & $write 'Use Cases Threat Hunting/AzureCustomDetections/AnalyticRules/one/azuredeploy.json' (ConvertTo-Json -InputObject $template -Depth 20)
            & $write 'Use Cases Threat Hunting/ADSecurityEvents/AnalyticRules/azuredeploy.json' '{ not json'
            & $write 'Use Cases Threat Hunting/M365OfficeActivity/AnalyticRules/azuredeploy.json' '{ "resources": [ { "type": "Microsoft.Insights/workbooks" } ] }'

            & git init -q -b main $root 2>&1 | Out-Null
            Invoke-Git $root @('add', '-A')
            Invoke-Git $root @('commit', '-q', '-m', 'upstream')
            [pscustomobject]@{ Path = $root; Url = ([System.Uri]::new($root)).AbsoluteUri; Commit = (& git -C $root rev-parse HEAD).Trim() }
        }

        function New-Tree {
            param([switch] $WithScript)
            $tree = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $tree 'Content') -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:repoRoot 'Content/AnalyticalRules') -Destination (Join-Path $tree 'Content') -Recurse
            if ($WithScript) {
                New-Item -ItemType Directory -Path (Join-Path $tree 'Tools') | Out-Null
                Copy-Item -LiteralPath $script:legacyScript -Destination (Join-Path $tree 'Tools/Import-CommunityRules.ps1')
            }
            $tree
        }

        function Invoke-Legacy {
            param([string] $Tree, [string] $Url, [string[]] $Extra = @('-IncludeKqlConversion'))
            $output = & pwsh -NoProfile -NonInteractive -File (Join-Path $Tree 'Tools/Import-CommunityRules.ps1') -SourceRepo $Url @Extra 2>&1 | Out-String
            $count = { param([string] $Label) if ($output -match "(?m)$([regex]::Escape($Label)):\s+(\d+)") { [int]$Matches[1] } else { 0 } }
            [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE; Imported = & $count 'Imported (new)'; Updated = & $count 'Updated'; Unchanged = & $count 'Skipped (no diff)'; Errors = & $count 'Errors' }
        }

        function Invoke-Module {
            param([string] $Tree, [string] $Url, [hashtable] $Parameters = @{ IncludeKqlConversion = $true })
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            Import-iSOCCommunityRule -RepoPath $Tree -SourceRepo $Url @Parameters
        }

        function Get-Snapshot {
            param([string] $Tree)
            $snapshot = [ordered]@{}
            foreach ($folder in 'Content/AnalyticalRules/Community/Dalonso', 'Docs/Content/Community') {
                $base = Join-Path $Tree $folder
                if (-not (Test-Path -LiteralPath $base)) { continue }
                $files = [string[]]@(Get-ChildItem -LiteralPath $base -Recurse -File | ForEach-Object { [System.IO.Path]::GetRelativePath($Tree, $_.FullName).Replace('\', '/') })
                [Array]::Sort($files, [System.StringComparer]::Ordinal)
                foreach ($file in $files) { $snapshot[$file] = Get-Content -LiteralPath (Join-Path $Tree $file) -Raw }
            }
            $snapshot
        }

        $script:upstream = New-Upstream -Name 'upstream'
        $script:legacyTree = New-Tree -WithScript
        $script:legacy = Invoke-Legacy -Tree $script:legacyTree -Url $script:upstream.Url
        $script:moduleTree = New-Tree
        $script:run = Invoke-Module -Tree $script:moduleTree -Url $script:upstream.Url
        $script:legacyFiles = Get-Snapshot $script:legacyTree
        $script:moduleFiles = Get-Snapshot $script:moduleTree
        $script:rules = 'Content/AnalyticalRules/Community/Dalonso'
    }

    It 'exercises every case' {
        $script:legacy.ExitCode | Should -Be 0 -Because $script:legacy.Output
        $script:legacy.Imported | Should -Be 6 -Because $script:legacy.Output
        $script:legacy.Updated | Should -Be 1
        $script:legacy.Errors | Should -Be 2
        $script:legacy.Output | Should -Match 'Failed to parse ARM template'
        $script:legacy.Output | Should -Match 'No alertRule resources found'
        $script:legacy.Output | Should -Match 'Source folder not found, skipping'
    }

    It 'counts the same' {
        $script:run.Created | Should -Be $script:legacy.Imported
        $script:run.Updated | Should -Be $script:legacy.Updated
        $script:run.Skipped | Should -Be $script:legacy.Errors
        $script:run.SourceCommit | Should -Be $script:upstream.Commit
        $script:run.ExitCode | Should -Be 0
    }

    It 'writes the same rule files, each ending in one newline where the script left a blank line (MIGRATION.md edit E29)' {
        $legacyRules = @($script:legacyFiles.Keys | Where-Object { $_ -like "$($script:rules)/*" -and $_ -notlike '*/import-manifest.json' })
        $moduleRules = @($script:moduleFiles.Keys | Where-Object { $_ -like "$($script:rules)/*" -and $_ -notlike '*/import-manifest.json' })
        $moduleRules | Should -Be $legacyRules
        foreach ($result in @($script:run.Results | Where-Object { $_.Outcome -in 'Created', 'Updated' })) {
            $file = "$($script:rules)/$($result.Path)"
            $script:legacyFiles[$file].EndsWith("`n`n") | Should -BeTrue -Because $file
            $script:moduleFiles[$file].EndsWith("`n`n") | Should -BeFalse -Because $file
            # The attribution is its own paragraph (MIGRATION.md edit E28).
            $legacy = $script:legacyFiles[$file].TrimEnd("`n").Replace("Licensed under The Unlicense.`n  ", "Licensed under The Unlicense.`n`n  ")
            $script:moduleFiles[$file].TrimEnd("`n") | Should -BeExactly $legacy -Because $file
        }
        foreach ($file in $legacyRules | Where-Object { $_ -notin @($script:run.Results | ForEach-Object { "$($script:rules)/$($_.Path)" }) }) {
            $script:moduleFiles[$file] | Should -BeExactly $script:legacyFiles[$file] -Because "$file is not imported"
        }
    }

    It 'makes the attribution its own paragraph, where the script''s here-string lost the blank line (MIGRATION.md edit E28)' {
        $file = "$($script:rules)/SigninLogs/A-new-rule.yaml"
        (ConvertFrom-Yaml $script:legacyFiles[$file]).description | Should -BeExactly ($script:attribution.TrimEnd("`n") + "`nNew sign-in rule | with a pipe does things.`nA second line.`n")
        (ConvertFrom-Yaml $script:moduleFiles[$file]).description | Should -BeExactly ($script:attribution + "New sign-in rule | with a pipe does things.`nA second line.`n")
    }

    It 'settles the same ids: the repository''s kept, a shared one and an in-house one derived' {
        $id = { param([string] $Files, [string] $Path) ([regex]::Match($Files, '(?m)^id:[ \t]*(\S+)')).Groups[1].Value }
        foreach ($tree in $script:legacyFiles, $script:moduleFiles) {
            & $id $tree["$($script:rules)/$($script:existingFile)"] | Should -Be $script:existingId
            & $id $tree["$($script:rules)/CommonSecurityLog/csl-shared.yaml"] | Should -Be 'aaaaaaaa-1111-4111-8111-000000000002'
            & $id $tree["$($script:rules)/SigninLogs/A-new-rule.yaml"] | Should -Not -Be 'aaaaaaaa-1111-4111-8111-000000000002'
            & $id $tree["$($script:rules)/CommonSecurityLog/csl-inhouse.yaml"] | Should -Not -Be $script:inHouseId
        }
        @($script:run.IdChanges).Count | Should -Be 3
    }

    It 'writes the same manifest' {
        $legacyManifest = $script:legacyFiles["$($script:rules)/import-manifest.json"] | ConvertFrom-Json -AsHashtable
        $moduleManifest = $script:moduleFiles["$($script:rules)/import-manifest.json"] | ConvertFrom-Json -AsHashtable
        foreach ($key in 'sourceRepo', 'sourceBranch', 'sourceCommitSha') { $moduleManifest[$key] | Should -BeExactly $legacyManifest[$key] }
        @($moduleManifest.files.Keys | Sort-Object) | Should -Be @($legacyManifest.files.Keys | Sort-Object)
        foreach ($key in $moduleManifest.files.Keys) {
            $moduleManifest.files[$key] | Should -BeExactly (Invoke-Private Get-iSOCTextHash @{ Content = $script:moduleFiles["$($script:rules)/$key"] }) -Because "the hash is of the file written, $key"
        }
        $script:moduleFiles["$($script:rules)/import-manifest.json"] | Should -Match '"importDate": "\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ"'
    }

    It 'writes the same README, but for the description column, the date and how to re-import (MIGRATION.md edit E30)' {
        $legacy = @($script:legacyFiles['Docs/Content/Community/Dalonso.md'] -split "`n")
        $module = @($script:moduleFiles['Docs/Content/Community/Dalonso.md'] -split "`n")
        $head = $legacy.IndexOf('## Categories')
        $module[0..$head] | Should -Be $legacy[0..$head]
        $rows = { param([string[]] $Lines) @($Lines | Where-Object { $_ -match '^\| .+ \| (High|Medium|Low|Informational) \| ' } | ForEach-Object { ($_ -split ' \| ')[0..1] -join ' | ' } | Sort-Object) }
        & $rows $module | Should -Be (& $rows $legacy)
        @($legacy | Where-Object { $_ -match '^\| .+ \| (High|Medium) \| Community rule by David Alonso' }).Count | Should -Be ($script:run.Created + $script:run.Updated)
        @($module | Where-Object { $_ -match 'Community rule by David Alonso' }).Count | Should -Be 0
        $module | Should -Contain '| New sign-in rule \| with a pipe | High | New sign-in rule \| with a pipe does things. |'
        $module | Should -Contain 'Import-iSOCCommunityRule -Source Dalonso'
        $legacy | Should -Contain '.\Tools\Import-CommunityRules.ps1'
    }

    It 'finds nothing to write when it runs again, where the script rewrote every rule (MIGRATION.md edit E29)' {
        $again = Invoke-Legacy -Tree $script:legacyTree -Url $script:upstream.Url
        $again.Updated | Should -Be ($script:legacy.Imported + $script:legacy.Updated) -Because $again.Output
        $again.Unchanged | Should -Be 0

        $before = Get-Snapshot $script:moduleTree
        $second = Invoke-Module -Tree $script:moduleTree -Url $script:upstream.Url
        $second.Unchanged | Should -Be ($script:run.Created + $script:run.Updated)
        $second.Created + $second.Updated | Should -Be 0
        $second.Manifest | Should -Be 'Unchanged'
        $second.Readme | Should -Be 'Unchanged'
        $after = Get-Snapshot $script:moduleTree
        (ConvertTo-Json -InputObject $after -Compress) | Should -BeExactly (ConvertTo-Json -InputObject $before -Compress)
    }

    It 'writes nothing with -WhatIf and says what each rule would be, where the script''s dry run counted every rule new (MIGRATION.md edit E28)' {
        $legacy = Invoke-Legacy -Tree (New-Tree -WithScript) -Url $script:upstream.Url -Extra @('-IncludeKqlConversion', '-DryRun')
        $legacy.Imported | Should -Be ($script:legacy.Imported + $script:legacy.Updated)
        $legacy.Updated | Should -Be 0

        $tree = New-Tree
        $before = Get-Snapshot $tree
        $run = Invoke-Module -Tree $tree -Url $script:upstream.Url -Parameters @{ IncludeKqlConversion = $true; WhatIf = $true }
        (ConvertTo-Json -InputObject (Get-Snapshot $tree) -Compress) | Should -BeExactly (ConvertTo-Json -InputObject $before -Compress)
        @($run.Results | Where-Object Reason -eq 'would be created').Count | Should -Be $script:legacy.Imported
        @($run.Results | Where-Object Reason -eq 'would be updated').Count | Should -Be $script:legacy.Updated
        $run.Manifest | Should -Be 'WhatIf'
        $run.Readme | Should -Be 'WhatIf'
    }

    It 'gives an ARM rule without a template name the same id every time, where the script made a new one (MIGRATION.md edit E31)' {
        $upstream = New-Upstream -Name 'upstream-no-template' -NoTemplateName
        $file = "$($script:rules)/AzureActivity/Azure-role-assigned-then-used.yaml"
        $id = { param([string] $Tree) Invoke-Private Get-iSOCRuleFileId @{ Path = (Join-Path $Tree $file) } }
        $legacyIds = foreach ($n in 1, 2) { $tree = New-Tree -WithScript; Invoke-Legacy -Tree $tree -Url $upstream.Url | Out-Null; & $id $tree }
        $moduleIds = foreach ($n in 1, 2) { $tree = New-Tree; Invoke-Module -Tree $tree -Url $upstream.Url | Out-Null; & $id $tree }
        $legacyIds[0] | Should -Not -BeNullOrEmpty
        $legacyIds[0] | Should -Not -Be $legacyIds[1]
        $moduleIds[0] | Should -Be $moduleIds[1]
    }

    It 'imports from a checkout on disk without cloning' {
        Mock -ModuleName iSOCDeployments Invoke-iSOCGit { [pscustomobject]@{ ExitCode = 0; Output = @($script:upstream.Commit) } } -ParameterFilter { $ArgumentList -contains 'rev-parse' }
        Mock -ModuleName iSOCDeployments Invoke-iSOCGit { throw 'no clone expected' } -ParameterFilter { $ArgumentList -contains 'clone' }
        $tree = New-Tree
        $run = Invoke-Module -Tree $tree -Url $script:upstream.Url -Parameters @{ IncludeKqlConversion = $true; SourcePath = $script:upstream.Path }
        $run.Created | Should -Be $script:run.Created
        Should -Invoke -ModuleName iSOCDeployments Invoke-iSOCGit -ParameterFilter { $ArgumentList -contains 'clone' } -Times 0 -Exactly
    }
}
