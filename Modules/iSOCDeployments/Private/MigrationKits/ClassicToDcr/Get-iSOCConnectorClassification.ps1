#Requires -Version 7.2

<#
.SYNOPSIS
    Classify the data connector of each solution that carries a classic table.

.DESCRIPTION
    For each solution the mapping names for the table, the first data
    connector its Content Hub package depends on, classified by
    Resolve-iSOCConnectorKind.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCConnectorClassification.ps1
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

function Get-iSOCConnectorClassification {
    <#
    .SYNOPSIS
        Classify the data connector of each solution that carries a classic
        table.

    .DESCRIPTION
        For each solution the mapping names for the table (looked up as in
        Get-iSOCSolutionMatch), the first DataConnector its Content Hub
        package depends on is classified by Resolve-iSOCConnectorKind. A
        solution not in the catalogue, or with no data connector, is
        Unknown.

    .PARAMETER TableName
        The classic table.

    .PARAMETER StaticMapping
        The mapping, from Get-iSOCSolutionMapping.

    .PARAMETER Packages
        The catalogue, from Read-iSOCContentHubPackage.

    .OUTPUTS
        [pscustomobject[]] SolutionName and ConnectorKind.

    .EXAMPLE
        Get-iSOCConnectorClassification -TableName MyApp_CL -StaticMapping $mapping -Packages $packages
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)]
        [string] $TableName,

        $StaticMapping,

        $Packages
    )

    $result = @()
    if (-not ($StaticMapping -and $StaticMapping['_normalizedLookup'])) { return $result }

    $lookup = $StaticMapping['_normalizedLookup']
    $solutionNames = $lookup[$TableName]
    if (-not $solutionNames) {
        $withoutCL = $TableName -replace '_CL$', ''
        $solutionNames = $lookup[$withoutCL]
    }
    if (-not $solutionNames) { return $result }

    $pkgByName = @{}
    foreach ($p in $Packages) {
        if ((Get-iSOCPropertyValue -InputObject $p -Path 'properties') -and (Get-iSOCPropertyValue -InputObject $p -Path 'properties.contentKind') -eq 'Solution') {
            $pkgByName[(Get-iSOCPropertyValue -InputObject $p -Path 'properties.displayName').ToLower()] = $p
        }
    }

    foreach ($name in $solutionNames) {
        $pkg = $pkgByName[$name.ToLower()]
        $kind = 'Unknown'
        $criteria = if ($pkg) { Get-iSOCPropertyValue -InputObject $pkg -Path 'properties.dependencies.criteria' } else { $null }
        if ($pkg -and $criteria) {
            $connectorIds = @()
            foreach ($c in $criteria) {
                $contentId = Get-iSOCPropertyValue -InputObject $c -Path 'contentId'
                if ((Get-iSOCPropertyValue -InputObject $c -Path 'kind') -eq 'DataConnector' -and $contentId) {
                    $connectorIds += $contentId
                }
            }
            if ($connectorIds.Count -gt 0) {
                $kind = Resolve-iSOCConnectorKind -ConnectorId $connectorIds[0] -SolutionName $name
            }
        }

        $result += [pscustomobject]@{
            SolutionName  = $name
            ConnectorKind = $kind
        }
    }
    $result
}
