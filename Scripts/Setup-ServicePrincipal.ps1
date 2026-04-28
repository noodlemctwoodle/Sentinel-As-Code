<#
.SYNOPSIS
    One-time bootstrap: grants the deployment SPN all permissions needed
    for fully autonomous Sentinel-As-Code pipeline execution.

.DESCRIPTION
    Configures a service principal with every permission the pipeline requires.
    Must be run ONCE by a user with Owner on the subscription and at least
    Privileged Role Administrator in Entra ID.

    After execution the pipeline is fully autonomous — no further manual steps.

    Permissions granted:
    1. Azure RBAC (subscription scope):
       - Contributor — resource group, workspace, Bicep, content, summary rules
       - User Access Administrator (ABAC-conditioned) — can only assign:
           Microsoft Sentinel Responder, Microsoft Sentinel Reader,
           Log Analytics Reader, Logic App Contributor, Managed Identity Operator

    2. Entra ID directory role:
       - Security Administrator — UEBA and Entity Analytics settings

    3. Microsoft Graph application permission:
       - CustomDetection.ReadWrite.All — Defender XDR custom detection rules

    Use -SkipEntraRole or -SkipGraphPermission to skip optional steps if your
    organisation handles those through a separate process.

.PARAMETER SubscriptionId
    Target Azure subscription ID.

.PARAMETER ServicePrincipalAppId
    Application (client) ID of the deployment service principal.

.PARAMETER SkipEntraRole
    Skip assigning the Security Administrator Entra ID directory role.

.PARAMETER SkipGraphPermission
    Skip granting the CustomDetection.ReadWrite.All Graph API permission.

.EXAMPLE
    ./Setup-ServicePrincipal.ps1 `
        -SubscriptionId "5305ccd2-977a-4630-843b-bad582e756a3" `
        -ServicePrincipalAppId "your-app-id-here"

.EXAMPLE
    # Skip Entra ID role (UEBA/Entity Analytics will need manual enablement)
    ./Setup-ServicePrincipal.ps1 `
        -SubscriptionId "5305ccd2-977a-4630-843b-bad582e756a3" `
        -ServicePrincipalAppId "your-app-id-here" `
        -SkipEntraRole

.EXAMPLE
    # Skip Graph permission (Defender XDR stage will fail — grant separately)
    ./Setup-ServicePrincipal.ps1 `
        -SubscriptionId "5305ccd2-977a-4630-843b-bad582e756a3" `
        -ServicePrincipalAppId "your-app-id-here" `
        -SkipGraphPermission

.NOTES
    Author:         noodlemctwoodle
    Version:        1.0.0
    Last Updated:   2026-04-28
    Repository:     Sentinel-As-Code
    Requires:       Az.Accounts, Az.Resources, Microsoft.Graph
    Permissions:    The user running this script needs Owner on the target
                    subscription AND at least Privileged Role Administrator
                    in Entra ID. Run ONCE; the pipeline SPN is fully
                    autonomous after.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ServicePrincipalAppId,

    [switch]$SkipEntraRole,

    [switch]$SkipGraphPermission
)

$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Sentinel-As-Code: Service Principal Bootstrap" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────
# Authentication check
# ─────────────────────────────────────────────────────────────────────────

Write-Host "Verifying authentication..." -ForegroundColor Yellow
$context = Get-AzContext -WarningAction SilentlyContinue
if (-not $context) {
    throw "Not authenticated. Run Connect-AzAccount first."
}
Write-Host "  Authenticated as: $($context.Account.Id)" -ForegroundColor Green

Set-AzContext -SubscriptionId $SubscriptionId -WarningAction SilentlyContinue | Out-Null
Write-Host "  Subscription:     $SubscriptionId" -ForegroundColor Green
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────
# Resolve the service principal
# ─────────────────────────────────────────────────────────────────────────

