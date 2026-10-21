#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 unit tests for Deploy/content/Deploy-SentinelContentHub.ps1:
    SemVer comparison, the customisation detector and the solution
    deployment request body.

.DESCRIPTION
    Covers:
      - Compare-SemanticVersion (SemVer comparison with parse-error
        fallback to ordinal string compare)
      - Test-RuleIsCustomised (the customisation-protection comparator
        that decides whether to overwrite a deployed rule with its
        Content Hub template, used by -ProtectCustomisedRules)
      - ConvertTo-SolutionDeploymentJson (the compact ARM deployment
        body a solution package is sent as)
      - Deploy-Solution's request size check, which skips a package over
        the 4 MB ARM limit instead of sending it. Invoke-SentinelApi is
        mocked, so nothing reaches Azure.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-DeploySentinelContentHub.Tests.ps1

    Runs the SemVer and customisation-detector tests.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-DeploySentinelContentHub.Tests.ps1 -FullName '*Test-RuleIsCustomised*'

    Runs only the customisation-protection comparator assertions.

.NOTES
    File:         Tests/Test-DeploySentinelContentHub.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-05-13
    Version:      0.2.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Deploy/content/Deploy-SentinelContentHub.ps1'

    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop
    Import-ScriptFunctions -Path $scriptPath

    # Pull in Write-PipelineMessage from the shared module rather than
    # stubbing it locally — the AST extractor skips the top-level
    # Import-Module statement, so this restores the dependency at runtime.
    Import-Module (Join-Path $repoRoot 'Modules/Sentinel.Common/Sentinel.Common.psd1') -Force -ErrorAction Stop

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

Describe 'Alert rules API version' {
    # Every GA version of alertRules leaves out subTechniques and
    # sentinelEntitiesMappings: a PUT on GA succeeds and silently drops them.
    It 'sends every alertRules call with the pinned preview version' {
        $text = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Deploy/content/Deploy-SentinelContentHub.ps1') -Raw
        $text | Should -Match '(?m)^\$script:AlertRuleApiVersion\s*=\s*"\d{4}-\d{2}-\d{2}-preview"'
        $calls = [regex]::Matches($text, '(?:alertRules|baseAlertUri\})[^"\r\n]*\?api-version=\$\(\$script:(\w+)\)')
        $calls.Count | Should -BeGreaterThan 0
        @($calls | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique) | Should -Be @('AlertRuleApiVersion')
    }
}

Describe 'ConvertTo-SolutionDeploymentJson' {
    BeforeAll {
        $package = [pscustomobject]@{
            contentVersion = '1.0.0.0'
            resources      = @(
                [pscustomobject]@{
                    type       = 'Microsoft.OperationalInsights/workspaces/providers/contentTemplates'
                    properties = [pscustomobject]@{
                        displayName  = 'Café rule'
                        mainTemplate = [pscustomobject]@{
                            resources = @(
                                [pscustomobject]@{ properties = [pscustomobject]@{ query = [pscustomobject]@{ text = 'SecurityEvent | take 1' } } }
                            )
                        }
                    }
                }
            )
        }
        $json = ConvertTo-SolutionDeploymentJson -PackagedContent $package -Workspace 'law-test' -Region 'uksouth'
    }

    It 'emits compact single-line JSON' {
        # Indented output pushed Microsoft Defender XDR over the 4 MB ARM
        # request limit, so any whitespace between tokens is a regression.
        $json | Should -Not -Match '\n'
        $json | Should -Not -Match '": '
    }

    It 'carries the workspace, region and incremental mode' {
        $body = $json | ConvertFrom-Json
        $body.properties.parameters.workspace.value | Should -Be 'law-test'
        $body.properties.parameters.'workspace-location'.value | Should -Be 'uksouth'
        $body.properties.mode | Should -Be 'Incremental'
    }

    It 'keeps template content nested beyond the default serialisation depth' {
        $body = $json | ConvertFrom-Json
        @($body.properties.template.resources)[0].properties.mainTemplate.resources[0].properties.query.text |
            Should -Be 'SecurityEvent | take 1'
    }

    It 'escapes non-ASCII characters' {
        $json | Should -BeLike '*Caf\u00e9 rule*'
    }
}

Describe 'Deploy-Solution request size check' {
    BeforeAll {
        $WhatIf        = $false
        $ResourceGroup = 'rg-test'
        $Workspace     = 'law-test'
        $Region        = 'uksouth'

        $script:BaseUri              = 'https://management.azure.com/subscriptions/0000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test'
        $script:ServerUrl            = 'https://management.azure.com'
        $script:SubscriptionId       = '0000'
        $script:AuthHeader           = @{ Authorization = 'Bearer test' }
        $script:SentinelApiVersion   = '2025-09-01'
        $script:DeploymentApiVersion = '2024-11-01'

        # A small limit keeps the fixtures small. The production value is
        # 4 MB, set at the top of the script.
        $script:MaxDeploymentRequestBytes = 2KB

        $status = [pscustomobject]@{
            Name             = 'Test Solution'
            CatalogEntry     = [pscustomobject]@{ name = 'test.solution'; properties = [pscustomobject]@{} }
            Action           = 'Install'
            InstalledVersion = $null
            AvailableVersion = '1.0.0'
        }
    }

    BeforeEach {
        Mock Write-PipelineMessage { }
        Mock Start-Sleep { }
        Mock Invoke-SentinelApi -ParameterFilter { $Method -eq 'Put' } { [pscustomobject]@{} }
    }

    It 'skips a package over the limit without sending it' {
        Mock Invoke-SentinelApi -ParameterFilter { $Method -eq 'Get' } {
            [pscustomobject]@{ properties = [pscustomobject]@{ packagedContent = [pscustomobject]@{
                resources = @([pscustomobject]@{ properties = [pscustomobject]@{ description = ('x' * 4000) } })
            } } }
        }

        Deploy-Solution -SolutionStatus $status | Should -BeFalse

        Should -Invoke Invoke-SentinelApi -ParameterFilter { $Method -eq 'Put' } -Times 0 -Exactly
        Should -Invoke Write-PipelineMessage -ParameterFilter {
            $Level -eq 'Error' -and $Message -like '*Test Solution v1.0.0 is * MB*over the * MB ARM limit*'
        } -Times 1 -Exactly
    }

    It 'sends a package under the limit as compact JSON' {
        Mock Invoke-SentinelApi -ParameterFilter { $Method -eq 'Get' } {
            [pscustomobject]@{ properties = [pscustomobject]@{ packagedContent = [pscustomobject]@{
                resources = @([pscustomobject]@{ properties = [pscustomobject]@{ description = 'small' } })
            } } }
        }

        Deploy-Solution -SolutionStatus $status | Should -BeTrue

        Should -Invoke Invoke-SentinelApi -ParameterFilter {
            $Method -eq 'Put' -and $Body -notmatch '\n' -and $Body -like '*"description":"small"*'
        } -Times 1 -Exactly
    }
}
