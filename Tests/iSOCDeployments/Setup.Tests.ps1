#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 tests for Initialize-iSOCServicePrincipal and the Graph SDK
    wrappers.

.DESCRIPTION
    Covers:
      - The grants: Contributor, the conditioned User Access Administrator
        and its ABAC condition, the Security Administrator directory role
        and the Graph application permission.
      - The Graph SDK wrappers: a sign-in kept when it holds the scopes and
        tenant, renewed when it does not, in the right cloud; requests and
        paging.
      - The command over one stand-in tenant: every grant made, held to the
        explicit role assignments, directory role and app role assignment
        the old setup script made over the same tenant; every grant left
        when held, the skip switches, a failure reported with ExitCode 1,
        -WhatIf, a missing service principal; and the differences
        MIGRATION.md edit E34 describes, shown. Parity with that script was
        proven on release/26.11.0 before it was removed.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Setup.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Setup.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+

    The stand-in Graph client grants a sign-in only the scopes it asked
    for, as a first sign-in does; the command has not been run here
    against a tenant.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force

    $script:Sub = '11111111-2222-3333-4444-555555555555'
    $script:Tenant = '99999999-8888-7777-6666-555555555555'
    $script:AppId = 'aaaaaaaa-1111-2222-3333-444444444444'
    $script:ObjectId = 'bbbbbbbb-1111-2222-3333-444444444444'
    $script:GraphSpId = 'cccccccc-1111-2222-3333-444444444444'
    $script:AppRoleId = 'dddddddd-1111-2222-3333-444444444444'
    $script:subScope = "/subscriptions/$($script:Sub)"
    $script:setup = InModuleScope iSOCDeployments -Parameters @{ S = $script:Sub } { param($S) Get-iSOCServicePrincipalSetup -SubscriptionId $S }

    function Invoke-Private {
        param([string] $Command, [hashtable] $Arguments = @{})
        InModuleScope iSOCDeployments -Parameters @{ C = $Command; A = $Arguments } { param($C, $A) Mock Write-iSOCLog { }; & $C @A }
    }

    # The stand-in tenant: the service principal, what it holds already,
    # and what refuses.
    function Get-StandInTenant {
        param([switch] $Held, [switch] $FailEntra)
        $state = [ordered]@{
            SubscriptionId = $script:Sub; TenantId = $script:Tenant; AppId = $script:AppId; ObjectId = $script:ObjectId
            DisplayName = 'sp-sentinel-deploy'; GraphSpId = $script:GraphSpId; AppRoleId = $script:AppRoleId
            Assignments = @(); DirectoryRoles = @(); AppRoleAssignments = @(); FailEntra = [bool]$FailEntra
        }
        if ($Held) {
            $state.Assignments = @(
                [ordered]@{ Scope = $script:subScope; PrincipalId = $script:ObjectId; RoleDefinitionId = $script:setup.Contributor }
                [ordered]@{ Scope = $script:subScope; PrincipalId = $script:ObjectId; RoleDefinitionId = $script:setup.UserAccessAdministrator.RoleDefinitionId }
            )
            $state.DirectoryRoles = @([ordered]@{ PrincipalId = $script:ObjectId; RoleDefinitionId = $script:setup.SecurityAdministratorTemplateId })
            $state.AppRoleAssignments = @([ordered]@{ PrincipalId = $script:ObjectId; ResourceId = $script:GraphSpId; AppRoleId = $script:AppRoleId })
        }
        $state
    }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'The grants' {
    It 'conditions User Access Administrator to assign and remove only the five playbook roles' {
        $condition = $script:setup.UserAccessAdministrator.Condition
        $condition | Should -Match ([regex]::Escape("(!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'}))"))
        $condition | Should -Match ([regex]::Escape("(!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'}))"))
        foreach ($id in $script:setup.UserAccessAdministrator.AllowedRoles.Values) {
            ([regex]::Matches($condition, [regex]::Escape("/subscriptions/$($script:Sub)/providers/Microsoft.Authorization/roleDefinitions/$id"))).Count | Should -Be 2
        }
        @($script:setup.UserAccessAdministrator.AllowedRoles.Keys) | Should -Not -Contain 'Microsoft Sentinel Contributor'
    }

    It 'adds the condition, at version 2.0, to the assignment it creates' {
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { }
        Invoke-Private New-iSOCRoleAssignment @{ Context = [pscustomobject]@{ SubscriptionId = $script:Sub }; Scope = $script:subScope; RoleDefinitionId = 'r'; PrincipalId = 'p'; Condition = 'c' } | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Invoke-iSOCRestRequest -ParameterFilter { $Body.properties.condition -eq 'c' -and $Body.properties.conditionVersion -eq '2.0' } -Times 1 -Exactly
    }
}

