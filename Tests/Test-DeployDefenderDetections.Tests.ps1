#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 unit tests for the pure function in
    Scripts/Deploy-DefenderDetections.ps1: the YAML-to-Graph-API body
    converter.

.DESCRIPTION
    The Defender deployer reads YAML rules from DefenderCustomDetections/
    and converts each into the JSON body expected by the Graph Security
    custom-detection-rule POST/PATCH endpoints. Schema docs:
    Docs/Content/Defender-Custom-Detections.md.

    `ConvertTo-GraphDetectionBody` is the conversion. These tests pin:
      - Required fields land in the right shape
      - Optional fields propagate when present, are absent when not
      - isEnabled defaults to $true when omitted
      - responseActions default to an empty array when the rule has none
      - mitreTechniques and impactedAssets are forced to arrays
      - lastModifiedDateTime forwards from queryCondition
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Scripts/Deploy-DefenderDetections.ps1'

    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop
    Import-ScriptFunctions -Path $scriptPath

    function Write-PipelineMessage {
        param([string]$Message, [string]$Level = 'Info')
    }

    # Minimal-shape factory for a detection rule. Covers required fields;
    # individual tests add optional fields via Override.
    function New-MinimalDetectionRule {
        param([hashtable]$Override = @{})
        $rule = @{
            displayName    = 'Test rule'
            queryCondition = @{
                queryText = 'IdentityLogonEvents | take 1'
            }
            schedule       = @{ period = '1H' }
            detectionAction = @{
                alertTemplate = @{
                    title    = 'Test alert'
                    severity = 'medium'
                    category = 'Execution'
                }
            }
        }
        foreach ($key in $Override.Keys) { $rule[$key] = $Override[$key] }
        return $rule
    }
}

