#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 unit tests for the pure functions in
    Deploy/content/Deploy-DefenderDetections.ps1: the legacy-shape
    translation, the rule validator and the Graph request body builder.

.DESCRIPTION
    The Defender deployer reads YAML rules from Content/DefenderCustomDetections/
    and sends each to the Graph beta detectionRules endpoint in the shape in
    place after Microsoft removed the original fields on 2026-10-01. Schema
    docs: Docs/Content/Defender-Custom-Detections.md. These tests pin:

      - ConvertTo-DetectionFrequency: ISO durations and legacy periods to
        the canonical frequency, rejecting frequencies the service does not run
      - ConvertTo-DetectionTactic: category + mitreTechniques to tactics,
        sub-techniques grouped under their parent
      - ConvertTo-DetectionEntityMapping / ConvertTo-DetectionAutomatedAction:
        identifier tokens to query column names
      - ConvertFrom-LegacyDetectionRule: a whole legacy rule translated, a
        current rule left alone
      - Test-DetectionRule: the problems that make the deployer skip a file
      - ConvertTo-GraphDetectionBody: the request body, with the id only
        when creating
      - Get-DetectionMappedColumn: the columns a rule depends on

.EXAMPLE
    Invoke-Pester -Path Tests/Test-DeployDefenderDetections.Tests.ps1

    Runs the translation, validation and body tests.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-DeployDefenderDetections.Tests.ps1 -Output Detailed

    Runs with per-assertion output, for diagnosing which converted field
    came out in the wrong shape.

.NOTES
    File:         Tests/Test-DeployDefenderDetections.Tests.ps1
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
    $scriptPath = Join-Path $repoRoot 'Deploy/content/Deploy-DefenderDetections.ps1'

    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop
    Import-ScriptFunctions -Path $scriptPath

    # Pull in Write-PipelineMessage from the shared module rather than
    # stubbing it locally; the AST extractor skips the top-level
    # Import-Module statement, so this restores the dependency at runtime.
    Import-Module (Join-Path $repoRoot 'Modules/Sentinel.Common/Sentinel.Common.psd1') -Force -ErrorAction Stop

    # A minimal rule in the current shape; tests add or replace fields.
    function New-CurrentRule {
        @{
            id              = 'test-rule'
            displayName     = 'Test rule'
            status          = 'enabled'
            queryCondition  = @{ queryText = 'DeviceProcessEvents | project Timestamp, ReportId, DeviceId, AccountSid' }
            schedule        = @{ frequency = 'PT1H' }
            detectionAction = @{
                alertTemplate = @{
                    title    = 'Test alert'
                    severity = 'medium'
                    tactics  = @(@{ tactic = 'Execution'; techniques = @(@{ technique = 'T1059'; subTechniques = @('T1059.001') }) })
                }
            }
        }
    }

    # The same rule written with the retired field names.
    function New-LegacyRule {
        @{
            displayName     = 'Legacy rule'
            isEnabled       = $false
            queryCondition  = @{ queryText = 'DeviceProcessEvents | take 1'; lastModifiedDateTime = '2026-03-20T00:00:00Z' }
            schedule        = @{ period = '24H' }
            detectionAction = @{
                alertTemplate   = @{
                    title           = 'Legacy alert'
                    severity        = 'high'
                    category        = 'CredentialAccess'
                    mitreTechniques = @('T1110.001', 'T1110.003', 'T1078')
                    impactedAssets  = @(@{ '@odata.type' = '#microsoft.graph.security.impactedUserAsset'; identifier = 'accountObjectId' })
                }
                responseActions = @(
                    @{ '@odata.type' = '#microsoft.graph.security.forceUserPasswordResetResponseAction'; identifier = 'accountSid' }
                )
            }
        }
    }
}

