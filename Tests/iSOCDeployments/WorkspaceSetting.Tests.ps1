#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the workspace setting content type.

.DESCRIPTION
    The handlers on their own: every file under Content/WorkspaceSettings/
    validates, each way a file can be wrong is reported, the request is the
    file's kind and properties, and the Deploy handler sends the
    workspace's etag and skips a setting it is not allowed to change.

    Then Deploy-iSOCContent -ContentType WorkspaceSetting over the
    repository's files, against one stand-in workspace
    (_helpers/WorkspaceStandIn.psm1), for a new workspace, one with every
    setting, an identity without the directory role and a setting the
    service rejects. Parity with the inline Configure Sentinel Settings steps
    it replaced (.github/workflows/sentinel-deploy.yml and
    Pipelines/Sentinel-Deploy.yml, MIGRATION.md edit E43) was proven before
    each step was replaced by the module, and both pipelines now deploy the
    settings with Deploy-iSOCWorkspace -Stage WorkspaceSettings.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/WorkspaceSetting.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/WorkspaceSetting.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.2.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:files = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Content/WorkspaceSettings') -Filter '*.json' -File | ForEach-Object { @{ File = $_.Name; Path = $_.FullName } })
    $cases = @(
        @{ Case = 'a new workspace'; State = @{}; Denied = @(); Failing = @() }
        @{ Case = 'a workspace with every setting'; State = @{ Settings = @{ Anomalies = 'W/"a-1"'; EyesOn = 'W/"e-1"'; EntityAnalytics = 'W/"ea-1"'; Ueba = 'W/"u-1"' } }; Denied = @(); Failing = @() }
        @{ Case = 'an identity without the directory role'; State = @{ Settings = @{ Ueba = 'W/"u-1"' }; Denied = @('Ueba', 'EntityAnalytics') }; Denied = @('Ueba', 'EntityAnalytics'); Failing = @() }
        @{ Case = 'a setting the service rejects'; State = @{ Failing = @('EyesOn') }; Denied = @(); Failing = @('EyesOn') }
    )
    $script:runs = $cases
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    $script:standInModule = Join-Path $PSScriptRoot '_helpers/WorkspaceStandIn.psm1'
    Import-Module $script:standInModule -Force
    $script:subscription = (Get-WorkspaceStandIn).SubscriptionId
    $script:workspacePath = "/subscriptions/$script:subscription/resourceGroups/rg-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-sentinel"
    $script:context = InModuleScope iSOCDeployments -Parameters @{ S = $script:subscription; W = $script:workspacePath } {
        param($S, $W)
        New-iSOCContext -Value @{
            TenantId = 'tenant-1'; SubscriptionId = $S; ResourceGroup = 'rg-sentinel'; WorkspaceName = 'law-sentinel'
            WorkspaceResourceId = $W; WorkspaceId = 'cccccccc-0000-0000-0000-000000000001'; Region = 'uksouth'; PlaybookResourceGroup = 'rg-sentinel'
            Environment = 'AzureCloud'; IsGov = $false; ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'deployer@example.test'
        }
    }

    function Get-SettingRepo {
        <#
        .SYNOPSIS
            A copy of the repository's workspace settings, so deploy writes its state file outside the repository.
        #>
        $copy = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path (Join-Path $copy 'Content') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'Content/WorkspaceSettings') -Destination (Join-Path $copy 'Content') -Recurse
        $copy
    }

    function Get-SettingItem {
        <#
        .SYNOPSIS
            A repository item for one setting written as $Text.
        .PARAMETER Text
            The text of the setting file.
        .PARAMETER Name
            The file name of the setting.
        #>
        param([string] $Text, [string] $Name = 'Setting.json')
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path (Join-Path $repo 'Content/WorkspaceSettings') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo "Content/WorkspaceSettings/$Name") -Value $Text
        InModuleScope iSOCDeployments -Parameters @{ R = $repo } {
            param($R)
            $type = Get-iSOCContentTypeDefinition -Name WorkspaceSetting
            Read-iSOCWorkspaceSettingRepo -RepoPath $R -ContentType $type
        }
    }

    function Invoke-ModuleSettingDeploy {
        <#
        .SYNOPSIS
            Deploy the repository's workspace settings with Deploy-iSOCContent over $State; -Preview runs it under -WhatIf.
        .PARAMETER State
            The stand-in state the deploy runs over.
        .PARAMETER Preview
            Runs the deploy under WhatIf.
        #>
        param($State, [switch] $Preview)

        $script:standIn = $State
        $script:logs = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
        Mock -ModuleName iSOCDeployments Start-Sleep { }
        Mock -ModuleName iSOCDeployments Write-iSOCLog { $script:logs.Add([pscustomobject]@{ Message = $Message; Level = $Level }) }
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
            $answer = Invoke-WorkspaceStandInArm -State $script:standIn -Method $Method -Path $Path -Body $Body
            if ($Method -eq 'PUT') { @($script:standIn.Writes)[-1].ApiVersion = $ApiVersion }
            if ($answer.Status -eq 404 -and $AllowNotFound) { return }
            if ($answer.Status -ge 400) {
                $exception = [System.Net.Http.HttpRequestException]::new("HTTP $($answer.Status) from $Method settings/$(($Path -split '/')[-1]): $($answer.Body.error.message)", $null, [System.Net.HttpStatusCode]$answer.Status)
                throw [System.Management.Automation.ErrorRecord]::new($exception, "iSOCRest.Http$($answer.Status)", 'InvalidOperation', $Path)
            }
            $answer.Body | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        }
        $run = Deploy-iSOCContent -ContentType WorkspaceSetting -Context $script:context -RepoPath (Get-SettingRepo) -WhatIf:$Preview
        [pscustomobject]@{ Run = $run; Logs = $script:logs.ToArray(); State = $script:standIn }
    }

}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
    Remove-Module WorkspaceStandIn -ErrorAction SilentlyContinue
}