Describe 'ConvertTo-GraphDetectionBody' {
    Context 'Required fields' {
        It 'includes displayName, queryCondition.queryText, schedule.period, alertTemplate.title/severity/category' {
            $rule = New-MinimalDetectionRule
            $body = ConvertTo-GraphDetectionBody -Rule $rule

            $body.displayName | Should -Be 'Test rule'
            $body.queryCondition.queryText | Should -Be 'IdentityLogonEvents | take 1'
            $body.schedule.period | Should -Be '1H'
            $body.detectionAction.alertTemplate.title    | Should -Be 'Test alert'
            $body.detectionAction.alertTemplate.severity | Should -Be 'medium'
            $body.detectionAction.alertTemplate.category | Should -Be 'Execution'
        }
    }

    Context 'isEnabled handling' {
        It 'defaults isEnabled to true when omitted from the rule' {
            $rule = New-MinimalDetectionRule
            $body = ConvertTo-GraphDetectionBody -Rule $rule
            $body.isEnabled | Should -BeTrue
        }

        It 'forwards isEnabled when explicitly set to false' {
            $rule = New-MinimalDetectionRule
            $rule['isEnabled'] = $false
            $body = ConvertTo-GraphDetectionBody -Rule $rule
            $body.isEnabled | Should -BeFalse
        }

        It 'coerces non-bool isEnabled to a bool' {
            $rule = New-MinimalDetectionRule
            $rule['isEnabled'] = 0   # PowerShell coerces 0 -> $false
            $body = ConvertTo-GraphDetectionBody -Rule $rule
            $body.isEnabled | Should -BeOfType ([bool])
            $body.isEnabled | Should -BeFalse
        }
    }

    Context 'Optional alertTemplate fields' {
        It 'includes description when present, omits when absent' {
            $without = ConvertTo-GraphDetectionBody -Rule (New-MinimalDetectionRule)
            $without.detectionAction.alertTemplate.ContainsKey('description') | Should -BeFalse

            $rule = New-MinimalDetectionRule
            $rule['detectionAction']['alertTemplate']['description'] = 'Optional description'
            $with = ConvertTo-GraphDetectionBody -Rule $rule
            $with.detectionAction.alertTemplate.description | Should -Be 'Optional description'
        }

        It 'forces mitreTechniques to an array' {
            $rule = New-MinimalDetectionRule
            $rule['detectionAction']['alertTemplate']['mitreTechniques'] = @('T1078', 'T1110.003')
            $body = ConvertTo-GraphDetectionBody -Rule $rule
            ($body.detectionAction.alertTemplate.mitreTechniques -is [System.Array]) | Should -BeTrue
            @($body.detectionAction.alertTemplate.mitreTechniques).Count | Should -Be 2
        }

        It 'forces impactedAssets to an array' {
            $rule = New-MinimalDetectionRule
            $rule['detectionAction']['alertTemplate']['impactedAssets'] = @(
                @{ '@odata.type' = '#microsoft.graph.security.impactedUserAsset'; identifier = 'accountObjectId' }
            )
            $body = ConvertTo-GraphDetectionBody -Rule $rule
            ($body.detectionAction.alertTemplate.impactedAssets -is [System.Array]) | Should -BeTrue
        }

        It 'forwards recommendedActions when present' {
            $rule = New-MinimalDetectionRule
            $rule['detectionAction']['alertTemplate']['recommendedActions'] = '1. Reset password.'
            $body = ConvertTo-GraphDetectionBody -Rule $rule
            $body.detectionAction.alertTemplate.recommendedActions | Should -Be '1. Reset password.'
        }
    }

    Context 'responseActions handling' {
        It 'defaults responseActions to an empty array when absent on the rule' {
            $rule = New-MinimalDetectionRule
            $body = ConvertTo-GraphDetectionBody -Rule $rule
            ($body.detectionAction.responseActions -is [System.Array]) | Should -BeTrue
            @($body.detectionAction.responseActions).Count | Should -Be 0
        }

        It 'forwards responseActions array when present' {
            $rule = New-MinimalDetectionRule
            $rule['detectionAction']['responseActions'] = @(
                @{
                    '@odata.type' = '#microsoft.graph.security.forceUserPasswordResetResponseAction'
                    identifier    = 'accountSid'
                }
            )
            $body = ConvertTo-GraphDetectionBody -Rule $rule
            @($body.detectionAction.responseActions).Count | Should -Be 1
            ($body.detectionAction.responseActions)[0].'@odata.type' | Should -Match 'forceUserPasswordResetResponseAction$'
        }

        It 'casts a single response action to an array' {
            $rule = New-MinimalDetectionRule
            $rule['detectionAction']['responseActions'] = @(
                @{ '@odata.type' = '#microsoft.graph.security.disableUserResponseAction'; identifier = 'accountSid' }
            )
            $body = ConvertTo-GraphDetectionBody -Rule $rule
            ($body.detectionAction.responseActions -is [System.Array]) | Should -BeTrue
        }
    }

    Context 'queryCondition optional fields' {
        It 'forwards lastModifiedDateTime when present on the rule' {
            $rule = New-MinimalDetectionRule
            $rule['queryCondition']['lastModifiedDateTime'] = '2026-04-29T00:00:00Z'
            $body = ConvertTo-GraphDetectionBody -Rule $rule
            $body.queryCondition.lastModifiedDateTime | Should -Be '2026-04-29T00:00:00Z'
        }

        It 'omits lastModifiedDateTime from the body when absent' {
            $body = ConvertTo-GraphDetectionBody -Rule (New-MinimalDetectionRule)
            $body.queryCondition.ContainsKey('lastModifiedDateTime') | Should -BeFalse
        }
    }

    Context 'organizationalScope' {
        It 'always sets organizationalScope to null on the body (current Graph contract)' {
            $body = ConvertTo-GraphDetectionBody -Rule (New-MinimalDetectionRule)
            $body.detectionAction.ContainsKey('organizationalScope') | Should -BeTrue
            $body.detectionAction.organizationalScope | Should -BeNullOrEmpty
        }
    }
}
