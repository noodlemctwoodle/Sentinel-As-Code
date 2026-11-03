#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the Content Hub commands, and for parity with
    Deploy/content/Deploy-SentinelContentHub.ps1.

.DESCRIPTION
    - The helpers carried over from Tests/Test-DeploySentinelContentHub.Tests.ps1:
      the version comparison, the customised-rule check, the deployment
      body and the 4 MB request limit.
    - The rule template reader, the rule body, the rule decision and the
      solution status, one case at a time.
    - Get-iSOCContentHubSolution and Install-iSOCContentHubSolution against
      a stand-in Content Hub (Fixtures/contenthub/standin.json, served by
      _helpers/ContentHubStandIn.psm1): an outcome for every solution and
      template, the alert rules api-version, -WhatIf writing nothing, the
      wait only after an install, exclusions and the comma-separated name.
    - Parity: the script's functions are lifted out by AST and run against
      their own copy of the same stand-in, in six scenarios (the defaults;
      every switch; -DisableRules alone; kinds left out; -WhatIf; and a
      clean run through the script's own Invoke-Main), and must send the same writes (method, path,
      api-version and body) and count the same outcomes. Where the module
      differs on purpose (MIGRATION.md edits E19 and E20) the tests say so.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/ContentHub.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/ContentHub.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+, Pester 5+

    The parity block goes when Deploy-SentinelContentHub.ps1 is removed at
    cut-over.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '_helpers/Parity.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '_helpers/ContentHubStandIn.psm1') -Force
    $script:fixture = Join-Path $PSScriptRoot 'Fixtures/contenthub/standin.json'
    $script:workspacePath = (Get-Content -LiteralPath $script:fixture -Raw | ConvertFrom-Json).workspace
    $script:allSolutions = @('Fixture Alpha', 'fixture bravo', 'Fixture Charlie', 'Fixture Delta', 'Fixture Missing')

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

    # The module against a fresh stand-in, with the REST client, GUIDs and
    # waits stood in for.
    function Invoke-ModuleRun {
        param([hashtable] $Parameters = @{}, [switch] $WhatIf, [string] $Command = 'Install-iSOCContentHubSolution')
        $script:moduleHub = New-ContentHubStandIn -Path $script:fixture
        $script:guidCounter = 0
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
        Mock -ModuleName iSOCDeployments Start-Sleep { }
        Mock -ModuleName iSOCDeployments New-Guid { $script:guidCounter++; [pscustomobject]@{ Guid = ('{0:D8}-0400-4000-8000-000000000000' -f $script:guidCounter) } }
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
            $answer = Invoke-ContentHubStandIn -StandIn $script:moduleHub -Method $Method -Path $Path -ApiVersion $ApiVersion -Body $Body
            if ($answer.Kind -eq 'Error') {
                $short = (@((($Path -split '\?')[0]) -split '/' | Where-Object { $_ }) | Select-Object -Last 2) -join '/'
                throw [System.Net.Http.HttpRequestException]::new("HTTP $($answer.Status) from $Method ${short}: $($answer.Code): $($answer.Message)")
            }
            $answer.Value
        }
        $splat = @{} + $Parameters
        if ($WhatIf) { $splat.WhatIf = $true }
        $run = & $Command -Context $script:context @splat
        [pscustomobject]@{ Run = $run; Writes = @($script:moduleHub.Writes) }
    }
    function Get-Result {
        param($Run, [string] $Name)
        @($Run.Results | Where-Object { $_.Name -eq $Name })
    }
    function Get-WriteKey {
        param($Write)
        "$($Write.Method) $($Write.Path) $($Write.ApiVersion) $(ConvertTo-ParityJson $Write.Body)"
    }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Compare-iSOCSemanticVersion' {
    It 'returns <Expected> for <V1> against <V2>' -ForEach @(
        @{ V1 = '1.0.0'; V2 = '1.0.1'; Expected = -1 }
        @{ V1 = '2.0.0'; V2 = '1.9.9'; Expected = 1 }
        @{ V1 = '3.0.10'; V2 = '3.0.9'; Expected = 1 }
        @{ V1 = '1.2.3'; V2 = '1.2.3'; Expected = 0 }
        @{ V1 = '1.2'; V2 = '1.2.0'; Expected = 0 }
        @{ V1 = '2.0'; V2 = '1.99.99'; Expected = 1 }
        @{ V1 = '5'; V2 = '4.9'; Expected = 1 }
    ) {
        Invoke-InModule { param($A, $B) Compare-iSOCSemanticVersion -Version1 $A -Version2 $B } @{ A = $V1; B = $V2 } | Should -Be $Expected
    }

    It 'falls back to ordinal text comparison when a part is not a number' {
        $result = Invoke-InModule { Compare-iSOCSemanticVersion -Version1 '1.0.0-beta' -Version2 '1.0.0-alpha' }
        [Math]::Sign($result) | Should -Be 1
    }
}