Describe 'The Graph SDK wrappers' {
    It 'keeps a sign-in to the same tenant holding every scope' {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments Get-MgContext { [pscustomobject]@{ TenantId = 't1'; Scopes = @('A', 'B', 'C') } }
        Mock -ModuleName iSOCDeployments Connect-MgGraph { }
        InModuleScope iSOCDeployments { Connect-iSOCGraphSession -Scope 'A', 'B' -TenantId 't1' }
        Should -Invoke -ModuleName iSOCDeployments Connect-MgGraph -Times 0 -Exactly
    }

    It 'signs in again, with every scope, to the tenant and cloud, when a scope is missing or the tenant differs' {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Mock -ModuleName iSOCDeployments Get-MgContext { [pscustomobject]@{ TenantId = 't1'; Scopes = @('A') } }
        Mock -ModuleName iSOCDeployments Connect-MgGraph { }
        InModuleScope iSOCDeployments { Connect-iSOCGraphSession -Scope 'A', 'B' -TenantId 't1' -Environment AzureUSGovernment }
        Should -Invoke -ModuleName iSOCDeployments Connect-MgGraph -ParameterFilter { @($Scopes) -join ',' -eq 'A,B' -and $TenantId -eq 't1' -and $Environment -eq 'USGov' } -Times 1 -Exactly
        InModuleScope iSOCDeployments { Connect-iSOCGraphSession -Scope 'A' -TenantId 't2' }
        Should -Invoke -ModuleName iSOCDeployments Connect-MgGraph -ParameterFilter { $TenantId -eq 't2' -and $Environment -eq 'Global' } -Times 1 -Exactly
    }

    It 'returns every page of a collection, and the object of a POST' {
        Mock -ModuleName iSOCDeployments Invoke-MgGraphRequest {
            if ($Method -eq 'POST') { return [pscustomobject]@{ id = 'new' } }
            if ($Uri -eq 'next') { return [pscustomobject]@{ value = @([pscustomobject]@{ id = 3 }) } }
            [pscustomobject]@{ value = @([pscustomobject]@{ id = 1 }, [pscustomobject]@{ id = 2 }); '@odata.nextLink' = 'next' }
        }
        @(InModuleScope iSOCDeployments { Invoke-iSOCGraphRequest -Method GET -Uri 'v1.0/x' } | ForEach-Object { $_.id }) | Should -Be @(1, 2, 3)
        (InModuleScope iSOCDeployments { Invoke-iSOCGraphRequest -Method POST -Uri 'v1.0/x' -Body @{ a = 1 } }).id | Should -Be 'new'
        Should -Invoke -ModuleName iSOCDeployments Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'POST' -and $Body -eq '{"a":1}' -and $ContentType -eq 'application/json' } -Times 1 -Exactly
    }
}

