#Requires -Version 7.6

<#
.SYNOPSIS
    Checks the required modules and returns an Az context for the
    subscription with a working token.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Azure/Assert-SdlPrerequisite.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function Assert-SdlPrerequisite {
    <#
    .SYNOPSIS
        Checks the required modules and returns an Az context for the
        subscription with a working token.

    .DESCRIPTION
        Fails fast when Az.Accounts, Az.OperationalInsights or
        ImportExcel is missing, and loads ImportExcel without its
        libgdiplus warning. Reuses the current context when it targets
        the subscription and has a working token; otherwise switches
        subscription, and when that still gives no usable token signs
        in interactively, scoped to the subscription's tenant.

    .PARAMETER SubscriptionId
        The subscription that holds the workspace.

    .OUTPUTS
        The Az context in use.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([object])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SubscriptionId
    )

    foreach ($module in @('Az.Accounts', 'Az.OperationalInsights', 'ImportExcel')) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            throw "$module module is not installed. Run: Install-Module $module -Scope CurrentUser"
        }
    }
    # ImportExcel prints a libgdiplus warning on load on macOS and Linux. Column
    # widths come from Resize-SdlColumn, so the warning is noise.
    Import-Module -Name 'ImportExcel' -ErrorAction Stop 3>$null

    $contextError = $null
    $context = Get-AzContext -ErrorAction SilentlyContinue -ErrorVariable contextError
    if ($contextError) {
        Write-Verbose -Message "Get-AzContext reported: $($contextError[0].Exception.Message)"
    }
    if ($context -and $context.Subscription.Id -eq $SubscriptionId -and (Test-SdlAzureToken)) {
        return $context
    }
    if ($context -and $context.Subscription.Id -ne $SubscriptionId) {
        Write-SdlStatus -Message "Switching context to subscription $SubscriptionId..."
        try {
            $context = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop -WarningAction SilentlyContinue
        } catch {
            Write-Verbose -Message "Set-AzContext failed: $($_.Exception.Message)"
            $context = $null
        }
        if ($context -and (Test-SdlAzureToken)) {
            return $context
        }
    }

    $connect = @{ SubscriptionId = $SubscriptionId }
    try {
        $tenant = (Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop -WarningAction SilentlyContinue).TenantId
        if ($tenant) {
            $connect['Tenant'] = $tenant
        }
    } catch {
        Write-Verbose -Message 'Subscription tenant not resolvable before sign-in; signing in without -Tenant.'
    }

    Write-SdlStatus -Message 'Azure sign-in is missing or has expired (or needs MFA); signing in...'
    $null = Connect-AzAccount @connect -ErrorAction Stop
    $context = Get-AzContext -ErrorAction Stop
    if (-not $context -or $context.Subscription.Id -ne $SubscriptionId -or -not (Test-SdlAzureToken)) {
        throw "Could not obtain an Azure token for subscription $SubscriptionId. Run Connect-AzAccount -SubscriptionId $SubscriptionId (add -Tenant <tenant-id> if the tenant needs MFA) and re-run."
    }
    return $context
}