Describe 'Test-iSOCContentHubRuleCustomised' {
    BeforeAll {
        function New-RuleProps {
            param([hashtable] $Override = @{})
            $base = [ordered]@{ query = 'T | take 1'; queryFrequency = 'PT5M'; queryPeriod = 'PT5M'; triggerOperator = 'GreaterThan'; triggerThreshold = 0; severity = 'Medium' }
            foreach ($key in $Override.Keys) { $base[$key] = $Override[$key] }
            [pscustomobject]$base
        }
        function Test-Customised {
            param([hashtable] $Rule = @{}, [hashtable] $Template = @{})
            Invoke-InModule { param($R, $T) Test-iSOCContentHubRuleCustomised -ExistingRule ([pscustomobject]@{ name = 'r'; properties = $R }) -TemplateProperties $T } @{ R = (New-RuleProps $Rule); T = (New-RuleProps $Template) }
        }
    }

    It 'finds nothing when every compared field matches' {
        $result = Test-Customised
        $result.IsCustomised | Should -BeFalse
        @($result.Modifications).Count | Should -Be 0
    }

    It 'ignores <Case>' -ForEach @(
        @{ Case = 'whitespace in the query'; Rule = @{ query = "T`n| take 1" }; Template = @{ query = 'T | take 1' } }
        @{ Case = 'two spellings of one duration'; Rule = @{ queryFrequency = 'P1D'; queryPeriod = 'P14D' }; Template = @{ queryFrequency = 'PT24H'; queryPeriod = 'PT336H' } }
        @{ Case = 'the case of the severity'; Rule = @{ severity = 'medium' }; Template = @{ severity = 'Medium' } }
    ) {
        (Test-Customised $Rule $Template).IsCustomised | Should -BeFalse
    }

    It 'names <Field> when it differs' -ForEach @(
        @{ Field = 'severity'; Rule = @{ severity = 'High' } }
        @{ Field = 'KQL query'; Rule = @{ query = 'T | take 1 | extend X = 1' } }
        @{ Field = 'triggerThreshold'; Rule = @{ triggerThreshold = 5 } }
        @{ Field = 'triggerOperator'; Rule = @{ triggerOperator = 'LessThan' } }
        @{ Field = 'queryFrequency'; Rule = @{ queryFrequency = 'PT15M' } }
        @{ Field = 'queryPeriod'; Rule = @{ queryPeriod = 'PT1H' } }
    ) {
        $result = Test-Customised $Rule
        $result.IsCustomised | Should -BeTrue
        @($result.Modifications) | Should -Be @($Field)
    }

    It 'names every field that differs, in the order it checks them' {
        @((Test-Customised @{ severity = 'High'; triggerThreshold = 5; query = 'X' }).Modifications) | Should -Be @('KQL query', 'triggerThreshold', 'severity')
    }

    It 'does not compare entity mappings or a field only one side has' {
        $rule = [pscustomobject]@{ name = 'r'; properties = (New-RuleProps) }
        $rule.properties | Add-Member -NotePropertyName entityMappings -NotePropertyValue @(@{ entityType = 'Account' })
        $template = [pscustomobject]@{ severity = 'Medium'; entityMappings = @(@{ entityType = 'Host' }) }
        (Invoke-InModule { param($R, $T) Test-iSOCContentHubRuleCustomised -ExistingRule $R -TemplateProperties $T } @{ R = $rule; T = $template }).IsCustomised | Should -BeFalse
    }
}

Describe 'ConvertTo-iSOCSolutionDeploymentJson' {
    BeforeAll {
        $package = [pscustomobject]@{
            contentVersion = '1.0.0.0'
            resources      = @([pscustomobject]@{
                    type       = 'Microsoft.OperationalInsights/workspaces/providers/contentTemplates'
                    properties = [pscustomobject]@{
                        displayName  = "Caf$([char]0xE9) rule"
                        mainTemplate = [pscustomobject]@{ resources = @([pscustomobject]@{ properties = [pscustomobject]@{ query = [pscustomobject]@{ text = 'SecurityEvent | take 1' } } }) }
                    }
                })
        }
        $script:deploymentJson = Invoke-InModule { param($P) ConvertTo-iSOCSolutionDeploymentJson -PackagedContent $P -Workspace 'law-test' -Region 'uksouth' } @{ P = $package }
    }

    It 'emits compact single-line JSON' {
        $script:deploymentJson | Should -Not -Match '\n'
        $script:deploymentJson | Should -Not -Match '": '
    }

    It 'carries the workspace, region and incremental mode' {
        $body = $script:deploymentJson | ConvertFrom-Json
        $body.properties.parameters.workspace.value | Should -BeExactly 'law-test'
        $body.properties.parameters.'workspace-location'.value | Should -BeExactly 'uksouth'
        $body.properties.mode | Should -BeExactly 'Incremental'
    }

    It 'keeps template content nested beyond the default serialisation depth' {
        $body = $script:deploymentJson | ConvertFrom-Json
        @($body.properties.template.resources)[0].properties.mainTemplate.resources[0].properties.query.text | Should -BeExactly 'SecurityEvent | take 1'
    }

    It 'escapes non-ASCII characters' {
        $script:deploymentJson | Should -BeLike '*Caf\u00e9 rule*'
    }
}

Describe 'Invoke-iSOCContentHubSolutionDeploy' {
    BeforeAll {
        $script:solutionStatus = @{
            Name = 'Test Solution'; Status = 'NotInstalled'; Action = 'Install'; InstalledVersion = $null; AvailableVersion = '1.0.0'
            CatalogEntry = [pscustomobject]@{ name = 'test.solution'; properties = [pscustomobject]@{ contentId = 'test.solution' } }; InstalledPackage = $null
        }
        function Invoke-Deploy {
            param([string] $Description)
            $script:puts = [System.Collections.Generic.List[object]]::new()
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            Mock -ModuleName iSOCDeployments Start-Sleep { }
            Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
                if ($Method -eq 'PUT') { $script:puts.Add([pscustomobject]@{ Path = $Path; ApiVersion = $ApiVersion; Body = $Body }); return }
                [pscustomobject]@{ properties = [pscustomobject]@{ packagedContent = [pscustomobject]@{ resources = @([pscustomobject]@{ properties = [pscustomobject]@{ description = $script:description } }) } } }
            }
            $script:description = $Description
            Invoke-InModule { param($C, $S) Invoke-iSOCContentHubSolutionDeploy -Context $C -SolutionStatus $S } @{ C = $script:context; S = $script:solutionStatus }
        }
    }

    It 'fails a package over the 4 MB limit without sending it' {
        $result = Invoke-Deploy -Description ('x' * (4MB + 10))
        $result.Outcome | Should -Be 'Failed'
        $result.Reason | Should -BeLike 'the package is * MB, over the 4 MB ARM limit'
        $script:puts.Count | Should -Be 0
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'Error' -and $Message -like '*Test Solution v1.0.0 is * MB*over the 4 MB ARM limit*' }
    }

    It 'sends a package under the limit as compact JSON to a deployment named after the catalogue entry' {
        $result = Invoke-Deploy -Description 'small'
        $result.Outcome | Should -Be 'Deployed'
        $script:puts.Count | Should -Be 1
        $script:puts[0].Path | Should -BeExactly '/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/rg/providers/Microsoft.Resources/deployments/sentinel-test.solution'
        $script:puts[0].ApiVersion | Should -BeExactly '2024-11-01'
        $script:puts[0].Body | Should -BeOfType [string]
        $script:puts[0].Body | Should -Not -Match '\n'
        $script:puts[0].Body | Should -BeLike '*"description":"small"*'
    }

    It 'leaves a current solution alone, and sends nothing under -WhatIf' {
        Invoke-Deploy -Description 'small' | Out-Null
        $script:puts.Clear()
        $current = @{} + $script:solutionStatus
        $current.Action = 'None'
        (Invoke-InModule { param($C, $S) Invoke-iSOCContentHubSolutionDeploy -Context $C -SolutionStatus $S } @{ C = $script:context; S = $current }).Outcome | Should -Be 'Unchanged'
        $result = Invoke-InModule { param($C, $S) Invoke-iSOCContentHubSolutionDeploy -Context $C -SolutionStatus $S -WhatIf } @{ C = $script:context; S = $script:solutionStatus }
        $result.Outcome | Should -Be 'WhatIf'
        $script:puts.Count | Should -Be 0
    }
}

