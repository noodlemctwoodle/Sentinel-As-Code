#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 tests for Grant-iSOCPlaybookPermission,
    Grant-iSOCRunbookPermission, Revoke-iSOCRunbookPermission and the role
    assignment helpers.

.DESCRIPTION
    Covers:
      - The playbook role analysis, with the cases of
        Tests/Test-SetPlaybookPermissions.Tests.ps1 carried over (connectors,
        the Contributor upgrade, HTTP audiences, scopes) and the PUT pattern
        that no longer upgrades a workflow that only reads.
      - Role assignments over REST: reading them, finding one that applies
        at a scope or above it, creating one under a stable name (a 409 is
        Exists), deleting one, and managed identity principals.
      - The commands over one stand-in tenant: the role assignments
        attempted, created and removed, and the counts, held to the
        explicit values the old permission scripts produced over the same
        tenant; and the differences MIGRATION.md edits E32 and E33
        describe, shown. Parity with those scripts was proven on
        release/26.11.0 before they were removed.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Permissions.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Permissions.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+

    The stand-in shapes objects as the ARM REST API returns them; the
    commands have not been run here against a tenant.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force

    $script:Sub = '11111111-2222-3333-4444-555555555555'
    $script:subScope = "/subscriptions/$($script:Sub)"
    $script:rgScope = "$($script:subScope)/resourceGroups/rg-sentinel"
    $script:kvScope = "$($script:rgScope)/providers/Microsoft.KeyVault/vaults/kv-lab"
    $script:context = InModuleScope iSOCDeployments -Parameters @{ S = $script:Sub } {
        param($S)
        New-iSOCContext -Value @{
            TenantId = 't'; SubscriptionId = $S; ResourceGroup = 'rg-sentinel'; WorkspaceName = 'law-lab'
            WorkspaceResourceId = "/subscriptions/$S/resourceGroups/rg-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-lab"
            WorkspaceId = 'w'; Region = 'uksouth'; PlaybookResourceGroup = 'rg-automation'; Environment = 'AzureCloud'
            IsGov = $false; ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'a'
        }
    }
    $script:roleIds = InModuleScope iSOCDeployments { Get-iSOCRoleDefinitionId }

    function Invoke-Private {
        param([string] $Command, [hashtable] $Arguments = @{})
        InModuleScope iSOCDeployments -Parameters @{ C = $Command; A = $Arguments } { param($C, $A) Mock Write-iSOCLog { }; & $C @A }
    }

    function New-Workflow {
        param([string[]] $Connector = @(), [System.Collections.IDictionary] $Actions = @{})
        $connections = [ordered]@{}
        foreach ($api in $Connector) { $connections[$api] = @{ id = "/subscriptions/x/providers/Microsoft.Web/locations/uksouth/managedApis/$api"; connectionId = 'c' } }
        $properties = [ordered]@{ state = 'Enabled'; definition = [ordered]@{ triggers = @{}; actions = $Actions } }
        if ($connections.Count -gt 0) { $properties.parameters = @{ '$connections' = @{ value = $connections } } }
        $properties | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
    }
    function Get-Roles { param($Properties) Invoke-Private Get-iSOCPlaybookRequiredRole @{ Properties = $Properties } }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Playbook role analysis (carried over from Test-SetPlaybookPermissions.Tests.ps1)' {
    It 'maps the <Api> connector to <Role> at the <Scope> scope' -ForEach @(
        @{ Api = 'azuresentinel'; Role = 'Microsoft Sentinel Responder'; Scope = 'rg' }
        @{ Api = 'microsoftsentinel'; Role = 'Microsoft Sentinel Responder'; Scope = 'rg' }
        @{ Api = 'keyvault'; Role = 'Key Vault Secrets User'; Scope = 'keyvault' }
        @{ Api = 'azuremonitorlogs'; Role = 'Log Analytics Reader'; Scope = 'rg' }
        @{ Api = 'azureloganalyticsdatacollector'; Role = 'Log Analytics Reader'; Scope = 'rg' }
    ) {
        $roles = Get-Roles (New-Workflow -Connector $Api)
        @($roles.Keys) | Should -Be @($Role)
        $roles[$Role] | Should -Be $Scope
    }

    It 'needs nothing for a connector it does not know, or a workflow with no connections' {
        (Get-Roles (New-Workflow -Connector 'somethingexotic')).Count | Should -Be 0
        (Get-Roles (New-Workflow)).Count | Should -Be 0
    }

    It 'upgrades Responder to Contributor for <Case>' -ForEach @(
        @{ Case = 'an /Incidents path'; Actions = @{ Update = @{ type = 'Http'; inputs = @{ uri = 'https://management.azure.com/Incidents' } } } }
        @{ Case = 'an Update_incident action'; Actions = @{ Update_incident = @{ type = 'ApiConnection' } } }
        @{ Case = 'a PUT request'; Actions = @{ Put = @{ type = 'Http'; inputs = @{ method = 'PUT'; uri = 'https://example.invalid/x' } } } }
    ) {
        $roles = Get-Roles (New-Workflow -Connector 'azuresentinel' -Actions $Actions)
        @($roles.Keys) | Should -Be @('Microsoft Sentinel Contributor')
    }

    It 'adds Contributor for a /Watchlists write without the Sentinel connector' {
        @((Get-Roles (New-Workflow -Actions @{ Put = @{ type = 'Http'; inputs = @{ uri = 'https://management.azure.com/Watchlists' } } })).Keys) | Should -Be @('Microsoft Sentinel Contributor')
    }

    It 'leaves a workflow that only reads at Responder, whatever its inputs and outputs say' {
        $roles = Get-Roles (New-Workflow -Connector 'azuresentinel' -Actions @{ Get = @{ type = 'Http'; inputs = @{ method = 'GET'; uri = 'https://graph.microsoft.com/v1.0/users' }; runAfter = @{}; outputs = 'x' } })
        @($roles.Keys) | Should -Be @('Microsoft Sentinel Responder')
    }

    It 'maps the <Audience> audience to <Expected>' -ForEach @(
        @{ Audience = 'https://management.azure.com'; Expected = @('Microsoft Sentinel Contributor') }
        @{ Audience = 'https://api.loganalytics.io'; Expected = @('Log Analytics Reader') }
        @{ Audience = 'https://graph.microsoft.com'; Expected = @() }
        @{ Audience = 'https://api.securitycenter.microsoft.com'; Expected = @() }
    ) {
        $roles = Get-Roles (New-Workflow -Actions @{ Call = @{ type = 'Http'; inputs = @{ method = 'GET'; authentication = @{ type = 'ManagedServiceIdentity'; audience = $Audience } } } })
        @($roles.Keys) | Should -Be $Expected
    }

    It 'resolves <Type> to its scope' -ForEach @(
        @{ Type = 'rg'; Expected = '/subscriptions/sub1/resourceGroups/rg-test' }
        @{ Type = 'workspace'; Expected = '/subscriptions/sub1/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test' }
        @{ Type = 'keyvault'; Expected = '/subscriptions/sub1/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test' }
        @{ Type = 'unknown'; Expected = '/subscriptions/sub1/resourceGroups/rg-test' }
    ) {
        Invoke-Private Resolve-iSOCRoleScope @{ ScopeType = $Type; SubscriptionId = 'sub1'; ResourceGroup = 'rg-test'; WorkspaceName = 'law-test'; KeyVaultName = 'kv-test' } | Should -Be $Expected
    }

    It 'has no Key Vault scope without a vault name' {
        Invoke-Private Resolve-iSOCRoleScope @{ ScopeType = 'keyvault'; SubscriptionId = 'sub1'; ResourceGroup = 'rg-test' } | Should -BeNullOrEmpty
    }
}

