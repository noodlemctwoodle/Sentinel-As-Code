#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 unit tests for the pure functions in
    Tools/Import-CommunityRules.ps1: the YAML/ARM normalisation
    pipeline applied to imported community rule content.

.DESCRIPTION
    The pure functions worth pinning with tests:
      - Get-ContentHash256 (SHA256 hashing for the import manifest)
      - Format-TriggerOperator (gt/lt/eq/ne -> GreaterThan/etc.)
      - Merge-Tags (case-insensitive, dedup-and-sort tag merge)
      - ConvertTo-Iso8601Duration (24h/7d -> PT24H/P7D shorthand expansion)
      - Build-RuleYaml (forces enabled=false, prepends attribution,
        merges tags, normalises trigger operator)
      - ConvertFrom-ArmAlertRule (ARM alertRule resource -> normalised
        rule hashtable)
      - Import-YamlFile (a YAML source rule, read as an ordered mapping)
      - New-CommunityRuleId, Get-RuleFileId, Get-ReservedRuleId and
        Resolve-CommunityRuleId (every rule gets an id no other rule file
        uses, keeping the ids the repository already has), including a
        simulated re-import of the Dalonso folder, and that Invoke-Main
        resolves ids before it writes

    Builds on the AST extractor in
    Tests/_helpers/Import-ScriptFunctions.psm1.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-ImportCommunityRules.Tests.ps1

    Runs the normalisation-pipeline tests.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-ImportCommunityRules.Tests.ps1 -FullName '*ConvertTo-Iso8601Duration*'

    Runs only the duration-shorthand expansion assertions.

.NOTES
    File:         Tests/Test-ImportCommunityRules.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-05-13
    Version:      0.3.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml (auto-installed if missing)
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Tools/Import-CommunityRules.ps1'

    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop
    Import-ScriptFunctions -Path $scriptPath

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Install-Module -Name powershell-yaml -Force -Scope CurrentUser -AllowClobber | Out-Null
    }
    Import-Module powershell-yaml -ErrorAction Stop

    # Mirror the script-scope constants. Keep these in sync with
    # Import-CommunityRules.ps1 lines 121-132 — the test will catch any
    # accidental divergence via assertion failures.
    $script:AttributionPrefix = "Community rule by David Alonso (https://github.com/davidalonsod/Dalonso-Security-Repo). Licensed under The Unlicense.`n`n"
    $script:RequiredTags      = @('Community', 'Dalonso', 'ThreatHunting')
    $script:TriggerOpMap      = @{
        gt = 'GreaterThan'
        lt = 'LessThan'
        eq = 'Equal'
        ne = 'NotEqual'
    }

    function Write-Status {
        param([string]$Message, [string]$Level = 'Info')
    }
}

Describe 'Get-ContentHash256' {
    It 'produces a 64-character hex string' {
        $hash = Get-ContentHash256 -Content 'hello'
        $hash | Should -Match '^[0-9A-Fa-f]{64}$'
    }

    It 'produces a stable hash for identical input' {
        Get-ContentHash256 -Content 'identical' | Should -Be (Get-ContentHash256 -Content 'identical')
    }

    It 'produces different hashes for different input' {
        (Get-ContentHash256 -Content 'a') | Should -Not -Be (Get-ContentHash256 -Content 'b')
    }

    It 'is sensitive to single-character changes' {
        (Get-ContentHash256 -Content 'hello') | Should -Not -Be (Get-ContentHash256 -Content 'Hello')
    }
}

