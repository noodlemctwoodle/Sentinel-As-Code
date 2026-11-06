#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the playbook content type's handlers and its
    Az.Resources wrappers.

.DESCRIPTION
    The handlers are tested on the fixture repository, which holds both
    formats (Module/AlphaCaller is Bicep, the rest JSON): which files are
    templates, names and identities, Bicep files compiled once each and
    read like JSON ones (a file that does not compile fails with the
    compiler's errors, bicepconfig.json is not a playbook, and a repository
    of JSON playbooks never needs the Bicep CLI), validation, the deployment parameters
    (only the template parameters the template declares are filled in),
    the order (modules first, each after the modules it calls, a cycle
    warned about) and the deploy handler, which deploys, or under -WhatIf
    validates without a deployment name (MIGRATION.md edit E14). The Az
    wrappers are held to refusing a deployment under -WhatIf and to passing
    the parameters through. Every template under Content/Playbooks/ in
    this repository is read through the ReadRepo handler, must pass
    Test-iSOCPlaybook with no issues, and must build its deployment
    parameters through the ToRequest handler; the module's deploy order
    over those templates must put every module after the modules it calls,
    checked by a helper written apart from the module's code.
    Convert-iSOCPlaybook is tested on copies of the fixture repository:
    -WhatIf checks everything and changes nothing, a real run leaves Bicep
    files that read with the same identities (parameters files kept) and
    has nothing to do a second time, -Name limits it, and a playbook the
    writer refuses, whose Bicep would deploy something else, or that
    already has a Bicep file is left as JSON. Parity with
    Deploy-CustomContent.ps1 was proven on release/26.11.0 before the
    script was removed.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Playbook.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Playbook.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.3.0
    Last Updated: 2026-11-06
    Requires:     PowerShell 7.2+, Pester 5+, the Bicep CLI

    Az.Resources is not needed: the cmdlets are stood in for.
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    # Every template the module should read: each Bicep and JSON file under
    # Content/Playbooks/ but parameter files, bicepconfig.json and the
    # Template folder.
    $script:playbookFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Content/Playbooks') -Recurse -File) |
        Where-Object { $_.Extension -in '.bicep', '.json' -and $_.Name -notmatch '\.parameters\.json$' -and $_.Name -ne 'bicepconfig.json' -and $_.Directory.Name -ne 'Template' } |
        ForEach-Object { @{ Path = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } }
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
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
            'Content/Playbooks/Module/AlphaCaller.bicep'
            'Content/Playbooks/Module/ZuluBase.json'
            'Content/Playbooks/NotArm.json'
        )
        @($script:items.Format) | Should -Be @('Json', 'Bicep', 'Json', 'Json')
    }

    It 'reads a Bicep playbook as its compiled template' {
        $alpha = $script:items | Where-Object { $_.Name -eq 'Module/AlphaCaller' }
        $alpha.ParseError | Should -BeNullOrEmpty
        $alpha.Data.'$schema' | Should -Match 'deploymentTemplate'
        $alpha.Data.parameters.PlaybookName.defaultValue | Should -BeExactly 'Module-AlphaCaller'
        $alpha.Data.resources[0].type | Should -BeExactly 'Microsoft.Logic/workflows'
        Test-Item $alpha | Should -BeNullOrEmpty
    }

    It 'fails a Bicep file that does not compile, with the compiler''s errors' {
        $repo = New-PlaybookRepo @{ 'Other/Broken.bicep' = 'resource x = {'; 'Other/Fine.json' = (New-Template) }
        $items = @(Get-PlaybookItem -Repo $repo)
        @($items.RelativePath) | Should -Be @('Content/Playbooks/Other/Broken.bicep', 'Content/Playbooks/Other/Fine.json')
        $items[0].ParseError | Should -BeLike 'the Bicep does not compile: *Error BCP*'
        @(Test-Item $items[0])[0] | Should -BeExactly $items[0].ParseError
        $items[0].Identity | Should -BeExactly 'broken'
    }

    It 'leaves out bicepconfig.json, and needs the Bicep CLI only when there is a Bicep playbook' {
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
        $repo = New-PlaybookRepo @{ 'bicepconfig.json' = '{ "analyzers": {} }'; 'Other/Fine.json' = (New-Template) }
        @(Get-PlaybookItem -Repo $repo).RelativePath | Should -Be @('Content/Playbooks/Other/Fine.json')
        Should -Invoke -ModuleName iSOCDeployments Assert-iSOCPrerequisite -Times 0 -Exactly
        @(Get-PlaybookItem).Count | Should -Be 4
        Should -Invoke -ModuleName iSOCDeployments Assert-iSOCPrerequisite -Times 1 -Exactly -ParameterFilter { $Name -eq 'bicep' }
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

Describe 'Content/Playbooks in this repository' {
    BeforeAll {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        function Invoke-RepoHandler {
            param([string] $Handler, [hashtable] $Parameters)
            InModuleScope iSOCDeployments -Parameters @{ T = $script:playbookType; H = $Handler; P = $Parameters } {
                param($T, $H, $P)
                Invoke-iSOCContentTypeHandler -ContentType $T -Handler $H -Parameters $P
            }
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

        $script:repoList = @(Invoke-RepoHandler -Handler ReadRepo -Parameters @{ RepoPath = $script:repoRoot; ContentType = $script:playbookType })
        $script:repoItems = @{}
        foreach ($item in $script:repoList) { $script:repoItems[$item.RelativePath] = $item }
    }

    It 'reads, validates and builds <Path>' -ForEach $script:playbookFiles {
        $item = $script:repoItems[$Path]
        $item | Should -Not -BeNullOrEmpty -Because 'the ReadRepo handler reads every template under Content/Playbooks'
        Test-Item $item | Should -BeNullOrEmpty
        { $script:repoRequest = Invoke-RepoHandler -Handler ToRequest -Parameters @{ Item = $item; Context = $script:context } } | Should -Not -Throw
        $script:repoRequest.Body | Should -Not -BeNullOrEmpty
    }

    It 'deploys every module in Content/Playbooks after the modules it calls' {
        $order = @(Get-Order $script:repoList)
        @(Test-ModulesFirst -Path @($order | ForEach-Object { $_.Path })) | Should -BeNullOrEmpty
        @($order | ForEach-Object { $_.Path } | Sort-Object) | Should -Be @($script:repoList | ForEach-Object { $_.Path } | Sort-Object)
    }
}

Describe 'Convert-iSOCPlaybook' {
    BeforeAll {
        function New-FixtureCopy {
            $copy = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            Copy-Item -LiteralPath $script:fixtureRepo -Destination $copy -Recurse
            $copy
        }
        function Get-PlaybookFile {
            param([string] $Repo)
            @(Get-ChildItem -LiteralPath (Join-Path $Repo 'Content/Playbooks') -Recurse -File | ForEach-Object { [System.IO.Path]::GetRelativePath($Repo, $_.FullName).Replace('\', '/') } | Sort-Object)
        }
    }

    BeforeEach { Mock -ModuleName iSOCDeployments Write-iSOCLog { } }

    It 'converts and checks every JSON playbook under -WhatIf, changing nothing' {
        $copy = New-FixtureCopy
        $before = Get-PlaybookFile $copy
        $run = Convert-iSOCPlaybook -RepoPath $copy -WhatIf
        @($run.Results | ForEach-Object { "$($_.Outcome) $($_.Path)" }) | Should -Be @(
            'WhatIf Content/Playbooks/Incident/FixtureIncident.json'
            'WhatIf Content/Playbooks/Module/ZuluBase.json'
            'Skipped Content/Playbooks/NotArm.json'
        )
        ($run.Results | Where-Object Path -like '*ZuluBase.json').Reason | Should -BeExactly 'would write ZuluBase.bicep and remove the JSON'
        $run.ExitCode | Should -Be 0
        Get-PlaybookFile $copy | Should -Be $before
    }

    It 'writes each as Bicep that deploys the same, removes the JSON, keeps its parameters file, and has nothing to do again' {
        $copy = New-FixtureCopy
        $before = @(Get-PlaybookItem -Repo $copy | Where-Object Name -ne 'NotArm')
        $run = Convert-iSOCPlaybook -RepoPath $copy
        $run.Converted | Should -Be 2
        $run.Skipped | Should -Be 1
        $run.Failed | Should -Be 0
        @($run.Results | Where-Object Outcome -eq 'Converted' | ForEach-Object { $_.Bicep }) | Should -Be @('Content/Playbooks/Incident/FixtureIncident.bicep', 'Content/Playbooks/Module/ZuluBase.bicep')
        Get-PlaybookFile $copy | Should -Be @(
            'Content/Playbooks/Incident/FixtureIncident.bicep'
            'Content/Playbooks/Incident/FixtureIncident.parameters.json'
            'Content/Playbooks/Module/AlphaCaller.bicep'
            'Content/Playbooks/Module/ZuluBase.bicep'
            'Content/Playbooks/NotArm.json'
            'Content/Playbooks/Template/FixtureTemplate.json'
        )
        $after = @(Get-PlaybookItem -Repo $copy | Where-Object Name -ne 'NotArm')
        @($after.Format | Sort-Object -Unique) | Should -Be @('Bicep')
        @($after.Identity) | Should -Be @($before.Identity)
        foreach ($item in $after) { Test-Item $item | Should -BeNullOrEmpty }
        (Get-Request ($after | Where-Object Name -eq 'Incident/FixtureIncident')).Body.TemplateParameterFile | Should -BeLike '*FixtureIncident.parameters.json'
        @((Convert-iSOCPlaybook -RepoPath $copy).Results | Where-Object Outcome -ne 'Skipped').Count | Should -Be 0
    }

    It 'converts only the playbooks -Name matches' {
        $copy = New-FixtureCopy
        @((Convert-iSOCPlaybook -RepoPath $copy -Name 'Module/*').Results.Path) | Should -Be @('Content/Playbooks/Module/ZuluBase.json')
        Test-Path (Join-Path $copy 'Content/Playbooks/Incident/FixtureIncident.json') | Should -BeTrue
    }

    It 'leaves a playbook as JSON when <Case>' -ForEach @(
        @{ Case = 'the writer cannot write it'; Prepare = { param($Repo) $path = Join-Path $Repo 'Content/Playbooks/Module/ZuluBase.json'; $t = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable; $t['outputs'] = @{ o = @{ type = 'string'; value = 'x' } }; Set-Content -LiteralPath $path -Value ($t | ConvertTo-Json -Depth 50) }; Reason = "cannot be written as Bicep: *'outputs'*" }
        @{ Case = 'the Bicep would deploy something else'; Prepare = { param($Repo) Mock -ModuleName iSOCDeployments Compare-iSOCArmTemplate { 'resources[0].properties.state: differs' } }; Reason = 'the Bicep would deploy something else: resources`[0`].properties.state: differs' }
        @{ Case = 'a Bicep file is already beside it'; Prepare = { param($Repo) Set-Content -LiteralPath (Join-Path $Repo 'Content/Playbooks/Module/ZuluBase.bicep') -Value 'param x string' }; Reason = 'already has ZuluBase.bicep beside it' }
    ) {
        $copy = New-FixtureCopy
        & $Prepare $copy
        $result = (Convert-iSOCPlaybook -RepoPath $copy -Name 'Module/ZuluBase').Results | Where-Object Path -like '*ZuluBase.json'
        $result.Reason | Should -BeLike $Reason
        Test-Path (Join-Path $copy 'Content/Playbooks/Module/ZuluBase.json') | Should -BeTrue
    }

    It 'fails the run when a playbook cannot be converted' {
        $copy = New-FixtureCopy
        Mock -ModuleName iSOCDeployments Compare-iSOCArmTemplate { 'different' }
        (Convert-iSOCPlaybook -RepoPath $copy).ExitCode | Should -Be 1
    }
}
