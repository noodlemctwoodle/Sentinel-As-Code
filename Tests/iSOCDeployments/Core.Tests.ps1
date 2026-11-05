#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the iSOCDeployments private core: logging, the API
    table, repository paths, the context and Connect-iSOCWorkspace.

.DESCRIPTION
    Runs offline. Connect-iSOCWorkspace is tested with the Az wrappers and
    the REST client mocked, so no sign-in or workspace is needed. The
    logging cases are the Write-PipelineMessage cases from
    Tests/Test-SentinelCommon.Tests.ps1, carried over, plus GitHub Actions.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Core.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Core.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.2.0
    Last Updated: 2026-11-05
    Requires:     PowerShell 7.2+, Pester 5+
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    $script:fixtureRepo = Join-Path $PSScriptRoot 'Fixtures/repo'
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Write-iSOCLog' {
    BeforeEach {
        $script:saved = @{ TF_BUILD = $env:TF_BUILD; BUILD_BUILDID = $env:BUILD_BUILDID; GITHUB_ACTIONS = $env:GITHUB_ACTIONS }
        $env:TF_BUILD = $null
        $env:BUILD_BUILDID = $null
        $env:GITHUB_ACTIONS = $null
    }

    AfterEach {
        foreach ($name in $script:saved.Keys) { [Environment]::SetEnvironmentVariable($name, $script:saved[$name]) }
    }

    Context 'Local console' {
        It 'writes Info as plain text' {
            InModuleScope iSOCDeployments { Write-iSOCLog -Message 'plain info' -Level Info 6>&1 } | Should -Be 'plain info'
        }

        It 'writes Section without the Azure DevOps marker' {
            $output = InModuleScope iSOCDeployments { Write-iSOCLog -Message 'a section' -Level Section 6>&1 }
            "$output" | Should -Match 'a section'
            "$output" | Should -Not -Match '##\[section\]'
        }

        It 'writes Warning to the warning stream' {
            $captured = InModuleScope iSOCDeployments { Write-iSOCLog -Message 'careful' -Level Warning -WarningAction Continue 3>&1 }
            ($captured | ForEach-Object { [string]$_ }) -join '|' | Should -Match 'careful'
        }

        It 'writes Error to the error stream without stopping the caller' {
            $captured = InModuleScope iSOCDeployments { Write-iSOCLog -Message 'broken' -Level Error 2>&1; 'carried on' }
            ($captured | ForEach-Object { [string]$_ }) -join '|' | Should -Match 'broken\|carried on'
        }

        It 'keeps Debug silent without -Verbose' {
            InModuleScope iSOCDeployments { Write-iSOCLog -Message 'debug noise' -Level Debug 6>&1 } | Should -BeNullOrEmpty
        }
    }

    Context 'Azure DevOps' {
        It 'recognises Azure DevOps by <Variable>' -ForEach @(
            @{ Variable = 'TF_BUILD'; Value = 'True' }
            @{ Variable = 'BUILD_BUILDID'; Value = '12345' }
        ) {
            [Environment]::SetEnvironmentVariable($Variable, $Value)
            InModuleScope iSOCDeployments { Get-iSOCPipelineHost } | Should -Be 'AzureDevOps'
        }

        It 'writes <Level> with the <Marker> logging command' -ForEach @(
            @{ Level = 'Section'; Marker = '##[section]' }
            @{ Level = 'Warning'; Marker = '##[warning]' }
            @{ Level = 'Error'; Marker = '##[error]' }
        ) {
            $env:TF_BUILD = 'True'
            $output = InModuleScope iSOCDeployments -Parameters @{ Level = $Level } { param($Level) Write-iSOCLog -Message 'an ADO line' -Level $Level 6>&1 }
            "$output" | Should -BeExactly "${Marker}an ADO line"
        }
    }

    Context 'GitHub Actions' {
        BeforeEach { $env:GITHUB_ACTIONS = 'true' }

        It 'recognises GitHub Actions' {
            InModuleScope iSOCDeployments { Get-iSOCPipelineHost } | Should -Be 'GitHubActions'
        }

        It 'writes <Level> as the <Command> workflow command' -ForEach @(
            @{ Level = 'Warning'; Command = '::warning::' }
            @{ Level = 'Error'; Command = '::error::' }
        ) {
            $output = InModuleScope iSOCDeployments -Parameters @{ Level = $Level } { param($Level) Write-iSOCLog -Message 'a GitHub line' -Level $Level 6>&1 }
            "$output" | Should -BeExactly "${Command}a GitHub line"
        }

        It 'escapes the characters that would end a workflow command' {
            $output = InModuleScope iSOCDeployments { Write-iSOCLog -Message "100% done`r`nnext line" -Level Warning 6>&1 }
            "$output" | Should -BeExactly '::warning::100%25 done%0D%0Anext line'
        }
    }

    Context 'Text that reads as a pipeline command' {
        BeforeAll {
            # Each form an agent acts on: Azure DevOps ##vso[ anywhere in a
            # line, GitHub ##[ anywhere in a line and a line that starts with
            # :: once trimmed; lines end at CR, LF or CRLF. The commands are
            # harmless ones, and no test name holds one, because a failing
            # test prints them into the PR validation log.
            $script:hostile = "rule x ##vso[task.setvariable variable=iSOCLogTest]syncBranch`n##VSO[task.setvariable variable=iSOCLogTest]y`r###[group]z`r`n  ::debug name=a::b`r`t::debug::t`n::::debug::m"

            # The commands an agent would find in the output, after the
            # module's own prefix.
            $script:findCommand = {
                param([string] $Output, [string] $Prefix)
                $body = if ($Prefix) { $Output.Substring($Prefix.Length) } else { $Output }
                $found = [System.Collections.Generic.List[string]]::new()
                foreach ($match in [regex]::Matches($body, '##(vso)?\[', 'IgnoreCase')) { $found.Add($match.Value) }
                foreach ($line in ($body -split '\r\n|\r|\n')) {
                    if ($line.Trim().StartsWith('::')) { $found.Add($line) }
                }
                , $found.ToArray()
            }

            $script:capture = {
                param([string] $Level, [string] $Message)
                $records = InModuleScope iSOCDeployments -Parameters @{ Level = $Level; Message = $Message } {
                    param($Level, $Message)
                    Write-iSOCLog -Message $Message -Level $Level -Verbose -WarningAction Continue *>&1
                }
                (@($records) | ForEach-Object { "$_" }) -join "`n"
            }
        }

        It 'leaves no command in <Level> on <PipelineHost>' -ForEach @(
            @{ PipelineHost = 'Local'; Level = 'Info'; Prefix = '' }
            @{ PipelineHost = 'Local'; Level = 'Section'; Prefix = '' }
            @{ PipelineHost = 'Local'; Level = 'Success'; Prefix = '' }
            @{ PipelineHost = 'Local'; Level = 'Warning'; Prefix = '' }
            @{ PipelineHost = 'Local'; Level = 'Error'; Prefix = '' }
            @{ PipelineHost = 'Local'; Level = 'Debug'; Prefix = '' }
            @{ PipelineHost = 'AzureDevOps'; Level = 'Info'; Prefix = '' }
            @{ PipelineHost = 'AzureDevOps'; Level = 'Section'; Prefix = '##[section]' }
            @{ PipelineHost = 'AzureDevOps'; Level = 'Success'; Prefix = '' }
            @{ PipelineHost = 'AzureDevOps'; Level = 'Warning'; Prefix = '##[warning]' }
            @{ PipelineHost = 'AzureDevOps'; Level = 'Error'; Prefix = '##[error]' }
            @{ PipelineHost = 'AzureDevOps'; Level = 'Debug'; Prefix = '' }
            @{ PipelineHost = 'GitHubActions'; Level = 'Info'; Prefix = '' }
            @{ PipelineHost = 'GitHubActions'; Level = 'Section'; Prefix = '' }
            @{ PipelineHost = 'GitHubActions'; Level = 'Success'; Prefix = '' }
            @{ PipelineHost = 'GitHubActions'; Level = 'Warning'; Prefix = '::warning::' }
            @{ PipelineHost = 'GitHubActions'; Level = 'Error'; Prefix = '::error::' }
            @{ PipelineHost = 'GitHubActions'; Level = 'Debug'; Prefix = '' }
        ) {
            switch ($PipelineHost) {
                'AzureDevOps' { $env:TF_BUILD = 'True' }
                'GitHubActions' { $env:GITHUB_ACTIONS = 'true' }
            }
            $output = & $script:capture $Level $script:hostile
            $output | Should -Match 'rule x .*syncBranch'
            if ($Prefix) { $output.StartsWith($Prefix) | Should -BeTrue -Because "the module's own $Prefix prefix stays" }
            (& $script:findCommand $output $Prefix) -join ' | ' | Should -BeNullOrEmpty
        }

        It 'breaks <Name> with a space' -ForEach @(
            @{ Name = 'an Azure DevOps command'; Message = 'x ##vso[task.setvariable variable=iSOCLogTest]b'; Expected = 'x # #vso[task.setvariable variable=iSOCLogTest]b' }
            @{ Name = 'an Azure DevOps command in capitals'; Message = 'x ##VSO[task.setvariable variable=iSOCLogTest]b'; Expected = 'x # #VSO[task.setvariable variable=iSOCLogTest]b' }
            @{ Name = 'a hash-bracket command'; Message = '##[group]g'; Expected = '# #[group]g' }
            @{ Name = 'a command after a third hash'; Message = '###vso[x]'; Expected = '## #vso[x]' }
            @{ Name = 'a line starting with two colons'; Message = '::debug name=a::b'; Expected = ': :debug name=a::b' }
            @{ Name = 'a line starting with spaces and two colons'; Message = '  ::x'; Expected = '  : :x' }
            @{ Name = 'a line after a lone carriage return'; Message = "a`r::x"; Expected = "a`r: :x" }
            @{ Name = 'a line after a line feed and a tab'; Message = "a`n`t::x"; Expected = "a`n`t: :x" }
            @{ Name = 'a line starting with four colons'; Message = '::::x'; Expected = ': :::x' }
        ) {
            InModuleScope iSOCDeployments -Parameters @{ Message = $Message } { param($Message) Write-iSOCLog -Message $Message 6>&1 } |
                ForEach-Object { "$_" } | Should -BeExactly $Expected
        }

        It 'leaves <Message> unchanged' -ForEach @(
            @{ Message = '[System.IO.File]::WriteAllText' }
            @{ Message = 'a::b' }
            @{ Message = '## [x]' }
            @{ Message = 'issue #12 [open]' }
            @{ Message = 'vso[x]' }
            @{ Message = '100% done' }
        ) {
            InModuleScope iSOCDeployments -Parameters @{ Message = $Message } { param($Message) Write-iSOCLog -Message $Message 6>&1 } |
                ForEach-Object { "$_" } | Should -BeExactly $Message
        }

        It 'breaks the commands before the GitHub escaping' {
            $env:GITHUB_ACTIONS = 'true'
            $output = InModuleScope iSOCDeployments { Write-iSOCLog -Message "50% ##vso[x]`n::y" -Level Warning 6>&1 }
            "$output" | Should -BeExactly '::warning::50%25 # #vso[x]%0A: :y'
        }
    }

    Context 'Input validation' {
        It 'rejects an unknown level' {
            { InModuleScope iSOCDeployments { Write-iSOCLog -Message 'x' -Level 'Bogus' } } | Should -Throw -ExpectedMessage '*Bogus*'
        }

        It 'accepts an empty message' {
            { InModuleScope iSOCDeployments { Write-iSOCLog -Message '' 6>$null } } | Should -Not -Throw
        }
    }
}