Describe 'Role assignments over REST' {
    It 'reads the assignments in effect at a scope, every page, with the role as its GUID' {
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
            @([pscustomobject]@{ id = "$($script:rgScope)/providers/Microsoft.Authorization/roleAssignments/a1"; name = 'a1'; properties = [pscustomobject]@{ scope = $script:rgScope; principalId = 'p1'; roleDefinitionId = "$($script:subScope)/providers/Microsoft.Authorization/roleDefinitions/$($script:roleIds['Log Analytics Reader'])" } })
        }
        $assignment = @(Invoke-Private Get-iSOCRoleAssignment @{ Context = $script:context; Scope = $script:rgScope })
        $assignment[0].RoleDefinitionId | Should -Be $script:roleIds['Log Analytics Reader']
        $assignment[0].PrincipalId | Should -Be 'p1'
        Should -Invoke -ModuleName iSOCDeployments Invoke-iSOCRestRequest -ParameterFilter { $Path -eq "$($script:rgScope)/providers/Microsoft.Authorization/roleAssignments?`$filter=atScope()" -and $ApiVersion -eq '2022-04-01' } -Times 1 -Exactly
        Invoke-Private Get-iSOCRoleAssignment @{ Context = $script:context; PrincipalId = 'p1' } | Out-Null
        Should -Invoke -ModuleName iSOCDeployments Invoke-iSOCRestRequest -ParameterFilter { $Path -eq "$($script:subScope)/providers/Microsoft.Authorization/roleAssignments?`$filter=assignedTo('p1')" } -Times 1 -Exactly
    }

    It 'finds an assignment at the scope or above it, and only at the scope with -Exact' {
        $reader = $script:roleIds['Log Analytics Reader']
        $assignments = @(
            [pscustomobject]@{ Id = 'sub'; Scope = $script:subScope; RoleDefinitionId = $reader; PrincipalId = 'p1' }
            [pscustomobject]@{ Id = 'other'; Scope = $script:rgScope; RoleDefinitionId = $reader; PrincipalId = 'p2' }
            [pscustomobject]@{ Id = 'sibling'; Scope = "$($script:subScope)/resourceGroups/rg-sentinel-old"; RoleDefinitionId = $reader; PrincipalId = 'p3' }
        )
        $find = { param($P, $S, [switch] $E) @(Invoke-Private Find-iSOCRoleAssignment @{ Assignment = $assignments; PrincipalId = $P; RoleDefinitionId = $reader; Scope = $S; Exact = $E }) }
        (& $find 'p1' $script:kvScope).Id | Should -Be 'sub'
        (& $find 'p1' $script:rgScope -E).Count | Should -Be 0
        (& $find 'p2' $script:rgScope).Id | Should -Be 'other'
        (& $find 'p3' $script:rgScope).Count | Should -Be 0 -Because 'rg-sentinel-old is not above rg-sentinel'
        (Invoke-Private Find-iSOCRoleAssignment @{ Assignment = $assignments; PrincipalId = 'p1'; RoleDefinitionId = $script:roleIds['Monitoring Reader']; Scope = $script:rgScope }).Count | Should -Be 0
    }

    It 'creates an assignment under a name made from scope, principal and role, with the ServicePrincipal type' {
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { }
        $role = $script:roleIds['Microsoft Sentinel Responder']
        Invoke-Private New-iSOCRoleAssignment @{ Context = $script:context; Scope = $script:rgScope; RoleDefinitionId = $role; PrincipalId = 'p1' } | Should -Be 'Created'
        $name = Invoke-Private ConvertTo-iSOCNameBasedGuid @{ Name = "$($script:rgScope)|p1|$role" }
        Should -Invoke -ModuleName iSOCDeployments Invoke-iSOCRestRequest -ParameterFilter {
            $Method -eq 'PUT' -and $Path -eq "$($script:rgScope)/providers/Microsoft.Authorization/roleAssignments/$name" -and
            $Body.properties.roleDefinitionId -eq "$($script:subScope)/providers/Microsoft.Authorization/roleDefinitions/$role" -and
            $Body.properties.principalId -eq 'p1' -and $Body.properties.principalType -eq 'ServicePrincipal'
        } -Times 1 -Exactly
    }

    It 'calls a 409 Exists and throws anything else' {
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { throw [System.Net.Http.HttpRequestException]::new('HTTP 409 from PUT roleAssignments/x: RoleAssignmentExists', $null, [System.Net.HttpStatusCode]::Conflict) }
        Invoke-Private New-iSOCRoleAssignment @{ Context = $script:context; Scope = $script:rgScope; RoleDefinitionId = 'r'; PrincipalId = 'p1' } | Should -Be 'Exists'
        Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { throw [System.Net.Http.HttpRequestException]::new('HTTP 403 from PUT roleAssignments/x: AuthorizationFailed', $null, [System.Net.HttpStatusCode]::Forbidden) }
        { Invoke-Private New-iSOCRoleAssignment @{ Context = $script:context; Scope = $script:rgScope; RoleDefinitionId = 'r'; PrincipalId = 'p1' } } | Should -Throw '*403*'
    }

    It 'gives the principal of a <Case> identity' -ForEach @(
        @{ Case = 'system-assigned'; Identity = @{ type = 'SystemAssigned'; principalId = 'sys' }; Expected = 'sys' }
        @{ Case = 'user-assigned'; Identity = @{ type = 'UserAssigned'; userAssignedIdentities = @{ '/subscriptions/x/uami' = @{ principalId = 'uami'; clientId = 'c' } } }; Expected = 'uami' }
        @{ Case = 'missing'; Identity = @{ type = 'None' }; Expected = $null }
    ) {
        $resource = @{ name = 'x'; identity = $Identity } | ConvertTo-Json -Depth 10 | ConvertFrom-Json -Depth 10
        (Invoke-Private Get-iSOCManagedIdentityPrincipal @{ Resource = $resource }).PrincipalId | Should -Be $Expected
    }
}

