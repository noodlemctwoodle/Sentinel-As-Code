#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the playbook content type's handlers, its Az.Resources
    wrappers, and parity with the deployer they were taken from.

.DESCRIPTION
    The handlers are tested on the fixture repository: which files are
    templates, names and identities, validation, the deployment parameters
    (only the template parameters the template declares are filled in),
    the order (modules first, each after the modules it calls, a cycle
    warned about) and the deploy handler, which deploys, or under -WhatIf
    validates without a deployment name (MIGRATION.md edit E14). The Az
    wrappers are held to refusing a deployment under -WhatIf and to passing
    the parameters through. The parity block lifts Deploy-CustomPlaybooks
    out of Deploy/content/Deploy-CustomContent.ps1 by AST and runs it over
    every playbook in Content/Playbooks/ with the Az cmdlets stood in for:
    each template must get the same deployment parameters from both, both
    orders must put every module after the modules it calls, and the
    script's own -WhatIf validation is shown to fail on the deployment name
    for every template.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Playbook.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Playbook.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+, Pester 5+

    Az.Resources is not needed: the cmdlets are stood in for. The parity
    block goes when Deploy-CustomContent.ps1 is removed at cut-over.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '_helpers/Parity.psm1') -Force
    $script:fixtureRepo = Join-Path $PSScriptRoot 'Fixtures/repo'

    function New-TestContext {
        param([string] $WorkspaceId = 'c')
        InModuleScope iSOCDeployments -Parameters @{ Id = $WorkspaceId } {
            param($Id)
            New-iSOCContext -Value @{
                TenantId = 't'; SubscriptionId = '00000000-0000-0000-0000-000000000000'; ResourceGroup = 'rg'; WorkspaceName = 'ws'
                WorkspaceResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/ws'
                WorkspaceId = $Id; Region = 'uksouth'; PlaybookResourceGroup = 'rg-playbooks'; Environment = 'AzureCloud'
                IsGov = $false; ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'a'
            }
        }
    }
    $script:context = New-TestContext

    function Get-PlaybookItem {
        param([string] $Repo = $script:fixtureRepo)
        InModuleScope iSOCDeployments -Parameters @{ R = $Repo } {
            param($R)
            $type = Get-iSOCContentTypeDefinition -Name Playbook
            Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $R; ContentType = $type }
        }
    }
    function Get-Request {
        param([psobject] $Item, [psobject] $Context = $script:context)
        InModuleScope iSOCDeployments -Parameters @{ I = $Item; C = $Context } { param($I, $C) ConvertTo-iSOCPlaybookRequest -Item $I -Context $C }
    }
    function Test-Item {
        param([psobject] $Item)
        @(InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) Test-iSOCPlaybook -Item $I })
    }
    function Get-Order {
        param([psobject[]] $Item)
        @(InModuleScope iSOCDeployments -Parameters @{ I = $Item } { param($I) Get-iSOCPlaybookOrder -Item $I })
    }
    function New-PlaybookRepo {
        param([hashtable] $File)
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        foreach ($relative in $File.Keys) {
            $path = Join-Path $repo "Content/Playbooks/$relative"
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            Set-Content -LiteralPath $path -Value $File[$relative]
        }
        $repo
    }
    function New-Template {
        param([string[]] $Calls = @())
        $actions = ($Calls | ForEach-Object { "`"$_`": { `"id`": `"[concat(resourceGroup().id, '/providers/Microsoft.Logic/workflows/$_')]`" }" }) -join ', '
        "{ `"`$schema`": `"https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#`", `"parameters`": {}, `"resources`": [ { $actions } ] }"
    }

    # Dependency pairs worked out here, apart from the module's code: a
    # module that names Microsoft.Logic/workflows/Module-X calls module X.
    function Test-ModulesFirst {
        param([string[]] $Path)
        $isModule = { param($P) (Split-Path -Leaf (Split-Path -Parent $P)) -eq 'Module' }
        $modules = @($Path | Where-Object { & $isModule $_ })
        $firstOther = @($Path | ForEach-Object { $_ } | Where-Object { -not (& $isModule $_) } | Select-Object -First 1)
        if ($firstOther) {
            $lastModule = [array]::LastIndexOf($Path, $modules[-1])
            if ($lastModule -gt [array]::IndexOf($Path, $firstOther[0])) { return "a playbook that is not a module deploys before $($modules[-1])" }
        }
        $position = @{}
        for ($i = 0; $i -lt $Path.Count; $i++) { $position["Module-$([System.IO.Path]::GetFileNameWithoutExtension($Path[$i]))"] = $i }
        foreach ($module in $modules) {
            $self = "Module-$([System.IO.Path]::GetFileNameWithoutExtension($module))"
            foreach ($match in [regex]::Matches((Get-Content -LiteralPath $module -Raw), 'Microsoft\.Logic/workflows/(Module-[A-Za-z0-9_-]+)')) {
                $called = $match.Groups[1].Value
                if ($called -ne $self -and $position.ContainsKey($called) -and $position[$called] -gt $position[$self]) { "$self deploys before $called, which it calls" }
            }
        }
    }

    $script:items = @(Get-PlaybookItem)
    $script:incident = $script:items | Where-Object { $_.RelativePath -like '*FixtureIncident.json' }
    $script:playbookType = InModuleScope iSOCDeployments { Get-iSOCContentTypeDefinition -Name Playbook }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Playbook handlers' {
    BeforeEach { Mock -ModuleName iSOCDeployments Write-iSOCLog { } }

    It 'reads every template, leaving out parameter files and the Template folder' {
        @($script:items.RelativePath) | Should -Be @(
            'Content/Playbooks/Incident/FixtureIncident.json'
            'Content/Playbooks/Module/AlphaCaller.json'
            'Content/Playbooks/Module/ZuluBase.json'
            'Content/Playbooks/NotArm.json'
        )
    }

    It 'names a playbook by its folder and file, and identifies it by its PlaybookName' {
        @($script:items.Name) | Should -Be @('Incident/FixtureIncident', 'Module/AlphaCaller', 'Module/ZuluBase', 'NotArm')
        @($script:items.Identity) | Should -Be @('fixture-incident', 'module-alphacaller', 'module-zulubase', 'notarm')
        $script:incident.Category | Should -Be 'Incident'
        $script:incident.ParametersPath | Should -BeLike '*Incident*FixtureIncident.parameters.json'
    }

    It 'skips a file that is not an ARM deployment template' {
        Test-Item ($script:items | Where-Object { $_.Name -eq 'NotArm' }) | Should -Be @('not an ARM deployment template.')
    }

    It 'skips a file with no $schema at all, rather than failing on it' {
        $repo = New-PlaybookRepo @{ 'Other/NoSchema.json' = '{ "parameters": {} }' }
        Test-Item @(Get-PlaybookItem -Repo $repo)[0] | Should -Be @('not an ARM deployment template.')
    }

    It 'fails a file that does not parse' {
        $repo = New-PlaybookRepo @{ 'Other/Broken.json' = '{ not json' }
        $item = @(Get-PlaybookItem -Repo $repo)[0]
        @(Test-Item $item)[0] | Should -BeExactly $item.ParseError
        $item.Identity | Should -BeExactly 'broken'
    }

    It 'passes the templates' {
        foreach ($item in $script:items | Where-Object { $_.Name -ne 'NotArm' }) { Test-Item $item | Should -BeNullOrEmpty }
    }

    It 'deploys to the playbook resource group with the parameters file beside the template' {
        $body = (Get-Request $script:incident).Body
        $body.ResourceGroupName | Should -BeExactly 'rg-playbooks'
        $body.TemplateFile | Should -BeExactly $script:incident.Path
        $body.TemplateParameterFile | Should -BeExactly $script:incident.ParametersPath
    }

    It 'fills in only the known parameters the template declares' {
        $request = Get-Request $script:incident
        $body = $request.Body
        @($body.Keys | Sort-Object) | Should -Be @('PlaybookResourceGroup', 'ResourceGroupName', 'SentinelWorkpaceName', 'SubscriptionId', 'TemplateFile', 'TemplateParameterFile', 'WorkspaceId')
        $body.SentinelWorkpaceName | Should -BeExactly 'ws'
        $body.SubscriptionId | Should -BeExactly '00000000-0000-0000-0000-000000000000'
        $body.WorkspaceId | Should -BeExactly 'c'
        $body.PlaybookResourceGroup | Should -BeExactly 'rg-playbooks'
        @($request.Injected) | Should -Be @('SentinelWorkpaceName', 'SubscriptionId', 'WorkspaceId', 'PlaybookResourceGroup')
    }

    It 'leaves out WorkspaceId when the context has none' {
        (Get-Request $script:incident (New-TestContext -WorkspaceId '')).Body.ContainsKey('WorkspaceId') | Should -BeFalse
    }

    It 'passes no parameters file when there is none' {
        (Get-Request ($script:items | Where-Object { $_.Name -eq 'Module/ZuluBase' })).Body.ContainsKey('TemplateParameterFile') | Should -BeFalse
    }
}