Write-Host "Resolving service principal..." -ForegroundColor Yellow
$spn = Get-AzADServicePrincipal -ApplicationId $ServicePrincipalAppId -ErrorAction Stop -WarningAction SilentlyContinue
if (-not $spn) {
    throw "Service principal with Application ID '$ServicePrincipalAppId' not found."
}
$spnObjectId = $spn.Id
$spnDisplayName = $spn.DisplayName
Write-Host "  Display Name: $spnDisplayName" -ForegroundColor Green
Write-Host "  Object ID:    $spnObjectId" -ForegroundColor Green
Write-Host "  App ID:       $ServicePrincipalAppId" -ForegroundColor Green
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────
# Disclaimer, permission summary, and consent
# ─────────────────────────────────────────────────────────────────────────

Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "  PERMISSION SUMMARY" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  This script will grant the following permissions to:" -ForegroundColor White
Write-Host "    SPN:          $spnDisplayName" -ForegroundColor White
Write-Host "    App ID:       $ServicePrincipalAppId" -ForegroundColor White
Write-Host "    Subscription: $SubscriptionId" -ForegroundColor White
Write-Host ""
Write-Host "  1. Azure RBAC (subscription scope):" -ForegroundColor White
Write-Host "     - Contributor" -ForegroundColor White
Write-Host "       Allows full management of all resources except" -ForegroundColor Gray
Write-Host "       access control (RBAC). Required for deploying" -ForegroundColor Gray
Write-Host "       resource groups, workspaces, Bicep, and content." -ForegroundColor Gray
Write-Host ""
Write-Host "     - User Access Administrator (ABAC-conditioned)" -ForegroundColor White
Write-Host "       Restricted via ABAC to ONLY assign these roles:" -ForegroundColor Gray
Write-Host "         - Microsoft Sentinel Responder" -ForegroundColor Gray
Write-Host "         - Microsoft Sentinel Reader" -ForegroundColor Gray
Write-Host "         - Log Analytics Reader" -ForegroundColor Gray
Write-Host "         - Logic App Contributor" -ForegroundColor Gray
Write-Host "         - Managed Identity Operator" -ForegroundColor Gray
Write-Host "       Required for playbook managed identity role" -ForegroundColor Gray
Write-Host "       assignments during ARM template deployment." -ForegroundColor Gray
Write-Host ""

if (-not $SkipEntraRole) {
    Write-Host "  2. Entra ID Directory Role:" -ForegroundColor White
    Write-Host "     - Security Administrator" -ForegroundColor White
    Write-Host "       Required for UEBA and Entity Analytics settings." -ForegroundColor Gray
    Write-Host "       Grants read/write access to security policies" -ForegroundColor Gray
    Write-Host "       and identity protection configuration." -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Host "  2. Entra ID Directory Role: SKIPPED (-SkipEntraRole)" -ForegroundColor DarkGray
    Write-Host ""
}

if (-not $SkipGraphPermission) {
    Write-Host "  3. Microsoft Graph Application Permission:" -ForegroundColor White
    Write-Host "     - CustomDetection.ReadWrite.All" -ForegroundColor White
    Write-Host "       Required for deploying Defender XDR custom" -ForegroundColor Gray
    Write-Host "       detection rules via the Microsoft Graph API." -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Host "  3. Microsoft Graph Permission: SKIPPED (-SkipGraphPermission)" -ForegroundColor DarkGray
    Write-Host ""
}

