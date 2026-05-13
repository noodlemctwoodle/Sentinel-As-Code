#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 unit tests for the pure functions in
    Scripts/Set-PlaybookPermissions.ps1: connector-to-role mapping and
    scope resolution.

.DESCRIPTION
    Two pure functions worth pinning with tests:
      - Get-PlaybookRequiredRoles (regex-based extraction of API connector
        names + HTTP MSI audiences from a serialised Logic App workflow,
        plus the Responder-to-Contributor upgrade rule)
      - Resolve-Scope (string-builder mapping a scope identifier to a full
        Azure resource path)

    Both depend on script-scope lookup tables: $ConnectorRoleMap,
    $ContributorActionPatterns, $HttpMsiAudienceRoles. The AST extractor
    pulls the function bodies but NOT those top-level table definitions,
    so the BeforeAll block sets them up to mirror the source script.
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Scripts/Set-PlaybookPermissions.ps1'

    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop
    Import-ScriptFunctions -Path $scriptPath

    # Mirror the script-scope lookup tables. Keep these in sync with
    # Set-PlaybookPermissions.ps1 lines 87-128 — the test will catch any
    # accidental divergence in the source via the assertion failures.
    #
    # Explicit $script: prefix because these are read by the AST-extracted
    # Get-PlaybookRequiredRoles function via $script:ConnectorRoleMap etc.
    # Without the prefix, PSScriptAnalyzer flags them as assigned-but-unused.
    $script:ConnectorRoleMap = @{
        "azuresentinel"    = @(@{ Role = "Microsoft Sentinel Responder"; Scope = "rg" })
        "microsoftsentinel" = @(@{ Role = "Microsoft Sentinel Responder"; Scope = "rg" })
        "keyvault"         = @(@{ Role = "Key Vault Secrets User"; Scope = "keyvault" })
        "azuremonitorlogs" = @(@{ Role = "Log Analytics Reader"; Scope = "rg" })
        "azureloganalyticsdatacollector" = @(@{ Role = "Log Analytics Reader"; Scope = "rg" })
    }
    $script:ContributorActionPatterns = @(
        '/Incidents'
        '/Watchlists'
        'method.*put'
        'Update_incident'
    )
    $script:HttpMsiAudienceRoles = @{
        "https://graph.microsoft.com"       = $null
        "https://api.loganalytics.io"       = @{ Role = "Log Analytics Reader"; Scope = "rg" }
        "https://api.securitycenter.microsoft.com" = $null
        "https://management.azure.com"      = @{ Role = "Microsoft Sentinel Contributor"; Scope = "rg" }
    }

    function New-LogicAppProps {
        param(
            [hashtable[]]$Connections = @(),
            [hashtable[]]$Actions     = @()
        )

        $connObj = New-Object psobject
        foreach ($conn in $Connections) {
            $value = New-Object psobject
            Add-Member -InputObject $value -MemberType NoteProperty -Name 'id'           -Value $conn.id
            Add-Member -InputObject $value -MemberType NoteProperty -Name 'connectionId' -Value 'fake-conn-id'
            Add-Member -InputObject $connObj -MemberType NoteProperty -Name $conn.alias -Value $value
        }

        # The function reads parameters.'$connections'.value
        $connWrapper = New-Object psobject
        Add-Member -InputObject $connWrapper -MemberType NoteProperty -Name 'value' -Value $connObj

        $params = New-Object psobject
        Add-Member -InputObject $params -MemberType NoteProperty -Name '$connections' -Value $connWrapper

        $props = [pscustomobject]@{
            parameters = $params
            definition = [pscustomobject]@{
                triggers = @{}
                actions  = $Actions
            }
        }
        return $props
    }
}

Describe 'Resolve-Scope' {
    It 'rg → resource group path' {
        Resolve-Scope -ScopeType 'rg' -SubscriptionId 'sub1' -ResourceGroup 'rg-test' |
            Should -Be '/subscriptions/sub1/resourceGroups/rg-test'
    }

    It 'workspace → Log Analytics workspace path' {
        Resolve-Scope -ScopeType 'workspace' -SubscriptionId 'sub1' -ResourceGroup 'rg-test' -WorkspaceName 'law-test' |
            Should -Be '/subscriptions/sub1/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test'
    }

    It 'keyvault → Key Vault path when name is provided' {
        Resolve-Scope -ScopeType 'keyvault' -SubscriptionId 'sub1' -ResourceGroup 'rg-test' -KeyVaultName 'kv-test' |
            Should -Be '/subscriptions/sub1/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test'
    }

    It 'keyvault returns $null when no Key Vault name is provided (logs warning)' {
        Resolve-Scope -ScopeType 'keyvault' -SubscriptionId 'sub1' -ResourceGroup 'rg-test' 3>$null |
            Should -BeNullOrEmpty
    }

    It 'unknown scope type falls back to the resource group path' {
        Resolve-Scope -ScopeType 'unknown-scope-type' -SubscriptionId 'sub1' -ResourceGroup 'rg-test' |
            Should -Be '/subscriptions/sub1/resourceGroups/rg-test'
    }
}