Describe 'Rule templates' {
    BeforeAll {
        $script:hubData = (New-ContentHubStandIn -Path $script:fixture).Data
        function Get-Record {
            param([string] $Id)
            $template = $script:hubData.templates | Where-Object { $_.name -eq $Id }
            Invoke-InModule { param($T) Read-iSOCContentHubRuleTemplate -Template $T } @{ T = $template }
        }
    }

    It 'reads the rule, its kind, the template contentId and the metadata resource''s version' {
        $record = Get-Record 'tmpl-a1'
        $record.Problem | Should -BeNullOrEmpty
        $record.DisplayName | Should -BeExactly 'Alpha new rule'
        $record.Severity | Should -BeExactly 'High'
        $record.Kind | Should -BeExactly 'Scheduled'
        $record.TemplateName | Should -BeExactly 'tmpl-a1'
        $record.TemplateVersion | Should -BeExactly '1.0.1'
        $record.PackageId | Should -BeExactly 'azuresentinel.fixture-alpha'
        (Get-Record 'tmpl-a8').Kind | Should -BeExactly 'NRT'
    }

    It 'says why a template carries no rule: <Id>' -ForEach @(
        @{ Id = 'tmpl-a11'; Problem = 'the template has no mainTemplate' }
        @{ Id = 'tmpl-a12'; Problem = 'the template has no resources' }
    ) {
        (Get-Record $Id).Problem | Should -BeExactly $Problem
    }

    It 'builds the body without the ARM fields, linked to the template' {
        $body = Invoke-InModule { param($R) ConvertTo-iSOCContentHubRuleRequest -Record $R } @{ R = (Get-Record 'tmpl-a1') }
        $body.kind | Should -BeExactly 'Scheduled'
        $p = $body.properties
        $p.PSObject.Properties.Name | Should -Not -Contain 'metadata'
        $p.alertRuleTemplateName | Should -BeExactly 'tmpl-a1'
        $p.templateVersion | Should -BeExactly '1.0.1'
        $p.enabled | Should -BeTrue
        @($p.entityMappings).Count | Should -Be 5
        $p.incidentConfiguration.groupingConfiguration.lookbackDuration | Should -BeExactly 'PT5H'
        $p.incidentConfiguration.groupingConfiguration.matchingMethod | Should -BeExactly 'AllEntities'
        @($p.subTechniques) | Should -Be @('T1078.004')
    }

    It 'leaves the template as it was' {
        $record = Get-Record 'tmpl-a1'
        Invoke-InModule { param($R) ConvertTo-iSOCContentHubRuleRequest -Record $R -DisableRules } @{ R = $record } | Out-Null
        $record.RuleProperties.enabled | Should -BeTrue
        $record.RuleProperties.incidentConfiguration.groupingConfiguration.lookbackDuration | Should -BeExactly '5h'
        $record.RuleProperties.incidentConfiguration.groupingConfiguration.PSObject.Properties.Name | Should -Not -Contain 'matchingMethod'
        @($record.RuleProperties.entityMappings).Count | Should -Be 6
    }

    It 'sends a rule disabled with -DisableRules, strips an NRT rule''s schedule, wraps a single mapping and fills an empty grouping' {
        (Invoke-InModule { param($R) ConvertTo-iSOCContentHubRuleRequest -Record $R -DisableRules } @{ R = (Get-Record 'tmpl-a1') }).properties.enabled | Should -BeFalse
        $nrt = (Invoke-InModule { param($R) ConvertTo-iSOCContentHubRuleRequest -Record $R } @{ R = (Get-Record 'tmpl-a8') }).properties
        foreach ($field in 'queryFrequency', 'queryPeriod', 'triggerOperator', 'triggerThreshold') { $nrt.PSObject.Properties.Name | Should -Not -Contain $field }
        $single = (Invoke-InModule { param($R) ConvertTo-iSOCContentHubRuleRequest -Record $R } @{ R = (Get-Record 'tmpl-d1') }).properties
        , $single.entityMappings | Should -BeOfType [object[]]
        $grouping = (Invoke-InModule { param($R) ConvertTo-iSOCContentHubRuleRequest -Record $R } @{ R = (Get-Record 'tmpl-c1') }).properties.incidentConfiguration.groupingConfiguration
        $grouping.matchingMethod | Should -BeExactly 'AllEntities'
        $grouping.lookbackDuration | Should -BeExactly 'PT1H'
    }

    Context 'Get-iSOCContentHubRuleAction' {
        BeforeAll {
            $script:byTemplate = @{}
            $script:byName = @{}
            foreach ($rule in $script:hubData.alertRules) {
                if ($rule.properties.PSObject.Properties['alertRuleTemplateName']) { $script:byTemplate[$rule.properties.alertRuleTemplateName] = $rule }
                $script:byName[$rule.properties.displayName] = $rule
            }
            function Get-Action {
                param([string] $Id, [hashtable] $Switches = @{})
                Invoke-InModule { param($R, $T, $N, $S) Get-iSOCContentHubRuleAction -Record $R -RulesByTemplate $T -RulesByName $N @S } @{ R = (Get-Record $Id); T = $script:byTemplate; N = $script:byName; S = $Switches }
            }
        }

        It '<Id> with <Label>: <Action>' -ForEach @(
            @{ Id = 'tmpl-a1'; Label = 'no rule'; Switches = @{}; Action = 'Create' }
            @{ Id = 'tmpl-a2'; Label = 'a current rule'; Switches = @{}; Action = 'Unchanged' }
            @{ Id = 'tmpl-a2'; Label = 'its solution just installed'; Switches = @{ FromNewSolution = $true }; Action = 'Update' }
            @{ Id = 'tmpl-a2'; Label = '-ForceContentDeployment'; Switches = @{ ForceContentDeployment = $true }; Action = 'Update' }
            @{ Id = 'tmpl-a3'; Label = 'a newer template and P1D for PT24H'; Switches = @{}; Action = 'Update' }
            @{ Id = 'tmpl-a4'; Label = 'a rule changed in the workspace'; Switches = @{}; Action = 'Protected' }
            @{ Id = 'tmpl-a4'; Label = 'protection off'; Switches = @{ ProtectCustomisedRules = $false }; Action = 'Update' }
            @{ Id = 'tmpl-a5'; Label = 'a rule of that name not linked'; Switches = @{}; Action = 'Protected' }
            @{ Id = 'tmpl-a5'; Label = 'a rule of that name, protection off'; Switches = @{ ProtectCustomisedRules = $false }; Action = 'Update' }
            @{ Id = 'tmpl-b1'; Label = '-DisableRules on an enabled rule'; Switches = @{ DisableRules = $true }; Action = 'Update' }
            @{ Id = 'tmpl-b2'; Label = '-DisableRules on a disabled rule'; Switches = @{ DisableRules = $true }; Action = 'Unchanged' }
        ) {
            (Get-Action $Id $Switches).Action | Should -BeExactly $Action
        }

        It 'names the fields a protected rule was changed in' {
            $decision = Get-Action 'tmpl-a4'
            @($decision.Modifications) | Should -Be @('KQL query', 'severity')
            $decision.Reason | Should -BeExactly 'modified fields: KQL query, severity'
            @((Get-Action 'tmpl-a5').Modifications).Count | Should -Be 0
        }
    }
}

