#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the Defender XDR custom detection content type's
    handlers.

.DESCRIPTION
    - The Graph contract helpers, ported from
      Tests/Test-DeployDefenderDetections.Tests.ps1: the frequency,
      tactic, entity mapping and automated action converters, the
      translation of a rule written with the retired fields, and the
      mapped columns.
    - The MITRE ATT&CK map (Get-iSOCDefenderDetectionAttackMap): version
      18.1, its tactics the ones Graph accepts, ids looked up without case.
    - The handlers on the fixture repository: reading one item per file
      (with the translation done once), validation (every problem on one
      line, as the deployer logged them, and each technique under a tactic
      it is in, which the deployer did not check: MIGRATION.md E46), and
      the request body.
    - The deploy handler with the REST client mocked: an existing rule
      updated by name, a new one created with its id, a new one without an
      id failed, -WhatIf reading the tenant's rules (MIGRATION.md edit
      E18), and a list that cannot be read.
    - Every detection under Content/DefenderCustomDetections/ in this
      repository: read through the ReadRepo handler, passing
      Test-iSOCDefenderDetection with no issues, and built into a Graph
      request through the ToRequest handler, for an update and for a
      create.

    Parity with Deploy-DefenderDetections.ps1 was proven on
    release/26.11.0 before the script was removed.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/DefenderDetection.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/DefenderDetection.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.3.0
    Last Updated: 2026-11-06
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $detectionFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Content/DefenderCustomDetections') -Include '*.yaml', '*.yml' -Recurse -File) |
        Sort-Object FullName |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module powershell-yaml -ErrorAction Stop
    $script:fixtureRepo = Join-Path $PSScriptRoot 'Fixtures/repo'

    $script:context = InModuleScope iSOCDeployments {
        New-iSOCContext -Value @{
            TenantId = 't'; SubscriptionId = 's'; ResourceGroup = 'rg'; WorkspaceName = 'ws'; WorkspaceResourceId = '/w'
            WorkspaceId = 'c'; Region = 'uksouth'; PlaybookResourceGroup = 'rg'; Environment = 'AzureCloud'; IsGov = $false
            ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'a'
        }
    }

    function Get-DetectionItem {
        param([string] $Repo = $script:fixtureRepo)
        InModuleScope iSOCDeployments -Parameters @{ R = $Repo } {
            param($R)
            $type = Get-iSOCContentTypeDefinition -Name DefenderDetection
            Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $R; ContentType = $type }
        }
    }
    function Test-Item {
        param([psobject] $Item)
        @(InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) Test-iSOCDefenderDetection -Item $I })
    }
    function Get-Body {
        param([psobject] $Item, [switch] $ForCreate)
        InModuleScope iSOCDeployments -Parameters @{ I = $Item; F = [bool]$ForCreate } { param($I, $F) (ConvertTo-iSOCDefenderDetectionRequest -Item $I -ForCreate:$F).Body }
    }
    function New-DetectionFile {
        param([string] $Yaml, [string] $Leaf = 'Rule.yaml')
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $repo 'Content/DefenderCustomDetections') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo "Content/DefenderCustomDetections/$Leaf") -Value $Yaml
        @(Get-DetectionItem -Repo $repo)[0]
    }
    # An item around a rule built in the test, as the reader would return it.
    function New-RuleItem {
        param([System.Collections.IDictionary] $Rule)
        [pscustomobject]@{ ContentType = 'DefenderDetection'; Identity = 'x'; Name = 'x'; RelativePath = 'Content/DefenderCustomDetections/x.yaml'; Rule = $Rule; LegacyFields = @(); ParseError = $null }
    }
    function Invoke-InModule {
        param([scriptblock] $ScriptBlock, [hashtable] $Parameters = @{})
        InModuleScope iSOCDeployments -ScriptBlock $ScriptBlock -Parameters $Parameters
    }

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
                    mitreTechniques = @('T1110.001', 'T1110.003', 'T1621')
                    impactedAssets  = @(@{ '@odata.type' = '#microsoft.graph.security.impactedUserAsset'; identifier = 'accountObjectId' })
                }
                responseActions = @(
                    @{ '@odata.type' = '#microsoft.graph.security.forceUserPasswordResetResponseAction'; identifier = 'accountSid' }
                )
            }
        }
    }

    $script:items = @(Get-DetectionItem)
    $script:encoded = $script:items | Where-Object { $_.RelativePath -like '*FixtureEncodedPowerShell.yaml' }
    $script:legacy = $script:items | Where-Object { $_.RelativePath -like '*FixtureLegacySpray.yaml' }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-iSOCDefenderDetectionFrequency' {
    It 'writes <Value> as <Expected>' -ForEach @(
        @{ Value = 'PT1H'; Expected = 'PT1H' }
        @{ Value = 'PT24H'; Expected = 'P1D' }
        @{ Value = 'P1D'; Expected = 'P1D' }
        @{ Value = '3H'; Expected = 'PT3H' }
        @{ Value = '12H'; Expected = 'PT12H' }
        @{ Value = 'pt1h'; Expected = 'PT1H' }
    ) {
        Invoke-InModule { param($V) ConvertTo-iSOCDefenderDetectionFrequency -Value $V } @{ V = $Value } | Should -BeExactly $Expected
    }

    It 'rejects <Value>, which the service does not run' -ForEach @(
        @{ Value = '0' }, @{ Value = 'PT5M' }, @{ Value = 'PT2H' }, @{ Value = 'P2D' }, @{ Value = 'hourly' }, @{ Value = '' }
    ) {
        Invoke-InModule { param($V) ConvertTo-iSOCDefenderDetectionFrequency -Value $V } @{ V = $Value } | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-iSOCDefenderDetectionTactic' {
    It 'groups sub-techniques under their parent in first-seen order' {
        $tactics = Invoke-InModule { ConvertTo-iSOCDefenderDetectionTactic -Category 'CredentialAccess' -MitreTechniques @('T1110.001', 'T1078', 'T1110.003') }
        @($tactics).Count | Should -Be 1
        $tactics[0].tactic | Should -BeExactly 'CredentialAccess'
        @($tactics[0].techniques.technique) | Should -Be @('T1110', 'T1078')
        @($tactics[0].techniques[0].subTechniques) | Should -Be @('T1110.001', 'T1110.003')
        $tactics[0].techniques[1].Contains('subTechniques') | Should -BeFalse
    }

    It 'keeps a lone tactic when there are no techniques' {
        $tactics = Invoke-InModule { ConvertTo-iSOCDefenderDetectionTactic -Category 'Impact' -MitreTechniques @() }
        @($tactics).Count | Should -Be 1
        $tactics[0].Contains('techniques') | Should -BeFalse
    }
}

