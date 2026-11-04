#Requires -Version 7.2
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
      - Parity: Deploy/permissions/Set-PlaybookPermissions.ps1 and
        Deploy/permissions/Set-RunbookPermissions.ps1, run unchanged in a
        child pwsh with the Az cmdlets and az stood in for over one stand-in
        tenant, beside the module against the same one: the same role
        assignments attempted, created and removed, and the same counts;
        and the differences MIGRATION.md edits E32 and E33 describe, shown.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Permissions.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Permissions.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+, Pester 5+

    The stand-ins shape objects as Az.Resources and the az CLI return them;
    the scripts have not been run here against a tenant. The parity block
    goes when the scripts are removed at cut-over.
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

Describe 'Parity with the permission scripts' {
    BeforeAll {
        $role = $script:roleIds
        $principal = { param([string] $Name) Invoke-Private ConvertTo-iSOCNameBasedGuid @{ Name = "principal:$Name" } }

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
        $script:standInPath = Join-Path $TestDrive 'permissions-standin.json'
        Set-Content -LiteralPath $script:standInPath -Value (ConvertTo-Json -InputObject $script:standIn -Depth 100)

        # Runs a script unchanged in a child pwsh, its Az cmdlets, az and
        # Read-Host stood in for by functions defined first; each write is
        # appended to a log as JSON.
        $script:stubs = @'
param([string] $Script, [string] $StandInPath, [string] $Log, [string] $Parameters)
$standIn = Get-Content -LiteralPath $StandInPath -Raw | ConvertFrom-Json -Depth 100
function Write-Log { param([hashtable] $Entry) Add-Content -LiteralPath $Log -Value (ConvertTo-Json -InputObject $Entry -Compress) }
function Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = $standIn.SubscriptionId }; Account = [pscustomobject]@{ Id = 'tester' } } }
function Set-AzContext { param($SubscriptionId, $WarningAction) }
function ConvertTo-PSResource {
    param($App)
    $tags = @{}
    if ($App.PSObject.Properties['tags'] -and $App.tags) { foreach ($p in $App.tags.PSObject.Properties) { $tags[$p.Name] = $p.Value } }
    $identity = [pscustomobject]@{ Type = $App.identity.type; PrincipalId = $(if ($App.identity.PSObject.Properties['principalId']) { $App.identity.principalId } else { $null }); UserAssignedIdentities = $null }
    [pscustomobject]@{ Name = $App.name; ResourceId = $App.id; Tags = $tags; Properties = $App.properties; Identity = $identity }
}
function Get-AzResource {
    param($ResourceGroupName, $ResourceType, $ResourceId, [switch] $ExpandProperties, $ErrorAction)
    if ($ResourceId) { return ConvertTo-PSResource (@($standIn.LogicApps | Where-Object { $_.id -eq $ResourceId })[0]) }
    foreach ($app in $standIn.LogicApps) { ConvertTo-PSResource $app }
}
function Get-AzRoleAssignment {
    param($Scope, $ErrorAction)
    foreach ($a in $standIn.Assignments) {
        if ($Scope -eq $a.Scope -or $Scope.StartsWith("$($a.Scope)/")) { [pscustomobject]@{ ObjectId = $a.PrincipalId; RoleDefinitionId = $a.RoleDefinitionId; Scope = $a.Scope } }
    }
}
function New-AzRoleAssignment {
    param($ObjectId, $RoleDefinitionId, $Scope, $ErrorAction)
    Write-Log @{ Action = 'Create'; PrincipalId = $ObjectId; RoleDefinitionId = $RoleDefinitionId; Scope = $Scope }
    if (@($standIn.Refuse) -contains $ObjectId) { throw 'Operation returned an invalid status code ''Forbidden''' }
    if (@($standIn.Conflict) -contains $ObjectId) { throw 'Operation returned an invalid status code ''Conflict''' }
}
function Read-Host { param($Prompt) 'Y' }
function az {
    $line = $args -join ' '
    $global:LASTEXITCODE = 0
    $flags = @{}
    for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -like '--*' -and $i + 1 -lt $args.Count) { $flags["$($args[$i])"] = "$($args[$i + 1])" } }
    if ($line -like 'automation account show*') { return $standIn.Automation.PrincipalId }
    if ($line -like 'role assignment create*') { Write-Log @{ Action = 'Create'; PrincipalId = $flags['--assignee']; Role = $flags['--role']; Scope = $flags['--scope'] }; return '' }
    if ($line -like 'role assignment delete*') { Write-Log @{ Action = 'Delete'; PrincipalId = $flags['--assignee']; Role = $flags['--role']; Scope = $flags['--scope'] }; return '' }
    ''
}
$splat = Get-Content -LiteralPath $Parameters -Raw | ConvertFrom-Json -AsHashtable
$global:LASTEXITCODE = 0
& $Script @splat
exit $LASTEXITCODE
'@

        function Invoke-LegacyPermission {
            param([string] $Script, [hashtable] $Parameters)
            $tree = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tree | Out-Null
            $copy = Join-Path $tree (Split-Path -Leaf $Script)
            Set-Content -LiteralPath $copy -Value ((Get-Content -LiteralPath (Join-Path $script:repoRoot $Script) -Raw) -replace '(?m)^#Requires -Modules[^\r\n]*\r?\n', '') -NoNewline
            $wrapper = Join-Path $tree 'run.ps1'
            Set-Content -LiteralPath $wrapper -Value $script:stubs
            $log = Join-Path $tree 'writes.jsonl'
            New-Item -ItemType File -Path $log | Out-Null
            $splat = Join-Path $tree 'parameters.json'
            Set-Content -LiteralPath $splat -Value (ConvertTo-Json -InputObject $Parameters)
            $output = & pwsh -NoProfile -NonInteractive -File $wrapper -Script $copy -StandInPath $script:standInPath -Log $log -Parameters $splat 2>&1 | Out-String
            $exit = $LASTEXITCODE
            $count = { param([string] $Label) if ($output -match "(?m)^\s*$($Label):\s+(\d+)") { [int]$Matches[1] } else { -1 } }
            [pscustomobject]@{
                Output   = $output
                ExitCode = $exit
                Writes   = @(Get-Content -LiteralPath $log | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
                Assigned = & $count 'Assigned'
                Skipped  = & $count 'Skipped'
                Failed   = & $count 'Failed'
            }
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
        $script:playbookArgs = @{ PlaybookResourceGroup = 'rg-automation'; SentinelResourceGroup = 'rg-sentinel'; SentinelWorkspaceName = 'law-lab'; KeyVaultName = 'kv-lab'; SubscriptionId = $script:Sub }
    }

    Context 'playbooks' {
        BeforeAll {
            $script:legacy = Invoke-LegacyPermission -Script 'Deploy/permissions/Set-PlaybookPermissions.ps1' -Parameters $script:playbookArgs
            $script:run = Invoke-ModulePermission { Grant-iSOCPlaybookPermission -Context $script:context -KeyVaultName 'kv-lab' }
        }

        It 'exercises every case' {
            $script:legacy.ExitCode | Should -Be 1 -Because $script:legacy.Output
            $script:legacy.Assigned | Should -Be 5
            $script:legacy.Failed | Should -Be 1
            $script:legacy.Output | Should -Match 'No managed identity configured'
            $script:legacy.Output | Should -Match 'already assigned \(conflict\)'
        }

        It 'attempts the same role assignments' {
            @($script:moduleWrites | ForEach-Object { & $script:key $_ } | Sort-Object) | Should -Be @($script:legacy.Writes | ForEach-Object { & $script:key $_ } | Sort-Object)
        }

        It 'counts the same' {
            $script:run.Assigned | Should -Be $script:legacy.Assigned
            ($script:run.Skipped + $script:run.Unchanged) | Should -Be $script:legacy.Skipped
            $script:run.Failed | Should -Be $script:legacy.Failed
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
            $legacy = Invoke-LegacyPermission -Script 'Deploy/permissions/Set-PlaybookPermissions.ps1' -Parameters ($script:playbookArgs + @{ WhatIf = $true })
            $legacy.Writes.Count | Should -Be 0
            $run = Invoke-ModulePermission { Grant-iSOCPlaybookPermission -Context $script:context -KeyVaultName 'kv-lab' -WhatIf }
            $script:moduleWrites.Count | Should -Be 0
            $run.WhatIf | Should -Be $legacy.Assigned
        }

        It 'skips Key Vault roles without -KeyVaultName' {
            $run = Invoke-ModulePermission { Grant-iSOCPlaybookPermission -Context $script:context -Name 'Module-GetSecret' }
            ($run.Results | Where-Object Role -eq 'Key Vault Secrets User').Reason | Should -Be 'no Key Vault named (-KeyVaultName)'
            $script:moduleWrites.Count | Should -Be 0
        }
    }

    Context 'the runbook' {
        BeforeAll {
            $script:runbookArgs = @{ SubscriptionId = $script:Sub; AutomationAccountName = 'aa-dcr-watchlist-sync'; AutomationResourceGroup = 'rg-dcr-watchlist-sync'; SentinelResourceGroup = 'rg-sentinel' }
            $script:automation = $script:standIn.Automation.PrincipalId
            $script:asModuleKey = { param($Write) "$($Write.Action) $($Write.PrincipalId) $($script:roleIds[$Write.Role]) $($Write.Scope)" }
        }

        It 'assigns the same two roles at the same scopes' {
            $legacy = Invoke-LegacyPermission -Script 'Deploy/permissions/Set-RunbookPermissions.ps1' -Parameters $script:runbookArgs
            $legacy.ExitCode | Should -Be 0 -Because $legacy.Output
            $run = Invoke-ModulePermission { Grant-iSOCRunbookPermission -Context $script:context -AutomationAccountName 'aa-dcr-watchlist-sync' -AutomationResourceGroup 'rg-dcr-watchlist-sync' -Confirm:$false }
            @($script:moduleWrites | ForEach-Object { & $script:key $_ } | Sort-Object) | Should -Be @($legacy.Writes | ForEach-Object { & $script:asModuleKey $_ } | Sort-Object)
            $run.Assigned | Should -Be 2
            @($script:moduleWrites | ForEach-Object { $_.Scope } | Sort-Object) | Should -Be @($script:rgScope, $script:subScope | Sort-Object)
        }

        It 'removes the same two, and only what is at the scope itself' {
            $legacy = Invoke-LegacyPermission -Script 'Deploy/permissions/Set-RunbookPermissions.ps1' -Parameters ($script:runbookArgs + @{ Remove = $true })
            @($legacy.Writes | ForEach-Object { "$($_.Role) $($_.Scope)" } | Sort-Object) | Should -Be @("Microsoft Sentinel Contributor $($script:rgScope)", "Monitoring Reader $($script:subScope)")
            $script:standIn.Assignments = @(
                [ordered]@{ Scope = $script:subScope; PrincipalId = $script:automation; RoleDefinitionId = $script:roleIds['Monitoring Reader'] }
                [ordered]@{ Scope = $script:subScope; PrincipalId = $script:automation; RoleDefinitionId = $script:roleIds['Microsoft Sentinel Contributor'] }
            )
            try {
                $run = Invoke-ModulePermission { Revoke-iSOCRunbookPermission -Context $script:context -AutomationAccountName 'aa-dcr-watchlist-sync' -AutomationResourceGroup 'rg-dcr-watchlist-sync' -Confirm:$false }
            }
            finally { $script:standIn.Assignments = @() }
            @($script:moduleWrites | ForEach-Object { $_.Id }) | Should -Be @("$($script:subScope)/providers/Microsoft.Authorization/roleAssignments/$($script:automation)-$($script:roleIds['Monitoring Reader'])")
            ($run.Results | Where-Object Role -eq 'Microsoft Sentinel Contributor').Reason | Should -Be 'not assigned at this scope'
        }

        It 'asks before changing anything, where the script asked with Read-Host (MIGRATION.md edit E33)' {
            foreach ($name in 'Grant-iSOCRunbookPermission', 'Revoke-iSOCRunbookPermission') {
                $binding = (Get-Command $name).ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
                $binding.ConfirmImpact | Should -Be 'High'
                $binding.SupportsShouldProcess | Should -BeTrue
            }
            (Get-Content -LiteralPath (Join-Path $script:repoRoot 'Deploy/permissions/Set-RunbookPermissions.ps1') -Raw) | Should -Match 'Read-Host'
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
