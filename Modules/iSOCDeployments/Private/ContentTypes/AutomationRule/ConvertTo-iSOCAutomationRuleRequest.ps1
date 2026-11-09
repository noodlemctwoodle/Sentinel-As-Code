#Requires -Version 7.6

<#
.SYNOPSIS
    ToRequest handler for automation rules: the body deploy sends.

.DESCRIPTION
    Copied from the body builder inside Deploy-CustomAutomationRules
    (Deploy/content/Deploy-CustomContent.ps1), unchanged in what it sends.
    Tests/iSOCDeployments/DeployParity.Tests.ps1 holds every automation rule
    in Content/AutomationRules/ to the request the script builds.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AutomationRule/ConvertTo-iSOCAutomationRuleRequest.ps1
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

function ConvertTo-iSOCAutomationRuleRequest {
    <#
    .SYNOPSIS
        Build the automation rule request body for one file.

    .DESCRIPTION
        The file's displayName, order, triggeringLogic and actions become
        the properties as they are. The function reads nothing outside the
        item and sends nothing.

    .PARAMETER Item
        A repository item from Read-iSOCAutomationRuleRepo that passed
        Test-iSOCAutomationRule.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.Request: ContentType, Identity,
        ResourceName (the automationRuleId as written) and Body.

    .EXAMPLE
        $request = ConvertTo-iSOCAutomationRuleRequest -Item $item
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    $rule = $Item.Data
    [pscustomobject]@{
        PSTypeName   = 'iSOCDeployments.Request'
        ContentType  = $Item.ContentType
        Identity     = $Item.Identity
        ResourceName = [string]$rule.automationRuleId
        Body         = @{
            properties = @{
                displayName     = $rule.displayName
                order           = [int]$rule.order
                triggeringLogic = $rule.triggeringLogic
                actions         = @($rule.actions)
            }
        }
    }
}