Describe 'Get-iSOCDefenderDetectionAttackMap' {
    BeforeAll {
        $script:attack = Invoke-InModule { Get-iSOCDefenderDetectionAttackMap }
    }

    It 'is MITRE ATT&CK 18.1, whose tactics are the ones Graph accepts' {
        $script:attack.AttackVersion | Should -BeExactly '18.1'
        $tactics = @($script:attack.Techniques.Values | ForEach-Object { $_ } | Sort-Object -Unique)
        $tactics | Should -Be @((Invoke-InModule { Get-iSOCDefenderDetectionContract }).ValidDetectionTactics | Sort-Object)
    }

    It 'holds techniques and sub-techniques, looked up without case' {
        $script:attack.Techniques['t1047'] | Should -Be @('Execution')
        $script:attack.Techniques['T1078.004'] | Should -Contain 'InitialAccess'
        $script:attack.Techniques.ContainsKey('T1574.002') | Should -BeTrue -Because 'a revoked id a rule still names is kept'
    }

    It 'warns and returns nothing when the file is missing' {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Invoke-InModule { param($P) Get-iSOCDefenderDetectionAttackMap -Path $P } @{ P = (Join-Path $TestDrive 'none.json') } | Should -BeNullOrEmpty
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warning' }
    }
}

Describe 'ConvertTo-iSOCDefenderDetectionEntityMapping' {
    It 'maps <Identifier> on a <Type> to <Collection>.<Property> = <Column>' -ForEach @(
        @{ Type = 'impactedUserAsset'; Identifier = 'accountObjectId'; Collection = 'accounts'; Property = 'aadUserIdColumn'; Column = 'AccountObjectId' }
        @{ Type = 'impactedUserAsset'; Identifier = 'accountSid'; Collection = 'accounts'; Property = 'sidColumn'; Column = 'AccountSid' }
        @{ Type = 'impactedUserAsset'; Identifier = 'accountUpn'; Collection = 'accounts'; Property = 'upnColumn'; Column = 'AccountUpn' }
        @{ Type = 'impactedUserAsset'; Identifier = 'accountName'; Collection = 'accounts'; Property = 'nameColumn'; Column = 'AccountName' }
        @{ Type = 'impactedUserAsset'; Identifier = 'accountDomain'; Collection = 'accounts'; Property = 'ntDomainColumn'; Column = 'AccountDomain' }
        @{ Type = 'impactedUserAsset'; Identifier = 'initiatingProcessAccountSid'; Collection = 'accounts'; Property = 'sidColumn'; Column = 'InitiatingProcessAccountSid' }
        @{ Type = 'impactedDeviceAsset'; Identifier = 'deviceId'; Collection = 'hosts'; Property = 'deviceIdColumn'; Column = 'DeviceId' }
        @{ Type = 'impactedDeviceAsset'; Identifier = 'deviceName'; Collection = 'hosts'; Property = 'nameColumn'; Column = 'DeviceName' }
        @{ Type = 'impactedMailboxAsset'; Identifier = 'recipientEmailAddress'; Collection = 'mailboxes'; Property = 'primaryAddressColumn'; Column = 'RecipientEmailAddress' }
    ) {
        $mapping = Invoke-InModule { param($T, $I) ConvertTo-iSOCDefenderDetectionEntityMapping -ImpactedAssets @(@{ '@odata.type' = "#microsoft.graph.security.$T"; identifier = $I }) } @{ T = $Type; I = $Identifier }
        $mapping[$Collection][0][$Property] | Should -BeExactly $Column
    }

    It 'adds one mapping per asset in the same collection' {
        $mapping = Invoke-InModule {
            ConvertTo-iSOCDefenderDetectionEntityMapping -ImpactedAssets @(
                @{ '@odata.type' = '#microsoft.graph.security.impactedUserAsset'; identifier = 'accountObjectId' }
                @{ '@odata.type' = '#microsoft.graph.security.impactedUserAsset'; identifier = 'accountUpn' }
            )
        }
        @($mapping['accounts']).Count | Should -Be 2
    }

    It 'throws for <Case>, rather than guess' -ForEach @(
        @{ Case = 'a user identifier it cannot place'; Type = 'impactedUserAsset'; Identifier = 'servicePrincipalId'; Match = '*servicePrincipalId*' }
        @{ Case = 'a device identifier it cannot place'; Type = 'impactedDeviceAsset'; Identifier = 'deviceSerial'; Match = '*deviceSerial*' }
        @{ Case = 'a mailbox identifier it cannot place'; Type = 'impactedMailboxAsset'; Identifier = 'recipientObjectId'; Match = '*recipientObjectId*' }
        @{ Case = 'an unknown asset type'; Type = 'impactedCloudAsset'; Identifier = 'resourceId'; Match = "*impactedCloudAsset*" }
    ) {
        { Invoke-InModule { param($T, $I) ConvertTo-iSOCDefenderDetectionEntityMapping -ImpactedAssets @(@{ '@odata.type' = "#microsoft.graph.security.$T"; identifier = $I }) } @{ T = $Type; I = $Identifier } } |
            Should -Throw -ExpectedMessage $Match
    }
}