Describe 'ConvertTo-DetectionFrequency' {
    It 'writes <Value> as <Expected>' -ForEach @(
        @{ Value = 'PT1H';  Expected = 'PT1H' }
        @{ Value = 'PT24H'; Expected = 'P1D' }
        @{ Value = 'P1D';   Expected = 'P1D' }
        @{ Value = '3H';    Expected = 'PT3H' }
        @{ Value = '12H';   Expected = 'PT12H' }
        @{ Value = 'pt1h';  Expected = 'PT1H' }
    ) {
        ConvertTo-DetectionFrequency -Value $Value | Should -BeExactly $Expected
    }

    It 'rejects <Value>, which the service does not run' -ForEach @(
        @{ Value = '0' }, @{ Value = 'PT5M' }, @{ Value = 'PT2H' }, @{ Value = 'P2D' }, @{ Value = 'hourly' }, @{ Value = '' }
    ) {
        ConvertTo-DetectionFrequency -Value $Value | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-DetectionTactic' {
    It 'groups sub-techniques under their parent in first-seen order' {
        $tactics = ConvertTo-DetectionTactic -Category 'CredentialAccess' -MitreTechniques @('T1110.001', 'T1078', 'T1110.003')
        @($tactics).Count | Should -Be 1
        $tactics[0].tactic | Should -Be 'CredentialAccess'
        @($tactics[0].techniques.technique) | Should -Be @('T1110', 'T1078')
        @($tactics[0].techniques[0].subTechniques) | Should -Be @('T1110.001', 'T1110.003')
        $tactics[0].techniques[1].Contains('subTechniques') | Should -BeFalse
    }

    It 'keeps a lone tactic when there are no techniques' {
        $tactics = ConvertTo-DetectionTactic -Category 'Impact' -MitreTechniques @()
        @($tactics).Count | Should -Be 1
        $tactics[0].Contains('techniques') | Should -BeFalse
    }
}

Describe 'ConvertTo-DetectionEntityMapping' {
    It 'maps <Identifier> on a <Type> to <Collection>.<Property> = <Column>' -ForEach @(
        @{ Type = 'impactedUserAsset';    Identifier = 'accountObjectId';             Collection = 'accounts';  Property = 'aadUserIdColumn';      Column = 'AccountObjectId' }
        @{ Type = 'impactedUserAsset';    Identifier = 'accountSid';                  Collection = 'accounts';  Property = 'sidColumn';            Column = 'AccountSid' }
        @{ Type = 'impactedUserAsset';    Identifier = 'accountUpn';                  Collection = 'accounts';  Property = 'upnColumn';            Column = 'AccountUpn' }
        @{ Type = 'impactedUserAsset';    Identifier = 'initiatingProcessAccountSid'; Collection = 'accounts';  Property = 'sidColumn';            Column = 'InitiatingProcessAccountSid' }
        @{ Type = 'impactedDeviceAsset';  Identifier = 'deviceId';                    Collection = 'hosts';     Property = 'deviceIdColumn';       Column = 'DeviceId' }
        @{ Type = 'impactedDeviceAsset';  Identifier = 'deviceName';                  Collection = 'hosts';     Property = 'nameColumn';           Column = 'DeviceName' }
        @{ Type = 'impactedMailboxAsset'; Identifier = 'recipientEmailAddress';       Collection = 'mailboxes'; Property = 'primaryAddressColumn'; Column = 'RecipientEmailAddress' }
    ) {
        $mapping = ConvertTo-DetectionEntityMapping -ImpactedAssets @(@{ '@odata.type' = "#microsoft.graph.security.$Type"; identifier = $Identifier })
        $mapping[$Collection][0][$Property] | Should -BeExactly $Column
    }

    It 'adds one mapping per asset in the same collection' {
        $mapping = ConvertTo-DetectionEntityMapping -ImpactedAssets @(
            @{ '@odata.type' = '#microsoft.graph.security.impactedUserAsset'; identifier = 'accountObjectId' }
            @{ '@odata.type' = '#microsoft.graph.security.impactedUserAsset'; identifier = 'accountUpn' }
        )
        @($mapping['accounts']).Count | Should -Be 2
    }

    It 'throws for an identifier it cannot place, rather than guess' {
        { ConvertTo-DetectionEntityMapping -ImpactedAssets @(@{ '@odata.type' = '#microsoft.graph.security.impactedUserAsset'; identifier = 'servicePrincipalId' }) } |
            Should -Throw -ExpectedMessage '*servicePrincipalId*'
    }
}

Describe 'ConvertTo-DetectionAutomatedAction' {
    It 'maps a single-identifier action to its column property' {
        $actions = ConvertTo-DetectionAutomatedAction -ResponseActions @(
            @{ '@odata.type' = '#microsoft.graph.security.markUserAsCompromisedResponseAction'; identifier = 'recipientObjectId' }
        )
        $actions['markUsersAsCompromised'][0]['accountObjectIdColumn'] | Should -BeExactly 'RecipientObjectId'
    }

    It 'splits a two-identifier email action into both column properties' {
        $actions = ConvertTo-DetectionAutomatedAction -ResponseActions @(
            @{ '@odata.type' = '#microsoft.graph.security.hardDeleteResponseAction'; identifier = 'networkMessageId, recipientEmailAddress' }
        )
        $entry = $actions['hardDeleteEmails'][0]
        $entry['networkMessageIdColumn'] | Should -BeExactly 'NetworkMessageId'
        $entry['recipientColumn']        | Should -BeExactly 'RecipientEmailAddress'
    }

    It 'keeps the isolation type on a device isolation' {
        $actions = ConvertTo-DetectionAutomatedAction -ResponseActions @(
            @{ '@odata.type' = '#microsoft.graph.security.isolateDeviceResponseAction'; identifier = 'deviceId'; isolationType = 'selective' }
        )
        $actions['isolateDevices'][0]['deviceIdColumn'] | Should -BeExactly 'DeviceId'
        $actions['isolateDevices'][0]['isolationType']  | Should -BeExactly 'selective'
    }

    It 'throws for an unknown response action type' {
        { ConvertTo-DetectionAutomatedAction -ResponseActions @(@{ '@odata.type' = '#microsoft.graph.security.madeUpResponseAction'; identifier = 'deviceId' }) } |
            Should -Throw -ExpectedMessage '*madeUpResponseAction*'
    }
}

Describe 'ConvertFrom-LegacyDetectionRule' {
    It 'translates every retired field and reports each one' {
        $result = ConvertFrom-LegacyDetectionRule -Rule (New-LegacyRule)
        $rule = $result.Rule

        $rule.status | Should -Be 'disabled'
        $rule.Contains('isEnabled') | Should -BeFalse
        $rule.schedule.frequency | Should -Be 'P1D'
        $rule.schedule.Contains('period') | Should -BeFalse
        $rule.queryCondition.Contains('lastModifiedDateTime') | Should -BeFalse

        $template = $rule.detectionAction.alertTemplate
        $template.tactics[0].tactic | Should -Be 'CredentialAccess'
        $template.Contains('category') | Should -BeFalse
        $template.Contains('mitreTechniques') | Should -BeFalse
        $template.entityMappings['accounts'][0]['aadUserIdColumn'] | Should -Be 'AccountObjectId'
        $template.Contains('impactedAssets') | Should -BeFalse

        $rule.detectionAction.automatedActions['forceUserPasswordResets'][0]['accountSidColumn'] | Should -Be 'AccountSid'
        $rule.detectionAction.Contains('responseActions') | Should -BeFalse

        $result.LegacyFields | Should -Contain 'isEnabled'
        $result.LegacyFields | Should -Contain 'schedule.period'
        $result.LegacyFields | Should -Contain 'detectionAction.responseActions'
    }

    It 'leaves a rule in the current shape unchanged' {
        $result = ConvertFrom-LegacyDetectionRule -Rule (New-CurrentRule)
        @($result.LegacyFields).Count | Should -Be 0
        $result.Rule.schedule.frequency | Should -Be 'PT1H'
        $result.Rule.detectionAction.alertTemplate.tactics[0].tactic | Should -Be 'Execution'
    }

    It 'keeps the current field when a rule sets both' {
        $rule = New-LegacyRule
        $rule['status'] = 'enabled'
        (ConvertFrom-LegacyDetectionRule -Rule $rule).Rule.status | Should -Be 'enabled'
    }

    It 'produces a rule the validator accepts' {
        $rule = (ConvertFrom-LegacyDetectionRule -Rule (New-LegacyRule)).Rule
        @(Test-DetectionRule -Rule $rule) | Should -BeNullOrEmpty
    }
}

Describe 'Test-DetectionRule' {
    It 'accepts a valid rule' {
        @(Test-DetectionRule -Rule (New-CurrentRule)) | Should -BeNullOrEmpty
    }

    It 'reports <Problem>' -ForEach @(
        @{ Problem = 'a missing displayName';  Change = { param($r) $r.Remove('displayName') };                                     Match = '*displayName*' }
        @{ Problem = 'a missing queryText';    Change = { param($r) $r.queryCondition = @{} };                                      Match = '*queryText*' }
        @{ Problem = 'an unrun frequency';     Change = { param($r) $r.schedule.frequency = 'PT2H' };                               Match = '*schedule.frequency*' }
        @{ Problem = 'an unknown status';      Change = { param($r) $r.status = 'autoDisabled' };                                   Match = '*status*' }
        @{ Problem = 'an unknown severity';    Change = { param($r) $r.detectionAction.alertTemplate.severity = 'critical' };       Match = '*severity*' }
        @{ Problem = 'missing tactics';        Change = { param($r) $r.detectionAction.alertTemplate.Remove('tactics') };           Match = '*tactics*' }
        @{ Problem = 'an unknown tactic';      Change = { param($r) $r.detectionAction.alertTemplate.tactics = @(@{ tactic = 'Exploit' }) }; Match = '*Exploit*' }
        @{ Problem = 'a foreign sub-technique'; Change = { param($r) $r.detectionAction.alertTemplate.tactics[0].techniques[0].subTechniques = @('T1078.004') }; Match = '*T1078.004*' }
        @{ Problem = 'an unknown entity collection'; Change = { param($r) $r.detectionAction.alertTemplate.entityMappings = @{ people = @() } }; Match = '*people*' }
        @{ Problem = 'an action missing its column'; Change = { param($r) $r.detectionAction.automatedActions = @{ isolateDevices = @(@{ deviceIdColumn = 'DeviceId' }) } }; Match = '*isolationType*' }
        @{ Problem = 'an unknown action member'; Change = { param($r) $r.detectionAction.automatedActions = @{ rebootDevices = @() } }; Match = '*rebootDevices*' }
    ) {
        $rule = New-CurrentRule
        & $Change $rule
        $issues = @(Test-DetectionRule -Rule $rule)
        $issues.Count | Should -BeGreaterThan 0
        ($issues -join '; ') | Should -BeLike $Match
    }
}

Describe 'ConvertTo-GraphDetectionBody' {
    It 'builds the current Graph shape' {
        $body = ConvertTo-GraphDetectionBody -Rule (New-CurrentRule)
        $body.displayName | Should -Be 'Test rule'
        $body.status | Should -Be 'enabled'
        $body.schedule.frequency | Should -Be 'PT1H'
        $body.queryCondition.queryText | Should -Match 'DeviceProcessEvents'
        $body.detectionAction.alertTemplate.tactics[0].tactic | Should -Be 'Execution'
        foreach ($retired in 'isEnabled', 'period', 'category', 'mitreTechniques', 'impactedAssets', 'responseActions') {
            ($body | ConvertTo-Json -Depth 20) | Should -Not -Match "`"$retired`"" -Because "$retired was removed from the Graph contract"
        }
    }

    It 'adds the client-provided id only when creating' {
        (ConvertTo-GraphDetectionBody -Rule (New-CurrentRule)).Contains('id') | Should -BeFalse
        (ConvertTo-GraphDetectionBody -Rule (New-CurrentRule) -ForCreate).id | Should -Be 'test-rule'
    }

    It 'defaults status to enabled and lowercases severity' {
        $rule = New-CurrentRule
        $rule.Remove('status')
        $rule.detectionAction.alertTemplate.severity = 'High'
        $body = ConvertTo-GraphDetectionBody -Rule $rule
        $body.status | Should -Be 'enabled'
        $body.detectionAction.alertTemplate.severity | Should -BeExactly 'high'
    }

    It 'writes the canonical frequency' {
        $rule = New-CurrentRule
        $rule.schedule.frequency = 'PT24H'
        (ConvertTo-GraphDetectionBody -Rule $rule).schedule.frequency | Should -Be 'P1D'
    }

    It 'sends an empty automatedActions set and a null scope when the rule sets neither' {
        $body = ConvertTo-GraphDetectionBody -Rule (New-CurrentRule)
        $body.detectionAction.automatedActions.Count | Should -Be 0
        $body.detectionAction.Contains('organizationalScope') | Should -BeTrue
        $body.detectionAction.organizationalScope | Should -BeNullOrEmpty
    }

    It 'forwards entity mappings, actions, device groups and incident configuration' {
        $rule = New-CurrentRule
        $rule.detectionAction.alertTemplate.entityMappings = @{ hosts = @(@{ deviceIdColumn = 'DeviceId' }) }
        $rule.detectionAction.automatedActions = @{ runAntivirusScans = @(@{ deviceIdColumn = 'DeviceId' }) }
        $rule.detectionAction.organizationalScope = @{ deviceGroups = @('Servers') }
        $rule.detectionAction.incidentConfiguration = @{ isExcludedFromIncidentCorrelation = $true }
        $body = ConvertTo-GraphDetectionBody -Rule $rule
        $body.detectionAction.alertTemplate.entityMappings.hosts[0].deviceIdColumn | Should -Be 'DeviceId'
        $body.detectionAction.automatedActions.runAntivirusScans[0].deviceIdColumn | Should -Be 'DeviceId'
        @($body.detectionAction.organizationalScope.deviceGroups) | Should -Be @('Servers')
        $body.detectionAction.incidentConfiguration.isExcludedFromIncidentCorrelation | Should -BeTrue
    }
}

Describe 'Get-DetectionMappedColumn' {
    It 'returns each column named by mappings, actions and custom details once' {
        $rule = New-CurrentRule
        $rule.detectionAction.alertTemplate.entityMappings = @{ hosts = @(@{ deviceIdColumn = 'DeviceId' }); accounts = @(@{ sidColumn = 'AccountSid' }) }
        $rule.detectionAction.alertTemplate.customDetails = @{ Process = 'ProcessCommandLine' }
        $rule.detectionAction.automatedActions = @{ isolateDevices = @(@{ deviceIdColumn = 'DeviceId'; isolationType = 'full' }) }
        $columns = @(Get-DetectionMappedColumn -Rule $rule)
        $columns | Sort-Object | Should -Be @('AccountSid', 'DeviceId', 'ProcessCommandLine')
    }
}