Describe 'Get-iSOCContentHubSolution' {
    It 'reports where each solution stands and what installing it would do' {
        $solutions = @((Invoke-ModuleRun -Command Get-iSOCContentHubSolution -Parameters @{ Name = 'Fixture Alpha,fixture bravo, Fixture Charlie,Fixture Delta,Fixture Missing' }).Run)
        @($solutions.Name) | Should -Be $script:allSolutions
        @($solutions | ForEach-Object { "$($_.Status)/$($_.Action)" }) | Should -Be @('UpdateAvailable/Update', 'Installed/None', 'NotInstalled/Install', 'Installed/ForceUpdate', 'NotFound/None')
        $solutions[0].InstalledVersion | Should -BeExactly '3.0.0'
        $solutions[0].AvailableVersion | Should -BeExactly '3.0.1'
        $solutions[1].ContentId | Should -BeExactly 'azuresentinel.fixture-bravo'
        $solutions[1].CatalogueName | Should -BeExactly 'bravo-pkg'
        $solutions[2].InstalledVersion | Should -BeNullOrEmpty
        $solutions[0].PSObject.TypeNames | Should -Contain 'iSOCDeployments.ContentHubSolution'
    }

    It 'lists every solution in the catalogue without a name, and writes nothing' {
        $read = Invoke-ModuleRun -Command Get-iSOCContentHubSolution
        @($read.Run.Name) | Should -Be @('Fixture Alpha', 'Fixture Bravo', 'Fixture Charlie', 'Fixture Delta', 'Fixture Echo')
        $read.Writes.Count | Should -Be 0
    }
}