Write-Host "============================================================" -ForegroundColor Red
Write-Host "  DISCLAIMER" -ForegroundColor Red
Write-Host "============================================================" -ForegroundColor Red
Write-Host ""
Write-Host "  This script modifies Azure RBAC role assignments, Entra" -ForegroundColor White
Write-Host "  ID directory roles, and Microsoft Graph API permissions" -ForegroundColor White
Write-Host "  at the SUBSCRIPTION and TENANT scope." -ForegroundColor White
Write-Host ""
Write-Host "  By proceeding you acknowledge that:" -ForegroundColor White
Write-Host ""
Write-Host "  - You have reviewed and understand the permissions listed" -ForegroundColor White
Write-Host "    above and accept the security implications." -ForegroundColor White
Write-Host "  - You have the authority to grant these permissions in" -ForegroundColor White
Write-Host "    your organisation (Owner / Privileged Role Admin)." -ForegroundColor White
Write-Host "  - The authors and contributors of Sentinel-As-Code" -ForegroundColor White
Write-Host "    accept NO LIABILITY for any damage, data loss," -ForegroundColor White
Write-Host "    security incidents, or unintended access resulting" -ForegroundColor White
Write-Host "    from the execution of this script." -ForegroundColor White
Write-Host "  - It is YOUR responsibility to validate that these" -ForegroundColor White
Write-Host "    permissions comply with your organisation's security" -ForegroundColor White
Write-Host "    policies, least-privilege requirements, and any" -ForegroundColor White
Write-Host "    applicable regulatory or compliance frameworks." -ForegroundColor White
Write-Host "  - You should review and audit the role assignments" -ForegroundColor White
Write-Host "    created by this script on a regular basis." -ForegroundColor White
Write-Host ""
Write-Host "============================================================" -ForegroundColor Red
Write-Host ""

$consent = Read-Host "  Do you accept the above and wish to proceed? (Y/N)"
if ($consent -notin @('Y', 'y', 'Yes', 'yes')) {
    Write-Host ""
    Write-Host "  Aborted. No changes have been made." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

Write-Host ""
Write-Host "  Proceeding with permission assignments..." -ForegroundColor Green
Write-Host ""

$results = @()

# ─────────────────────────────────────────────────────────────────────────
# 1. Contributor (Azure RBAC)
# ─────────────────────────────────────────────────────────────────────────

Write-Host "── 1/4: Contributor ────────────────────────────────────────" -ForegroundColor Cyan
$contributorRoleId = "b24988ac-6180-42a0-ab88-20f7382dd24c"
$contributorScope = "/subscriptions/$SubscriptionId"

$existing = Get-AzRoleAssignment -ObjectId $spnObjectId -RoleDefinitionId $contributorRoleId -Scope $contributorScope -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "  Already assigned. Skipping." -ForegroundColor Green
    $results += @{ Step = "Contributor"; Status = "Already exists" }
} else {
    Write-Host "  Assigning Contributor at subscription scope..." -ForegroundColor Yellow
    New-AzRoleAssignment `
        -ObjectId $spnObjectId `
        -RoleDefinitionId $contributorRoleId `
        -Scope $contributorScope `
        -ErrorAction Stop | Out-Null
    Write-Host "  Assigned." -ForegroundColor Green
    $results += @{ Step = "Contributor"; Status = "Assigned" }
}
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────
# 2. User Access Administrator — ABAC-conditioned (Azure RBAC)
# ─────────────────────────────────────────────────────────────────────────

Write-Host "── 2/4: User Access Administrator (conditioned) ───────────" -ForegroundColor Cyan

$allowedRoles = @(
    @{ Name = "Microsoft Sentinel Responder"; Id = "3e150937-b8fe-4cfb-8069-0eaf05ecd056" }
    @{ Name = "Microsoft Sentinel Reader";    Id = "8d289c81-5878-46d4-8554-54e1e3d8b5cb" }
    @{ Name = "Log Analytics Reader";         Id = "73c42c96-874c-492b-b04d-ab87d138a893" }
    @{ Name = "Logic App Contributor";        Id = "87a39d53-fc1b-424a-814c-f7e04687dc9e" }
    @{ Name = "Managed Identity Operator";    Id = "f1a07417-d97a-45cb-824c-7a7467783830" }
)

Write-Host "  ABAC condition restricts assignment to:" -ForegroundColor Gray
foreach ($role in $allowedRoles) {
    Write-Host "    - $($role.Name)" -ForegroundColor Gray
}

$roleConditions = $allowedRoles | ForEach-Object {
    "(@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] StringEquals '/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions/$($_.Id)')"
}
$roleExpr = $roleConditions -join ' OR '
$condition = "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR ($roleExpr)) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR ($roleExpr))"