Describe 'Get-iSOCPlaybookOrder' {
    BeforeEach { Mock -ModuleName iSOCDeployments Write-iSOCLog { } }

    It 'deploys the modules first, each after the modules it calls, then the rest in repository order' {
        @((Get-Order $script:items).Name) | Should -Be @('Module/ZuluBase', 'Module/AlphaCaller', 'Incident/FixtureIncident', 'NotArm')
    }

    It 'warns about calls to modules the repository does not have' {
        Get-Order $script:items | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Level -eq 'Warning' -and $Message -eq '  Incident-FixtureIncident -> Module-NotInRepo' }
    }

    It 'keeps repository order for modules that do not depend on each other' {
        $repo = New-PlaybookRepo @{ 'Module/Charlie.json' = (New-Template); 'Module/Alpha.json' = (New-Template); 'Module/Bravo.json' = (New-Template) }
        @((Get-Order @(Get-PlaybookItem -Repo $repo)).BaseName) | Should -Be @('Alpha', 'Bravo', 'Charlie')
    }

    It 'deploys modules caught in a cycle after the others, with a warning' {
        $repo = New-PlaybookRepo @{
            'Module/Alpha.json' = (New-Template -Calls 'Module-Bravo')
            'Module/Bravo.json' = (New-Template -Calls 'Module-Alpha')
            'Module/Zulu.json'  = (New-Template)
        }
        @((Get-Order @(Get-PlaybookItem -Repo $repo)).BaseName) | Should -Be @('Zulu', 'Alpha', 'Bravo')
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Message -like '*Circular dependency detected among 2 module(s)*' }
    }

    It 'returns nothing for no playbooks' {
        @(Get-Order @()).Count | Should -Be 0
    }
}

