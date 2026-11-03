#Requires -Version 7.2

<#
.SYNOPSIS
    Get-iSOCContentHubSolution: where Content Hub solutions stand in the
    connected workspace.

.DESCRIPTION
    The solution assessment Deploy/content/Deploy-SentinelContentHub.ps1
    made before it installed anything, as a command of its own.

.NOTES
    File:         Modules/iSOCDeployments/Public/Get-iSOCContentHubSolution.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCContentHubSolution {
    <#
    .SYNOPSIS
        List Content Hub solutions with their installed and available
        versions and what installing them would do.

    .DESCRIPTION
        Reads the Content Hub catalogue and what the workspace has
        installed, after waiting up to three minutes for its onboarding to
        read. Each solution is NotFound (the catalogue does not have it),
        NotInstalled, UpdateAvailable or Installed, and its Action is what
        Install-iSOCContentHubSolution would do: Install, Update, None, or
        ForceUpdate for a package the workspace lists that the catalogue
        does not report installed (left behind by a deleted workspace).
        Nothing is changed.

    .PARAMETER Name
        The solutions' display names (matched in any case). One
        comma-separated string is split. Without it, every solution in the
        catalogue is listed.

    .PARAMETER Context
        The workspace to read. Defaults to the one Connect-iSOCWorkspace
        connected.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.ContentHubSolution: Name, Status,
        InstalledVersion, AvailableVersion, Action, ContentId and
        CatalogueName (the catalogue entry's name).

    .EXAMPLE
        Get-iSOCContentHubSolution -Name 'Azure Activity', 'Microsoft Entra ID'

        Shows whether two solutions are installed and current.

    .EXAMPLE
        Get-iSOCContentHubSolution | Where-Object Status -eq UpdateAvailable

        Lists the installed solutions the catalogue has a newer version of.
    #>
    [CmdletBinding()]
    [OutputType('iSOCDeployments.ContentHubSolution')]
    param(
        [string[]] $Name,

        [psobject] $Context
    )

    $ctx = Resolve-iSOCContext -Context $Context
    Assert-iSOCPrerequisite -Step Connect
    $hub = Get-iSOCContentHubCatalogue -Context $ctx

    $solutions = @($Name)
    if ($solutions.Count -eq 1 -and $solutions[0] -match ',') {
        $solutions = @($solutions[0] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    if (-not $Name) {
        $solutions = @($hub.Available | ForEach-Object { Get-iSOCPropertyValue -InputObject $_ -Path 'properties.displayName' } | Where-Object { $_ } | Select-Object -Unique)
    }

    foreach ($solution in $solutions) {
        $status = Get-iSOCContentHubSolutionStatus -SolutionName $solution -AvailableSolutions $hub.Available -InstalledLookup $hub.InstalledLookup -Context $ctx
        $entry = $status.CatalogEntry
        [pscustomobject]@{
            PSTypeName       = 'iSOCDeployments.ContentHubSolution'
            Name             = $status.Name
            Status           = $status.Status
            InstalledVersion = $status.InstalledVersion
            AvailableVersion = $status.AvailableVersion
            Action           = $status.Action
            ContentId        = Get-iSOCPropertyValue -InputObject $entry -Path 'properties.contentId'
            CatalogueName    = Get-iSOCPropertyValue -InputObject $entry -Path 'name'
        }
    }
}