Describe 'The repository''s workspace setting <File>' -ForEach $script:files {
    It 'validates and names the setting after its kind' {
        $item = @(Get-SettingItem -Text (Get-Content -LiteralPath $Path -Raw) -Name $File)
        $item.Count | Should -Be 1
        @(InModuleScope iSOCDeployments -Parameters @{ I = $item[0] } { param($I) Test-iSOCWorkspaceSetting -Item $I }) | Should -BeNullOrEmpty
        $item[0].Data.name | Should -BeExactly ([System.IO.Path]::GetFileNameWithoutExtension($File))
    }
}

Describe 'Test-iSOCWorkspaceSetting' {
    It 'passes <Case>' -ForEach @(
        @{ Case = 'anomalies with no properties'; Text = '{ "name": "Anomalies", "kind": "Anomalies" }' }
        @{ Case = 'EyesOn with empty properties'; Text = '{ "name": "EyesOn", "kind": "EyesOn", "properties": {} }' }
        @{ Case = 'Entity Analytics with both providers'; Text = '{ "name": "EntityAnalytics", "kind": "EntityAnalytics", "properties": { "entityProviders": ["AzureActiveDirectory", "ActiveDirectory"] } }' }
        @{ Case = 'UEBA with one source'; Text = '{ "name": "Ueba", "kind": "Ueba", "properties": { "dataSources": ["SigninLogs"] } }' }
    ) {
        $item = Get-SettingItem -Text $Text
        @(InModuleScope iSOCDeployments -Parameters @{ I = $item } { param($I) Test-iSOCWorkspaceSetting -Item $I }) | Should -BeNullOrEmpty
    }

    It 'reports <Case>' -ForEach @(
        @{ Case = 'a file that does not parse'; Text = '{ "name": '; Message = 'the JSON does not parse*' }
        @{ Case = 'a list rather than a setting'; Text = '[ { "name": "Ueba", "kind": "Ueba" }, { "name": "EyesOn", "kind": "EyesOn" } ]'; Message = 'the file does not hold one setting object.' }
        @{ Case = 'no kind'; Text = '{ "name": "Ueba" }'; Message = 'missing required field kind.' }
        @{ Case = 'a kind Sentinel does not have'; Text = '{ "name": "Fusion", "kind": "Fusion" }'; Message = "kind 'Fusion' is not one of Anomalies, EntityAnalytics, EyesOn, Ueba." }
        @{ Case = 'a kind in the wrong case'; Text = '{ "name": "ueba", "kind": "ueba" }'; Message = "kind 'ueba' is not one of*" }
        @{ Case = 'no name'; Text = '{ "kind": "EyesOn" }'; Message = 'missing required field name.' }
        @{ Case = 'a name that is not its kind'; Text = '{ "name": "MyUeba", "kind": "Ueba", "properties": { "dataSources": ["SigninLogs"] } }'; Message = "name 'MyUeba' is not its kind 'Ueba'*" }
        @{ Case = 'properties that are not an object'; Text = '{ "name": "EyesOn", "kind": "EyesOn", "properties": [] }'; Message = 'properties is not an object.' }
        @{ Case = 'Entity Analytics without providers'; Text = '{ "name": "EntityAnalytics", "kind": "EntityAnalytics", "properties": {} }'; Message = 'missing required field properties.entityProviders.' }
        @{ Case = 'UEBA without properties'; Text = '{ "name": "Ueba", "kind": "Ueba" }'; Message = 'missing required field properties.dataSources.' }
        @{ Case = 'sources as one string'; Text = '{ "name": "Ueba", "kind": "Ueba", "properties": { "dataSources": "SigninLogs" } }'; Message = 'properties.dataSources is not a list of names.' }
        @{ Case = 'an empty source list'; Text = '{ "name": "Ueba", "kind": "Ueba", "properties": { "dataSources": [] } }'; Message = 'properties.dataSources is not a list of names.' }
        @{ Case = 'a blank provider'; Text = '{ "name": "EntityAnalytics", "kind": "EntityAnalytics", "properties": { "entityProviders": ["AzureActiveDirectory", " "] } }'; Message = 'properties.entityProviders is not a list of names.' }
        @{ Case = 'a provider that is not a name'; Text = '{ "name": "EntityAnalytics", "kind": "EntityAnalytics", "properties": { "entityProviders": [1] } }'; Message = 'properties.entityProviders is not a list of names.' }
    ) {
        $item = Get-SettingItem -Text $Text
        $issues = @(InModuleScope iSOCDeployments -Parameters @{ I = $item } { param($I) Test-iSOCWorkspaceSetting -Item $I })
        $issues.Count | Should -Be 1
        $issues[0] | Should -BeLike $Message
    }
}

