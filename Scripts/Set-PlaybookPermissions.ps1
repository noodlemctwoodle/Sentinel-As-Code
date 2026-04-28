<#
.SYNOPSIS
    Assigns required RBAC roles to Logic App managed identities after playbook deployment.

.DESCRIPTION
    Scans all Logic Apps in the target resource group that have the 'Source: Sentinel-As-Code'
    tag, inspects their workflow definitions to determine which API connectors and HTTP actions
    they use, and assigns the minimum required RBAC roles for each playbook.

    Role mapping is derived from:
    - API connectors (azuresentinel, keyvault, wdatp, azuremonitorlogs, etc.)
    - HTTP actions using ManagedServiceIdentity (Graph API, Defender API, Log Analytics API)
    - Workflow actions that modify Sentinel resources (incidents, watchlists, comments)

    This script should run as a post-deployment step after Deploy-CustomContent.ps1 deploys
    playbooks. It requires the executing principal to have 'User Access Administrator' or
    'Owner' role on the target scope.

.PARAMETER SubscriptionId
    Azure subscription ID. Falls back to the current Az context if omitted.

.PARAMETER PlaybookResourceGroup
    Resource group where Logic App playbooks are deployed.

.PARAMETER SentinelResourceGroup
    Resource group containing the Sentinel workspace. Defaults to PlaybookResourceGroup.

.PARAMETER SentinelWorkspaceName
    Name of the Log Analytics workspace with Sentinel enabled.

.PARAMETER KeyVaultName
    Name of the Key Vault used by playbooks. Required only if playbooks reference Key Vault.

.PARAMETER WhatIf
    Preview role assignments without applying them.

