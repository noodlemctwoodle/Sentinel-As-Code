#Requires -Version 7.6

<#
.SYNOPSIS
    How many templates of one kind the requested solutions ship.

.DESCRIPTION
    Replaces Get-AutomationRuleStatus and Get-HuntingQueryStatus
    (Deploy/content/Deploy-SentinelContentHub.ps1), which were the same
    function for two kinds. Automation rules and hunting queries arrive
    with the solution package itself; this step only reports how many
    there are. Every page is counted; the script counted the first only
    (MIGRATION.md edit E20).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubTemplateCount.ps1
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

function Get-iSOCContentHubTemplateCount {
    <#
    .SYNOPSIS
        Count the requested solutions' automation rule or hunting query
        templates.

    .DESCRIPTION
        When the templates cannot be read the count is 0, logged as none
        found, as the script did.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Kind
        AutomationRule or HuntingQuery.

    .PARAMETER SolutionNames
        The solutions to count for.

    .PARAMETER AvailableSolutions
        The catalogue, from Get-iSOCContentHubCatalogue.

    .OUTPUTS
        [int]

    .EXAMPLE
        Get-iSOCContentHubTemplateCount -Context $ctx -Kind HuntingQuery -SolutionNames $names -AvailableSolutions $hub.Available
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [ValidateSet('AutomationRule', 'HuntingQuery')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $SolutionNames,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $AvailableSolutions
    )

    $label = if ($Kind -eq 'AutomationRule') { @{ Title = 'Automation Rule'; Noun = 'automation rule' } } else { @{ Title = 'Hunting Query'; Noun = 'hunting query' } }
    Write-iSOCLog "Checking $($label.Title) status..." -Level Section
    try {
        $allTemplates = @(Get-iSOCContentHubTemplate -Context $Context -Kind $Kind)
    }
    catch {
        Write-iSOCLog "  No $($label.Title) templates found."
        return 0
    }

    $lookup = Get-iSOCContentHubSolutionLookup -SolutionNames $SolutionNames -AvailableSolutions $AvailableSolutions
    $count = @($allTemplates | Where-Object { ($_.properties.PSObject.Properties.Name -contains 'packageId') -and $lookup.ById.ContainsKey($_.properties.packageId) }).Count
    Write-iSOCLog "  $count $($label.Noun) template(s) available from deployed solutions."
    $count
}
