#Requires -Version 7.6

<#
.SYNOPSIS
    The display name of every Content Hub solution, by the id its
    templates give as their packageId.

.DESCRIPTION
    Copied from Get-ContentHubSolutionLookup (Tools/Test-SentinelRuleDrift.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubSolutionName.ps1
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

function Get-iSOCContentHubSolutionName {
    <#
    .SYNOPSIS
        Map each catalogue solution's contentId to its display name.

    .DESCRIPTION
        A solution with no contentId is keyed by its catalogue name. When
        the catalogue cannot be read the map is empty, with a warning: the
        names are only for the report and the solution filter.

    .PARAMETER Context
        The workspace context.

    .OUTPUTS
        [hashtable] packageId to display name.

    .EXAMPLE
        $names = Get-iSOCContentHubSolutionName -Context $ctx
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context
    )

    $lookup = @{}
    try {
        $packages = @(Invoke-iSOCRestRequest -Method GET -Path "$($Context.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/contentProductPackages" -ApiVersion (Get-iSOCApiVersion SecurityInsights))
        foreach ($pkg in $packages) {
            $displayName = Get-iSOCPropertyValue -InputObject $pkg -Path 'properties.displayName'
            $contentId = if ($pkg.properties.PSObject.Properties.Name -contains 'contentId') { $pkg.properties.contentId } else { $pkg.name }
            if ($displayName -and $contentId) { $lookup[[string]$contentId] = [string]$displayName }
        }
        Write-iSOCLog "Mapped $($lookup.Count) Content Hub package IDs to solution names."
    } catch {
        Write-iSOCLog "Could not fetch Content Hub solution catalogue: $($_.Exception.Message). Solution names will be unavailable in the report." -Level Warning
    }
    $lookup
}
