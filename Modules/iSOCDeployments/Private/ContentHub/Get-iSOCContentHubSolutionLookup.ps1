#Requires -Version 7.2

<#
.SYNOPSIS
    The requested solutions' catalogue ids, for matching templates to the
    solution that ships them.

.DESCRIPTION
    Replaces the solution lookups Deploy-AnalyticsRules, Deploy-Workbooks,
    Get-AutomationRuleStatus and Get-HuntingQueryStatus each built
    (Deploy/content/Deploy-SentinelContentHub.ps1); they were four copies
    of the same loop.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubSolutionLookup.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCContentHubSolutionLookup {
    <#
    .SYNOPSIS
        Map each requested solution's contentId and catalogue name to its
        display name, and to the source a metadata record names.

    .DESCRIPTION
        A template's packageId is its solution's contentId or catalogue
        name. ById maps both to the display name, for the solutions named
        (in any case); Detail maps the same keys to the display name and
        contentId (the catalogue name when there is no contentId) that a
        rule's metadata gives as its source.

    .PARAMETER SolutionNames
        The solutions whose templates are wanted.

    .PARAMETER AvailableSolutions
        The catalogue, from Get-iSOCContentHubCatalogue.

    .OUTPUTS
        [hashtable] ById and Detail.

    .EXAMPLE
        $lookup = Get-iSOCContentHubSolutionLookup -SolutionNames $names -AvailableSolutions $hub.Available
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $SolutionNames,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $AvailableSolutions
    )

    $namesLower = @($SolutionNames | ForEach-Object { $_.ToLower() })
    $byId = @{}
    foreach ($sol in $AvailableSolutions) {
        $solName = if ($sol.properties.PSObject.Properties.Name -contains 'displayName') { $sol.properties.displayName } else { $null }
        if ($solName -and $namesLower -contains $solName.ToLower()) {
            if ($sol.properties.PSObject.Properties.Name -contains 'contentId' -and $sol.properties.contentId) {
                $byId[$sol.properties.contentId] = $solName
            }
            if ($sol.name) { $byId[$sol.name] = $solName }
        }
    }

    $detail = @{}
    foreach ($sol in $AvailableSolutions) {
        $solName = if ($sol.properties.PSObject.Properties.Name -contains 'displayName') { $sol.properties.displayName } else { $null }
        $solCid = if ($sol.properties.PSObject.Properties.Name -contains 'contentId') { $sol.properties.contentId } else { $sol.name }
        if ($solName -and $solCid) {
            if ($byId.ContainsKey($solCid)) { $detail[$solCid] = @{ Name = $solName; ContentId = $solCid } }
            if ($sol.name -and $byId.ContainsKey($sol.name)) { $detail[$sol.name] = @{ Name = $solName; ContentId = $solCid } }
        }
    }

    @{ ById = $byId; Detail = $detail }
}
