<#
.SYNOPSIS
    Assigns RBAC permissions to the DCR Watchlist Sync Automation Account
    managed identity. Run once after initial infrastructure deployment.

.DESCRIPTION
    The pipeline service principal does not have
    Microsoft.Authorization/roleAssignments/write, so RBAC must be applied
    manually by a user with Owner or User Access Administrator on the
    subscription.

    This script assigns:
      - Monitoring Reader (subscription scope)
        Allows the runbook to list DCRs and their associations via ARM.
      - Microsoft Sentinel Contributor (subscription scope)
        Allows the runbook to create/update the Sentinel watchlist.

.PARAMETER SubscriptionId
    Target subscription ID.

.PARAMETER AutomationAccountName
    Name of the Automation Account. Defaults to aa-dcr-watchlist-sync.

.PARAMETER AutomationResourceGroup
    Resource group containing the Automation Account. Defaults to rg-dcr-watchlist-sync.

.PARAMETER Remove
    Switch to remove the role assignments instead of creating them.

.NOTES
    Author:         noodlemctwoodle
    Version:        1.0.0
    Last Updated:   2026-03-23
    Repository:     Sentinel-As-Code
    Website:        https://sentinel.blog
    Requires:       Azure CLI (az), Owner or User Access Administrator on subscription

.EXAMPLE
    # Apply permissions
    .\Set-RunbookPermissions.ps1 -SubscriptionId '5305ccd2-977a-4630-843b-bad582e756a3'

.EXAMPLE
    # Remove permissions
    .\Set-RunbookPermissions.ps1 -SubscriptionId '5305ccd2-977a-4630-843b-bad582e756a3' -Remove
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string] $SubscriptionId

  , [Parameter(Mandatory)]
    [string] $AutomationAccountName

  , [Parameter(Mandatory)]
    [string] $AutomationResourceGroup

  , [Parameter(Mandatory)]
    [string] $SentinelResourceGroup

  , [switch] $Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Role definitions ──────────────────────────────────────────────────────────

$subscriptionScope = "/subscriptions/$SubscriptionId"
$sentinelRgScope   = "/subscriptions/$SubscriptionId/resourceGroups/$SentinelResourceGroup"

$roles = @(
    @{
        Name   = 'Monitoring Reader'
        Scope  = $subscriptionScope
        Reason = 'List DCRs and associations via ARM API (subscription-wide)'
    }
    @{
        Name   = 'Microsoft Sentinel Contributor'
        Scope  = $sentinelRgScope
        Reason = 'Create and update Sentinel watchlists (Sentinel RG only)'
    }
)

# ── Resolve managed identity principal ID ─────────────────────────────────────

Write-Host "`nResolving managed identity for '$AutomationAccountName'..." -ForegroundColor Cyan

$principalId = az automation account show `
    --name $AutomationAccountName `
    --resource-group $AutomationResourceGroup `
    --subscription $SubscriptionId `
    --query identity.principalId `
    --output tsv

if (-not $principalId) {
    Write-Error "Could not resolve managed identity. Ensure the Automation Account '$AutomationAccountName' exists in '$AutomationResourceGroup' and has a system-assigned managed identity enabled."
    exit 1
}

Write-Host "  Principal ID: $principalId" -ForegroundColor Green

# ── Permission summary ────────────────────────────────────────────────────────

$action = if ($Remove) { 'REMOVE' } else { 'ASSIGN' }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "  PERMISSION SUMMARY — $action" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  This script will $($action.ToLower()) the following permissions to:" -ForegroundColor White
Write-Host "    Identity:     $AutomationAccountName (managed identity)" -ForegroundColor White
Write-Host "    Principal ID: $principalId" -ForegroundColor White
Write-Host "    Subscription: $SubscriptionId" -ForegroundColor White
Write-Host ""

$roleIndex = 1
foreach ($role in $roles) {
    $scopeLabel = if ($role.Scope -match '/resourceGroups/') { "resource group scope: $SentinelResourceGroup" } else { 'subscription scope' }
    Write-Host "  $roleIndex. Azure RBAC ($scopeLabel):" -ForegroundColor White
    Write-Host "     - $($role.Name)" -ForegroundColor White
    Write-Host "       $($role.Reason)" -ForegroundColor Gray
    Write-Host "       Scope: $($role.Scope)" -ForegroundColor DarkGray
    Write-Host ""
    $roleIndex++
}

Write-Host "============================================================" -ForegroundColor Red
Write-Host "  DISCLAIMER" -ForegroundColor Red
Write-Host "============================================================" -ForegroundColor Red
Write-Host ""
Write-Host "  This script modifies Azure RBAC role assignments at" -ForegroundColor White
Write-Host "  the SUBSCRIPTION scope." -ForegroundColor White
Write-Host ""
Write-Host "  By proceeding you acknowledge that:" -ForegroundColor White
Write-Host ""
Write-Host "  - You have reviewed and understand the permissions listed" -ForegroundColor White
Write-Host "    above and accept the security implications." -ForegroundColor White
Write-Host "  - You have the authority to grant these permissions in" -ForegroundColor White
Write-Host "    your organisation (Owner / User Access Administrator)." -ForegroundColor White
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
Write-Host "  Proceeding with permission $($action.ToLower())ments..." -ForegroundColor Green
Write-Host ""

# ── Apply or remove role assignments ──────────────────────────────────────────

foreach ($role in $roles) {

    $roleName  = $role.Name
    $roleScope = $role.Scope
    $reason    = $role.Reason

    if ($Remove) {
        if ($PSCmdlet.ShouldProcess("$roleName on $roleScope", 'Remove role assignment')) {
            Write-Host "  [-] $roleName" -ForegroundColor Yellow
            Write-Host "      Scope:  $roleScope" -ForegroundColor DarkGray
            Write-Host "      Reason: $reason" -ForegroundColor DarkGray

            az role assignment delete `
                --assignee $principalId `
                --role $roleName `
                --scope $roleScope `
                --yes 2>&1 | Out-Null

            Write-Host "      Removed." -ForegroundColor Green
        }
    }
    else {
        if ($PSCmdlet.ShouldProcess("$roleName on $roleScope", 'Create role assignment')) {
            Write-Host "  [+] $roleName" -ForegroundColor Green
            Write-Host "      Scope:  $roleScope" -ForegroundColor DarkGray
            Write-Host "      Reason: $reason" -ForegroundColor DarkGray

            $result = az role assignment create `
                --assignee $principalId `
                --role $roleName `
                --scope $roleScope 2>&1

            if ($LASTEXITCODE -ne 0) {
                if ($result -match 'already exists') {
                    Write-Host "      Already assigned — skipping." -ForegroundColor DarkYellow
                }
                else {
                    Write-Warning "      Failed: $result"
                }
            }
            else {
                Write-Host "      Assigned." -ForegroundColor Green
            }
        }
    }
}

# ── Verification ──────────────────────────────────────────────────────────────

if (-not $Remove) {
    Write-Host "`nVerifying assignments..." -ForegroundColor Cyan

    $assignments = az role assignment list `
        --assignee $principalId `
        --all `
        --query "[].{Role:roleDefinitionName, Scope:scope}" `
        --output table

    Write-Host $assignments
}

Write-Host "`nDone.`n" -ForegroundColor Green