Describe 'Format-TriggerOperator' {
    It 'maps short forms to long forms (case-insensitive)' {
        Format-TriggerOperator -Value 'gt' | Should -Be 'GreaterThan'
        Format-TriggerOperator -Value 'lt' | Should -Be 'LessThan'
        Format-TriggerOperator -Value 'eq' | Should -Be 'Equal'
        Format-TriggerOperator -Value 'ne' | Should -Be 'NotEqual'
        Format-TriggerOperator -Value 'GT' | Should -Be 'GreaterThan' -Because 'lookup is case-insensitive'
    }

    It 'returns the original value unchanged when not in the map' {
        Format-TriggerOperator -Value 'GreaterThan' | Should -Be 'GreaterThan'
        Format-TriggerOperator -Value 'Custom'      | Should -Be 'Custom'
    }

    It 'returns the original value unchanged for null/empty/whitespace' {
        Format-TriggerOperator -Value $null | Should -BeNullOrEmpty
        Format-TriggerOperator -Value ''    | Should -Be ''
        Format-TriggerOperator -Value '   ' | Should -Be '   '
    }
}

Describe 'Merge-Tags' {
    It 'merges existing array tags with the required set, deduplicates, sorts' {
        $merged = Merge-Tags -Existing @('CustomTag', 'Community')
        @($merged) | Should -Contain 'CustomTag'
        @($merged) | Should -Contain 'Community'
        @($merged) | Should -Contain 'Dalonso'
        @($merged) | Should -Contain 'ThreatHunting'
        # Sorted alphabetically (case-insensitive)
        $names = @($merged)
        $sorted = $names | Sort-Object
        @($names) | Should -Be @($sorted)
    }

    It 'deduplicates case-insensitively' {
        $merged = Merge-Tags -Existing @('community', 'COMMUNITY', 'Community')
        ($merged | Where-Object { $_ -ieq 'community' }).Count | Should -Be 1
    }

    It 'accepts a single string and merges it into the required set' {
        $merged = Merge-Tags -Existing 'SoloTag'
        @($merged) | Should -Contain 'SoloTag'
        foreach ($r in $script:RequiredTags) { @($merged) | Should -Contain $r }
    }

    It 'returns just the required tags when input is empty/null' {
        $mergedNull  = Merge-Tags -Existing $null
        $mergedEmpty = Merge-Tags -Existing @()
        @($mergedNull).Count  | Should -Be $script:RequiredTags.Count
        @($mergedEmpty).Count | Should -Be $script:RequiredTags.Count
    }
}

Describe 'ConvertTo-Iso8601Duration' {
    It 'converts shorthand minute durations' {
        ConvertTo-Iso8601Duration -Value '5m'  | Should -Be 'PT5M'
        ConvertTo-Iso8601Duration -Value '30m' | Should -Be 'PT30M'
    }

    It 'converts shorthand hour durations' {
        ConvertTo-Iso8601Duration -Value '1h'  | Should -Be 'PT1H'
        ConvertTo-Iso8601Duration -Value '24h' | Should -Be 'PT24H'
    }

    It 'converts shorthand day durations' {
        ConvertTo-Iso8601Duration -Value '1d'  | Should -Be 'P1D'
        ConvertTo-Iso8601Duration -Value '7d'  | Should -Be 'P7D'
    }

    It 'returns the original value unchanged when already in ISO-8601' {
        ConvertTo-Iso8601Duration -Value 'PT5M' | Should -Be 'PT5M'
        ConvertTo-Iso8601Duration -Value 'P1D'  | Should -Be 'P1D'
    }

    It 'returns the original value unchanged for unrecognised formats' {
        ConvertTo-Iso8601Duration -Value 'abc'  | Should -Be 'abc'
        ConvertTo-Iso8601Duration -Value '5'    | Should -Be '5'
        ConvertTo-Iso8601Duration -Value ''     | Should -Be ''
    }
}