Describe 'ConvertTo-iSOCWorkspaceSettingRequest' {
    It 'sends the kind and the file''s properties, named by the setting' {
        $item = Get-SettingItem -Text '{ "name": "Ueba", "kind": "Ueba", "properties": { "dataSources": ["SigninLogs", "AuditLogs"], "futureFlag": true } }'
        $request = InModuleScope iSOCDeployments -Parameters @{ I = $item } { param($I) ConvertTo-iSOCWorkspaceSettingRequest -Item $I }
        $request.PSObject.TypeNames | Should -Contain 'iSOCDeployments.Request'
        $request.ResourceName | Should -Be 'Ueba'
        $request.Identity | Should -Be 'ueba'
        ConvertTo-Json $request.Body -Depth 5 -Compress | Should -Be '{"kind":"Ueba","properties":{"dataSources":["SigninLogs","AuditLogs"],"futureFlag":true}}'
    }

    It 'sends empty properties for a setting that has none' {
        $item = Get-SettingItem -Text '{ "name": "Anomalies", "kind": "Anomalies" }'
        $request = InModuleScope iSOCDeployments -Parameters @{ I = $item } { param($I) ConvertTo-iSOCWorkspaceSettingRequest -Item $I }
        ConvertTo-Json $request.Body -Depth 5 -Compress | Should -Be '{"kind":"Anomalies","properties":{}}'
    }
}