Describe 'Invoke-iSOCPlaybookDeploy' {
    BeforeEach {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments New-iSOCAzResourceGroupDeployment { }
        Mock -ModuleName iSOCDeployments Test-iSOCAzResourceGroupDeployment { }
        $script:run = [pscustomobject]@{ Context = $script:context }
    }

    It 'deploys the template as a deployment named after the file and the time' {
        $sent = InModuleScope iSOCDeployments -Parameters @{ R = $script:run; T = $script:playbookType; I = $script:incident } {
            param($R, $T, $I)
            Invoke-iSOCPlaybookDeploy -Run $R -ContentType $T -Item $I
        }
        $sent.Outcome | Should -BeExactly 'Deployed'
        Should -Invoke -ModuleName iSOCDeployments New-iSOCAzResourceGroupDeployment -Times 1 -Exactly -ParameterFilter {
            $Name -match '^Playbook-FixtureIncident-\d{14}$' -and $Parameters.TemplateFile -like '*FixtureIncident.json' -and $Parameters.SentinelWorkpaceName -eq 'ws'
        }
        Should -Invoke -ModuleName iSOCDeployments Test-iSOCAzResourceGroupDeployment -Times 0 -Exactly
    }

    It 'cuts a long file name so the deployment name fits in 64 characters' {
        $long = [pscustomobject]@{ ContentType = 'Playbook'; Identity = 'x'; Name = 'Other/x'; Path = $script:incident.Path; RelativePath = 'x'
            Data = $script:incident.Data; BaseName = ('P' * 70); ParametersPath = 'none' }
        InModuleScope iSOCDeployments -Parameters @{ R = $script:run; T = $script:playbookType; I = $long } {
            param($R, $T, $I)
            Invoke-iSOCPlaybookDeploy -Run $R -ContentType $T -Item $I
        } | Out-Null
        Should -Invoke -ModuleName iSOCDeployments New-iSOCAzResourceGroupDeployment -Times 1 -Exactly -ParameterFilter {
            $Name.Length -eq 64 -and $Name -match "^Playbook-$('P' * 40)-\d{14}$"
        }
    }

    It 'validates instead under -WhatIf, with no deployment name (MIGRATION.md edit E14)' {
        $sent = InModuleScope iSOCDeployments -Parameters @{ R = $script:run; T = $script:playbookType; I = $script:incident } {
            param($R, $T, $I)
            Invoke-iSOCPlaybookDeploy -Run $R -ContentType $T -Item $I -WhatIf
        }
        $sent.Outcome | Should -BeExactly 'WhatIf'
        Should -Invoke -ModuleName iSOCDeployments New-iSOCAzResourceGroupDeployment -Times 0 -Exactly
        Should -Invoke -ModuleName iSOCDeployments Test-iSOCAzResourceGroupDeployment -Times 1 -Exactly -ParameterFilter {
            -not $Parameters.ContainsKey('Name') -and $Parameters.ResourceGroupName -eq 'rg-playbooks'
        }
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Level -eq 'Success' -and $Message -like '*validation passed*' }
    }

    It 'reports what validation found under -WhatIf: <Case>' -ForEach @(
        @{ Case = 'errors returned'; Behaviour = { [pscustomobject]@{ Code = 'InvalidTemplate'; Message = 'Deployment template validation failed.' } }; Expect = '*validation failed*Deployment template validation failed.' }
        @{ Case = 'an exception'; Behaviour = { throw 'The resource group was not found.' }; Expect = '*validation failed*The resource group was not found.' }
    ) {
        Mock -ModuleName iSOCDeployments Test-iSOCAzResourceGroupDeployment $Behaviour
        $sent = InModuleScope iSOCDeployments -Parameters @{ R = $script:run; T = $script:playbookType; I = $script:incident } {
            param($R, $T, $I)
            Invoke-iSOCPlaybookDeploy -Run $R -ContentType $T -Item $I -WhatIf
        }
        $sent.Outcome | Should -BeExactly 'WhatIf'
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Level -eq 'Warning' -and $Message -like $Expect }
    }

    It 'names the parameters it filled in, not their values' {
        InModuleScope iSOCDeployments -Parameters @{ R = $script:run; T = $script:playbookType; I = $script:incident } {
            param($R, $T, $I)
            Invoke-iSOCPlaybookDeploy -Run $R -ContentType $T -Item $I
        } | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Message -eq '  Injected parameter: SubscriptionId' }
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -Times 0 -Exactly -ParameterFilter { $Message -like '*00000000-0000-0000-0000-000000000000*' }
    }
}