Describe 'Build-RuleYaml' {
    It 'throws when required fields are missing' {
        { Build-RuleYaml -Rule @{ id = 'x' } -SourceFile 'fake.yaml' } |
            Should -Throw -ExpectedMessage '*missing required fields*'
    }

    It 'forces enabled=false even when the source rule has enabled=true' {
        $rule = @{
            id        = 'sample-id'
            name      = 'Sample'
            kind      = 'Scheduled'
            severity  = 'Medium'
            query     = 'T | take 1'
            enabled   = $true
        }
        $yaml = Build-RuleYaml -Rule $rule -SourceFile 'fake.yaml'
        $parsed = ConvertFrom-Yaml $yaml
        $parsed.enabled | Should -BeFalse
    }

    It 'prepends attribution to the description' {
        $rule = @{
            id        = 'x'; name = 'Sample'; kind = 'Scheduled'; severity = 'Medium'; query = 'T'
            description = 'Original description'
        }
        $yaml = Build-RuleYaml -Rule $rule -SourceFile 'fake.yaml'
        $parsed = ConvertFrom-Yaml $yaml
        $parsed.description | Should -Match '^Community rule by David Alonso'
        $parsed.description | Should -Match 'Original description$'
    }

    It 'merges tags with the required set' {
        $rule = @{
            id = 'x'; name = 'Sample'; kind = 'Scheduled'; severity = 'Medium'; query = 'T'
            tags = @('UserTag')
        }
        $yaml = Build-RuleYaml -Rule $rule -SourceFile 'fake.yaml'
        $parsed = ConvertFrom-Yaml $yaml
        @($parsed.tags) | Should -Contain 'UserTag'
        @($parsed.tags) | Should -Contain 'Community'
        @($parsed.tags) | Should -Contain 'Dalonso'
        @($parsed.tags) | Should -Contain 'ThreatHunting'
    }

    It 'normalises triggerOperator from short to long form' {
        $rule = @{
            id = 'x'; name = 'Sample'; kind = 'Scheduled'; severity = 'Medium'; query = 'T'
            triggerOperator = 'gt'
        }
        $yaml = Build-RuleYaml -Rule $rule -SourceFile 'fake.yaml'
        $parsed = ConvertFrom-Yaml $yaml
        $parsed.triggerOperator | Should -Be 'GreaterThan'
    }
}

Describe 'ConvertFrom-ArmAlertRule' {
    BeforeAll {
        function New-ArmResource {
            param([hashtable]$PropOverride = @{})
            $base = @{
                displayName      = 'Sample ARM rule'
                description      = 'ARM description'
                severity         = 'High'
                query            = 'AuditLogs | take 1'
                queryFrequency   = '1h'
                queryPeriod      = '1d'
                triggerOperator  = 'gt'
                triggerThreshold = 0
                tactics          = @('InitialAccess')
                techniques       = @('T1078')
            }
            foreach ($k in $PropOverride.Keys) { $base[$k] = $PropOverride[$k] }

            $props = New-Object psobject
            foreach ($k in $base.Keys) {
                Add-Member -InputObject $props -MemberType NoteProperty -Name $k -Value $base[$k]
            }

            [pscustomobject]@{
                kind       = 'Scheduled'
                properties = $props
            }
        }
    }

    It 'maps every standard ARM alertRule field into the normalised rule' {
        $resource = New-ArmResource
        $yaml = ConvertFrom-ArmAlertRule -Resource $resource -SourceFile 'fake-arm.json'
        $parsed = ConvertFrom-Yaml $yaml
        $parsed.name             | Should -Be 'Sample ARM rule'
        $parsed.severity         | Should -Be 'High'
        $parsed.query            | Should -Be 'AuditLogs | take 1'
        $parsed.queryFrequency   | Should -Be 'PT1H'   # Iso-converted
        $parsed.queryPeriod      | Should -Be 'P1D'    # Iso-converted
        $parsed.triggerOperator  | Should -Be 'GreaterThan'  # short -> long via Build-RuleYaml
        $parsed.triggerThreshold | Should -Be 0
        @($parsed.tactics)       | Should -Contain 'InitialAccess'
        @($parsed.techniques)    | Should -Contain 'T1078'
    }

    It 'falls back to alertRuleTemplateName when displayName is absent' {
        $resource = New-ArmResource
        $resource.properties.PSObject.Properties.Remove('displayName')
        Add-Member -InputObject $resource.properties -MemberType NoteProperty -Name 'alertRuleTemplateName' -Value 'TemplateGuidName'
        $yaml = ConvertFrom-ArmAlertRule -Resource $resource -SourceFile 'fake-arm.json'
        $parsed = ConvertFrom-Yaml $yaml
        $parsed.name | Should -Be 'TemplateGuidName'
    }

    It 'forces enabled=false on the absorbed rule' {
        $resource = New-ArmResource
        $yaml = ConvertFrom-ArmAlertRule -Resource $resource -SourceFile 'fake-arm.json'
        $parsed = ConvertFrom-Yaml $yaml
        $parsed.enabled | Should -BeFalse
    }

    It 'preserves entityMappings when present' {
        $resource = New-ArmResource
        Add-Member -InputObject $resource.properties -MemberType NoteProperty -Name 'entityMappings' -Value @(
            @{ entityType = 'Account'; fieldMappings = @(@{ identifier = 'AadUserId'; columnName = 'Caller' }) }
        )
        $yaml = ConvertFrom-ArmAlertRule -Resource $resource -SourceFile 'fake-arm.json'
        $parsed = ConvertFrom-Yaml $yaml
        $parsed.ContainsKey('entityMappings') | Should -BeTrue
    }
}

