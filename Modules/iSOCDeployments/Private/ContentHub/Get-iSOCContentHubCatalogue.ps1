#Requires -Version 7.6

<#
.SYNOPSIS
    The Content Hub catalogue and the solutions a workspace has installed.

.DESCRIPTION
    Copied from Get-ContentHubSolutions
    (Deploy/content/Deploy-SentinelContentHub.ps1). Both lists are read
    through every page; the script read the first page of each only
    (MIGRATION.md edit E20).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubCatalogue.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCContentHubCatalogue {
    <#
    .SYNOPSIS
        Wait for onboarding, then read the catalogue and the installed
        packages.

    .DESCRIPTION
        The catalogue is contentProductPackages, the installed packages
        contentPackages. When the installed packages cannot be read, every
        solution is treated as new, with a warning. The installed packages
        are looked up by display name, the last of a name winning.

    .PARAMETER Context
        The workspace context.

    .OUTPUTS
        [hashtable] Available (the catalogue), Installed (the installed
        packages) and InstalledLookup (display name to installed package).

    .EXAMPLE
        $hub = Get-iSOCContentHubCatalogue -Context $ctx
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context
    )

    Wait-iSOCWorkspaceOnboarding -Context $Context

    Write-iSOCLog 'Fetching available Content Hub solutions...' -Level Section
    $root = "$($Context.WorkspaceResourceId)/providers/Microsoft.SecurityInsights"
    $apiVersion = Get-iSOCApiVersion SecurityInsights
    $availableSolutions = @(Invoke-iSOCRestRequest -Method GET -Path "$root/contentProductPackages" -ApiVersion $apiVersion)
    Write-iSOCLog "Found $($availableSolutions.Count) solutions in the Content Hub catalogue."

    try {
        $installedPackages = @(Invoke-iSOCRestRequest -Method GET -Path "$root/contentPackages" -ApiVersion $apiVersion)
        Write-iSOCLog "Found $($installedPackages.Count) installed solutions."
    }
    catch {
        Write-iSOCLog "Could not fetch installed solutions: $($_.Exception.Message). Treating all as new." -Level Warning
        $installedPackages = @()
    }

    $installedLookup = @{}
    foreach ($pkg in $installedPackages) {
        $name = Get-iSOCPropertyValue -InputObject $pkg -Path 'properties.displayName'
        if ($name) { $installedLookup[$name] = $pkg }
    }

    @{
        Available       = $availableSolutions
        Installed       = $installedPackages
        InstalledLookup = $installedLookup
    }
}