Describe 'Install-iSOCContentHubSolution' {
    BeforeAll {
        $script:full = Invoke-ModuleRun -Parameters @{ Name = $script:allSolutions }
    }

    It 'reports an outcome for every solution' {
        @($script:full.Run.Solutions | ForEach-Object { "$($_.Name)=$($_.Outcome)" }) | Should -Be @(
            'Fixture Alpha=Updated', 'fixture bravo=Unchanged', 'Fixture Charlie=Deployed', 'Fixture Delta=Updated', 'Fixture Missing=Failed'
        )
        (Get-Result $script:full.Run 'Fixture Charlie').Reason | Should -BeExactly 'registered the package only'
    }

    It 'reports an outcome for every rule template of the requested solutions: <Name>' -ForEach @(
        @{ Name = 'Alpha new rule'; Outcome = 'Deployed' }
        @{ Name = 'Alpha current rule'; Outcome = 'Updated' }
        @{ Name = 'Alpha newer template'; Outcome = 'Updated' }
        @{ Name = 'Alpha customised rule'; Outcome = 'Protected' }
        @{ Name = 'Alpha hand made rule'; Outcome = 'Protected' }
        @{ Name = '[Deprecated] Alpha old rule'; Outcome = 'Deprecated' }
        @{ Name = 'Alpha informational rule'; Outcome = 'Deployed' }
        @{ Name = 'Alpha NRT rule'; Outcome = 'Deployed' }
        @{ Name = 'Alpha missing table rule'; Outcome = 'Skipped' }
        @{ Name = 'Alpha conflict rule'; Outcome = 'Failed' }
        @{ Name = 'tmpl-a11'; Outcome = 'Skipped' }
        @{ Name = 'tmpl-a12'; Outcome = 'Skipped' }
        @{ Name = 'Alpha bad request rule'; Outcome = 'Skipped' }
        @{ Name = 'Bravo enabled rule'; Outcome = 'Unchanged' }
        @{ Name = 'Bravo disabled rule'; Outcome = 'Unchanged' }
        @{ Name = 'Charlie low rule'; Outcome = 'Deployed' }
        @{ Name = 'Delta single mapping rule'; Outcome = 'Updated' }
    ) {
        $result = @(Get-Result $script:full.Run $Name | Where-Object ContentType -eq AnalyticsRule)
        $result.Count | Should -Be 1
        $result[0].Outcome | Should -Be $Outcome
    }

    It 'leaves out the templates of solutions it was not asked for' {
        Get-Result $script:full.Run 'Echo rule' | Should -BeNullOrEmpty
        Get-Result $script:full.Run 'Echo workbook' | Should -BeNullOrEmpty
    }

    It 'says why a rule was skipped or protected' {
        (Get-Result $script:full.Run 'Alpha missing table rule').Reason | Should -BeExactly 'missing tables in the environment'
        (Get-Result $script:full.Run 'Alpha bad request rule').Reason | Should -BeLike 'bad request: HTTP 400 - *'
        (Get-Result $script:full.Run 'Alpha customised rule').Reason | Should -BeExactly 'modified fields: KQL query, severity'
        (Get-Result $script:full.Run 'Alpha conflict rule').Reason | Should -BeLike 'HTTP 409 - Conflict*'
        (Get-Result $script:full.Run 'Alpha conflict rule').Solution | Should -BeExactly 'Fixture Alpha'
    }

    It 'classifies a refusal on the service''s answer, not the new rule''s GUID (every stand-in GUID contains 400)' {
        $conflict = $script:full.Writes | Where-Object { $_.Method -eq 'PUT' -and $_.Path -like '*/alertRules/*' -and $_.Body.properties.displayName -eq 'Alpha conflict rule' }
        $conflict.Path | Should -Match '0400'
        (Get-Result $script:full.Run 'Alpha conflict rule').Outcome | Should -Be 'Failed'
    }

    It 'reports an outcome for every workbook template: <Name>' -ForEach @(
        @{ Name = 'Alpha new workbook'; Outcome = 'Deployed' }
        @{ Name = 'Alpha current workbook'; Outcome = 'Updated' }
        @{ Name = 'Alpha updated workbook'; Outcome = 'Updated' }
        @{ Name = 'Alpha registered workbook'; Outcome = 'Deployed' }
        @{ Name = '[Deprecated] Alpha old workbook'; Outcome = 'Deprecated' }
        @{ Name = 'Alpha fallback workbook'; Outcome = 'Deployed' }
        @{ Name = 'Alpha unreadable workbook'; Outcome = 'Failed' }
        @{ Name = 'Alpha template without a workbook'; Outcome = 'Failed' }
        @{ Name = 'Alpha workbook without data'; Outcome = 'Skipped' }
        @{ Name = 'Alpha refused workbook'; Outcome = 'Failed' }
        @{ Name = 'Bravo new workbook'; Outcome = 'Deployed' }
        @{ Name = 'Delta current workbook'; Outcome = 'Updated' }
    ) {
        $result = @(Get-Result $script:full.Run $Name | Where-Object ContentType -eq Workbook)
        $result.Count | Should -Be 1
        $result[0].Outcome | Should -Be $Outcome
    }

    It 'updates a saved workbook under its own name, and names the solution in its metadata' {
        $updated = @($script:full.Writes | Where-Object { $_.Path -like '*/workbooks/22222222-2222-4222-8222-222222222222' })
        $updated.Count | Should -Be 1
        $updated[0].ApiVersion | Should -BeExactly '2022-04-01'
        $updated[0].Body.properties.sourceId | Should -BeExactly $script:workspacePath
        $updated[0].Body.tags.'hidden-sentinelWorkspaceId' | Should -BeExactly $script:workspacePath
        $meta = $script:full.Writes | Where-Object { $_.Path -like '*/metadata/workbook-22222222-2222-4222-8222-222222222222' }
        $meta.Body.properties.source.name | Should -BeExactly 'Fixture Alpha'
        $meta.Body.properties.version | Should -BeExactly '2.1.0'
    }

    It 'sends every alert rule call with the preview api-version, which keeps sub-techniques' {
        $ruleCalls = @($script:full.Writes | Where-Object { $_.Path -like '*/alertRules/*' })
        $ruleCalls.Count | Should -BeGreaterThan 0
        @($ruleCalls.ApiVersion | Select-Object -Unique) | Should -Be @('2025-07-01-preview')
    }

    It 'recreates an NRT rule being updated under a new name' {
        @($script:full.Writes | Where-Object { $_.Method -eq 'DELETE' } | ForEach-Object Path) | Should -Be @("$($script:workspacePath)/providers/Microsoft.SecurityInsights/alertRules/r-a8")
        $nrt = $script:full.Writes | Where-Object { $_.Method -eq 'PUT' -and $_.Path -like '*/alertRules/*' -and $_.Body.properties.displayName -eq 'Alpha NRT rule' }
        $nrt.Path | Should -Not -BeLike '*r-a8'
    }

    It 'links rules to their solution, by contentId when the template names the catalogue entry' {
        $script:full.Run.MetadataLinked | Should -BeGreaterThan 0
        $script:full.Run.MetadataFailed | Should -Be 0
        $bravo = $script:full.Writes | Where-Object { $_.Path -like '*/metadata/analyticsrule-r-b1' }
        $bravo.Body.properties.source.sourceId | Should -BeExactly 'azuresentinel.fixture-bravo'
        $bravo.Body.properties.source.name | Should -BeExactly 'Fixture Bravo'
    }

    It 'counts the automation rule and hunting query templates over every page (MIGRATION.md edit E20)' {
        $script:full.Run.AutomationRuleTemplates | Should -Be 2
        $script:full.Run.HuntingQueryTemplates | Should -Be 3
    }

    It 'fails the run when anything failed' {
        $script:full.Run.ExitCode | Should -Be 1
        $script:full.Run.Failed | Should -Be @($script:full.Run.Results | Where-Object Outcome -eq Failed).Count
        $script:full.Run.PSObject.TypeNames | Should -Contain 'iSOCDeployments.ContentHubRun'
    }

    It 'waits a minute for templates only when a solution was installed or updated (MIGRATION.md edit E19)' {
        Should -Invoke -ModuleName iSOCDeployments Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 60 } -Scope Describe
        Invoke-ModuleRun -Parameters @{ Name = 'fixture bravo' } | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Start-Sleep -Times 0 -Exactly -ParameterFilter { $Seconds -eq 60 } -Scope It
        Invoke-ModuleRun -Parameters @{ Name = $script:allSolutions; ExcludeContentType = 'Solution' } | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Start-Sleep -Times 0 -Exactly -ParameterFilter { $Seconds -eq 60 } -Scope It
    }

    It 'writes nothing with -WhatIf, the metadata of unchanged rules included (MIGRATION.md edit E19)' {
        $dry = Invoke-ModuleRun -Parameters @{ Name = $script:allSolutions } -WhatIf
        $dry.Writes.Count | Should -Be 0
        @($dry.Run.Results | Where-Object Outcome -in 'Deployed', 'Updated').Count | Should -Be 0
        (Get-Result $dry.Run 'Fixture Alpha').Outcome | Should -Be 'WhatIf'
        (Get-Result $dry.Run 'Alpha new rule').Reason | Should -BeExactly 'deploy'
        (Get-Result $dry.Run 'Alpha newer template').Reason | Should -BeExactly 'update'
        Should -Invoke -ModuleName iSOCDeployments Start-Sleep -Times 0 -Exactly -ParameterFilter { $Seconds -eq 60 } -Scope It
    }

    It 'leaves out the kinds -ExcludeContentType names' {
        $part = Invoke-ModuleRun -Parameters @{ Name = $script:allSolutions; ExcludeContentType = 'Solution', 'Workbook', 'HuntingQuery' }
        @($part.Run.Results.ContentType | Select-Object -Unique) | Should -Be @('AnalyticsRule')
        $part.Run.HuntingQueryTemplates | Should -Be 0
        $part.Run.AutomationRuleTemplates | Should -Be 2
        @($part.Writes | Where-Object { $_.Path -like '*/deployments/*' }).Count | Should -Be 0
    }

    It 'splits one comma-separated name' {
        $split = Invoke-ModuleRun -Parameters @{ Name = 'fixture bravo, Fixture Missing' }
        @($split.Run.Solutions.Name) | Should -Be @('fixture bravo', 'Fixture Missing')
    }

    It 'needs a connected workspace' {
        InModuleScope iSOCDeployments { $script:iSOCContext = $null }
        { Install-iSOCContentHubSolution -Name 'Fixture Alpha' } | Should -Throw -ExpectedMessage '*Run Connect-iSOCWorkspace first*'
    }
}