Describe 'Az.Resources wrappers' {
    BeforeAll {
        function global:New-AzResourceGroupDeployment {
            [CmdletBinding(SupportsShouldProcess)]
            param($Name, $ResourceGroupName, $TemplateFile, $SentinelWorkspaceName)
            $global:iSOCAzCall = [hashtable] $PSBoundParameters
        }
        function global:Test-AzResourceGroupDeployment {
            [CmdletBinding()]
            param($ResourceGroupName, $TemplateFile, $SentinelWorkspaceName)
            $global:iSOCAzCall = [hashtable] $PSBoundParameters
        }
    }

    AfterAll {
        Remove-Item -LiteralPath function:global:New-AzResourceGroupDeployment, function:global:Test-AzResourceGroupDeployment -ErrorAction SilentlyContinue
        Remove-Variable -Name iSOCAzCall -Scope Global -ErrorAction SilentlyContinue
    }

    BeforeEach { $global:iSOCAzCall = $null }

    It 'passes the template parameters through by name, and never asks or runs what-if' {
        InModuleScope iSOCDeployments {
            New-iSOCAzResourceGroupDeployment -Name 'd1' -Parameters @{ ResourceGroupName = 'rg-playbooks'; TemplateFile = 't.json'; SentinelWorkspaceName = 'ws' }
        }
        $global:iSOCAzCall.Name | Should -BeExactly 'd1'
        $global:iSOCAzCall.SentinelWorkspaceName | Should -BeExactly 'ws'
        $global:iSOCAzCall.WhatIf | Should -BeFalse
        $global:iSOCAzCall.Confirm | Should -BeFalse
    }

    It 'refuses to deploy under -WhatIf' {
        { InModuleScope iSOCDeployments { $WhatIfPreference = $true; New-iSOCAzResourceGroupDeployment -Name 'd1' -Parameters @{ TemplateFile = 't.json' } } } |
            Should -Throw -ExpectedMessage "*'t.json' reached New-iSOCAzResourceGroupDeployment under -WhatIf*"
        $global:iSOCAzCall | Should -BeNullOrEmpty
    }

    It 'validates with the same parameters and no deployment name' {
        InModuleScope iSOCDeployments { Test-iSOCAzResourceGroupDeployment -Parameters @{ ResourceGroupName = 'rg-playbooks'; TemplateFile = 't.json'; SentinelWorkspaceName = 'ws' } }
        @($global:iSOCAzCall.Keys | Where-Object { $_ -ne 'ErrorAction' } | Sort-Object) | Should -Be @('ResourceGroupName', 'SentinelWorkspaceName', 'TemplateFile')
    }
}