Describe 'ConvertTo-iSOCDefenderDetectionAutomatedAction' {
    It 'maps a single-identifier action to its column property' {
        $actions = Invoke-InModule {
            ConvertTo-iSOCDefenderDetectionAutomatedAction -ResponseActions @(
                @{ '@odata.type' = '#microsoft.graph.security.markUserAsCompromisedResponseAction'; identifier = 'recipientObjectId' }
            )
        }
        $actions['markUsersAsCompromised'][0]['accountObjectIdColumn'] | Should -BeExactly 'RecipientObjectId'
    }

    It 'splits a two-identifier email action into both column properties' {
        $actions = Invoke-InModule {
            ConvertTo-iSOCDefenderDetectionAutomatedAction -ResponseActions @(
                @{ '@odata.type' = '#microsoft.graph.security.hardDeleteResponseAction'; identifier = 'networkMessageId, recipientEmailAddress' }
            )
        }
        $entry = $actions['hardDeleteEmails'][0]
        $entry['networkMessageIdColumn'] | Should -BeExactly 'NetworkMessageId'
        $entry['recipientColumn'] | Should -BeExactly 'RecipientEmailAddress'
    }

    It 'writes the hash columns in capitals' {
        $actions = Invoke-InModule {
            ConvertTo-iSOCDefenderDetectionAutomatedAction -ResponseActions @(
                @{ '@odata.type' = '#microsoft.graph.security.stopAndQuarantineFileResponseAction'; identifier = 'deviceId, sha1' }
            )
        }
        $actions['stopAndQuarantineFiles'][0]['sha1Column'] | Should -BeExactly 'SHA1'
        $actions['stopAndQuarantineFiles'][0]['deviceIdColumn'] | Should -BeExactly 'DeviceId'
    }

    It 'keeps the isolation type and device groups on a device isolation' {
        $actions = Invoke-InModule {
            ConvertTo-iSOCDefenderDetectionAutomatedAction -ResponseActions @(
                @{ '@odata.type' = '#microsoft.graph.security.isolateDeviceResponseAction'; identifier = 'deviceId'; isolationType = 'selective'; deviceGroupNames = @('Servers') }
            )
        }
        $actions['isolateDevices'][0]['deviceIdColumn'] | Should -BeExactly 'DeviceId'
        $actions['isolateDevices'][0]['isolationType'] | Should -BeExactly 'selective'
        @($actions['isolateDevices'][0]['deviceGroupNames']) | Should -Be @('Servers')
    }

    It 'throws for <Case>' -ForEach @(
        @{ Case = 'an unknown response action type'; Type = 'madeUpResponseAction'; Identifier = 'deviceId'; Match = '*madeUpResponseAction*' }
        @{ Case = 'a token in a multi-identifier action it cannot place'; Type = 'softDeleteResponseAction'; Identifier = 'networkMessageId, senderAddress'; Match = '*senderAddress*' }
    ) {
        { Invoke-InModule { param($T, $I) ConvertTo-iSOCDefenderDetectionAutomatedAction -ResponseActions @(@{ '@odata.type' = "#microsoft.graph.security.$T"; identifier = $I }) } @{ T = $Type; I = $Identifier } } |
            Should -Throw -ExpectedMessage $Match
    }
}