Describe 'Parity with Deploy-SentinelContentHub.ps1' {
    BeforeAll {
        Import-Module (Join-Path $script:repoRoot 'Tests/_helpers/Import-ScriptFunctions.psm1') -Force
        Import-ScriptFunctions -Path (Join-Path $script:repoRoot 'Deploy/content/Deploy-SentinelContentHub.ps1')
        function Write-PipelineMessage { param($Message, $Level) }
        Mock Start-Sleep { }
        function New-Guid { $script:guidCounter++; [pscustomobject]@{ Guid = ('{0:D8}-0400-4000-8000-000000000000' -f $script:guidCounter) } }
        function Invoke-SentinelApi {
            param($Uri, $Method, $Headers, $Body, $MaxRetries)
            $answer = Invoke-ContentHubStandIn -StandIn $script:legacyHub -Method $Method -Path ($Uri -replace '^https://management\.azure\.com', '') -Body $Body
            switch ($answer.Kind) {
                'Error' { throw "API call failed: HTTP $($answer.Status) - {`"error`":{`"code`":`"$($answer.Code)`",`"message`":`"$($answer.Message)`"}}" }
                'Collection' {
                    if ($answer.ContainsKey('FirstPage')) { return [pscustomobject]@{ value = @($answer.FirstPage); nextLink = 'https://management.azure.com/next-page' } }
                    return [pscustomobject]@{ value = @($answer.Value) }
                }
                default { return $answer.Value }
            }
        }
        function Invoke-AzRestMethod {
            param($Path, $Method, $Payload)
            $answer = Invoke-ContentHubStandIn -StandIn $script:legacyHub -Method $Method -Path $Path -Body $Payload
            if ($answer.Kind -eq 'Error') { return [pscustomobject]@{ StatusCode = $answer.Status; Content = $answer.Message } }
            [pscustomobject]@{ StatusCode = 200; Content = '{}' }
        }
        function Connect-AzureEnvironment {
            param($ResourceGroup, $Workspace, $Region, $SubscriptionId, [switch] $IsGov)
            @{
                SubscriptionId = '00000000-0000-0000-0000-000000000000'; ServerUrl = 'https://management.azure.com'
                BaseUri = "https://management.azure.com$($script:workspacePath)"; WorkspaceResourceId = $script:workspacePath; WorkspaceId = 'c'; AuthHeader = @{}
            }
        }

        $script:SentinelApiVersion = '2025-09-01'
        $script:AlertRuleApiVersion = '2025-07-01-preview'
        $script:DeploymentApiVersion = '2024-11-01'
        $script:MetadataApiVersion = '2025-09-01'
        $script:MaxDeploymentRequestBytes = 4MB
        $script:ResourceGroup = 'rg'
        $script:Workspace = 'ws'
        $script:Region = 'uksouth'

        # The script's settings, as its parameters would set them.
        function Set-LegacySetting {
            param([hashtable] $Setting = @{})
            $script:SeveritiesToInclude = if ($Setting.ContainsKey('Severity')) { $Setting.Severity } else { @('High', 'Medium', 'Low', 'Informational') }
            foreach ($name in 'DisableRules', 'ForceSolutionUpdate', 'ForceContentDeployment', 'WhatIf', 'SkipSolutionDeployment', 'SkipAnalyticsRules', 'SkipWorkbooks', 'SkipAutomationRules', 'SkipHuntingQueries') {
                Set-Variable -Scope Script -Name $name -Value ([bool]$Setting[$name])
            }
            $script:ProtectCustomisedRules = if ($Setting.ContainsKey('ProtectCustomisedRules')) { $Setting.ProtectCustomisedRules } else { $true }
            $script:BaseUri = "https://management.azure.com$($script:workspacePath)"
            $script:ServerUrl = 'https://management.azure.com'
            $script:SubscriptionId = '00000000-0000-0000-0000-000000000000'
            $script:AuthHeader = @{}
            $script:MetadataLinked = 0
            $script:MetadataFailed = 0
            $script:legacyHub = New-ContentHubStandIn -Path $script:fixture
            $script:guidCounter = 0
        }

        # Invoke-Main's phases (Deploy-SentinelContentHub.ps1, from "Discover
        # solutions" to the summary) without its exit, so a run that fails
        # can be compared.
        function Invoke-LegacyRun {
            param([string[]] $Solutions, [hashtable] $Setting = @{})
            Set-LegacySetting $Setting
            $hubData = Get-ContentHubSolutions
            $solutionStatuses = @(foreach ($solName in $Solutions) { Get-SolutionStatus -SolutionName $solName -AvailableSolutions $hubData.Available -InstalledLookup $hubData.InstalledLookup })
            $overall = @{
                Solutions       = @{ Deployed = 0; Updated = 0; Skipped = 0; Failed = 0 }
                AnalyticsRules  = @{ Deployed = 0; Updated = 0; Skipped = 0; CustomisedSkipped = 0; Deprecated = 0; Failed = 0 }
                Workbooks       = @{ Deployed = 0; Updated = 0; Skipped = 0; Failed = 0 }
                AutomationRules = @{ Deployed = 0 }
                HuntingQueries  = @{ Deployed = 0 }
            }
            if (-not $script:SkipSolutionDeployment) {
                foreach ($status in $solutionStatuses) {
                    if ($status.Status -eq 'NotFound') { $overall.Solutions.Failed++; continue }
                    $success = Deploy-Solution -SolutionStatus $status
                    switch ($status.Action) {
                        'Install' { if ($success) { $overall.Solutions.Deployed++ } else { $overall.Solutions.Failed++ } }
                        'Update' { if ($success) { $overall.Solutions.Updated++ } else { $overall.Solutions.Failed++ } }
                        'ForceUpdate' { if ($success) { $overall.Solutions.Updated++ } else { $overall.Solutions.Failed++ } }
                        'None' { $overall.Solutions.Skipped++ }
                    }
                }
            }
            $script:NewlyDeployedSolutions = @($solutionStatuses | Where-Object { $_.Action -in @('Install', 'Update', 'ForceUpdate') } | ForEach-Object { $_.Name })
            $contentSolutionNames = @($solutionStatuses | Where-Object { $_.Status -ne 'NotFound' } | ForEach-Object { $_.Name })
            if ($contentSolutionNames.Count -gt 0) {
                if (-not $script:SkipAnalyticsRules) { $overall.AnalyticsRules = Deploy-AnalyticsRules -SolutionNames $contentSolutionNames -AvailableSolutions $hubData.Available }
                if (-not $script:SkipWorkbooks) { $overall.Workbooks = Deploy-Workbooks -SolutionNames $contentSolutionNames -AvailableSolutions $hubData.Available }
                if (-not $script:SkipAutomationRules) { $overall.AutomationRules = Get-AutomationRuleStatus -SolutionNames $contentSolutionNames -AvailableSolutions $hubData.Available }
                if (-not $script:SkipHuntingQueries) { $overall.HuntingQueries = Get-HuntingQueryStatus -SolutionNames $contentSolutionNames -AvailableSolutions $hubData.Available }
            }
            [pscustomobject]@{ Overall = $overall; Writes = @($script:legacyHub.Writes); MetadataLinked = $script:MetadataLinked; MetadataFailed = $script:MetadataFailed }
        }

        function Get-ModuleCount {
            param($Run, [string] $Type, [string[]] $Outcome)
            @($Run.Results | Where-Object { $_.ContentType -eq $Type -and $_.Outcome -in $Outcome }).Count
        }
        function Assert-SameOutcome {
            param($Legacy, $Module)
            $old = $Legacy.Overall
            $run = $Module.Run
            Get-ModuleCount $run Solution Deployed | Should -Be $old.Solutions.Deployed -Because 'solutions installed'
            Get-ModuleCount $run Solution Updated | Should -Be $old.Solutions.Updated -Because 'solutions updated'
            Get-ModuleCount $run Solution Unchanged | Should -Be $old.Solutions.Skipped -Because 'solutions left alone'
            Get-ModuleCount $run Solution Failed | Should -Be $old.Solutions.Failed -Because 'solutions failed'
            Get-ModuleCount $run AnalyticsRule Deployed | Should -Be $old.AnalyticsRules.Deployed -Because 'rules created'
            Get-ModuleCount $run AnalyticsRule Updated | Should -Be $old.AnalyticsRules.Updated -Because 'rules updated'
            Get-ModuleCount $run AnalyticsRule Unchanged, Skipped | Should -Be $old.AnalyticsRules.Skipped -Because 'rules skipped'
            Get-ModuleCount $run AnalyticsRule Protected | Should -Be $old.AnalyticsRules.CustomisedSkipped -Because 'rules protected'
            Get-ModuleCount $run AnalyticsRule Deprecated | Should -Be $old.AnalyticsRules.Deprecated -Because 'rules deprecated'
            Get-ModuleCount $run AnalyticsRule Failed | Should -Be $old.AnalyticsRules.Failed -Because 'rules failed'
            Get-ModuleCount $run Workbook Deployed | Should -Be $old.Workbooks.Deployed -Because 'workbooks saved'
            Get-ModuleCount $run Workbook Updated | Should -Be $old.Workbooks.Updated -Because 'workbooks updated'
            Get-ModuleCount $run Workbook Unchanged, Skipped, Deprecated | Should -Be $old.Workbooks.Skipped -Because 'workbooks skipped'
            Get-ModuleCount $run Workbook Failed | Should -Be $old.Workbooks.Failed -Because 'workbooks failed'
            $run.AutomationRuleTemplates | Should -Be $old.AutomationRules.Deployed -Because 'automation rule templates (one page)'
            $run.MetadataLinked | Should -Be $Legacy.MetadataLinked
            $run.MetadataFailed | Should -Be $Legacy.MetadataFailed
            $totalFailed = $old.Solutions.Failed + $old.AnalyticsRules.Failed + $old.Workbooks.Failed
            $run.ExitCode | Should -Be ([int]($totalFailed -gt 0))
        }
        function Assert-SameWrite {
            param($Legacy, $Module)
            $old = @($Legacy.Writes | ForEach-Object { Get-WriteKey $_ } | Sort-Object -CaseSensitive)
            $new = @($Module.Writes | ForEach-Object { Get-WriteKey $_ } | Sort-Object -CaseSensitive)
            $new.Count | Should -Be $old.Count
            ($new -join "`n") | Should -BeExactly ($old -join "`n")
        }
    }

    Context 'the defaults, every kind of solution and template' {
        BeforeAll {
            $script:legacyA = Invoke-LegacyRun -Solutions $script:allSolutions
            $script:moduleA = Invoke-ModuleRun -Parameters @{ Name = $script:allSolutions }
        }

        It 'sends the same writes' { Assert-SameWrite $script:legacyA $script:moduleA }
        It 'counts the same outcomes' { Assert-SameOutcome $script:legacyA $script:moduleA }
        It 'exercises every path: failures, protection, skips and recreation' {
            $old = $script:legacyA.Overall.AnalyticsRules
            foreach ($counter in 'Deployed', 'Updated', 'Skipped', 'CustomisedSkipped', 'Deprecated', 'Failed') { $old[$counter] | Should -BeGreaterThan 0 -Because $counter }
            @($script:legacyA.Writes | Where-Object Method -eq 'DELETE').Count | Should -Be 1
        }
        It 'counts the hunting query templates on every page, where the script read the first (MIGRATION.md edit E20)' {
            $script:legacyA.Overall.HuntingQueries.Deployed | Should -Be 1
            $script:moduleA.Run.HuntingQueryTemplates | Should -Be 3
        }
    }

    Context 'every switch: disabled rules, forced updates, no protection, two severities' {
        BeforeAll {
            $setting = @{ DisableRules = $true; ForceSolutionUpdate = $true; ForceContentDeployment = $true; ProtectCustomisedRules = $false; Severity = @('High', 'Medium') }
            $script:legacyB = Invoke-LegacyRun -Solutions $script:allSolutions -Setting $setting
            $script:moduleB = Invoke-ModuleRun -Parameters @{ Name = $script:allSolutions; DisableRules = $true; ForceSolutionUpdate = $true; ForceContentDeployment = $true; OverwriteCustomisedRules = $true; Severity = 'High', 'Medium' }
        }

        It 'sends the same writes' { Assert-SameWrite $script:legacyB $script:moduleB }
        It 'counts the same outcomes' { Assert-SameOutcome $script:legacyB $script:moduleB }
        It 'sends every rule disabled and overwrites the changed ones' {
            @($script:moduleB.Writes | Where-Object { $_.Path -like '*/alertRules/*' -and $_.Method -eq 'PUT' } | ForEach-Object { $_.Body.properties.enabled } | Select-Object -Unique) | Should -Be @($false)
            $script:legacyB.Overall.AnalyticsRules.CustomisedSkipped | Should -Be 0
        }
    }

    Context '-DisableRules on its own, which updates enabled rules that are current' {
        BeforeAll {
            $script:legacyE = Invoke-LegacyRun -Solutions $script:allSolutions -Setting @{ DisableRules = $true }
            $script:moduleE = Invoke-ModuleRun -Parameters @{ Name = $script:allSolutions; DisableRules = $true }
        }

        It 'sends the same writes' { Assert-SameWrite $script:legacyE $script:moduleE }
        It 'counts the same outcomes' { Assert-SameOutcome $script:legacyE $script:moduleE }
        It 'updates the enabled rule of a current solution and leaves the disabled one' {
            (Get-Result $script:moduleE.Run 'Bravo enabled rule').Outcome | Should -Be 'Updated'
            (Get-Result $script:moduleE.Run 'Bravo disabled rule').Outcome | Should -Be 'Unchanged'
        }
    }

    Context 'the kinds left out' {
        BeforeAll {
            $script:legacyC = Invoke-LegacyRun -Solutions $script:allSolutions -Setting @{ SkipSolutionDeployment = $true; SkipWorkbooks = $true; SkipHuntingQueries = $true }
            $script:moduleC = Invoke-ModuleRun -Parameters @{ Name = $script:allSolutions; ExcludeContentType = 'Solution', 'Workbook', 'HuntingQuery' }
        }

        It 'sends the same writes' { Assert-SameWrite $script:legacyC $script:moduleC }
        It 'counts the same outcomes' { Assert-SameOutcome $script:legacyC $script:moduleC }
    }

    Context '-WhatIf' {
        BeforeAll {
            $script:legacyD = Invoke-LegacyRun -Solutions $script:allSolutions -Setting @{ WhatIf = $true }
            $script:moduleD = Invoke-ModuleRun -Parameters @{ Name = $script:allSolutions } -WhatIf
        }

        It 'reports as would-do what the script counted as done' {
            $old = $script:legacyD.Overall
            $run = $script:moduleD.Run
            @($run.Solutions | Where-Object { $_.Outcome -eq 'WhatIf' -and $_.Reason -eq 'install' }).Count | Should -Be $old.Solutions.Deployed
            @($run.Solutions | Where-Object { $_.Outcome -eq 'WhatIf' -and $_.Reason -in 'update', 'forceupdate' }).Count | Should -Be $old.Solutions.Updated
            @($run.Results | Where-Object { $_.ContentType -eq 'AnalyticsRule' -and $_.Outcome -eq 'WhatIf' -and $_.Reason -eq 'deploy' }).Count | Should -Be $old.AnalyticsRules.Deployed
            @($run.Results | Where-Object { $_.ContentType -eq 'AnalyticsRule' -and $_.Outcome -eq 'WhatIf' -and $_.Reason -eq 'update' }).Count | Should -Be $old.AnalyticsRules.Updated
            Get-ModuleCount $run AnalyticsRule Protected | Should -Be $old.AnalyticsRules.CustomisedSkipped
            @($run.Results | Where-Object { $_.ContentType -eq 'Workbook' -and $_.Outcome -eq 'WhatIf' -and $_.Reason -eq 'deploy' }).Count | Should -Be $old.Workbooks.Deployed
            @($run.Results | Where-Object { $_.ContentType -eq 'Workbook' -and $_.Outcome -eq 'WhatIf' -and $_.Reason -eq 'update' }).Count | Should -Be $old.Workbooks.Updated
        }

        It 'writes nothing, where the script wrote the metadata of unchanged rules (MIGRATION.md edit E19)' {
            $script:moduleD.Writes.Count | Should -Be 0
            $script:legacyD.Writes.Count | Should -BeGreaterThan 0
            @($script:legacyD.Writes | Where-Object { $_.Path -notlike '*/metadata/analyticsrule-*' }).Count | Should -Be 0
        }
    }

    Context 'a clean run through the script''s own Invoke-Main' {
        BeforeAll {
            Set-LegacySetting
            $script:Solutions = @('fixture bravo')
            $script:IsGov = $false
            $savedBuild = $env:BUILD_BUILDID
            $env:BUILD_BUILDID = $null
            try { Invoke-Main } finally { $env:BUILD_BUILDID = $savedBuild }
            $script:legacyMain = [pscustomobject]@{ Writes = @($script:legacyHub.Writes); MetadataLinked = $script:MetadataLinked }
            $script:moduleMain = Invoke-ModuleRun -Parameters @{ Name = 'fixture bravo' }
        }

        It 'sends the same writes' { Assert-SameWrite $script:legacyMain $script:moduleMain }
        It 'succeeds, and links the same rules' {
            $script:moduleMain.Run.ExitCode | Should -Be 0
            $script:moduleMain.Run.MetadataLinked | Should -Be $script:legacyMain.MetadataLinked
            $script:legacyMain.Writes.Count | Should -BeGreaterThan 0
        }
    }
}
