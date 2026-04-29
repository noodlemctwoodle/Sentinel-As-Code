#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 unit tests for the pure functions in
    Scripts/Deploy-SentinelContentHub.ps1: SemVer comparison and the
    customisation detector.

.DESCRIPTION
    Two pure functions worth pinning with tests:
      - Compare-SemanticVersion (SemVer comparison with parse-error
        fallback to ordinal string compare)
      - Test-RuleIsCustomised (the customisation-protection comparator
        that decides whether to overwrite a deployed rule with its
        Content Hub template, used by -ProtectCustomisedRules)
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Scripts/Deploy-SentinelContentHub.ps1'

    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop
    Import-ScriptFunctions -Path $scriptPath

    # Stub Write-PipelineMessage since extracted functions may call it.
    function Write-PipelineMessage {
        param([string]$Message, [string]$Level = 'Info')
    }

    # Mock builders. Both functions take PSObject-shaped rule/template
    # objects mirroring what the Sentinel REST API returns.
    function New-DeployedRuleProps {
        param([hashtable]$Override = @{})
        $base = @{
            query            = 'T | take 1'
            queryFrequency   = 'PT5M'
            queryPeriod      = 'PT5M'
            triggerOperator  = 'GreaterThan'
            triggerThreshold = 0
            severity         = 'Medium'
        }
        foreach ($key in $Override.Keys) { $base[$key] = $Override[$key] }

        $obj = New-Object psobject
        foreach ($key in $base.Keys) {
            Add-Member -InputObject $obj -MemberType NoteProperty -Name $key -Value $base[$key]
        }
        return $obj
    }

    function New-DeployedRule {
        param([hashtable]$PropsOverride = @{})
        [pscustomobject]@{
            name       = (New-Guid).Guid
            properties = (New-DeployedRuleProps -Override $PropsOverride)
        }
    }
}

Describe 'Compare-SemanticVersion' {
    It 'returns -1 when v1 is older than v2' {
        Compare-SemanticVersion -Version1 '1.0.0' -Version2 '2.0.0' | Should -Be -1
        Compare-SemanticVersion -Version1 '1.2.3' -Version2 '1.2.4' | Should -Be -1
        Compare-SemanticVersion -Version1 '1.0.0' -Version2 '1.0.1' | Should -Be -1
    }

    It 'returns 1 when v1 is newer than v2' {
        Compare-SemanticVersion -Version1 '2.0.0' -Version2 '1.0.0' | Should -Be 1
        Compare-SemanticVersion -Version1 '1.2.4' -Version2 '1.2.3' | Should -Be 1
    }

    It 'returns 0 for identical versions' {
        Compare-SemanticVersion -Version1 '1.2.3' -Version2 '1.2.3' | Should -Be 0
        Compare-SemanticVersion -Version1 '0.0.1' -Version2 '0.0.1' | Should -Be 0
    }

    It 'pads missing components with zero (1.2 == 1.2.0)' {
        Compare-SemanticVersion -Version1 '1.2'   -Version2 '1.2.0' | Should -Be 0
        Compare-SemanticVersion -Version1 '1.2.0' -Version2 '1.2'   | Should -Be 0
        Compare-SemanticVersion -Version1 '1'     -Version2 '1.0.0' | Should -Be 0
    }

    It 'compares major before minor before patch' {
        # 2.0.0 > 1.99.99: major dominates
        Compare-SemanticVersion -Version1 '2.0.0' -Version2 '1.99.99' | Should -Be 1
        # 1.2.0 > 1.1.99: minor dominates patch
        Compare-SemanticVersion -Version1 '1.2.0' -Version2 '1.1.99'  | Should -Be 1
    }

    It 'falls back to ordinal string comparison on parse failure' {
        # Non-numeric versions cannot parse as int; function falls back.
        $result = Compare-SemanticVersion -Version1 '1.0.0-alpha' -Version2 '1.0.0-beta'
        # 'alpha' < 'beta' ordinally, so result should be < 0.
        $result | Should -BeLessThan 0
    }
}