Describe 'Invoke-iSOCWorkspaceSettingDeploy' {
    BeforeAll {
        $script:item = Get-SettingItem -Text '{ "name": "Ueba", "kind": "Ueba", "properties": { "dataSources": ["SigninLogs"] } }' -Name 'Ueba.json'
        $script:anomalies = Get-SettingItem -Text '{ "name": "Anomalies", "kind": "Anomalies" }' -Name 'Anomalies.json'
        $script:runObject = [pscustomobject]@{ Context = $script:context }
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
    }

    It 'sends the etag the workspace has for the setting' {
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { if ($Method -eq 'GET') { [pscustomobject]@{ name = 'Ueba'; etag = 'W/"7"' } } }
        $sent = InModuleScope iSOCDeployments -Parameters @{ R = $script:runObject; I = $script:item } { param($R, $I) Invoke-iSOCWorkspaceSettingDeploy -Run $R -ContentType (Get-iSOCContentTypeDefinition -Name WorkspaceSetting) -Item $I }
        $sent.Outcome | Should -Be 'Deployed'
        Should -Invoke -ModuleName iSOCDeployments Invoke-iSOCRestRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Path -eq "$script:workspacePath/providers/Microsoft.SecurityInsights/settings/Ueba" -and $ApiVersion -eq '2025-07-01-preview' -and
            (ConvertTo-Json $Body -Depth 5 -Compress) -eq '{"kind":"Ueba","etag":"W/\"7\"","properties":{"dataSources":["SigninLogs"]}}'
        }
    }

    It 'creates a setting the workspace does not have, with no etag' {
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { }
        InModuleScope iSOCDeployments -Parameters @{ R = $script:runObject; I = $script:item } { param($R, $I) Invoke-iSOCWorkspaceSettingDeploy -Run $R -ContentType (Get-iSOCContentTypeDefinition -Name WorkspaceSetting) -Item $I } | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Invoke-iSOCRestRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'GET' -and $AllowNotFound }
        Should -Invoke -ModuleName iSOCDeployments Invoke-iSOCRestRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PUT' -and -not $Body.Contains('etag') }
    }

    It 'skips a <Kind> setting it is refused with <Status>, saying what is needed' -ForEach @(
        @{ Kind = 'UEBA'; Status = 403; Item = 'item'; Reason = '*Security Administrator directory role*' }
        @{ Kind = 'UEBA'; Status = 401; Item = 'item'; Reason = '*Security Administrator directory role*' }
        @{ Kind = 'anomalies'; Status = 403; Item = 'anomalies'; Reason = '*Microsoft Sentinel Contributor*' }
    ) {
        $script:status = $Status
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
            if ($Method -eq 'GET') { return }
            $exception = [System.Net.Http.HttpRequestException]::new("HTTP $script:status from PUT settings", $null, [System.Net.HttpStatusCode]$script:status)
            throw [System.Management.Automation.ErrorRecord]::new($exception, 'iSOCRest.Http', 'InvalidOperation', $Path)
        }
        $target = Get-Variable -Name $Item -Scope Script -ValueOnly
        $sent = InModuleScope iSOCDeployments -Parameters @{ R = $script:runObject; I = $target } { param($R, $I) Invoke-iSOCWorkspaceSettingDeploy -Run $R -ContentType (Get-iSOCContentTypeDefinition -Name WorkspaceSetting) -Item $I }
        $sent.Outcome | Should -Be 'Skipped'
        $sent.Reason | Should -BeLike $Reason
        Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warning' -and $Message -like "Skipping 'Content/WorkspaceSettings/*': not authorised*" }
    }

    It 'throws any other failure, for deploy to fail the item' {
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
            if ($Method -eq 'GET') { return }
            $exception = [System.Net.Http.HttpRequestException]::new('HTTP 400 from PUT settings/Ueba: bad', $null, [System.Net.HttpStatusCode]400)
            throw [System.Management.Automation.ErrorRecord]::new($exception, 'iSOCRest.Http400', 'InvalidOperation', $Path)
        }
        { InModuleScope iSOCDeployments -Parameters @{ R = $script:runObject; I = $script:item } { param($R, $I) Invoke-iSOCWorkspaceSettingDeploy -Run $R -ContentType (Get-iSOCContentTypeDefinition -Name WorkspaceSetting) -Item $I } } |
            Should -Throw 'HTTP 400 from PUT settings/Ueba: bad'
    }

    It 'reads and sends nothing under -WhatIf' {
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { }
        $sent = InModuleScope iSOCDeployments -Parameters @{ R = $script:runObject; I = $script:item } { param($R, $I) Invoke-iSOCWorkspaceSettingDeploy -Run $R -ContentType (Get-iSOCContentTypeDefinition -Name WorkspaceSetting) -Item $I -WhatIf }
        $sent.Outcome | Should -Be 'WhatIf'
        Should -Invoke -ModuleName iSOCDeployments Invoke-iSOCRestRequest -Times 0 -Exactly
    }
}

Describe 'Deploy-iSOCContent -ContentType WorkspaceSetting over a stand-in workspace: <Case>' -ForEach $script:runs {
    BeforeAll {
        $script:new = Invoke-ModuleSettingDeploy -State (Get-WorkspaceStandIn @State)
        $script:newWrites = @($script:new.State.Writes)
    }

    It 'writes each of the four settings once' {
        $script:newWrites.Count | Should -Be 4
        @($script:newWrites | ForEach-Object { $_.Name } | Sort-Object -Unique).Count | Should -Be 4
    }

    It 'deploys what it can, and skips or fails the rest' {
        $results = @($script:new.Run.Results)
        $names = @($script:newWrites | ForEach-Object { $_.Name })
        $expected = @($names | Where-Object { $_ -notin $Denied -and $_ -notin $Failing } | Sort-Object)
        @($results | Where-Object Outcome -EQ 'Deployed' | ForEach-Object { $_.Name } | Sort-Object) | Should -Be $expected
        @($results | Where-Object Outcome -EQ 'Skipped' | ForEach-Object { $_.Name } | Sort-Object) | Should -Be @($Denied | Sort-Object)
        @($results | Where-Object Outcome -EQ 'Failed' | ForEach-Object { $_.Name } | Sort-Object) | Should -Be @($Failing | Sort-Object)
    }

    It 'fails the run only for a rejected setting' {
        $script:new.Run.ExitCode | Should -Be $(if ($Failing.Count) { 1 } else { 0 })
    }

    It 'sends at 2025-07-01-preview' {
        foreach ($new in $script:newWrites) { $new.ApiVersion | Should -Be '2025-07-01-preview' }
    }

    It 'logs nothing that names the subscription' {
        @($script:new.Logs | Where-Object { $_.Message -like "*$script:subscription*" }) | Should -BeNullOrEmpty
    }
}

Describe 'Deploy-iSOCContent -ContentType WorkspaceSetting' {
    It 'reads and writes nothing under -WhatIf' {
        $run = Invoke-ModuleSettingDeploy -State (Get-WorkspaceStandIn) -Preview
        @($run.State.Reads) | Should -BeNullOrEmpty
        @($run.State.Writes) | Should -BeNullOrEmpty
        @($run.Run.Results | Where-Object Outcome -EQ 'WhatIf').Count | Should -Be 4
    }

    It 'deploys before every other content type' {
        $types = @(InModuleScope iSOCDeployments { Get-iSOCContentTypeRegistry })
        $types[0].Name | Should -Be 'WorkspaceSetting'
    }
}
