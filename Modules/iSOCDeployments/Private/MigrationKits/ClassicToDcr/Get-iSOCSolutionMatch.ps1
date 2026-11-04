#Requires -Version 7.2

<#
.SYNOPSIS
    The Content Hub solutions that carry a classic table, and whether each is installed.

.DESCRIPTION
    Looked up in the mapping without case, then without the _CL suffix, and
    checked against the workspace's catalogue.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCSolutionMatch.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCSolutionMatch {
    <#
    .SYNOPSIS
        The Content Hub solutions that carry a classic table, and whether
        each is installed.

    .DESCRIPTION
        The table is looked up in the mapping without case, then without its
        _CL suffix. Each solution named is checked against the catalogue's
        solutions by display name, without case: whether it is in Content
        Hub and installed. The mapping gives its GitHub link.

    .PARAMETER TableName
        The classic table.

    .PARAMETER StaticMapping
        The mapping, from Get-iSOCSolutionMapping.

    .PARAMETER Packages
        The catalogue, from Read-iSOCContentHubPackage.

    .OUTPUTS
        [pscustomobject] TableName, MatchCount and Solutions (SolutionName,
        IsInstalled, IsInContentHub, GithubUrl, DisplayName).

    .EXAMPLE
        Get-iSOCSolutionMatch -TableName MyApp_CL -StaticMapping $mapping -Packages $packages
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $TableName,

        $StaticMapping,

        $Packages
    )

    $pkgByName = @{}
    foreach ($p in $Packages) {
        if ((Get-iSOCPropertyValue -InputObject $p -Path 'properties') -and (Get-iSOCPropertyValue -InputObject $p -Path 'properties.contentKind') -eq 'Solution') {
            $pkgByName[(Get-iSOCPropertyValue -InputObject $p -Path 'properties.displayName').ToLower()] = $p
        }
    }

    $matchedSolutions = @()
    if ($StaticMapping -and $StaticMapping['_normalizedLookup']) {
        $lookup = $StaticMapping['_normalizedLookup']
        $solutionNames = $lookup[$TableName]
        if (-not $solutionNames) {
            $withoutCL = $TableName -replace '_CL$', ''
            $solutionNames = $lookup[$withoutCL]
        }
        if ($solutionNames) {
            foreach ($name in $solutionNames) {
                $pkg = $pkgByName[$name.ToLower()]
                $installed = if ($pkg) { [bool](Get-iSOCPropertyValue -InputObject $pkg -Path 'properties.installedVersion') } else { $false }
                $meta = $StaticMapping['solutionMetadata'][$name]
                $githubUrl = if ($meta) { $meta['githubUrl'] } else { $null }
                $matchedSolutions += [pscustomobject]@{
                    SolutionName   = $name
                    IsInstalled    = $installed
                    IsInContentHub = [bool]$pkg
                    GithubUrl      = $githubUrl
                    DisplayName    = if ($pkg) { Get-iSOCPropertyValue -InputObject $pkg -Path 'properties.displayName' } else { $name }
                }
            }
        }
    }

    [pscustomobject]@{
        TableName  = $TableName
        MatchCount = $matchedSolutions.Count
        Solutions  = @($matchedSolutions)
    }
}