Describe 'Import-YamlFile' {
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

    It 'imports a YAML source rule (ConvertFrom-Yaml -Ordered returns an OrderedDictionary, which used to be rejected)' {
        $yaml = Import-YamlFile -Path $script:sourcePath
        $yaml | Should -Not -BeNullOrEmpty
        $parsed = ConvertFrom-Yaml $yaml
        $parsed.id | Should -Be '11111111-2222-4333-8444-555555555555'
        $parsed.enabled | Should -BeFalse
        $parsed.triggerOperator | Should -Be 'GreaterThan'
        $parsed.description | Should -Match '^Community rule by David Alonso'
    }

    It 'keeps the source rule''s key order' {
        $keys = @((Import-YamlFile -Path $script:sourcePath) -split "`r?`n" | Where-Object { $_ -match '^[A-Za-z]+:' } | ForEach-Object { ($_ -split ':')[0] })
        $keys[0..3] | Should -Be @('id', 'name', 'description', 'severity')
        $keys | Should -Contain 'tags'
    }

    It 'skips a file that is not a mapping' {
        $list = Join-Path $TestDrive 'list.yaml'
        Set-Content -LiteralPath $list -Value "- a`n- b"
        Import-YamlFile -Path $list | Should -BeNullOrEmpty
    }
}

Describe 'Under Set-StrictMode -Version Latest, as the script runs' {
    # The script sets strict mode; these tests import its functions without
    # it, which hid a .Count on $null (no field missing) and on one string
    # (one field missing), and reads of ARM properties a resource lacks.
    It 'normalises a rule with every required field' {
        $yaml = & {
            Set-StrictMode -Version Latest
            Build-RuleYaml -Rule ([ordered]@{ id = 'x'; name = 'Sample'; kind = 'Scheduled'; severity = 'Medium'; query = 'T' }) -SourceFile 'fake.yaml'
        }
        (ConvertFrom-Yaml $yaml).enabled | Should -BeFalse
    }

    It 'names the one field a rule is missing' {
        { & { Set-StrictMode -Version Latest; Build-RuleYaml -Rule ([ordered]@{ id = 'x'; name = 'Sample'; kind = 'Scheduled'; query = 'T' }) -SourceFile 'fake.yaml' } } |
            Should -Throw -ExpectedMessage '*missing required fields: severity'
    }

    It 'converts an ARM rule without the optional properties' {
        $resource = [pscustomobject]@{ kind = 'Scheduled'; properties = [pscustomobject]@{ displayName = 'Bare'; alertRuleTemplateName = 't-1'; severity = 'Low'; query = 'T' } }
        $yaml = & { Set-StrictMode -Version Latest; ConvertFrom-ArmAlertRule -Resource $resource -SourceFile 'fake-arm.json' }
        $parsed = ConvertFrom-Yaml $yaml
        $parsed.id | Should -Be 't-1'
        $parsed.Contains('customDetails') | Should -BeFalse
    }
}