Describe 'ConvertFrom-iSOCLegacyDefenderDetection' {
    It 'translates every retired field and reports each one' {
        $result = Invoke-InModule { param($R) ConvertFrom-iSOCLegacyDefenderDetection -Rule $R } @{ R = (New-LegacyRule) }
        $rule = $result.Rule

        $rule.status | Should -BeExactly 'disabled'
        $rule.Contains('isEnabled') | Should -BeFalse
        $rule.schedule.frequency | Should -BeExactly 'P1D'
        $rule.schedule.Contains('period') | Should -BeFalse
        $rule.queryCondition.Contains('lastModifiedDateTime') | Should -BeFalse

        $template = $rule.detectionAction.alertTemplate
        $template.tactics[0].tactic | Should -BeExactly 'CredentialAccess'
        $template.Contains('category') | Should -BeFalse
        $template.Contains('mitreTechniques') | Should -BeFalse
        $template.entityMappings['accounts'][0]['aadUserIdColumn'] | Should -BeExactly 'AccountObjectId'
        $template.Contains('impactedAssets') | Should -BeFalse

        $rule.detectionAction.automatedActions['forceUserPasswordResets'][0]['accountSidColumn'] | Should -BeExactly 'AccountSid'
        $rule.detectionAction.Contains('responseActions') | Should -BeFalse

        @($result.LegacyFields) | Should -Be @(
            'isEnabled', 'queryCondition.lastModifiedDateTime', 'schedule.period', 'alertTemplate.category'
            'alertTemplate.mitreTechniques', 'alertTemplate.impactedAssets', 'detectionAction.responseActions'
        )
    }

    It 'leaves a rule in the current shape unchanged' {
        $result = Invoke-InModule { param($R) ConvertFrom-iSOCLegacyDefenderDetection -Rule $R } @{ R = (New-CurrentRule) }
        @($result.LegacyFields).Count | Should -Be 0
        $result.Rule.schedule.frequency | Should -BeExactly 'PT1H'
        $result.Rule.detectionAction.alertTemplate.tactics[0].tactic | Should -BeExactly 'Execution'
    }

    It 'keeps the current field when a rule sets both' {
        $rule = New-LegacyRule
        $rule['status'] = 'enabled'
        $rule.schedule['frequency'] = 'PT3H'
        $translated = (Invoke-InModule { param($R) ConvertFrom-iSOCLegacyDefenderDetection -Rule $R } @{ R = $rule }).Rule
        $translated.status | Should -BeExactly 'enabled'
        $translated.schedule.frequency | Should -BeExactly 'PT3H'
    }

    It 'keeps a period it cannot convert, for validation to report' {
        $rule = New-LegacyRule
        $rule.schedule.period = '2H'
        (Invoke-InModule { param($R) ConvertFrom-iSOCLegacyDefenderDetection -Rule $R } @{ R = $rule }).Rule.schedule.frequency | Should -BeExactly '2H'
    }

    It 'turns scope names into device groups' {
        $rule = New-CurrentRule
        $rule.detectionAction.organizationalScope = @{ scopeNames = @('Servers') }
        $result = Invoke-InModule { param($R) ConvertFrom-iSOCLegacyDefenderDetection -Rule $R } @{ R = $rule }
        @($result.Rule.detectionAction.organizationalScope.deviceGroups) | Should -Be @('Servers')
        @($result.LegacyFields) | Should -Be @('organizationalScope.scopeNames')
    }

    It 'produces a rule the validator accepts' {
        $rule = (Invoke-InModule { param($R) ConvertFrom-iSOCLegacyDefenderDetection -Rule $R } @{ R = (New-LegacyRule) }).Rule
        Test-Item (New-RuleItem $rule) | Should -BeNullOrEmpty
    }
}

Describe 'Get-iSOCDefenderDetectionMappedColumn' {
    It 'returns each column named by mappings, actions and custom details once' {
        $rule = New-CurrentRule
        $rule.detectionAction.alertTemplate.entityMappings = @{ hosts = @(@{ deviceIdColumn = 'DeviceId' }); accounts = @(@{ sidColumn = 'AccountSid' }) }
        $rule.detectionAction.alertTemplate.customDetails = @{ Process = 'ProcessCommandLine' }
        $rule.detectionAction.automatedActions = @{ isolateDevices = @(@{ deviceIdColumn = 'DeviceId'; isolationType = 'full' }) }
        $columns = @(Invoke-InModule { param($R) Get-iSOCDefenderDetectionMappedColumn -Rule $R } @{ R = $rule })
        $columns | Sort-Object | Should -Be @('AccountSid', 'DeviceId', 'ProcessCommandLine')
    }

    It 'names every column a fixture rule maps' {
        @(Invoke-InModule { param($R) Get-iSOCDefenderDetectionMappedColumn -Rule $R } @{ R = $script:encoded.Rule }) | Sort-Object |
            Should -Be @('AccountSid', 'DeviceId', 'ProcessCommandLine')
    }
}

