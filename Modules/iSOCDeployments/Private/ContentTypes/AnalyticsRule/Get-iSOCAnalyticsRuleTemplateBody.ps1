#Requires -Version 7.6

<#
.SYNOPSIS
    The rule a Content Hub analytics rule template carries, in the shape
    deploy sends.

.DESCRIPTION
    Replaces ConvertTo-NormalisedTemplateRule
    (Tools/Test-SentinelRuleDrift.ps1), with the same choice of resource.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Get-iSOCAnalyticsRuleTemplateBody.ps1
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

function Get-iSOCAnalyticsRuleTemplateBody {
    <#
    .SYNOPSIS
        Return the kind and properties of the template's alert rule
        resource, or nothing when it has none.

    .DESCRIPTION
        The resource is the first in the template's mainTemplate whose type
        names alertRules, else the first resource. Its kind is Scheduled
        when it has none. A template with no mainTemplate, no resources, or
        a resource with no properties returns nothing.

    .PARAMETER Template
        A content template, read with its mainTemplate.

    .OUTPUTS
        [hashtable] kind and properties.

    .EXAMPLE
        $expected = Get-iSOCAnalyticsRuleTemplateBody -Template $template
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Template
    )

    $mainTemplate = Get-iSOCPropertyValue -InputObject $Template -Path 'properties.mainTemplate'
    if ($null -eq $mainTemplate) { return $null }
    # Assigned first: the getter returns a list as one object, which @()
    # would nest.
    $resources = Get-iSOCPropertyValue -InputObject $mainTemplate -Path 'resources'
    $resources = @($resources | Where-Object { $null -ne $_ })
    if ($resources.Count -eq 0) { return $null }

    $ruleResource = $resources | Where-Object {
        $type = Get-iSOCPropertyValue -InputObject $_ -Path 'type'
        $type -and ($type -like '*alertRules*' -or $type -eq 'Microsoft.OperationalInsights/workspaces/providers/alertRules')
    } | Select-Object -First 1
    if (-not $ruleResource) { $ruleResource = $resources[0] }

    $properties = Get-iSOCPropertyValue -InputObject $ruleResource -Path 'properties'
    if ($null -eq $properties) { return $null }
    $kind = Get-iSOCPropertyValue -InputObject $ruleResource -Path 'kind'
    @{
        kind       = if ($kind) { [string]$kind } else { 'Scheduled' }
        properties = $properties
    }
}