$uaaRoleId = "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9"
$uaaScope = "/subscriptions/$SubscriptionId"

$existing = Get-AzRoleAssignment -ObjectId $spnObjectId -RoleDefinitionId $uaaRoleId -Scope $uaaScope -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "  Already assigned. Skipping." -ForegroundColor Green
    $results += @{ Step = "User Access Administrator (conditioned)"; Status = "Already exists" }
} else {
    Write-Host "  Assigning conditioned User Access Administrator..." -ForegroundColor Yellow
    New-AzRoleAssignment `
        -ObjectId $spnObjectId `
        -RoleDefinitionId $uaaRoleId `
        -Scope $uaaScope `
        -Condition $condition `
        -ConditionVersion "2.0" `
        -ErrorAction Stop | Out-Null
    Write-Host "  Assigned." -ForegroundColor Green
    $results += @{ Step = "User Access Administrator (conditioned)"; Status = "Assigned" }
}
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────
# 3. Security Administrator — Entra ID directory role (optional)
# ─────────────────────────────────────────────────────────────────────────

Write-Host "── 3/4: Security Administrator (Entra ID) ─────────────────" -ForegroundColor Cyan

if ($SkipEntraRole) {
    Write-Host "  Skipped (-SkipEntraRole). UEBA/Entity Analytics will need manual enablement." -ForegroundColor Yellow
    $results += @{ Step = "Security Administrator (Entra ID)"; Status = "Skipped" }
} else {
    # Security Administrator directory role template ID
    $secAdminTemplateId = "194ae4cb-b126-40b2-bd5b-6091b380977d"

    try {
        # Check if Microsoft.Graph module is available
        if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Identity.DirectoryManagement)) {
            Write-Host "  Installing Microsoft.Graph.Identity.DirectoryManagement module..." -ForegroundColor Yellow
            Install-Module -Name Microsoft.Graph.Identity.DirectoryManagement -Force -Scope CurrentUser -AllowClobber
        }

        # Connect to Graph if not already connected
        $graphContext = Get-MgContext -ErrorAction SilentlyContinue
        if (-not $graphContext) {
            Write-Host "  Connecting to Microsoft Graph (browser sign-in may be required)..." -ForegroundColor Yellow
            Connect-MgGraph -Scopes "RoleManagement.ReadWrite.Directory" -NoWelcome
        }

        # Check if role is already assigned
        $existingAssignment = Get-MgRoleManagementDirectoryRoleAssignment -Filter "principalId eq '$spnObjectId' and roleDefinitionId eq '$secAdminTemplateId'" -ErrorAction SilentlyContinue

        if ($existingAssignment) {
            Write-Host "  Already assigned. Skipping." -ForegroundColor Green
            $results += @{ Step = "Security Administrator (Entra ID)"; Status = "Already exists" }
        } else {
            Write-Host "  Assigning Security Administrator directory role..." -ForegroundColor Yellow
            New-MgRoleManagementDirectoryRoleAssignment `
                -PrincipalId $spnObjectId `
                -RoleDefinitionId $secAdminTemplateId `
                -DirectoryScopeId "/" `
                -ErrorAction Stop | Out-Null
            Write-Host "  Assigned." -ForegroundColor Green
            $results += @{ Step = "Security Administrator (Entra ID)"; Status = "Assigned" }
        }
    } catch {
        Write-Host "  Failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  You may need Privileged Role Administrator to assign Entra ID roles." -ForegroundColor Yellow
        Write-Host "  Use -SkipEntraRole to skip this step and enable UEBA manually." -ForegroundColor Yellow
        $results += @{ Step = "Security Administrator (Entra ID)"; Status = "Failed" }
    }
}
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────
# 4. CustomDetection.ReadWrite.All — Graph API permission (optional)
# ─────────────────────────────────────────────────────────────────────────

Write-Host "── 4/4: CustomDetection.ReadWrite.All (Graph) ─────────────" -ForegroundColor Cyan