Describe 'Defender detection handlers' {
    It 'reads one item per file, named by its displayName, identified by it in lower case' {
        @($script:items.RelativePath) | Should -Be @(
            'Content/DefenderCustomDetections/Email/FixtureExistingNoId.yaml'
            'Content/DefenderCustomDetections/Email/InvalidFrequency.yaml'
            'Content/DefenderCustomDetections/Endpoint/FixtureEncodedPowerShell.yaml'
            'Content/DefenderCustomDetections/Identity/FixtureLegacySpray.yaml'
        )
        $script:encoded.Name | Should -BeExactly 'Fixture: encoded PowerShell'
        $script:encoded.Identity | Should -BeExactly 'fixture: encoded powershell'
        $script:encoded.Source | Should -Be 'Custom'
        $script:encoded.ParseError | Should -BeNullOrEmpty
        @($script:encoded.LegacyFields).Count | Should -Be 0
    }

    It 'translates a file written with the retired fields once, when it is read' {
        $script:legacy.Data.Contains('isEnabled') | Should -BeTrue
        $script:legacy.Rule.status | Should -BeExactly 'disabled'
        $script:legacy.Rule.schedule.frequency | Should -BeExactly 'PT3H'
        @($script:legacy.LegacyFields) | Should -Contain 'detectionAction.responseActions'
        @($script:legacy.LegacyFields) | Should -Contain 'organizationalScope.scopeNames'
    }

    It 'names a file without a displayName after the file' {
        (New-DetectionFile -Yaml 'id: x' -Leaf 'Unnamed.yaml').Name | Should -BeExactly 'Unnamed'
    }

    It 'fails <Case>, as the deployer did' -ForEach @(
        @{ Case = 'a file that does not parse'; Yaml = "displayName: [unclosed"; Match = 'YAML does not parse:*' }
        @{ Case = 'a file that holds a list'; Yaml = "- one`n- two"; Match = 'the file does not hold a YAML mapping' }
        @{ Case = 'a file whose retired fields cannot be translated'; Yaml = "displayName: X`ndetectionAction:`n  alertTemplate:`n    impactedAssets:`n      - '@odata.type': '#microsoft.graph.security.impactedUserAsset'`n        identifier: servicePrincipalId"; Match = 'the retired Graph fields cannot be translated: *servicePrincipalId*' }
    ) {
        $item = New-DetectionFile -Yaml $Yaml
        $item.ParseError | Should -BeLike $Match
        $item.Rule | Should -BeNullOrEmpty
        @(Test-Item $item) -join "`n" | Should -BeExactly $item.ParseError
    }

    It 'passes the complete fixture rules' {
        foreach ($item in $script:items | Where-Object { $_.RelativePath -notlike '*InvalidFrequency.yaml' }) {
            Test-Item $item | Should -BeNullOrEmpty -Because $item.RelativePath
        }
    }

    It 'reports every problem on one line' {
        $item = $script:items | Where-Object { $_.RelativePath -like '*InvalidFrequency.yaml' }
        @(Test-Item $item) -join "`n" | Should -BeExactly "invalid schedule.frequency 'PT2H'; use PT1H, PT3H, PT12H or P1D; unknown tactic 'Exploit'"
    }

    It 'reports <Problem>' -ForEach @(
        @{ Problem = 'a missing displayName'; Change = { param($r) $r.Remove('displayName') }; Expected = "missing required field 'displayName'" }
        @{ Problem = 'a missing queryText'; Change = { param($r) $r.queryCondition = @{} }; Expected = "missing required field 'queryCondition.queryText'" }
        @{ Problem = 'a missing frequency'; Change = { param($r) $r.Remove('schedule') }; Expected = "missing required field 'schedule.frequency'" }
        @{ Problem = 'an unrun frequency'; Change = { param($r) $r.schedule.frequency = 'PT2H' }; Expected = "invalid schedule.frequency 'PT2H'; use PT1H, PT3H, PT12H or P1D" }
        @{ Problem = 'an unknown status'; Change = { param($r) $r.status = 'autoDisabled' }; Expected = "invalid status 'autoDisabled'; use enabled or disabled" }
        @{ Problem = 'no alert template'; Change = { param($r) $r.detectionAction = @{} }; Expected = "missing required field 'detectionAction.alertTemplate'" }
        @{ Problem = 'a missing title'; Change = { param($r) $r.detectionAction.alertTemplate.Remove('title') }; Expected = "alertTemplate missing required field 'title'" }
        @{ Problem = 'an unknown severity'; Change = { param($r) $r.detectionAction.alertTemplate.severity = 'critical' }; Expected = "invalid alertTemplate.severity 'critical'; use informational, low, medium, high" }
        @{ Problem = 'missing tactics'; Change = { param($r) $r.detectionAction.alertTemplate.Remove('tactics') }; Expected = "alertTemplate missing required field 'tactics'" }
        @{ Problem = 'an unknown tactic'; Change = { param($r) $r.detectionAction.alertTemplate.tactics = @(@{ tactic = 'Exploit' }) }; Expected = "unknown tactic 'Exploit'" }
        @{ Problem = 'a malformed technique'; Change = { param($r) $r.detectionAction.alertTemplate.tactics[0].techniques[0] = @{ technique = '1059' } }; Expected = "invalid technique '1059' under Execution" }
        @{ Problem = 'a foreign sub-technique'; Change = { param($r) $r.detectionAction.alertTemplate.tactics[0].techniques[0].subTechniques = @('T1078.004') }; Expected = "sub-technique 'T1078.004' does not belong to T1059" }
        @{ Problem = 'a technique under a tactic it is not in'; Change = { param($r) $r.detectionAction.alertTemplate.tactics[0].techniques[0] = @{ technique = 'T1105' } }; Expected = "technique 'T1105' belongs to CommandAndControl, not Execution, in MITRE ATT&CK 18.1" }
        @{ Problem = 'a technique MITRE ATT&CK does not have'; Change = { param($r) $r.detectionAction.alertTemplate.tactics[0].techniques[0] = @{ technique = 'T1999' } }; Expected = "technique 'T1999' is not in MITRE ATT&CK 18.1" }
        @{ Problem = 'a sub-technique MITRE ATT&CK does not have'; Change = { param($r) $r.detectionAction.alertTemplate.tactics[0].techniques[0].subTechniques = @('T1059.999') }; Expected = "sub-technique 'T1059.999' is not in MITRE ATT&CK 18.1" }
        @{ Problem = 'an unknown entity collection'; Change = { param($r) $r.detectionAction.alertTemplate.entityMappings = @{ people = @() } }; Expected = "unknown entityMappings collection 'people'" }
        @{ Problem = 'an action missing its column'; Change = { param($r) $r.detectionAction.automatedActions = @{ isolateDevices = @(@{ deviceIdColumn = 'DeviceId' }) } }; Expected = "automatedActions.isolateDevices entry missing 'isolationType'" }
        @{ Problem = 'an unknown action member'; Change = { param($r) $r.detectionAction.automatedActions = @{ rebootDevices = @() } }; Expected = "unknown automatedActions member 'rebootDevices'" }
    ) {
        $rule = New-CurrentRule
        & $Change $rule
        @(Test-Item (New-RuleItem $rule)) -join "`n" | Should -BeExactly $Expected
    }

    It 'accepts a technique under each tactic it is in, and a revoked one a rule may still name' {
        $rule = New-CurrentRule
        $rule.detectionAction.alertTemplate.tactics = @(
            @{ tactic = 'InitialAccess'; techniques = @(@{ technique = 'T1078'; subTechniques = @('T1078.004') }) }
            @{ tactic = 'Persistence'; techniques = @(@{ technique = 'T1078' }) }
            @{ tactic = 'DefenseEvasion'; techniques = @(@{ technique = 'T1574'; subTechniques = @('T1574.002') }) }
        )
        Test-Item (New-RuleItem $rule) | Should -BeNullOrEmpty
    }

    It 'reports a misplaced technique once, not again for each of its sub-techniques' {
        $rule = New-CurrentRule
        $rule.detectionAction.alertTemplate.tactics = @(@{ tactic = 'InitialAccess'; techniques = @(@{ technique = 'T1090'; subTechniques = @('T1090.003') }) })
        @(Test-Item (New-RuleItem $rule)) -join "`n" | Should -BeExactly "technique 'T1090' belongs to CommandAndControl, not InitialAccess, in MITRE ATT&CK 18.1"
    }

    It 'reports a sub-technique under a tactic it is not in, when its technique is in it' {
        Mock -ModuleName iSOCDeployments Get-iSOCDefenderDetectionAttackMap {
            $techniques = [System.Collections.Generic.Dictionary[string, string[]]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $techniques['T1059'] = @('Execution', 'Persistence')
            $techniques['T1059.001'] = @('Execution')
            [pscustomobject]@{ AttackVersion = 'test'; Techniques = $techniques }
        }
        $rule = New-CurrentRule
        $rule.detectionAction.alertTemplate.tactics[0].tactic = 'Persistence'
        @(Test-Item (New-RuleItem $rule)) -join "`n" | Should -BeExactly "sub-technique 'T1059.001' belongs to Execution, not Persistence, in MITRE ATT&CK test"
    }

    It 'checks only the id patterns when the map is missing' {
        Mock -ModuleName iSOCDeployments Get-iSOCDefenderDetectionAttackMap { }
        $rule = New-CurrentRule
        $rule.detectionAction.alertTemplate.tactics[0].techniques[0] = @{ technique = 'T1105' }
        Test-Item (New-RuleItem $rule) | Should -BeNullOrEmpty
    }

    It 'builds the current Graph shape, without the id for an update' {
        $body = Get-Body (New-RuleItem (New-CurrentRule))
        @($body.Keys) | Should -Be @('displayName', 'status', 'queryCondition', 'schedule', 'detectionAction')
        $body.displayName | Should -BeExactly 'Test rule'
        $body.status | Should -BeExactly 'enabled'
        $body.schedule.frequency | Should -BeExactly 'PT1H'
        $body.queryCondition.queryText | Should -Match 'DeviceProcessEvents'
        $body.detectionAction.alertTemplate.tactics[0].tactic | Should -BeExactly 'Execution'
        foreach ($retired in 'isEnabled', 'period', 'category', 'mitreTechniques', 'impactedAssets', 'responseActions') {
            (ConvertTo-Json -InputObject $body -Depth 20) | Should -Not -Match "`"$retired`"" -Because "$retired was removed from the Graph contract"
        }
    }

    It 'adds the client-provided id first when creating, and names the request by it' {
        $item = New-RuleItem (New-CurrentRule)
        $body = Get-Body $item -ForCreate
        @($body.Keys)[0] | Should -BeExactly 'id'
        $body.id | Should -BeExactly 'test-rule'
        (Invoke-InModule { param($I) ConvertTo-iSOCDefenderDetectionRequest -Item $I } @{ I = $item }).ResourceName | Should -BeExactly 'test-rule'
    }

    It 'defaults status to enabled and lowercases severity' {
        $rule = New-CurrentRule
        $rule.Remove('status')
        $rule.detectionAction.alertTemplate.severity = 'High'
        $body = Get-Body (New-RuleItem $rule)
        $body.status | Should -BeExactly 'enabled'
        $body.detectionAction.alertTemplate.severity | Should -BeExactly 'high'
    }

    It 'writes the canonical frequency' {
        $rule = New-CurrentRule
        $rule.schedule.frequency = 'PT24H'
        (Get-Body (New-RuleItem $rule)).schedule.frequency | Should -BeExactly 'P1D'
    }

    It 'sends an empty automatedActions set and a null scope when the rule sets neither' {
        $body = Get-Body (New-RuleItem (New-CurrentRule))
        $body.detectionAction.automatedActions.Count | Should -Be 0
        $body.detectionAction.Contains('organizationalScope') | Should -BeTrue
        $body.detectionAction.organizationalScope | Should -BeNullOrEmpty
        $body.detectionAction.Contains('incidentConfiguration') | Should -BeFalse
        ConvertTo-Json -InputObject $body -Depth 20 -Compress | Should -BeLike '*"automatedActions":{}*"organizationalScope":null*'
    }

    It 'sends a null scope for an empty device group list' {
        $rule = New-CurrentRule
        $rule.detectionAction.organizationalScope = @{ deviceGroups = @() }
        (Get-Body (New-RuleItem $rule)).detectionAction.organizationalScope | Should -BeNullOrEmpty
    }

    It 'forwards the description, mappings, details, actions, device groups and incident configuration' {
        $body = Get-Body $script:encoded
        $body.description | Should -BeExactly 'Fixture detection in the current Graph shape.'
        $template = $body.detectionAction.alertTemplate
        $template.severity | Should -BeExactly 'medium'
        $template.description | Should -BeExactly 'An encoded PowerShell command ran.'
        $template.recommendedActions | Should -BeExactly 'Review the command line.'
        $template.entityMappings.hosts[0].deviceIdColumn | Should -BeExactly 'DeviceId'
        $template.customDetails.CommandLine | Should -BeExactly 'ProcessCommandLine'
        $body.detectionAction.automatedActions.isolateDevices[0].isolationType | Should -BeExactly 'selective'
        @($body.detectionAction.organizationalScope.deviceGroups) | Should -Be @('Fixture servers')
        $body.detectionAction.incidentConfiguration.isExcludedFromIncidentCorrelation | Should -BeFalse
        $body.schedule.frequency | Should -BeExactly 'P1D'
    }

    It 'sends the translated rule for a file written with the retired fields' {
        $body = Get-Body $script:legacy -ForCreate
        $body.status | Should -BeExactly 'disabled'
        $body.schedule.frequency | Should -BeExactly 'PT3H'
        $body.detectionAction.automatedActions.isolateDevices[0].deviceIdColumn | Should -BeExactly 'DeviceId'
        $body.detectionAction.automatedActions.isolateDevices[0].isolationType | Should -BeExactly 'full'
        @($body.detectionAction.organizationalScope.deviceGroups) | Should -Be @('Fixture workstations')
        $body.detectionAction.alertTemplate.entityMappings.accounts[0].aadUserIdColumn | Should -BeExactly 'AccountObjectId'
    }
}

Describe 'Defender detection deploy' {
    BeforeEach {
        $script:copy = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:copy | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:fixtureRepo 'Content') -Destination $script:copy -Recurse
        $script:calls = [System.Collections.Generic.List[object]]::new()
        $script:tenant = @([pscustomobject]@{ id = 'tenant-rule-1'; displayName = 'FIXTURE: MAIL RULE THE TENANT ALREADY HAS' })
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
            $script:calls.Add([pscustomobject]@{ Method = $Method; Api = $Api; Path = $Path; ApiVersion = $ApiVersion; Body = $Body })
            if ($Method -eq 'GET') { return $script:tenant }
            if ($Method -eq 'POST') { return [pscustomobject]@{ id = $Body.id } }
        }
        function Get-Outcome { param($Run, [string] $Leaf) $Run.Results | Where-Object { $_.RelativePath -like "*$Leaf" } }
    }

    It 'updates the rule the tenant has by name, in any case, and creates the new ones with their ids' {
        $run = Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -ContentType DefenderDetection
        (Get-Outcome $run 'FixtureExistingNoId.yaml').Outcome | Should -Be 'Deployed'
        (Get-Outcome $run 'FixtureEncodedPowerShell.yaml').Outcome | Should -Be 'Deployed'
        (Get-Outcome $run 'FixtureLegacySpray.yaml').Outcome | Should -Be 'Deployed'
        (Get-Outcome $run 'InvalidFrequency.yaml').Outcome | Should -Be 'Skipped'
        $run.ExitCode | Should -Be 0

        @($script:calls | ForEach-Object { "$($_.Method) $($_.Path)" }) | Should -Be @(
            'GET /security/rules/detectionRules'
            'PATCH /security/rules/detectionRules/tenant-rule-1'
            'POST /security/rules/detectionRules'
            'POST /security/rules/detectionRules'
        )
        @($script:calls.Api | Select-Object -Unique) | Should -Be @('Graph')
        @($script:calls.ApiVersion | Select-Object -Unique) | Should -Be @('beta')
        $script:calls[1].Body.Contains('id') | Should -BeFalse
        @($script:calls[2].Body.Keys)[0] | Should -BeExactly 'id'
        $script:calls[2].Body.id | Should -BeExactly 'fixture-encoded-powershell'
        $script:calls[3].Body.id | Should -BeExactly 'fixture-legacy-spray'
    }

    It 'warns about a file that uses the retired fields, naming them' {
        Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -ContentType DefenderDetection | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -like "'Content/DefenderCustomDetections/Identity/FixtureLegacySpray.yaml' uses retired Graph fields (isEnabled, *); deploying a translated copy.*"
        }
    }

    It 'reads the tenant''s rules once per run' {
        Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -ContentType DefenderDetection | Out-Null
        @($script:calls | Where-Object Method -eq 'GET').Count | Should -Be 1
    }

    It 'fails a new rule whose file has no id, and forgets it in the state' {
        $script:tenant = @()
        $run = Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -ContentType DefenderDetection
        $result = Get-Outcome $run 'FixtureExistingNoId.yaml'
        $result.Outcome | Should -Be 'Failed'
        $result.Reason | Should -BeExactly "'Fixture: mail rule the tenant already has' does not exist yet and the file has no 'id'; Graph needs a client-provided id to create a rule."
        $run.ExitCode | Should -Be 1
        @($script:calls | Where-Object Method -ne 'GET').Count | Should -Be 2
        $state = Get-Content -LiteralPath (Join-Path $script:copy 'deployment-state.json') -Raw | ConvertFrom-Json
        $state.deployedItems.PSObject.Properties['Content/DefenderCustomDetections/Email/FixtureExistingNoId.yaml'] | Should -BeNullOrEmpty
        $state.deployedItems.PSObject.Properties['Content/DefenderCustomDetections/Endpoint/FixtureEncodedPowerShell.yaml'] | Should -Not -BeNullOrEmpty
    }

    It 'reads the tenant''s rules under -WhatIf and says what it would do, sending nothing (MIGRATION.md edit E18)' {
        $script:tenant = @([pscustomobject]@{ id = 'tenant-rule-2'; displayName = 'Fixture: encoded PowerShell' })
        $run = Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -ContentType DefenderDetection -WhatIf
        @($script:calls.Method) | Should -Be @('GET')
        @($run.Results | Where-Object Outcome -eq 'WhatIf').Count | Should -Be 3
        (Get-Outcome $run 'FixtureExistingNoId.yaml').Reason | Should -BeLike "would fail: 'Fixture: mail rule the tenant already has' does not exist yet*"
        (Get-Outcome $run 'FixtureEncodedPowerShell.yaml').Reason | Should -BeNullOrEmpty
        $run.ExitCode | Should -Be 0
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Message -eq '[WhatIf] Would update: Fixture: encoded PowerShell (ID: tenant-rule-2)' }
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Message -eq '[WhatIf] Would create: Fixture: legacy password spray (ID: fixture-legacy-spray)' }
        Test-Path -LiteralPath (Join-Path $script:copy 'deployment-state.json') | Should -BeFalse
    }

    It 'treats every rule as new, with a warning, when the tenant''s rules cannot be read' {
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { throw 'HTTP 403 from GET rules/detectionRules: Forbidden' } -ParameterFilter { $Method -eq 'GET' }
        $run = Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -ContentType DefenderDetection
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Level -eq 'Warning' -and $Message -like 'Could not fetch existing rules: HTTP 403*All rules will be created as new.' }
        (Get-Outcome $run 'FixtureExistingNoId.yaml').Outcome | Should -Be 'Failed'
        @($script:calls | Where-Object Method -eq 'POST').Count | Should -Be 2
    }

    It 'logs the body Graph refused, and fails the rule' {
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { throw 'HTTP 400 from POST rules/detectionRules: BadRequest' } -ParameterFilter { $Method -eq 'POST' -and $Body.id -eq 'fixture-encoded-powershell' }
        $run = Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -ContentType DefenderDetection
        $result = Get-Outcome $run 'FixtureEncodedPowerShell.yaml'
        $result.Outcome | Should -Be 'Failed'
        $result.Reason | Should -Match 'BadRequest'
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warning' -and $Message -like 'Request body: *fixture-encoded-powershell*' }
        (Get-Outcome $run 'FixtureLegacySpray.yaml').Outcome | Should -Be 'Deployed'
    }

    It 'warns once that US Government clouds do not offer the API' {
        $gov = InModuleScope iSOCDeployments {
            New-iSOCContext -Value @{
                TenantId = 't'; SubscriptionId = 's'; ResourceGroup = 'rg'; WorkspaceName = 'ws'; WorkspaceResourceId = '/w'
                WorkspaceId = 'c'; Region = 'usgovvirginia'; PlaybookResourceGroup = 'rg'; Environment = 'AzureUSGovernment'; IsGov = $true
                ArmUrl = 'https://management.usgovcloudapi.net'; GraphUrl = 'https://graph.microsoft.us'; Account = 'a'
            }
        }
        Deploy-iSOCContent -Context $gov -RepoPath $script:copy -ContentType DefenderDetection | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warning' -and $Message -like 'Azure Government cloud:*' }
    }

    It 'checks for powershell-yaml only when there are detections to deploy' {
        Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -ContentType DefenderDetection | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Assert-iSOCPrerequisite -Times 1 -Exactly -ParameterFilter { $Name -contains 'powershell-yaml' -and $Purpose -ceq 'deploying Defender XDR custom detections' }
    }
}

Describe 'Content/DefenderCustomDetections in this repository' {
    BeforeAll {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        $script:repoType = InModuleScope iSOCDeployments { Get-iSOCContentTypeDefinition -Name DefenderDetection }
        function Invoke-RepoHandler {
            param([string] $Handler, [hashtable] $Parameters)
            InModuleScope iSOCDeployments -Parameters @{ T = $script:repoType; H = $Handler; P = $Parameters } {
                param($T, $H, $P)
                Invoke-iSOCContentTypeHandler -ContentType $T -Handler $H -Parameters $P
            }
        }
        $script:repoItems = @{}
        foreach ($item in Invoke-RepoHandler -Handler ReadRepo -Parameters @{ RepoPath = $script:repoRoot; ContentType = $script:repoType }) {
            $script:repoItems[$item.RelativePath] = $item
        }
    }

    It 'reads, validates and builds <Path>' -ForEach $detectionFiles {
        $item = $script:repoItems[$Path]
        $item | Should -Not -BeNullOrEmpty -Because 'the ReadRepo handler reads everything under Content/DefenderCustomDetections'
        Test-Item $item | Should -BeNullOrEmpty
        { $script:repoRequest = Invoke-RepoHandler -Handler ToRequest -Parameters @{ Item = $item } } | Should -Not -Throw
        $script:repoRequest.Body | Should -Not -BeNullOrEmpty
        { $script:repoCreate = Invoke-RepoHandler -Handler ToRequest -Parameters @{ Item = $item; ForCreate = $true } } | Should -Not -Throw
        $script:repoCreate.Body | Should -Not -BeNullOrEmpty
    }
}