Describe 'The permission commands over a stand-in tenant' {
    BeforeAll {
        $role = $script:roleIds
        $principal = { param([string] $Name) Invoke-Private ConvertTo-iSOCNameBasedGuid @{ Name = "principal:$Name" } }
        $script:principal = $principal

        # The stand-in tenant: tagged Logic Apps needing each kind of role,
        # one untagged, one without an identity, one needing nothing, one
        # already holding its role at the resource group and one from the
        # subscription, one whose assignment is refused, and one whose
        # assignment appears between the read and the write (a conflict).
        $apps = [System.Collections.Generic.List[object]]::new()
        $addApp = {
            param([string] $Name, $Workflow, [string] $Identity = 'SystemAssigned', [switch] $Untagged)
            $app = [ordered]@{ id = "/subscriptions/$($script:Sub)/resourceGroups/rg-automation/providers/Microsoft.Logic/workflows/$Name"; name = $Name; type = 'Microsoft.Logic/workflows'; location = 'uksouth' }
            if (-not $Untagged) { $app.tags = @{ Source = 'Sentinel-As-Code' } }
            $app.identity = if ($Identity -eq 'None') { @{ type = 'None' } } else { @{ type = 'SystemAssigned'; principalId = (& $principal $Name); tenantId = 't' } }
            $app.properties = $Workflow
            $apps.Add($app)
        }
        # A method followed by inputs, which the old method.*put pattern
        # took for a PUT.
        & $addApp 'Incident-Reader' (New-Workflow -Connector 'azuresentinel' -Actions ([ordered]@{ Entities = [ordered]@{ type = 'ApiConnection'; inputs = [ordered]@{ method = 'post'; path = '/entities/host' } }; Parse = [ordered]@{ type = 'ParseJson'; inputs = [ordered]@{ content = 'x' } } }))
        & $addApp 'Incident-Closer' (New-Workflow -Connector 'azuresentinel' -Actions @{ Close = @{ type = 'ApiConnection'; inputs = @{ method = 'put'; path = '/Incidents' } } })
        & $addApp 'Module-GetSecret' (New-Workflow -Connector 'keyvault' -Actions @{ Graph = @{ type = 'Http'; inputs = @{ method = 'GET'; uri = 'https://graph.microsoft.com/v1.0/me'; authentication = @{ type = 'ManagedServiceIdentity'; audience = 'https://graph.microsoft.com' } } } })
        & $addApp 'Module-Query' (New-Workflow -Connector 'azuremonitorlogs' -Actions @{ Query = @{ type = 'Http'; inputs = @{ method = 'POST'; authentication = @{ type = 'ManagedServiceIdentity'; audience = 'https://api.loganalytics.io' } } } })
        & $addApp 'Module-Arm' (New-Workflow -Actions @{ Arm = @{ type = 'Http'; inputs = @{ method = 'GET'; authentication = @{ type = 'ManagedServiceIdentity'; audience = 'https://management.azure.com' } } } })
        & $addApp 'Untagged-App' (New-Workflow -Connector 'azuresentinel') -Untagged
        & $addApp 'Incident-NoIdentity' (New-Workflow -Connector 'azuresentinel') -Identity None
        & $addApp 'Other-NoRoles' (New-Workflow -Actions @{ Wait = @{ type = 'Wait' } })
        & $addApp 'Incident-Already' (New-Workflow -Connector 'azuresentinel')
        & $addApp 'Incident-Inherited' (New-Workflow -Connector 'azuresentinel')
        & $addApp 'Incident-Refused' (New-Workflow -Connector 'azuresentinel')
        & $addApp 'Incident-Race' (New-Workflow -Connector 'azuresentinel')

        $assignment = {
            param([string] $Scope, [string] $App, [string] $Role)
            [ordered]@{ Scope = $Scope; PrincipalId = (& $principal $App); RoleDefinitionId = $script:roleIds[$Role] }
        }
        $script:standIn = [ordered]@{
            SubscriptionId = $script:Sub
            LogicApps      = $apps.ToArray()
            Assignments    = @(
                (& $assignment $script:rgScope 'Incident-Already' 'Microsoft Sentinel Responder')
                (& $assignment $script:subScope 'Incident-Inherited' 'Microsoft Sentinel Responder')
            )
            Refuse         = @((& $principal 'Incident-Refused'))
            Conflict       = @((& $principal 'Incident-Race'))
            Automation     = @{ Name = 'aa-dcr-watchlist-sync'; ResourceGroup = 'rg-dcr-watchlist-sync'; PrincipalId = (& $principal 'automation') }
        }

        function Invoke-ModulePermission {
            param([scriptblock] $Command)
            $script:moduleWrites = [System.Collections.Generic.List[object]]::new()
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
            Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
                $data = $script:standIn
                if ($Method -eq 'GET' -and $Path -like '*/Microsoft.Logic/workflows?*') { return ($data.LogicApps | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100) }
                if ($Method -eq 'GET' -and $Path -like '*/automationAccounts/*') { return [pscustomobject]@{ name = $data.Automation.Name; identity = [pscustomobject]@{ type = 'SystemAssigned'; principalId = $data.Automation.PrincipalId } } }
                if ($Method -eq 'GET' -and $Path -like '*/roleAssignments?*') {
                    $scope = ($Path -split '/providers/Microsoft.Authorization/')[0]
                    $assigned = if ($Path -match "assignedTo\('([^']+)'\)") { $who = $Matches[1]; @($data.Assignments | Where-Object { $_.PrincipalId -eq $who }) } else { @($data.Assignments | Where-Object { $scope -eq $_.Scope -or $scope.StartsWith("$($_.Scope)/") }) }
                    return @($assigned | ForEach-Object { [pscustomobject]@{ id = "$($_.Scope)/providers/Microsoft.Authorization/roleAssignments/$($_.PrincipalId)-$($_.RoleDefinitionId)"; name = 'x'; properties = [pscustomobject]@{ scope = $_.Scope; principalId = $_.PrincipalId; roleDefinitionId = "/subscriptions/$($data.SubscriptionId)/providers/Microsoft.Authorization/roleDefinitions/$($_.RoleDefinitionId)" } } })
                }
                if ($Method -eq 'PUT') {
                    $script:moduleWrites.Add([pscustomobject]@{ Action = 'Create'; PrincipalId = $Body.properties.principalId; RoleDefinitionId = ($Body.properties.roleDefinitionId -split '/')[-1]; Scope = ($Path -split '/providers/Microsoft.Authorization/')[0] })
                    if (@($data.Refuse) -contains $Body.properties.principalId) { throw [System.Net.Http.HttpRequestException]::new('HTTP 403 from PUT roleAssignments: AuthorizationFailed', $null, [System.Net.HttpStatusCode]::Forbidden) }
                    if (@($data.Conflict) -contains $Body.properties.principalId) { throw [System.Net.Http.HttpRequestException]::new('HTTP 409 from PUT roleAssignments: RoleAssignmentExists', $null, [System.Net.HttpStatusCode]::Conflict) }
                    return
                }
                if ($Method -eq 'DELETE') { $script:moduleWrites.Add([pscustomobject]@{ Action = 'Delete'; Id = $Path }); return }
                throw "unexpected $Method $Path"
            }
            & $Command
        }

        $script:key = { param($Write) "$($Write.Action) $($Write.PrincipalId) $($Write.RoleDefinitionId) $($Write.Scope)" }

        # The role definition GUIDs, written out so the expected writes do not
        # come from the module's own table.
        $script:guid = @{
            Responder   = '3e150937-b8fe-4cfb-8069-0eaf05ecd056'
            Contributor = 'ab8e14d6-4a74-4a29-9ba8-549422addade'
            SecretsUser = '4633458b-17de-408a-b874-0445c86b69e6'
            LogReader   = '73c42c96-874c-492b-b04d-ab87d138a893'
            MonReader   = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
        }
    }

    Context 'playbooks' {
        BeforeAll {
            $script:run = Invoke-ModulePermission { Grant-iSOCPlaybookPermission -Context $script:context -KeyVaultName 'kv-lab' }
        }

        It 'attempts the role assignments the old playbook script attempted over this tenant' {
            # The writes the script made over this stand-in tenant on release/26.11.0.
            $expected = @(
                @{ App = 'Incident-Closer'; Role = $script:guid.Contributor; Scope = $script:rgScope }
                @{ App = 'Incident-Race'; Role = $script:guid.Responder; Scope = $script:rgScope }
                @{ App = 'Incident-Reader'; Role = $script:guid.Responder; Scope = $script:rgScope }
                @{ App = 'Incident-Refused'; Role = $script:guid.Responder; Scope = $script:rgScope }
                @{ App = 'Module-Arm'; Role = $script:guid.Contributor; Scope = $script:rgScope }
                @{ App = 'Module-GetSecret'; Role = $script:guid.SecretsUser; Scope = $script:kvScope }
                @{ App = 'Module-Query'; Role = $script:guid.LogReader; Scope = $script:rgScope }
            ) | ForEach-Object { "Create $(& $script:principal $_.App) $($_.Role) $($_.Scope)" }
            @($script:moduleWrites | ForEach-Object { & $script:key $_ } | Sort-Object) | Should -Be @($expected | Sort-Object)
        }

        It 'counts as the old playbook script counted over this tenant' {
            $script:run.Assigned | Should -Be 5
            ($script:run.Skipped + $script:run.Unchanged) | Should -Be 5
            $script:run.Failed | Should -Be 1
            $script:run.ExitCode | Should -Be 1
        }

        It 'gives each playbook the roles it needs, and leaves the untagged one out' {
            $roles = @{}
            foreach ($r in $script:run.Results) { $roles["$($r.Name)|$($r.Role)"] = $r.Outcome }
            $roles['Incident-Reader|Microsoft Sentinel Responder'] | Should -Be 'Assigned'
            $roles['Incident-Closer|Microsoft Sentinel Contributor'] | Should -Be 'Assigned'
            $roles['Module-GetSecret|Key Vault Secrets User'] | Should -Be 'Assigned'
            $roles['Module-Arm|Microsoft Sentinel Contributor'] | Should -Be 'Assigned'
            $roles['Incident-Already|Microsoft Sentinel Responder'] | Should -Be 'Unchanged'
            $roles['Incident-Inherited|Microsoft Sentinel Responder'] | Should -Be 'Unchanged'
            $roles['Incident-Race|Microsoft Sentinel Responder'] | Should -Be 'Unchanged'
            $roles['Incident-Refused|Microsoft Sentinel Responder'] | Should -Be 'Failed'
            @($script:run.Results | Where-Object Name -eq 'Untagged-App').Count | Should -Be 0
        }

        It 'assigns nothing with -WhatIf and says what would be' {
            $run = Invoke-ModulePermission { Grant-iSOCPlaybookPermission -Context $script:context -KeyVaultName 'kv-lab' -WhatIf }
            $script:moduleWrites.Count | Should -Be 0
            $run.WhatIf | Should -Be 7
        }

        It 'skips Key Vault roles without -KeyVaultName' {
            $run = Invoke-ModulePermission { Grant-iSOCPlaybookPermission -Context $script:context -Name 'Module-GetSecret' }
            ($run.Results | Where-Object Role -eq 'Key Vault Secrets User').Reason | Should -Be 'no Key Vault named (-KeyVaultName)'
            $script:moduleWrites.Count | Should -Be 0
        }
    }

    Context 'the runbook' {
        BeforeAll {
            $script:automation = $script:standIn.Automation.PrincipalId
        }

        It 'assigns Monitoring Reader on the subscription and Microsoft Sentinel Contributor on the resource group' {
            $run = Invoke-ModulePermission { Grant-iSOCRunbookPermission -Context $script:context -AutomationAccountName 'aa-dcr-watchlist-sync' -AutomationResourceGroup 'rg-dcr-watchlist-sync' -Confirm:$false }
            $expected = @("Create $($script:automation) $($script:guid.MonReader) $($script:subScope)", "Create $($script:automation) $($script:guid.Contributor) $($script:rgScope)")
            @($script:moduleWrites | ForEach-Object { & $script:key $_ } | Sort-Object) | Should -Be @($expected | Sort-Object)
            $run.Assigned | Should -Be 2
            @($script:moduleWrites | ForEach-Object { $_.Scope } | Sort-Object) | Should -Be @($script:rgScope, $script:subScope | Sort-Object)
        }

        It 'removes those two, and only what is at the scope itself' {
            $script:standIn.Assignments = @(
                [ordered]@{ Scope = $script:subScope; PrincipalId = $script:automation; RoleDefinitionId = $script:roleIds['Monitoring Reader'] }
                [ordered]@{ Scope = $script:subScope; PrincipalId = $script:automation; RoleDefinitionId = $script:roleIds['Microsoft Sentinel Contributor'] }
            )
            try {
                $run = Invoke-ModulePermission { Revoke-iSOCRunbookPermission -Context $script:context -AutomationAccountName 'aa-dcr-watchlist-sync' -AutomationResourceGroup 'rg-dcr-watchlist-sync' -Confirm:$false }
            }
            finally { $script:standIn.Assignments = @() }
            @($run.Results | ForEach-Object { "$($_.Role) $($_.Scope)" } | Sort-Object) | Should -Be @("Microsoft Sentinel Contributor $($script:rgScope)", "Monitoring Reader $($script:subScope)")
            @($script:moduleWrites | ForEach-Object { $_.Id }) | Should -Be @("$($script:subScope)/providers/Microsoft.Authorization/roleAssignments/$($script:automation)-$($script:roleIds['Monitoring Reader'])")
            ($run.Results | Where-Object Role -eq 'Microsoft Sentinel Contributor').Reason | Should -Be 'not assigned at this scope'
        }

        It 'asks before changing anything, where the script asked with Read-Host (MIGRATION.md edit E33)' {
            foreach ($name in 'Grant-iSOCRunbookPermission', 'Revoke-iSOCRunbookPermission') {
                $binding = (Get-Command $name).ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
                $binding.ConfirmImpact | Should -Be 'High'
                $binding.SupportsShouldProcess | Should -BeTrue
            }
        }

        It 'leaves an assignment it finds alone, where the script asked az to create it again (MIGRATION.md edit E33)' {
            $script:standIn.Assignments = @([ordered]@{ Scope = $script:subScope; PrincipalId = $script:automation; RoleDefinitionId = $script:roleIds['Monitoring Reader'] })
            try {
                $run = Invoke-ModulePermission { Grant-iSOCRunbookPermission -Context $script:context -AutomationAccountName 'aa-dcr-watchlist-sync' -AutomationResourceGroup 'rg-dcr-watchlist-sync' -Confirm:$false }
            }
            finally { $script:standIn.Assignments = @() }
            ($run.Results | Where-Object Role -eq 'Monitoring Reader').Outcome | Should -Be 'Unchanged'
            @($script:moduleWrites).Count | Should -Be 1
            @($run.Assignments | ForEach-Object { $_.Role }) | Should -Be @('Monitoring Reader')
        }

        It 'stops when the Automation Account has no identity' {
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
            Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { [pscustomobject]@{ name = 'aa' } }
            { Grant-iSOCRunbookPermission -Context $script:context -AutomationAccountName 'aa' -AutomationResourceGroup 'rg' -Confirm:$false } | Should -Throw '*Could not resolve managed identity*'
        }
    }
}