Describe 'Get-iSOCApiVersion' {
    It 'returns the preview alert rules version that keeps sub-techniques' {
        InModuleScope iSOCDeployments { Get-iSOCApiVersion SecurityInsightsPreview } | Should -Be '2025-07-01-preview'
    }

    It 'returns the whole table without a name' {
        $table = InModuleScope iSOCDeployments { Get-iSOCApiVersion }
        $table.Keys | Should -Contain 'SecurityInsights'
        $table.Keys | Should -Contain 'GraphSecurity'
    }

    It 'pins the versions the scripts it replaces use' {
        $table = InModuleScope iSOCDeployments { Get-iSOCApiVersion }
        $table.SecurityInsights | Should -Be '2025-09-01'
        $table.SavedSearches | Should -Be '2025-07-01'
        $table.SummaryRules | Should -Be '2025-07-01'
        $table.Workbooks | Should -Be '2022-04-01'
        $table.Deployments | Should -Be '2024-11-01'
        $table.OperationalInsights | Should -Be '2022-10-01'
    }

    It 'throws on an unknown name, listing the known ones' {
        { InModuleScope iSOCDeployments { Get-iSOCApiVersion Nope } } | Should -Throw -ExpectedMessage '*Known:*SecurityInsights*'
    }
}

Describe 'Resolve-iSOCRepoPath' {
    It 'returns an explicit repository root without a trailing separator' {
        $resolved = InModuleScope iSOCDeployments -Parameters @{ Repo = "$($script:fixtureRepo)/" } { param($Repo) Resolve-iSOCRepoPath -RepoPath $Repo }
        $resolved | Should -Be ([System.IO.Path]::GetFullPath($script:fixtureRepo))
    }

    It 'finds the root from a folder inside it' {
        Push-Location (Join-Path $script:fixtureRepo 'Content/AnalyticalRules/Identity')
        try { InModuleScope iSOCDeployments { Resolve-iSOCRepoPath } | Should -Be ([System.IO.Path]::GetFullPath($script:fixtureRepo)) }
        finally { Pop-Location }
    }

    It 'refuses an explicit folder with no Content folder' {
        { InModuleScope iSOCDeployments -Parameters @{ Repo = $TestDrive } { param($Repo) Resolve-iSOCRepoPath -RepoPath $Repo } } |
            Should -Throw -ExpectedMessage '*no Content folder*'
    }

    It 'says how to fix it when no repository is above the current folder' {
        Push-Location $TestDrive
        try { { InModuleScope iSOCDeployments { Resolve-iSOCRepoPath } } | Should -Throw -ExpectedMessage '*pass -RepoPath*' }
        finally { Pop-Location }
    }
}