Describe 'Initialize-iSOCServicePrincipal' {
    BeforeAll {
        function Invoke-ModuleSetup {
            param([hashtable] $Tenant, [hashtable] $Parameters = @{})
            $script:tenantState = $Tenant
            $script:moduleWrites = [System.Collections.Generic.List[object]]::new()
            $script:graphScopes = @()
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
            Mock -ModuleName iSOCDeployments Get-iSOCAzSession { @{ TenantId = $script:Tenant; SubscriptionId = $script:Sub; Account = 'tester'; Environment = 'AzureCloud'; IsGov = $false; ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com' } }
            Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
                $t = $script:tenantState
                if ($Api -eq 'Graph') { if ($Path -match [regex]::Escape([Uri]::EscapeDataString("appId eq '$($t.AppId)'"))) { return [pscustomobject]@{ id = $t.ObjectId; displayName = $t.DisplayName } } else { return } }
                if ($Method -eq 'GET') {
                    $scope = ($Path -split '/providers/Microsoft.Authorization/')[0]
                    return @($t.Assignments | Where-Object { $scope -eq $_.Scope -or $scope.StartsWith("$($_.Scope)/") } | ForEach-Object { [pscustomobject]@{ id = 'a'; name = 'a'; properties = [pscustomobject]@{ scope = $_.Scope; principalId = $_.PrincipalId; roleDefinitionId = "/subscriptions/$($t.SubscriptionId)/providers/Microsoft.Authorization/roleDefinitions/$($_.RoleDefinitionId)" } } })
                }
                $script:moduleWrites.Add([pscustomobject]@{ Kind = 'Rbac'; PrincipalId = $Body.properties.principalId; RoleDefinitionId = ($Body.properties.roleDefinitionId -split '/')[-1]; Scope = ($Path -split '/providers/Microsoft.Authorization/')[0]; Condition = $Body.properties.condition; ConditionVersion = $Body.properties.conditionVersion })
            }
            Mock -ModuleName iSOCDeployments Connect-iSOCGraphSession { $script:graphScopes = @($Scope); $script:moduleWrites.Add([pscustomobject]@{ Kind = 'SignIn'; Scopes = @($Scope); TenantId = $TenantId }) }
            Mock -ModuleName iSOCDeployments Invoke-iSOCGraphRequest {
                $t = $script:tenantState
                $query = [Uri]::UnescapeDataString($Uri)
                if ($Method -eq 'GET' -and $query -like 'v1.0/roleManagement/directory/roleAssignments?*') { return @($t.DirectoryRoles | Where-Object { $query -like "*principalId eq '$($_.PrincipalId)' and roleDefinitionId eq '$($_.RoleDefinitionId)'*" } | ForEach-Object { [pscustomobject]@{ id = 'x' } }) }
                if ($Method -eq 'GET' -and $query -like "v1.0/servicePrincipals?*00000003-0000-0000-c000-000000000000*") { return [pscustomobject]@{ id = $t.GraphSpId; appRoles = @([pscustomobject]@{ value = 'User.Read.All'; id = 'other' }, [pscustomobject]@{ value = 'CustomDetection.ReadWrite.All'; id = $t.AppRoleId }) } }
                if ($Method -eq 'GET' -and $query -eq "v1.0/servicePrincipals/$($t.ObjectId)/appRoleAssignments") { return @($t.AppRoleAssignments | ForEach-Object { [pscustomobject]@{ appRoleId = $_.AppRoleId; resourceId = $_.ResourceId } }) }
                if ($Method -eq 'POST' -and $query -eq 'v1.0/roleManagement/directory/roleAssignments') {
                    if ($script:graphScopes -notcontains 'RoleManagement.ReadWrite.Directory') { throw 'Insufficient privileges' }
                    if ($t.FailEntra) { throw 'Insufficient privileges to complete the operation.' }
                    $script:moduleWrites.Add([pscustomobject]@{ Kind = 'DirectoryRole'; PrincipalId = $Body.principalId; RoleDefinitionId = $Body.roleDefinitionId; DirectoryScopeId = $Body.directoryScopeId }); return
                }
                if ($Method -eq 'POST' -and $query -eq "v1.0/servicePrincipals/$($t.GraphSpId)/appRoleAssignedTo") {
                    if ($script:graphScopes -notcontains 'AppRoleAssignment.ReadWrite.All') { throw 'Insufficient privileges' }
                    $script:moduleWrites.Add([pscustomobject]@{ Kind = 'AppRole'; PrincipalId = $Body.principalId; ResourceId = $Body.resourceId; AppRoleId = $Body.appRoleId }); return
                }
                throw "unexpected $Method $Uri"
            }
            Initialize-iSOCServicePrincipal -ServicePrincipalAppId $script:AppId -Confirm:$false @Parameters
        }

        $script:writeKey = {
            param($Write)
            switch ($Write.Kind) {
                'Rbac' { "Rbac $($Write.PrincipalId) $($Write.RoleDefinitionId) $($Write.Scope) $($Write.Condition) $($Write.ConditionVersion)" }
                'DirectoryRole' { "DirectoryRole $($Write.PrincipalId) $($Write.RoleDefinitionId) $($Write.DirectoryScopeId)" }
                'AppRole' { "AppRole $($Write.PrincipalId) $($Write.ResourceId) $($Write.AppRoleId)" }
            }
        }
        function Get-WriteKey { param($Writes, [string[]] $Kind) @($Writes | Where-Object { $_.Kind -in $Kind } | ForEach-Object { & $script:writeKey $_ } | Sort-Object) }

        # The grants Setup-ServicePrincipal.ps1 made over this stand-in tenant
        # on release/26.11.0, with the role definition GUIDs and the condition
        # written out so they do not come from the module: Contributor and the
        # conditioned User Access Administrator on the subscription, Security
        # Administrator in Entra ID, and CustomDetection.ReadWrite.All on
        # Microsoft Graph.
        $allowed = @('3e150937-b8fe-4cfb-8069-0eaf05ecd056', '8d289c81-5878-46d4-8554-54e1e3d8b5cb', '73c42c96-874c-492b-b04d-ab87d138a893', '87a39d53-fc1b-424a-814c-f7e04687dc9e', 'f1a07417-d97a-45cb-824c-7a7467783830') |
            ForEach-Object { "(@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] StringEquals '/subscriptions/$($script:Sub)/providers/Microsoft.Authorization/roleDefinitions/$_')" }
        $allowed = $allowed -join ' OR '
        $condition = "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR ($allowed)) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR ($allowed))"
        $script:expectedRbac = @(
            [pscustomobject]@{ Kind = 'Rbac'; PrincipalId = $script:ObjectId; RoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'; Scope = $script:subScope; Condition = $null; ConditionVersion = $null }
            [pscustomobject]@{ Kind = 'Rbac'; PrincipalId = $script:ObjectId; RoleDefinitionId = '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'; Scope = $script:subScope; Condition = $condition; ConditionVersion = '2.0' }
        )
        $script:expectedDirectoryRole = [pscustomobject]@{ Kind = 'DirectoryRole'; PrincipalId = $script:ObjectId; RoleDefinitionId = '194ae4cb-b126-40b2-bd5b-6091b380977d'; DirectoryScopeId = '/' }
        $script:expectedAppRole = [pscustomobject]@{ Kind = 'AppRole'; PrincipalId = $script:ObjectId; ResourceId = $script:GraphSpId; AppRoleId = $script:AppRoleId }
    }

    It 'makes the Azure role assignments and directory role assignment the old setup script made on a fresh tenant' {
        $run = Invoke-ModuleSetup -Tenant (Get-StandInTenant)
        Get-WriteKey $script:moduleWrites 'Rbac', 'DirectoryRole' | Should -Be (Get-WriteKey (@($script:expectedRbac) + $script:expectedDirectoryRole) 'Rbac', 'DirectoryRole')
        $run.Assigned | Should -Be 4
        $run.ExitCode | Should -Be 0
    }

    It 'grants the Graph permission, which the script could not do after the directory role: it kept that sign-in, without the scope (MIGRATION.md edit E34)' {
        Invoke-ModuleSetup -Tenant (Get-StandInTenant) | Out-Null
        Get-WriteKey $script:moduleWrites 'AppRole' | Should -Be (Get-WriteKey $script:expectedAppRole 'AppRole')
        $signIn = @($script:moduleWrites | Where-Object Kind -EQ 'SignIn')
        $signIn.Count | Should -Be 1
        @($signIn[0].Scopes) | Should -Be @('RoleManagement.ReadWrite.Directory', 'AppRoleAssignment.ReadWrite.All', 'Application.Read.All')
        $signIn[0].TenantId | Should -Be $script:Tenant
    }

    It 'leaves alone every grant the service principal holds' {
        $run = Invoke-ModuleSetup -Tenant (Get-StandInTenant -Held)
        @($script:moduleWrites | Where-Object { $_.Kind -ne 'SignIn' }).Count | Should -Be 0
        $run.Unchanged | Should -Be 4
    }

    It 'leaves out the directory role and the Graph permission when skipped, and never signs in to Graph' {
        $skip = @{ SkipEntraRole = $true; SkipGraphPermission = $true }
        $run = Invoke-ModuleSetup -Tenant (Get-StandInTenant) -Parameters $skip
        @($script:moduleWrites | Where-Object { $_.Kind -in 'SignIn', 'DirectoryRole', 'AppRole' }).Count | Should -Be 0
        Get-WriteKey $script:moduleWrites 'Rbac' | Should -Be (Get-WriteKey $script:expectedRbac 'Rbac')
        @($run.Results | Where-Object Outcome -EQ 'Skipped' | ForEach-Object { $_.Role }) | Should -Be @('Security Administrator (Entra ID)', 'CustomDetection.ReadWrite.All (Graph)')
    }

    It 'reports a refused directory role and fails the run, where the script ended with exit code 0 (MIGRATION.md edit E34)' {
        $run = Invoke-ModuleSetup -Tenant (Get-StandInTenant -FailEntra) -Parameters @{ SkipGraphPermission = $true }
        ($run.Results | Where-Object Role -EQ 'Security Administrator (Entra ID)').Outcome | Should -Be 'Failed'
        $run.ExitCode | Should -Be 1
    }

    It 'grants nothing with -WhatIf, and asks before each grant (MIGRATION.md edit E34)' {
        $run = Invoke-ModuleSetup -Tenant (Get-StandInTenant) -Parameters @{ WhatIf = $true }
        @($script:moduleWrites | Where-Object { $_.Kind -ne 'SignIn' }).Count | Should -Be 0
        $run.WhatIf | Should -Be 4
        $binding = (Get-Command Initialize-iSOCServicePrincipal).ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
        $binding.ConfirmImpact | Should -Be 'High'
    }

    It 'stops when the service principal does not exist' {
        $tenant = Get-StandInTenant
        $tenant.AppId = 'eeeeeeee-1111-2222-3333-444444444444'
        { Invoke-ModuleSetup -Tenant $tenant } | Should -Throw "*Application ID '$($script:AppId)' not found*"
    }
}