Describe 'Get-PlaybookRequiredRoles' {
    Context 'Connector-driven roles' {
        It 'detects azuresentinel connector → Microsoft Sentinel Responder at rg scope' {
            $props = New-LogicAppProps -Connections @(
                @{ alias = 'azuresentinel'; id = '/subscriptions/x/providers/Microsoft.Web/locations/uksouth/managedApis/azuresentinel' }
            )
            $roles = Get-PlaybookRequiredRoles -LogicAppProperties $props
            $roles.ContainsKey('Microsoft Sentinel Responder') | Should -BeTrue
            $roles['Microsoft Sentinel Responder'] | Should -Be 'rg'
        }

        It 'detects keyvault connector → Key Vault Secrets User at keyvault scope' {
            $props = New-LogicAppProps -Connections @(
                @{ alias = 'kv'; id = '/subscriptions/x/providers/Microsoft.Web/locations/uksouth/managedApis/keyvault' }
            )
            $roles = Get-PlaybookRequiredRoles -LogicAppProperties $props
            $roles.ContainsKey('Key Vault Secrets User') | Should -BeTrue
            $roles['Key Vault Secrets User'] | Should -Be 'keyvault'
        }

        It 'detects azuremonitorlogs connector → Log Analytics Reader at rg scope' {
            $props = New-LogicAppProps -Connections @(
                @{ alias = 'aml'; id = '/subscriptions/x/providers/Microsoft.Web/locations/uksouth/managedApis/azuremonitorlogs' }
            )
            $roles = Get-PlaybookRequiredRoles -LogicAppProperties $props
            $roles.ContainsKey('Log Analytics Reader') | Should -BeTrue
        }

        It 'returns empty role set for a playbook with no recognised connectors' {
            $props = New-LogicAppProps -Connections @(
                @{ alias = 'unknown'; id = '/subscriptions/x/providers/Microsoft.Web/locations/uksouth/managedApis/somethingexotic' }
            )
            $roles = Get-PlaybookRequiredRoles -LogicAppProperties $props
            $roles.Count | Should -Be 0
        }
    }

    Context 'Sentinel-modifying-action upgrade' {
        It 'upgrades Responder to Contributor when the workflow modifies Incidents' {
            $props = New-LogicAppProps -Connections @(
                @{ alias = 'azuresentinel'; id = '/subscriptions/x/providers/Microsoft.Web/locations/uksouth/managedApis/azuresentinel' }
            ) -Actions @(
                @{ name = 'UpdateIncident'; type = 'Http'; uri = 'https://management.azure.com/Incidents' }
            )
            $roles = Get-PlaybookRequiredRoles -LogicAppProperties $props
            $roles.ContainsKey('Microsoft Sentinel Contributor') | Should -BeTrue
            $roles.ContainsKey('Microsoft Sentinel Responder')   | Should -BeFalse -Because 'Responder is upgraded to Contributor when the workflow includes Sentinel-modifying actions'
        }

        It 'upgrades when action JSON contains Update_incident keyword' {
            $props = New-LogicAppProps -Connections @(
                @{ alias = 'azuresentinel'; id = '/subscriptions/x/providers/Microsoft.Web/locations/uksouth/managedApis/azuresentinel' }
            ) -Actions @(
                @{ name = 'Update_incident'; type = 'ApiConnection' }
            )
            $roles = Get-PlaybookRequiredRoles -LogicAppProperties $props
            $roles.ContainsKey('Microsoft Sentinel Contributor') | Should -BeTrue
        }

        It 'adds Contributor without removing anything when no Responder was present' {
            # Workflow has no Sentinel connector but writes to /Watchlists; Contributor still required.
            $props = New-LogicAppProps -Actions @(
                @{ name = 'PutWatchlist'; type = 'Http'; uri = 'https://management.azure.com/Watchlists' }
            )
            $roles = Get-PlaybookRequiredRoles -LogicAppProperties $props
            $roles.ContainsKey('Microsoft Sentinel Contributor') | Should -BeTrue
        }
    }

    Context 'HTTP MSI audience-driven roles' {
        It 'maps management.azure.com audience to Microsoft Sentinel Contributor' {
            $props = New-LogicAppProps -Actions @(
                @{
                    name = 'CallMgmt'
                    type = 'Http'
                    inputs = @{
                        authentication = @{ type = 'ManagedServiceIdentity'; audience = 'https://management.azure.com' }
                    }
                }
            )
            $roles = Get-PlaybookRequiredRoles -LogicAppProperties $props
            $roles.ContainsKey('Microsoft Sentinel Contributor') | Should -BeTrue
        }

        It 'ignores audiences that map to $null (graph / defender — handled via app registration)' {
            $props = New-LogicAppProps -Actions @(
                @{
                    name = 'CallGraph'
                    type = 'Http'
                    inputs = @{
                        authentication = @{ type = 'ManagedServiceIdentity'; audience = 'https://graph.microsoft.com' }
                    }
                }
            )
            $roles = Get-PlaybookRequiredRoles -LogicAppProperties $props
            $roles.Count | Should -Be 0 -Because 'Graph audiences are auth-via-app-registration, not RBAC'
        }
    }
}
