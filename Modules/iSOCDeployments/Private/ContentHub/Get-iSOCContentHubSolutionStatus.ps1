#Requires -Version 7.6

<#
.SYNOPSIS
    Where one solution stands: not in the catalogue, not installed, current
    or behind.

.DESCRIPTION
    Copied from Get-SolutionStatus (Deploy/content/Deploy-SentinelContentHub.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubSolutionStatus.ps1
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

function Get-iSOCContentHubSolutionStatus {
    <#
    .SYNOPSIS
        Return a solution's versions and what installing it would do.

    .DESCRIPTION
        A name the catalogue does not have is NotFound, with a warning. One
        the workspace has not installed is NotInstalled (Install). An
        installed one is UpdateAvailable (Update) when the catalogue's
        version is newer; otherwise it is Installed, and needs nothing
        unless -ForceSolutionUpdate is given (ForceUpdate). An installed
        package is checked against the catalogue entry, which is what the
        Content Hub page shows: contentPackages can keep entries from a
        workspace that was deleted and recreated, and a package the
        catalogue does not report installed is reinstalled (ForceUpdate),
        with a warning. The installed version is installedVersion, else
        version, else 0.0.0.

    .PARAMETER SolutionName
        The solution's display name, as the catalogue spells it (matched in
        any case).

    .PARAMETER AvailableSolutions
        The catalogue, from Get-iSOCContentHubCatalogue.

    .PARAMETER InstalledLookup
        The installed packages by display name, from
        Get-iSOCContentHubCatalogue.

    .PARAMETER Context
        The workspace context.

    .PARAMETER ForceSolutionUpdate
        Reinstall a solution that is already current.

    .OUTPUTS
        [hashtable] Name, Status (NotFound, NotInstalled, UpdateAvailable or
        Installed), AvailableVersion, InstalledVersion, CatalogEntry,
        InstalledPackage and Action (None, Install, Update or ForceUpdate).

    .EXAMPLE
        Get-iSOCContentHubSolutionStatus -SolutionName 'Azure Activity' -AvailableSolutions $hub.Available -InstalledLookup $hub.InstalledLookup -Context $ctx
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $SolutionName,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $AvailableSolutions,

        [Parameter(Mandatory)]
        [hashtable] $InstalledLookup,

        [Parameter(Mandatory)]
        [psobject] $Context,

        [switch] $ForceSolutionUpdate
    )

    $result = @{
        Name             = $SolutionName
        Status           = 'NotFound'
        AvailableVersion = $null
        InstalledVersion = $null
        CatalogEntry     = $null
        InstalledPackage = $null
        Action           = 'None'
    }

    $catalogMatch = $AvailableSolutions | Where-Object {
        ($_.properties.PSObject.Properties.Name -contains 'displayName') -and
        ($_.properties.displayName -eq $SolutionName)
    } | Select-Object -First 1

    if (-not $catalogMatch) {
        Write-iSOCLog "Solution '$SolutionName' not found in the Content Hub catalogue." -Level Warning
        return $result
    }

    $result.CatalogEntry = $catalogMatch
    $result.AvailableVersion = if ($catalogMatch.properties.PSObject.Properties.Name -contains 'version') { $catalogMatch.properties.version } else { '0.0.0' }

    if (-not $InstalledLookup.ContainsKey($SolutionName)) {
        $result.Status = 'NotInstalled'
        $result.Action = 'Install'
        return $result
    }

    $installed = $InstalledLookup[$SolutionName]
    $result.InstalledPackage = $installed
    if ($installed.properties.PSObject.Properties.Name -contains 'installedVersion') {
        $result.InstalledVersion = $installed.properties.installedVersion
    }
    if (-not $result.InstalledVersion -and $installed.properties.PSObject.Properties.Name -contains 'version') {
        $result.InstalledVersion = $installed.properties.version
    }
    if (-not $result.InstalledVersion) { $result.InstalledVersion = '0.0.0' }

    $versionComparison = Compare-iSOCSemanticVersion -Version1 $result.AvailableVersion -Version2 $result.InstalledVersion
    if ($versionComparison -gt 0) {
        $result.Status = 'UpdateAvailable'
        $result.Action = 'Update'
        return $result
    }
    if ($ForceSolutionUpdate) {
        $result.Status = 'Installed'
        $result.Action = 'ForceUpdate'
        return $result
    }

    $catContentId = if ($catalogMatch.properties.PSObject.Properties.Name -contains 'contentId') { $catalogMatch.properties.contentId } else { $null }
    $isGenuinelyInstalled = $false
    if ($catContentId) {
        $verifyPath = "$($Context.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/contentProductPackages/$($catalogMatch.name)"
        try {
            $verifyResult = Invoke-iSOCRestRequest -Method GET -Path $verifyPath -ApiVersion (Get-iSOCApiVersion SecurityInsights) -MaxAttempts 1
            $prodProps = $verifyResult.properties
            if ($prodProps.PSObject.Properties.Name -contains 'isInstalled' -and $prodProps.isInstalled -eq $true) {
                $isGenuinelyInstalled = $true
            } elseif ($prodProps.PSObject.Properties.Name -contains 'installedVersion' -and $prodProps.installedVersion) {
                $isGenuinelyInstalled = $true
            }
        } catch {
            Write-iSOCLog "  Could not read the catalogue entry for ${SolutionName}: $($_.Exception.Message)" -Level Debug
        }
    }

    $result.Status = 'Installed'
    if ($isGenuinelyInstalled) {
        $result.Action = 'None'
    } else {
        Write-iSOCLog "  $SolutionName shows as installed in contentPackages but not in Content Hub; forcing reinstall." -Level Warning
        $result.Action = 'ForceUpdate'
    }
    $result
}