Describe 'Parity with Deploy-CustomContent.ps1' {
    BeforeAll {
        Import-Module (Join-Path $script:repoRoot 'Tests/_helpers/Import-ScriptFunctions.psm1') -Force
        Import-ScriptFunctions -Path (Join-Path $script:repoRoot 'Deploy/content/Deploy-CustomContent.ps1')
        function Write-PipelineMessage { param($Message, $Level) $script:legacyLog.Add([pscustomobject]@{ Message = $Message; Level = $Level }) }
        function Test-ShouldDeployFile { param($FilePath) $true }
        function Test-ContentDependencies { param($ContentPath) @{ Passed = $true; Missing = @() } }
        function Set-DeploymentItemState { param($FilePath, $Status) }
        # Stand-ins with the real cmdlets' parameters for everything the
        # script passes: New-AzResourceGroupDeployment takes -Name and
        # Test-AzResourceGroupDeployment does not.
        function New-AzResourceGroupDeployment {
            [CmdletBinding()]
            param($Name, $ResourceGroupName, $TemplateFile, $TemplateParameterFile, $AutomationResourceGroup, $SentinelResourceGroup,
                $SentinelResourceGroupName, $PlaybookResourceGroup, $SentinelWorkpaceName, $SentinelWorkspaceName, $SubscriptionId, $WorkspaceId)
            $script:legacyDeployments.Add([hashtable] $PSBoundParameters)
        }
        function Test-AzResourceGroupDeployment {
            [CmdletBinding()]
            param($ResourceGroupName, $TemplateFile, $TemplateParameterFile, $AutomationResourceGroup, $SentinelResourceGroup,
                $SentinelResourceGroupName, $PlaybookResourceGroup, $SentinelWorkpaceName, $SentinelWorkspaceName, $SubscriptionId, $WorkspaceId)
        }

        $script:BasePath = $script:repoRoot
        $script:PlaybookRG = 'rg-playbooks'
        $script:ResourceGroup = 'rg'
        $script:Workspace = 'ws'
        $script:SubscriptionId = '00000000-0000-0000-0000-000000000000'
        $script:WorkspaceId = 'c'

        $script:WhatIf = $true
        $script:legacyLog = [System.Collections.Generic.List[object]]::new()
        $script:legacyDeployments = [System.Collections.Generic.List[object]]::new()
        $script:whatIfCounters = Deploy-CustomPlaybooks
        $script:whatIfLog = @($script:legacyLog)

        $script:WhatIf = $false
        $script:legacyLog = [System.Collections.Generic.List[object]]::new()
        $script:legacyCounters = Deploy-CustomPlaybooks

        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        $script:moduleItems = @(Get-PlaybookItem -Repo $script:repoRoot)
        $script:moduleOrder = Get-Order $script:moduleItems
    }

    It 'deployed every template it read' {
        $script:legacyCounters.Failed | Should -Be 0
        $script:legacyCounters.Skipped | Should -Be 0
        $script:legacyDeployments.Count | Should -Be $script:moduleItems.Count
        @($script:moduleItems | Where-Object { @(Test-Item $_).Count -gt 0 }) | Should -BeNullOrEmpty
    }

    It 'gives every template the same deployment parameters, apart from the deployment name' {
        $legacyByFile = @{}
        foreach ($deployment in $script:legacyDeployments) {
            $deployment.Name | Should -Match '^Playbook-.{1,40}-\d{14}$'
            $parameters = @{} + $deployment
            $parameters.Remove('Name')
            $parameters.Remove('ErrorAction')
            $legacyByFile[$deployment.TemplateFile] = ConvertTo-ParityJson $parameters
        }
        $different = foreach ($item in $script:moduleItems) {
            if ((ConvertTo-ParityJson (Get-Request $item).Body) -cne $legacyByFile[$item.Path]) { $item.RelativePath }
        }
        @($different) | Should -BeNullOrEmpty
    }

    It 'deploys every module after the modules it calls, as the script does' {
        @(Test-ModulesFirst -Path @($script:legacyDeployments | ForEach-Object { $_.TemplateFile })) | Should -BeNullOrEmpty
        @(Test-ModulesFirst -Path @($script:moduleOrder | ForEach-Object { $_.Path })) | Should -BeNullOrEmpty
        @($script:moduleOrder | ForEach-Object { $_.Path } | Sort-Object) | Should -Be @($script:legacyDeployments | ForEach-Object { $_.TemplateFile } | Sort-Object)
    }

    It 'shows the script''s -WhatIf validation failing on the deployment name for every template (MIGRATION.md edit E14)' {
        $failed = @($script:whatIfLog | Where-Object { $_.Message -like '`[WhatIf`] Template validation failed*' })
        $failed.Count | Should -Be $script:moduleItems.Count
        @($failed | Where-Object { $_.Message -notlike "*parameter name 'Name'*" }) | Should -BeNullOrEmpty
        $script:whatIfCounters.Deployed | Should -Be $script:moduleItems.Count
    }
}