if ($SkipGraphPermission) {
    Write-Host "  Skipped (-SkipGraphPermission). Defender XDR stage will fail without this." -ForegroundColor Yellow
    $results += @{ Step = "CustomDetection.ReadWrite.All (Graph)"; Status = "Skipped" }
} else {
    try {
        # Check if Microsoft.Graph module is available
        if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
            Write-Host "  Installing Microsoft.Graph.Applications module..." -ForegroundColor Yellow
            Install-Module -Name Microsoft.Graph.Applications -Force -Scope CurrentUser -AllowClobber
        }

        # Connect to Graph if not already connected
        $graphContext = Get-MgContext -ErrorAction SilentlyContinue
        if (-not $graphContext) {
            Write-Host "  Connecting to Microsoft Graph (browser sign-in may be required)..." -ForegroundColor Yellow
            Connect-MgGraph -Scopes "Application.ReadWrite.All,AppRoleAssignment.ReadWrite.All" -NoWelcome
        }

        # Microsoft Graph service principal (well-known app ID)
        $graphAppId = "00000003-0000-0000-c000-000000000000"
        $graphSp = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'" -ErrorAction Stop

        # Find the CustomDetection.ReadWrite.All app role
        $appRole = $graphSp.AppRoles | Where-Object { $_.Value -eq "CustomDetection.ReadWrite.All" }
        if (-not $appRole) {
            throw "CustomDetection.ReadWrite.All app role not found on the Microsoft Graph service principal."
        }

        # Check if already granted
        $existingGrant = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $spnObjectId -ErrorAction SilentlyContinue |
            Where-Object { $_.AppRoleId -eq $appRole.Id }

        if ($existingGrant) {
            Write-Host "  Already granted. Skipping." -ForegroundColor Green
            $results += @{ Step = "CustomDetection.ReadWrite.All (Graph)"; Status = "Already exists" }
        } else {
            Write-Host "  Granting CustomDetection.ReadWrite.All with admin consent..." -ForegroundColor Yellow
            New-MgServicePrincipalAppRoleAssignment `
                -ServicePrincipalId $spnObjectId `
                -PrincipalId $spnObjectId `
                -ResourceId $graphSp.Id `
                -AppRoleId $appRole.Id `
                -ErrorAction Stop | Out-Null
            Write-Host "  Granted with admin consent." -ForegroundColor Green
            $results += @{ Step = "CustomDetection.ReadWrite.All (Graph)"; Status = "Granted" }
        }
    } catch {
        Write-Host "  Failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  You may need Application Administrator or Global Administrator." -ForegroundColor Yellow
        Write-Host "  Use -SkipGraphPermission to skip and grant manually in Entra ID." -ForegroundColor Yellow
        $results += @{ Step = "CustomDetection.ReadWrite.All (Graph)"; Status = "Failed" }
    }
}
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Bootstrap Summary" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  SPN: $spnDisplayName ($ServicePrincipalAppId)" -ForegroundColor White
Write-Host ""

foreach ($r in $results) {
    $colour = switch ($r.Status) {
        "Assigned"       { "Green" }
        "Granted"        { "Green" }
        "Already exists" { "Green" }
        "Skipped"        { "Yellow" }
        "Failed"         { "Red" }
        default          { "White" }
    }
    $icon = switch ($r.Status) {
        "Assigned"       { "[+]" }
        "Granted"        { "[+]" }
        "Already exists" { "[=]" }
        "Skipped"        { "[-]" }
        "Failed"         { "[!]" }
        default          { "[?]" }
    }
    Write-Host "  $icon $($r.Step): $($r.Status)" -ForegroundColor $colour
}

Write-Host ""

$failures = $results | Where-Object { $_.Status -eq "Failed" }
if ($failures) {
    Write-Host "  Some steps failed. Review the errors above and re-run," -ForegroundColor Red
    Write-Host "  or grant those permissions manually." -ForegroundColor Red
} else {
    Write-Host "  The pipeline is now fully autonomous." -ForegroundColor Green
    Write-Host "  No further manual steps required." -ForegroundColor Green
}
Write-Host ""