Describe 'Build-RuleYaml with an ordered rule' {
    It 'keeps the order of an ordered dictionary' {
        $rule = [ordered]@{ id = 'x'; name = 'Sample'; zeta = 1; kind = 'Scheduled'; severity = 'Medium'; alpha = 2; query = 'T' }
        $keys = @((Build-RuleYaml -Rule $rule -SourceFile 'fake.yaml') -split "`r?`n" | Where-Object { $_ -match '^[A-Za-z]+:' } | ForEach-Object { ($_ -split ':')[0] })
        $keys[0..6] | Should -Be @('id', 'name', 'zeta', 'kind', 'severity', 'alpha', 'query')
    }
}

Describe 'New-CommunityRuleId' {
    It 'matches the RFC 4122 version 5 GUID for <Name>' -ForEach @(
        @{ Name = 'example'; Expected = 'f8b72323-0e40-5a08-bd7f-039dfb85a9b2' }
        @{ Name = 'https://github.com/davidalonsod/Dalonso-Security-Repo#CommonSecurityLog/01-CSL-Beaconing-Detection.yaml'; Expected = '27601f16-757a-51d0-8d83-290d329141fc' }
    ) {
        # Expected values from Python's uuid.uuid5(uuid.NAMESPACE_URL, name).
        New-CommunityRuleId -Name $Name | Should -BeExactly $Expected
    }

    It 'gives different names different ids, and the same name the same id' {
        New-CommunityRuleId -Name 'a' | Should -Not -Be (New-CommunityRuleId -Name 'b')
        New-CommunityRuleId -Name 'a' | Should -BeExactly (New-CommunityRuleId -Name 'a')
    }
}

