#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 unit tests for the pure functions in
    Scripts/Import-CommunityRules.ps1: the YAML/ARM normalisation
    pipeline applied to imported community rule content.

.DESCRIPTION
    Six pure functions worth pinning with tests:
      - Get-ContentHash256 (SHA256 hashing for the import manifest)
      - Format-TriggerOperator (gt/lt/eq/ne -> GreaterThan/etc.)
      - Merge-Tags (case-insensitive, dedup-and-sort tag merge)
      - ConvertTo-Iso8601Duration (24h/7d -> PT24H/P7D shorthand expansion)
      - Build-RuleYaml (forces enabled=false, prepends attribution,
        merges tags, normalises trigger operator)
      - ConvertFrom-ArmAlertRule (ARM alertRule resource -> normalised
        rule hashtable)

    Builds on the AST extractor in
    Tests/_helpers/Import-ScriptFunctions.psm1.
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Scripts/Import-CommunityRules.ps1'

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