Describe 'ConvertTo-iSOCRepoRelativePath' {
    It 'makes a path inside the repository relative, with forward slashes' {
        $path = Join-Path $script:fixtureRepo 'Content/AnalyticalRules/Identity/NrtRule.yaml'
        InModuleScope iSOCDeployments -Parameters @{ Path = $path; Repo = $script:fixtureRepo } { param($Path, $Repo) ConvertTo-iSOCRepoRelativePath -Path $Path -RepoPath $Repo } |
            Should -BeExactly 'Content/AnalyticalRules/Identity/NrtRule.yaml'
    }

    It 'keeps only the file name for a path outside the repository' {
        InModuleScope iSOCDeployments -Parameters @{ Path = (Join-Path $TestDrive 'elsewhere/report.md'); Repo = $script:fixtureRepo } { param($Path, $Repo) ConvertTo-iSOCRepoRelativePath -Path $Path -RepoPath $Repo } |
            Should -BeExactly 'report.md'
    }

    It 'returns a relative or empty path as given' {
        InModuleScope iSOCDeployments -Parameters @{ Repo = $script:fixtureRepo } { param($Repo) ConvertTo-iSOCRepoRelativePath -Path 'Content/x.yaml' -RepoPath $Repo } | Should -BeExactly 'Content/x.yaml'
        InModuleScope iSOCDeployments -Parameters @{ Repo = $script:fixtureRepo } { param($Repo) ConvertTo-iSOCRepoRelativePath -Path '' -RepoPath $Repo } | Should -BeNullOrEmpty
    }
}