Describe 'Get-RuleFileId' {
    It 'reads a bare or quoted top-level id' {
        $bare = Join-Path $TestDrive 'bare.yaml'
        Set-Content -LiteralPath $bare -Value "id: 6F1C2A3B-0D4E-4F5A-9B8C-7D6E5F4A3B2C`nname: x"
        Get-RuleFileId -Path $bare | Should -BeExactly '6F1C2A3B-0D4E-4F5A-9B8C-7D6E5F4A3B2C'
        $quoted = Join-Path $TestDrive 'quoted.yaml'
        Set-Content -LiteralPath $quoted -Value "name: x`nid: 'abc-123'"
        Get-RuleFileId -Path $quoted | Should -BeExactly 'abc-123'
    }

    It 'returns nothing for a missing file or a file without an id' {
        Get-RuleFileId -Path (Join-Path $TestDrive 'absent.yaml') | Should -BeNullOrEmpty
        $none = Join-Path $TestDrive 'none.yaml'
        Set-Content -LiteralPath $none -Value "name: x`n  id: nested"
        Get-RuleFileId -Path $none | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-CommunityRuleId' {
    BeforeAll {
        $script:source = 'https://github.com/example-org/rules.git'
        function New-Pending {
            param([string] $RelativePath, [string] $Id)
            @{ RelativePath = $RelativePath; YamlContent = "id: $Id`nname: $RelativePath`nquery: |`n  T`n"; Category = 'X' }
        }
        function Get-PendingId { param($Rule) ([regex]::Match($Rule.YamlContent, '(?m)^id: (.+)$')).Groups[1].Value }
    }

    BeforeEach {
        $script:out = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:out | Out-Null
    }

    It 'leaves unique upstream ids alone and reports nothing' {
        $pending = [System.Collections.ArrayList]@((New-Pending 'A/one.yaml' 'id-1'), (New-Pending 'B/two.yaml' 'id-2'))
        @(Resolve-CommunityRuleId -PendingRules $pending -OutputPath $script:out -SourceRepo $script:source).Count | Should -Be 0
        Get-PendingId $pending[0] | Should -Be 'id-1'
        Get-PendingId $pending[1] | Should -Be 'id-2'
    }

    It 'keeps the first rule in path order on a shared upstream id and derives one for the next' {
        $pending = [System.Collections.ArrayList]@((New-Pending 'SigninLogs/x.yaml' 'shared'), (New-Pending 'CommonSecurityLog/y.yaml' 'SHARED'))
        $changes = @(Resolve-CommunityRuleId -PendingRules $pending -OutputPath $script:out -SourceRepo $script:source)
        Get-PendingId $pending[1] | Should -Be 'SHARED'
        $expected = New-CommunityRuleId -Name 'https://github.com/example-org/rules#SigninLogs/x.yaml'
        Get-PendingId $pending[0] | Should -Be $expected
        $changes.Count | Should -Be 1
        $changes[0].RelativePath | Should -Be 'SigninLogs/x.yaml'
        $changes[0].UpstreamId | Should -Be 'shared'
        $changes[0].Reason | Should -Match 'already used by CommonSecurityLog/y.yaml'
    }

    It 'keeps the id a repository file already has, whatever the upstream says' {
        New-Item -ItemType Directory -Path (Join-Path $script:out 'A') | Out-Null
        Set-Content -LiteralPath (Join-Path $script:out 'A/one.yaml') -Value "id: repo-id`nname: one"
        $pending = [System.Collections.ArrayList]@((New-Pending 'A/one.yaml' 'upstream-id'))
        $changes = @(Resolve-CommunityRuleId -PendingRules $pending -OutputPath $script:out -SourceRepo $script:source)
        Get-PendingId $pending[0] | Should -Be 'repo-id'
        $changes[0].Reason | Should -Be 'kept the id the repository file has'
    }

    It 'lets a repository file keep its id over a new rule that brings the same id' {
        New-Item -ItemType Directory -Path (Join-Path $script:out 'Z') | Out-Null
        Set-Content -LiteralPath (Join-Path $script:out 'Z/existing.yaml') -Value "id: taken`nname: existing"
        $pending = [System.Collections.ArrayList]@((New-Pending 'A/new.yaml' 'taken'), (New-Pending 'Z/existing.yaml' 'taken'))
        Resolve-CommunityRuleId -PendingRules $pending -OutputPath $script:out -SourceRepo $script:source | Out-Null
        Get-PendingId $pending[1] | Should -Be 'taken'
        Get-PendingId $pending[0] | Should -Be (New-CommunityRuleId -Name 'https://github.com/example-org/rules#A/new.yaml')
    }

    It 'derives an id when an in-house rule has the upstream id' {
        $pending = [System.Collections.ArrayList]@((New-Pending 'A/one.yaml' 'In-House-Id'))
        Resolve-CommunityRuleId -PendingRules $pending -OutputPath $script:out -SourceRepo $script:source -ReservedIds @{ 'in-house-id' = 'Identity/Rule.yaml' } | Out-Null
        Get-PendingId $pending[0] | Should -Not -Be 'In-House-Id'
    }

    It 'changes only the id line' {
        $pending = [System.Collections.ArrayList]@((New-Pending 'B/b.yaml' 'same'), (New-Pending 'A/a.yaml' 'same'))
        $before = $pending[0].YamlContent
        Resolve-CommunityRuleId -PendingRules $pending -OutputPath $script:out -SourceRepo $script:source | Out-Null
        $after = $pending[0].YamlContent
        ($after -split "`n")[1..9] | Should -Be (($before -split "`n")[1..9])
        ($after -split "`n")[0] | Should -Not -Be (($before -split "`n")[0])
    }

    It 'gives the same ids on every run' {
        $first = [System.Collections.ArrayList]@((New-Pending 'B/b.yaml' 'same'), (New-Pending 'A/a.yaml' 'same'))
        $second = [System.Collections.ArrayList]@((New-Pending 'A/a.yaml' 'same'), (New-Pending 'B/b.yaml' 'same'))
        Resolve-CommunityRuleId -PendingRules $first -OutputPath $script:out -SourceRepo $script:source | Out-Null
        Resolve-CommunityRuleId -PendingRules $second -OutputPath $script:out -SourceRepo "$($script:source)/" | Out-Null
        Get-PendingId $first[0] | Should -Be (Get-PendingId $second[1])
    }

    It 'refuses a rule with no top-level id line' {
        $pending = [System.Collections.ArrayList]@(@{ RelativePath = 'A/x.yaml'; YamlContent = "name: x`n" })
        { Resolve-CommunityRuleId -PendingRules $pending -OutputPath $script:out -SourceRepo $script:source } | Should -Throw -ExpectedMessage '*no top-level id line*'
    }
}

Describe 'A re-import of the Dalonso rules' {
    BeforeAll {
        $script:dalonso = Join-Path $repoRoot 'Content/AnalyticalRules/Community/Dalonso'
        $script:files = @(Get-ChildItem -LiteralPath $script:dalonso -Recurse -File -Include '*.yaml', '*.yml')
        $script:shared = Get-RuleFileId -Path (Join-Path $script:dalonso 'SigninLogs/11-SIGNIN-SlowLowPasswordSpray.yaml')
    }

    It 'keeps every id the repository has, even when the upstream reuses one across categories' {
        # Stand in for the upstream: every CommonSecurityLog rule arrives
        # with the id a SigninLogs rule has, as twelve of them once did.
        $pending = [System.Collections.ArrayList]::new()
        foreach ($file in $script:files) {
            $relative = [System.IO.Path]::GetRelativePath($script:dalonso, $file.FullName)
            $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8
            if ($relative -like 'CommonSecurityLog*') { $content = [regex]::new('(?m)^id:[^\r\n]*').Replace($content, "id: $($script:shared)", 1) }
            [void]$pending.Add(@{ RelativePath = $relative; YamlContent = $content; Category = 'x' })
        }
        $reserved = Get-ReservedRuleId -RulesRoot (Join-Path $repoRoot 'Content/AnalyticalRules') -ExcludePath $script:dalonso
        Resolve-CommunityRuleId -PendingRules $pending -OutputPath $script:dalonso -SourceRepo 'https://github.com/davidalonsod/Dalonso-Security-Repo.git' -ReservedIds $reserved | Out-Null

        $ids = @($pending | ForEach-Object { ([regex]::Match($_.YamlContent, '(?m)^id:[ \t]*(\S+)')).Groups[1].Value })
        @($ids | Group-Object | Where-Object Count -gt 1).Name | Should -BeNullOrEmpty
        for ($i = 0; $i -lt $pending.Count; $i++) {
            $ids[$i] | Should -Be (Get-RuleFileId -Path (Join-Path $script:dalonso $pending[$i].RelativePath)) -Because $pending[$i].RelativePath
        }
    }

    It 'reserves the in-house ids and none of the community folder''s' {
        $reserved = Get-ReservedRuleId -RulesRoot (Join-Path $repoRoot 'Content/AnalyticalRules') -ExcludePath $script:dalonso
        $reserved.Count | Should -BeGreaterThan 50
        @($reserved.Values | Where-Object { $_ -like 'Community/Dalonso/*' }) | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-Main' {
    It 'resolves the ids before it hashes or writes any rule' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'Tools/Import-CommunityRules.ps1'), [ref]$null, [ref]$null)
        $main = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-Main' }, $false) | Select-Object -First 1
        $text = $main.Extent.Text
        $resolve = $text.IndexOf('Resolve-CommunityRuleId')
        $resolve | Should -BeGreaterThan 0
        $resolve | Should -BeLessThan $text.IndexOf('Get-ContentHash256')
        $resolve | Should -BeLessThan $text.IndexOf('Write-OutputFile -FilePath $destFile')
        $resolve | Should -BeGreaterThan $text.IndexOf('Total rules collected')
    }
}
