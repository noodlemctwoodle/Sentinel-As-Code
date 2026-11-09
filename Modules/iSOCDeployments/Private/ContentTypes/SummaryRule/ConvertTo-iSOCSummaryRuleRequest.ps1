#Requires -Version 7.6

<#
.SYNOPSIS
    ToRequest handler for summary rules: the body deploy sends.

.DESCRIPTION
    Copied from the body builder inside Deploy-CustomSummaryRules
    (Deploy/content/Deploy-CustomContent.ps1), unchanged in what it sends.
    Tests/iSOCDeployments/DeployParity.Tests.ps1 holds every summary rule
    in Content/SummaryRules/ to the request the script builds.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/SummaryRule/ConvertTo-iSOCSummaryRuleRequest.ps1
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

function ConvertTo-iSOCSummaryRuleRequest {
    <#
    .SYNOPSIS
        Build the summary rule request body for one file.

    .DESCRIPTION
        A User rule whose definition is the file's query, binSize and
        destinationTable, with binDelay and binStartTime when the file sets
        them, and the description and display name when it has them. The
        function reads nothing outside the item and sends nothing.

    .PARAMETER Item
        A repository item from Read-iSOCSummaryRuleRepo that passed
        Test-iSOCSummaryRule.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.Request: ContentType, Identity,
        ResourceName (the rule name as written) and Body.

    .EXAMPLE
        $request = ConvertTo-iSOCSummaryRuleRequest -Item $item
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    $rule = $Item.Data
    $ruleDefinition = @{
        query            = $rule.query
        binSize          = [int]$rule.binSize
        destinationTable = $rule.destinationTable
    }
    $binDelay = Get-iSOCPropertyValue -InputObject $rule -Path 'binDelay'
    if ($null -ne $binDelay) { $ruleDefinition.binDelay = [int]$binDelay }
    $binStartTime = Get-iSOCPropertyValue -InputObject $rule -Path 'binStartTime'
    if ($binStartTime) { $ruleDefinition.binStartTime = $binStartTime }

    $properties = @{
        ruleType       = 'User'
        ruleDefinition = $ruleDefinition
    }
    $description = Get-iSOCPropertyValue -InputObject $rule -Path 'description'
    if ($description) { $properties.description = $description }
    $displayName = Get-iSOCPropertyValue -InputObject $rule -Path 'displayName'
    if ($displayName) { $properties.displayName = $displayName }

    [pscustomobject]@{
        PSTypeName   = 'iSOCDeployments.Request'
        ContentType  = $Item.ContentType
        Identity     = $Item.Identity
        ResourceName = [string]$rule.name
        Body         = @{ properties = $properties }
    }
}