Describe 'Get-iSOCPropertyValue' {
    It 'follows a path through objects and dictionaries alike' {
        InModuleScope iSOCDeployments {
            $value = [pscustomobject]@{ properties = @{ inner = [pscustomobject]@{ leaf = 'found' } } }
            Get-iSOCPropertyValue -InputObject $value -Path 'properties.inner.leaf' | Should -Be 'found'
        }
    }

    It 'returns nothing for a missing segment, in strict mode' {
        InModuleScope iSOCDeployments {
            Set-StrictMode -Version Latest
            Get-iSOCPropertyValue -InputObject ([pscustomobject]@{ a = 1 }) -Path 'b.c' | Should -BeNullOrEmpty
            Get-iSOCPropertyValue -InputObject @{ a = 1 } -Path 'b' | Should -BeNullOrEmpty
            Get-iSOCPropertyValue -InputObject $null -Path 'a' | Should -BeNullOrEmpty
        }
    }

    It 'returns a list as a list, even with one member' {
        InModuleScope iSOCDeployments {
            $value = Get-iSOCPropertyValue -InputObject @{ list = @('only') } -Path 'list'
            , $value | Should -BeOfType [object[]]
            $value.Count | Should -Be 1
        }
    }
}

Describe 'Context' {
    BeforeAll {
        $script:values = @{
            TenantId = 't'; SubscriptionId = '00000000-0000-0000-0000-000000000001'; ResourceGroup = 'rg'; WorkspaceName = 'ws'
            WorkspaceResourceId = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/ws'
            WorkspaceId = 'customer-id'; Region = 'uksouth'; PlaybookResourceGroup = 'rg-playbooks'; Environment = 'AzureCloud'
            IsGov = $false; ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'someone'
        }
    }

    It 'carries every value, under its type name' {
        $ctx = InModuleScope iSOCDeployments -Parameters @{ Values = $script:values } { param($Values) New-iSOCContext -Value $Values }
        $ctx.PSObject.TypeNames | Should -Contain 'iSOCDeployments.Context'
        foreach ($key in $script:values.Keys) { $ctx.$key | Should -Be $script:values[$key] }
    }

    It 'cannot be changed' {
        $ctx = InModuleScope iSOCDeployments -Parameters @{ Values = $script:values } { param($Values) New-iSOCContext -Value $Values }
        { $ctx.WorkspaceName = 'other' } | Should -Throw
        $ctx.WorkspaceName | Should -Be 'ws'
    }

    It 'needs every property' {
        $partial = $script:values.Clone()
        $partial.Remove('GraphUrl')
        { InModuleScope iSOCDeployments -Parameters @{ Values = $partial } { param($Values) New-iSOCContext -Value $Values } } |
            Should -Throw -ExpectedMessage '*GraphUrl*'
    }

    It 'is passed through by Resolve-iSOCContext, and anything else is refused' {
        InModuleScope iSOCDeployments -Parameters @{ Values = $script:values } {
            param($Values)
            $ctx = New-iSOCContext -Value $Values
            Resolve-iSOCContext -Context $ctx | Should -Be $ctx
            { Resolve-iSOCContext -Context ([pscustomobject]@{ WorkspaceName = 'x' }) } | Should -Throw -ExpectedMessage '*Connect-iSOCWorkspace*'
        }
    }

    It 'falls back to the connected context, and says to connect when there is none' {
        InModuleScope iSOCDeployments -Parameters @{ Values = $script:values } {
            param($Values)
            $saved = $script:iSOCContext
            try {
                $script:iSOCContext = $null
                { Resolve-iSOCContext } | Should -Throw -ExpectedMessage '*Run Connect-iSOCWorkspace first*'
                $script:iSOCContext = New-iSOCContext -Value $Values
                (Resolve-iSOCContext).WorkspaceName | Should -Be 'ws'
            }
            finally { $script:iSOCContext = $saved }
        }
    }

    It 'builds the request path for each scope' -ForEach @(
        @{ Scope = 'Workspace'; Expected = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/ws/c/item' }
        @{ Scope = 'ResourceGroup'; Expected = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg/c/item' }
        @{ Scope = 'PlaybookResourceGroup'; Expected = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-playbooks/c/item' }
        @{ Scope = 'Tenant'; Expected = '/c/item' }
    ) {
        InModuleScope iSOCDeployments -Parameters @{ Values = $script:values; Scope = $Scope; Expected = $Expected } {
            param($Values, $Scope, $Expected)
            $ctx = New-iSOCContext -Value $Values
            $type = [pscustomobject]@{ Name = 'Test'; Scope = $Scope; CollectionPath = '/c' }
            Get-iSOCResourcePath -Context $ctx -ContentType $type -Name 'item' | Should -BeExactly $Expected
        }
    }

    It 'refuses an unknown scope' {
        InModuleScope iSOCDeployments -Parameters @{ Values = $script:values } {
            param($Values)
            $ctx = New-iSOCContext -Value $Values
            { Get-iSOCResourcePath -Context $ctx -ContentType ([pscustomobject]@{ Name = 'Test'; Scope = 'Galaxy'; CollectionPath = '/c' }) } |
                Should -Throw -ExpectedMessage '*unknown scope*'
        }
    }
}

Describe 'Connect-iSOCWorkspace' {
    BeforeAll {
        $script:subscription = '00000000-0000-0000-0000-00000000000a'
        $script:azContext = [pscustomobject]@{
            Subscription = [pscustomobject]@{ Id = $script:subscription; Name = 'Lab'; TenantId = 'tenant-from-subscription' }
            Tenant       = [pscustomobject]@{ Id = 'tenant-1' }
            Account      = [pscustomobject]@{ Id = 'deployer@example.test' }
            Environment  = [pscustomobject]@{
                Name               = 'AzureCloud'
                ResourceManagerUrl = 'https://management.azure.com/'
                ExtendedProperties = [System.Collections.Generic.Dictionary[string, string]]::new()
            }
        }
        $script:azContext.Environment.ExtendedProperties['MicrosoftGraphUrl'] = 'https://graph.microsoft.com'
    }

    BeforeEach {
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
        Mock -ModuleName iSOCDeployments Get-iSOCAzContext { $script:azContext }
        Mock -ModuleName iSOCDeployments Set-iSOCAzContext { $script:azContext }
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
            if ($Path -like '*/workspaces/*') {
                [pscustomobject]@{ location = 'uksouth'; properties = [pscustomobject]@{ customerId = 'workspace-customer-id' } }
            }
            elseif ($Path -like '*/resourceGroups/rg-playbooks') { [pscustomobject]@{ name = 'rg-playbooks' } }
        }
    }

    AfterEach {
        InModuleScope iSOCDeployments { $script:iSOCContext = $null }
    }

    It 'says to sign in when there is no Az sign-in' {
        Mock -ModuleName iSOCDeployments Get-iSOCAzContext { $null }
        { Connect-iSOCWorkspace -ResourceGroup rg -WorkspaceName ws } | Should -Throw -ExpectedMessage '*Run Connect-AzAccount*'
    }

    It 'builds the context from the sign-in and the workspace' {
        $ctx = Connect-iSOCWorkspace -ResourceGroup rg -WorkspaceName ws
        $ctx.SubscriptionId | Should -Be $script:subscription
        $ctx.TenantId | Should -Be 'tenant-1'
        $ctx.WorkspaceResourceId | Should -BeExactly "/subscriptions/$($script:subscription)/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/ws"
        $ctx.WorkspaceId | Should -Be 'workspace-customer-id'
        $ctx.Region | Should -Be 'uksouth'
        $ctx.PlaybookResourceGroup | Should -Be 'rg'
        $ctx.Environment | Should -Be 'AzureCloud'
        $ctx.IsGov | Should -BeFalse
        $ctx.ArmUrl | Should -BeExactly 'https://management.azure.com'
        $ctx.GraphUrl | Should -BeExactly 'https://graph.microsoft.com'
        $ctx.Account | Should -Be 'deployer@example.test'
    }

    It 'reads the workspace with the Log Analytics API version' {
        Connect-iSOCWorkspace -ResourceGroup rg -WorkspaceName ws | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Invoke-iSOCRestRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Path -like '*/workspaces/ws' -and $ApiVersion -eq '2022-10-01' -and $AllowNotFound
        }
    }

    It 'becomes the connected context' {
        $ctx = Connect-iSOCWorkspace -ResourceGroup rg -WorkspaceName ws
        Get-iSOCContext | Should -Be $ctx
    }

    It 'switches subscription only when asked for another one' {
        Connect-iSOCWorkspace -ResourceGroup rg -WorkspaceName ws -SubscriptionId $script:subscription | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Set-iSOCAzContext -Times 0 -Exactly
        Connect-iSOCWorkspace -ResourceGroup rg -WorkspaceName ws -SubscriptionId '00000000-0000-0000-0000-00000000000b' | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Set-iSOCAzContext -Times 1 -Exactly -ParameterFilter { $SubscriptionId -eq '00000000-0000-0000-0000-00000000000b' }
    }

    It 'refuses a subscription that is not a GUID' {
        { Connect-iSOCWorkspace -ResourceGroup rg -WorkspaceName ws -SubscriptionId 'not-a-guid' } | Should -Throw
    }

    It 'stops when the workspace is not there' {
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { }
        { Connect-iSOCWorkspace -ResourceGroup rg -WorkspaceName missing } | Should -Throw -ExpectedMessage "*Workspace 'missing' was not found*"
        Get-iSOCContext | Should -BeNullOrEmpty
    }

    It 'checks a separate playbook resource group exists' {
        (Connect-iSOCWorkspace -ResourceGroup rg -WorkspaceName ws -PlaybookResourceGroup rg-playbooks).PlaybookResourceGroup | Should -Be 'rg-playbooks'
        { Connect-iSOCWorkspace -ResourceGroup rg -WorkspaceName ws -PlaybookResourceGroup rg-absent } | Should -Throw -ExpectedMessage "*'rg-absent' does not exist*"
    }

    It 'takes the cloud from the sign-in: <Name>' -ForEach @(
        @{ Name = 'AzureUSGovernment'; Arm = 'https://management.usgovcloudapi.net/'; Graph = 'https://graph.microsoft.us'; IsGov = $true }
        @{ Name = 'AzureChinaCloud'; Arm = 'https://management.chinacloudapi.cn/'; Graph = 'https://microsoftgraph.chinacloudapi.cn'; IsGov = $false }
    ) {
        $sovereign = [pscustomobject]@{
            Subscription = $script:azContext.Subscription
            Tenant       = $script:azContext.Tenant
            Account      = $script:azContext.Account
            Environment  = [pscustomobject]@{ Name = $Name; ResourceManagerUrl = $Arm; ExtendedProperties = @{} }
        }
        Mock -ModuleName iSOCDeployments Get-iSOCAzContext { $sovereign }
        $ctx = Connect-iSOCWorkspace -ResourceGroup rg -WorkspaceName ws
        $ctx.ArmUrl | Should -BeExactly $Arm.TrimEnd('/')
        $ctx.GraphUrl | Should -BeExactly $Graph
        $ctx.IsGov | Should -Be $IsGov
    }

    It 'logs neither the subscription id nor the workspace id' {
        Connect-iSOCWorkspace -ResourceGroup rg -WorkspaceName ws -PlaybookResourceGroup rg-playbooks | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -Times 1 -ParameterFilter { $Message -match 'Connected to workspace ws' }
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -Times 0 -Exactly -ParameterFilter {
            $Message -match [regex]::Escape($script:subscription) -or $Message -match 'workspace-customer-id'
        }
    }

    It 'checks the Connect prerequisites before anything else' {
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { throw 'missing Az.Accounts' }
        { Connect-iSOCWorkspace -ResourceGroup rg -WorkspaceName ws } | Should -Throw -ExpectedMessage 'missing Az.Accounts'
        Should -Invoke -ModuleName iSOCDeployments Get-iSOCAzContext -Times 0 -Exactly
    }
}

Describe 'Requirements' {
    It 'finds this PowerShell' {
        $result = InModuleScope iSOCDeployments { Test-iSOCRequirement -Requirement (Get-iSOCRequirement | Where-Object Kind -eq 'PowerShell' | Select-Object -First 1) }
        $result.Found | Should -BeTrue
        $result.Name | Should -Be 'PowerShell 7.2+'
    }

    It 'reports a missing module with its install hint' {
        $result = InModuleScope iSOCDeployments {
            Test-iSOCRequirement -Requirement ([pscustomobject]@{ Name = 'No.Such.Module.iSOC'; Kind = 'Module'; Step = @('Read'); Required = $true; MinimumVersion = '1.0.0'; Hint = 'Install it.' })
        }
        $result.Found | Should -BeFalse
        $result.Detail | Should -Be 'Install it.'
    }

    It 'stops a step that is missing something, naming it' {
        Mock -ModuleName iSOCDeployments Test-iSOCRequirement { [pscustomobject]@{ Name = 'powershell-yaml 0.4.12+'; Found = $false; Detail = 'Install-Module powershell-yaml' } }
        { InModuleScope iSOCDeployments { Assert-iSOCPrerequisite -Step Read } } | Should -Throw -ExpectedMessage '*powershell-yaml 0.4.12+: Install-Module powershell-yaml*'
    }

    It 'lets a step run when everything is there' {
        Mock -ModuleName iSOCDeployments Test-iSOCRequirement { [pscustomobject]@{ Name = 'x'; Found = $true; Detail = 'here' } }
        { InModuleScope iSOCDeployments { Assert-iSOCPrerequisite -Step Connect } } | Should -Not -Throw
    }
}