.EXAMPLE
    ./Set-PlaybookPermissions.ps1 `
        -PlaybookResourceGroup "rg-sentinel-prod" `
        -SentinelWorkspaceName "law-sentinel-prod" `
        -KeyVaultName "kv-sentinel-prod"

.NOTES
    Author:         noodlemctwoodle
    Version:        1.0.0
    Last Updated:   2026-04-28
    Repository:     Sentinel-As-Code
    Requires:       Az.Accounts, Az.Resources, Az.LogicApp
    Permissions:    User Access Administrator OR Owner on the playbook resource
                    group (and Sentinel resource group, if different).
                    The deployment SPN's ABAC-conditioned UAA does NOT
                    permit Sentinel-tier role assignments, so this script
                    is intended for ad-hoc execution by a separate elevated
                    identity rather than the pipeline SPN.
#>

[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [Parameter(Mandatory)]
    [string]$PlaybookResourceGroup,
    [string]$SentinelResourceGroup,
    [Parameter(Mandatory)]
    [string]$SentinelWorkspaceName,
    [string]$KeyVaultName,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────────────────────────────────────
# Role definition IDs (Azure built-in roles)
# ─────────────────────────────────────────────────────────────────────────────
$RoleDefinitions = @{
    "Microsoft Sentinel Responder"    = "3e150937-b8fe-4cfb-8069-0eaf05ecd056"
    "Microsoft Sentinel Contributor"  = "ab8e14d6-4a74-4a29-9ba8-549422addade"
    "Log Analytics Reader"            = "73c42c96-874c-492b-b04d-ab87d138a893"
    "Key Vault Secrets User"          = "4633458b-17de-408a-b874-0445c86b69e6"
    "Logic App Contributor"           = "87a39d53-fc1b-424a-814c-f7e04687dc9e"
}

# ─────────────────────────────────────────────────────────────────────────────
# Connector → role mapping
# Maps API connector names to required RBAC roles and their assignment scope.
# ─────────────────────────────────────────────────────────────────────────────
$ConnectorRoleMap = @{
    # Sentinel connector — read incidents, entities, comments
    "azuresentinel"    = @(
        @{ Role = "Microsoft Sentinel Responder"; Scope = "rg" }
    )
    "microsoftsentinel" = @(
        @{ Role = "Microsoft Sentinel Responder"; Scope = "rg" }
    )
    # Key Vault connector — read secrets
    "keyvault"         = @(
        @{ Role = "Key Vault Secrets User"; Scope = "keyvault" }
    )
    # Log Analytics — run queries
    "azuremonitorlogs" = @(
        @{ Role = "Log Analytics Reader"; Scope = "rg" }
    )
    "azureloganalyticsdatacollector" = @(
        @{ Role = "Log Analytics Reader"; Scope = "rg" }
    )
}

# ─────────────────────────────────────────────────────────────────────────────
# Action pattern → role upgrades
# If the playbook modifies Sentinel resources, upgrade from Responder to Contributor.
# ─────────────────────────────────────────────────────────────────────────────
$ContributorActionPatterns = @(
    '/Incidents',             # Update/close incidents
    '/Watchlists',            # Create/modify watchlists
    'method.*put',            # PUT requests to Sentinel
    'Update_incident'         # Named action for updating incidents
)

# ─────────────────────────────────────────────────────────────────────────────
# HTTP + MSI audience → role mapping
# Playbooks using direct HTTP calls with ManagedServiceIdentity auth.
# ─────────────────────────────────────────────────────────────────────────────
$HttpMsiAudienceRoles = @{
    "https://graph.microsoft.com"       = $null   # Graph permissions handled via app registration, not RBAC
    "https://api.loganalytics.io"       = @{ Role = "Log Analytics Reader"; Scope = "rg" }
    "https://api.securitycenter.microsoft.com" = $null  # Defender permissions via app registration
    "https://management.azure.com"      = @{ Role = "Microsoft Sentinel Contributor"; Scope = "rg" }
}

# ─────────────────────────────────────────────────────────────────────────────
# Functions
# ─────────────────────────────────────────────────────────────────────────────
function Get-PlaybookRequiredRoles {
    <#
    .SYNOPSIS
        Analyses a Logic App workflow to determine its required RBAC roles.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $LogicAppProperties
    )

    $roles = [System.Collections.Generic.Dictionary[string, string]]::new()
    $json = $LogicAppProperties | ConvertTo-Json -Depth 50 -Compress

    # 1. Detect API connectors from $connections parameter values
    $connParams = $LogicAppProperties.parameters.'$connections'.value
    if ($connParams) {
        foreach ($prop in $connParams.PSObject.Properties) {
            $connValue = $prop.Value
            $apiId = $null
            if ($connValue.PSObject.Properties.Name -contains 'id') {
                $apiId = $connValue.id
            }
            if ($apiId -and $apiId -match '/managedApis/([^"'']+)') {
                $connectorName = $Matches[1].ToLower()
                if ($ConnectorRoleMap.ContainsKey($connectorName)) {
                    foreach ($mapping in $ConnectorRoleMap[$connectorName]) {
                        if (-not $roles.ContainsKey($mapping.Role)) {
                            $roles[$mapping.Role] = $mapping.Scope
                        }
                    }
                }
            }
        }
    }

    # 2. Check for Sentinel Contributor upgrade (modifying actions)
    $needsContributor = $false
    foreach ($pattern in $ContributorActionPatterns) {
        if ($json -match $pattern) {
            $needsContributor = $true
            break
        }
    }

    if ($needsContributor -and $roles.ContainsKey("Microsoft Sentinel Responder")) {
        $roles.Remove("Microsoft Sentinel Responder")
        $roles["Microsoft Sentinel Contributor"] = "rg"
    }
    elseif ($needsContributor) {
        $roles["Microsoft Sentinel Contributor"] = "rg"
    }

    # 3. Detect HTTP actions with ManagedServiceIdentity
    $msiMatches = [regex]::Matches($json, '"audience"\s*:\s*"(https://[^"]+)"')
    foreach ($m in $msiMatches) {
        $audience = $m.Groups[1].Value
        if ($HttpMsiAudienceRoles.ContainsKey($audience)) {
            $mapping = $HttpMsiAudienceRoles[$audience]
            if ($mapping -and -not $roles.ContainsKey($mapping.Role)) {
                $roles[$mapping.Role] = $mapping.Scope
            }
        }
    }

    return $roles
}

function Resolve-Scope {
    <#
    .SYNOPSIS
        Resolves a scope identifier to a full Azure resource path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ScopeType,
        [Parameter(Mandatory)] [string]$SubscriptionId,
        [Parameter(Mandatory)] [string]$ResourceGroup,
        [string]$WorkspaceName,
        [string]$KeyVaultName
    )

    switch ($ScopeType) {
        "rg" {
            return "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"
        }
        "workspace" {
            return "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"
        }
        "keyvault" {
            if (-not $KeyVaultName) {
                Write-Warning "Key Vault name not provided — skipping Key Vault role assignment."
                return $null
            }
            return "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.KeyVault/vaults/$KeyVaultName"
        }
        default {
            return "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
if (-not $SubscriptionId) {
    $context = Get-AzContext
    if (-not $context) { throw "Not logged in. Run Connect-AzAccount first." }
    $SubscriptionId = $context.Subscription.Id
}

if (-not $SentinelResourceGroup) {
    $SentinelResourceGroup = $PlaybookResourceGroup
}

Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
Write-Host ""
Write-Host "=== Set-PlaybookPermissions ===" -ForegroundColor Cyan
Write-Host "  Subscription:        $SubscriptionId"
Write-Host "  Playbook RG:         $PlaybookResourceGroup"
Write-Host "  Sentinel RG:         $SentinelResourceGroup"
Write-Host "  Sentinel Workspace:  $SentinelWorkspaceName"
if ($KeyVaultName) { Write-Host "  Key Vault:           $KeyVaultName" }
Write-Host ""

# --- Discover Logic Apps with Source: Sentinel-As-Code tag ---
Write-Host "Discovering Logic Apps..." -ForegroundColor Yellow
$logicApps = @(Get-AzResource `
    -ResourceGroupName $PlaybookResourceGroup `
    -ResourceType "Microsoft.Logic/workflows" `
    -ErrorAction Stop |
    Where-Object { $_.Tags -and $_.Tags['Source'] -eq 'Sentinel-As-Code' })