Describe 'Test-RuleIsCustomised' {
    Context 'No customisation' {
        It 'returns IsCustomised=false when every compared field matches' {
            $rule     = New-DeployedRule
            $template = New-DeployedRuleProps   # same defaults as rule.properties
            $result = Test-RuleIsCustomised -ExistingRule $rule -TemplateProperties $template
            $result.IsCustomised  | Should -BeFalse
            @($result.Modifications).Count | Should -Be 0
        }

        It 'tolerates whitespace differences in the query (does not flag as customised)' {
            $rule     = New-DeployedRule -PropsOverride @{ query = "T`n| take 1" }
            $template = New-DeployedRuleProps -Override @{ query = 'T | take 1' }
            $result = Test-RuleIsCustomised -ExistingRule $rule -TemplateProperties $template
            $result.IsCustomised | Should -BeFalse -Because 'whitespace is collapsed before comparison; a multi-line vs single-line query with the same tokens is not a real customisation'
        }
    }

    Context 'Single-field customisation' {
        It 'detects severity drift' {
            $rule     = New-DeployedRule -PropsOverride @{ severity = 'High' }
            $template = New-DeployedRuleProps -Override @{ severity = 'Medium' }
            $result = Test-RuleIsCustomised -ExistingRule $rule -TemplateProperties $template
            $result.IsCustomised | Should -BeTrue
            @($result.Modifications) | Should -Contain 'severity'
        }

        It 'detects query drift after whitespace collapse' {
            $rule     = New-DeployedRule -PropsOverride @{ query = 'T | take 1 | extend X = 1' }
            $template = New-DeployedRuleProps -Override @{ query = 'T | take 1' }
            $result = Test-RuleIsCustomised -ExistingRule $rule -TemplateProperties $template
            $result.IsCustomised | Should -BeTrue
            @($result.Modifications) | Should -Contain 'KQL query'
        }

        It 'detects triggerThreshold drift' {
            $rule     = New-DeployedRule -PropsOverride @{ triggerThreshold = 5 }
            $template = New-DeployedRuleProps -Override @{ triggerThreshold = 0 }
            $result = Test-RuleIsCustomised -ExistingRule $rule -TemplateProperties $template
            $result.IsCustomised | Should -BeTrue
            @($result.Modifications) | Should -Contain 'triggerThreshold'
        }

        It 'detects triggerOperator drift' {
            $rule     = New-DeployedRule -PropsOverride @{ triggerOperator = 'LessThan' }
            $template = New-DeployedRuleProps -Override @{ triggerOperator = 'GreaterThan' }
            $result = Test-RuleIsCustomised -ExistingRule $rule -TemplateProperties $template
            $result.IsCustomised | Should -BeTrue
            @($result.Modifications) | Should -Contain 'triggerOperator'
        }

        It 'detects queryFrequency drift' {
            $rule     = New-DeployedRule -PropsOverride @{ queryFrequency = 'PT15M' }
            $template = New-DeployedRuleProps -Override @{ queryFrequency = 'PT5M' }
            $result = Test-RuleIsCustomised -ExistingRule $rule -TemplateProperties $template
            $result.IsCustomised | Should -BeTrue
            @($result.Modifications) | Should -Contain 'queryFrequency'
        }

        It 'detects queryPeriod drift' {
            $rule     = New-DeployedRule -PropsOverride @{ queryPeriod = 'PT1H' }
            $template = New-DeployedRuleProps -Override @{ queryPeriod = 'PT5M' }
            $result = Test-RuleIsCustomised -ExistingRule $rule -TemplateProperties $template
            $result.IsCustomised | Should -BeTrue
            @($result.Modifications) | Should -Contain 'queryPeriod'
        }
    }

    Context 'Multi-field customisation' {
        It 'reports every modified field in the Modifications array' {
            $rule     = New-DeployedRule -PropsOverride @{
                severity         = 'High'
                triggerThreshold = 5
            }
            $template = New-DeployedRuleProps -Override @{
                severity         = 'Medium'
                triggerThreshold = 0
            }
            $result = Test-RuleIsCustomised -ExistingRule $rule -TemplateProperties $template
            $result.IsCustomised | Should -BeTrue
            @($result.Modifications).Count | Should -Be 2
            @($result.Modifications) | Should -Contain 'severity'
            @($result.Modifications) | Should -Contain 'triggerThreshold'
        }
    }

    Context 'No false positives on entityMappings' {
        It 'does not flag entityMappings JSON shape differences' {
            # Both rule and template have entityMappings, but with different
            # internal serialisation (array vs nested). The function explicitly
            # excludes entityMappings from comparison to avoid false positives.
            $ruleProps = New-DeployedRuleProps
            Add-Member -InputObject $ruleProps -MemberType NoteProperty -Name 'entityMappings' -Value @(
                @{ entityType = 'Account'; fieldMappings = @(@{ identifier = 'AadUserId'; columnName = 'Caller' }) }
            )
            $rule = [pscustomobject]@{ name = 'r1'; properties = $ruleProps }

            $template = New-DeployedRuleProps
            Add-Member -InputObject $template -MemberType NoteProperty -Name 'entityMappings' -Value @(
                # Same logical content, different ordering / serialisation.
                @{ fieldMappings = @(@{ columnName = 'Caller'; identifier = 'AadUserId' }); entityType = 'Account' }
            )

            $result = Test-RuleIsCustomised -ExistingRule $rule -TemplateProperties $template
            $result.IsCustomised | Should -BeFalse
        }
    }

    Context 'Missing fields' {
        It 'skips comparison when only one side has the field' {
            $ruleProps = New-DeployedRuleProps
            $template = New-Object psobject   # template has no comparable fields
            Add-Member -InputObject $template -MemberType NoteProperty -Name 'severity' -Value 'Medium'

            $rule = [pscustomobject]@{ name = 'r1'; properties = $ruleProps }
            $result = Test-RuleIsCustomised -ExistingRule $rule -TemplateProperties $template
            # Severity is the only field on both: deployed Medium == template Medium.
            $result.IsCustomised | Should -BeFalse
        }
    }
}