if ($logicApps.Count -eq 0) {
    Write-Host "No Logic Apps found with 'Source: Sentinel-As-Code' tag." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($logicApps.Count) playbook(s) with Source: Sentinel-As-Code tag.`n" -ForegroundColor Green

# --- Cache existing role assignments at RG scope ---
Write-Host "Checking existing role assignments..." -ForegroundColor Yellow
$rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$SentinelResourceGroup"
$existingAssignments = @(Get-AzRoleAssignment -Scope $rgScope -ErrorAction SilentlyContinue)

# Also get Key Vault scope assignments if applicable
if ($KeyVaultName) {
    $kvScope = Resolve-Scope -ScopeType "keyvault" -SubscriptionId $SubscriptionId `
        -ResourceGroup $SentinelResourceGroup -KeyVaultName $KeyVaultName
    if ($kvScope) {
        $existingAssignments += @(Get-AzRoleAssignment -Scope $kvScope -ErrorAction SilentlyContinue)
    }
}

# --- Process each Logic App ---
$counters = @{ Assigned = 0; Skipped = 0; Failed = 0 }

foreach ($la in $logicApps) {
    $laName = $la.Name
    Write-Host ""
    Write-Host "  Processing: $laName" -ForegroundColor White

    # Get the Logic App details
    $laDetail = Get-AzResource -ResourceId $la.ResourceId -ExpandProperties -ErrorAction Stop
    $identityType = $laDetail.Properties.identity.type
    if (-not $identityType) { $identityType = $laDetail.Identity.Type }

    if (-not $identityType -or $identityType -eq 'None') {
        Write-Host "    [SKIP] No managed identity configured." -ForegroundColor DarkGray
        $counters.Skipped++
        continue
    }

    $principalId = $null
    if ($identityType -match 'SystemAssigned') {
        $principalId = $laDetail.Identity.PrincipalId
    }
    elseif ($identityType -match 'UserAssigned') {
        $umiIds = $laDetail.Identity.UserAssignedIdentities
        if ($umiIds) {
            $firstUmi = $umiIds.PSObject.Properties | Select-Object -First 1
            if ($firstUmi) { $principalId = $firstUmi.Value.PrincipalId }
        }
    }

    if (-not $principalId) {
        Write-Host "    [SKIP] Could not determine principal ID." -ForegroundColor DarkYellow
        $counters.Skipped++
        continue
    }

    # Analyse workflow to determine required roles
    $requiredRoles = Get-PlaybookRequiredRoles -LogicAppProperties $laDetail.Properties

    if ($requiredRoles.Count -eq 0) {
        Write-Host "    [SKIP] No RBAC roles required (no matching connectors/actions)." -ForegroundColor DarkGray
        $counters.Skipped++
        continue
    }

    $roleList = ($requiredRoles.Keys | Sort-Object) -join ", "
    Write-Host "    Identity: $identityType | Roles needed: $roleList"

    foreach ($entry in $requiredRoles.GetEnumerator()) {
        $roleName = $entry.Key
        $scopeType = $entry.Value
        $roleDefId = $RoleDefinitions[$roleName]

        if (-not $roleDefId) {
            Write-Host "    [SKIP] Unknown role: $roleName" -ForegroundColor DarkYellow
            $counters.Skipped++
            continue
        }

        $scope = Resolve-Scope -ScopeType $scopeType -SubscriptionId $SubscriptionId `
            -ResourceGroup $SentinelResourceGroup -WorkspaceName $SentinelWorkspaceName `
            -KeyVaultName $KeyVaultName

        if (-not $scope) {
            $counters.Skipped++
            continue
        }

        $fullRoleDefId = "/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions/$roleDefId"

        # Check if assignment already exists
        $existing = $existingAssignments | Where-Object {
            $_.ObjectId -eq $principalId -and
            $_.RoleDefinitionId -eq $fullRoleDefId -and
            $_.Scope -eq $scope
        }

        if ($existing) {
            Write-Host "    [OK]   $roleName — already assigned." -ForegroundColor DarkGray
            $counters.Skipped++
            continue
        }

        if ($WhatIf) {
            Write-Host "    [WhatIf] Would assign '$roleName' at $scopeType scope." -ForegroundColor Cyan
            $counters.Assigned++
        }
        else {
            try {
                New-AzRoleAssignment `
                    -ObjectId $principalId `
                    -RoleDefinitionId $roleDefId `
                    -Scope $scope `
                    -ErrorAction Stop | Out-Null
                Write-Host "    [OK]   Assigned: $roleName" -ForegroundColor Green
                $counters.Assigned++
            }
            catch {
                if ($_.Exception.Message -match "Conflict|already exists") {
                    Write-Host "    [OK]   $roleName — already assigned (conflict)." -ForegroundColor DarkGray
                    $counters.Skipped++
                }
                else {
                    Write-Host "    [FAIL] $roleName — $($_.Exception.Message)" -ForegroundColor Red
                    $counters.Failed++
                }
            }
        }
    }
}

# --- Summary ---
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "  Assigned: $($counters.Assigned)"
Write-Host "  Skipped:  $($counters.Skipped) (already assigned or no identity)"
Write-Host "  Failed:   $($counters.Failed)"
Write-Host ""

if ($counters.Failed -gt 0) {
    Write-Warning "Some role assignments failed. Ensure the executing principal has 'User Access Administrator' or 'Owner' role."
    exit 1
}
